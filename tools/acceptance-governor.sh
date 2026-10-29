#!/bin/zsh
# AB-T-0371's acceptance: the cross-process governor on MLXMemoryPolicy (mlx-engine-swift 0.73.0), with three model
# plugins from their GitHub releases under a 70 GB budget, far less than their lanes' sum (Qwen-Image-Edit 63 GB,
# Qwen-Image Flash 31.6, Z-Image Turbo int4 39.9, FLUX.2 Klein bf16 25.9):
#
#   1. Klein, then Z-Image: both fit, since the idle Klein worker is charged what it holds, not its peak;
#   2. Qwen-Image-Edit: the policy evicts Klein, then Z-Image, least recently used first, each logged with its reason;
#   3. Z-Image again: the idle Qwen worker is evicted;
#   4. Flash, then Qwen-Image-Edit in the same worker: Edit fits only without Flash, which is unloaded from the worker,
#      and the idle Z-Image worker is evicted; then Flash again, with Edit unloaded;
#   5. no OOM: every job succeeds, no worker dies, and the sampled sum of the workers' phys_footprint stays under the
#      budget; the ledger after each job sets what each worker reports beside what the host reads;
#   6. every recorded GPP session passes the validator.
#
#   tools/acceptance-governor.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh), the plugins' weights in MLXEngine's store, and network access to GitHub.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
BUDGET=${BUDGET:-70000000000}
Q=com.xocialize.gaea.qwen-image; Z=com.xocialize.gaea.z-image; K=com.xocialize.gaea.flux2-klein
FOX="a red fox sitting in a snowy forest at sunrise, photorealistic"
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { # name, then a command whose exit status decides
  local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
ok() { eval "$1" } # a check written with this script's own functions
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
job() { # port, json body → prints the settled job
  local id j; id=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  for _ in {1..90}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
upload() { mes -X POST "http://127.0.0.1:$1/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @"$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["upload_id"])' }
start() { # home, port, extra args… → waits for the operator socket
  local home=$1 port=$2; shift 2
  GAEA_HOME=$home "$GAEA" --headless --port $port --no-advertise "$@" > "$home.out" 2>&1 &
  for _ in {1..50}; do [[ -S $home/operator.sock ]] && return; sleep 0.2; done
  say "Gaea at $home didn't start:"; cat "$home.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
workers() { $CLI ledger --json | py "import json,sys; print(' '.join(sorted(w['pluginID'] for w in json.load(sys.stdin)['workers'])))" }
logged() { grep -c -F -- "$1" "$H.out" }
step() { # n, label, body → runs the job, keeps it and the ledger after it
  job $P "$3" > "$OUT/job-$1.json"
  $CLI ledger --json > "$OUT/ledger-$1.json"; $CLI ledger > "$OUT/ledger-$1.txt"
  say "      $1 $2: $(py "import json; j = json.load(open('$OUT/job-$1.json')); print(j['outcome'], j['result']['provenance']['model']['id'] if j.get('result') else j.get('error'))"); workers now: $(workers)"
}
succeeded() { py "import json; j = json.load(open('$OUT/job-$1.json')); assert j['outcome'] == 'succeeded', j" }

say "# Governor acceptance (AB-T-0371) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), budget $BUDGET, plugins from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API

H=$WORK/main; P=17700
start $H $P --budget-bytes $BUDGET
export GAEA_HOME=$H
check "add Qwen-Image, Z-Image and FLUX.2 Klein by repo URL" zsh -c "for r in qwen-image z-image flux2-klein; do $CLI plugins add https://github.com/xocialize/gaea-plugin-\$r | grep -q Installed || exit 1; done"
$CLI models > "$OUT/models.txt"
$CLI status > "$OUT/status.txt"

# Σ phys_footprint of Gaea's workers, sampled every second while the jobs run.
( while [[ -S $H/operator.sock ]]; do
    $CLI ledger --json 2>/dev/null | py "import json,sys,time; l = json.load(sys.stdin); print(round(time.time(), 1), sum(w.get('physFootprintBytes') or 0 for w in l['workers']), ' '.join(sorted(w['pluginID'].split('.')[-1] for w in l['workers'])))" 2>/dev/null
    sleep 1
  done ) > "$OUT/footprint-samples.txt" &
SAMPLER=$!

step 1 "Klein bf16" '{"operation":"image.generate","model":"klein-4b","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
mes -o "$WORK/fox.png" "http://127.0.0.1:$P$(py "import json; print(json.load(open('$OUT/job-1.json'))['result']['outputs'][0]['href'])")"
step 2 "Z-Image Turbo int4" '{"operation":"image.generate","model":"z-image-turbo","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
check "1. Klein, then Z-Image: both fit, Klein charged what it holds" ok 'succeeded 1 && succeeded 2 && [[ $(workers) == "$K $Z" ]] && (( $(logged "scheduler: evicting") == 0 ))'

EDIT='{"operation":"image.edit","model":"qwen-image-edit","inputs":{"images":[{"upload":"UPLOAD"}],"instruction":"Make it a snowy night with the northern lights in the sky"},"params":{"seed":7},"extensions":{"x-qwen.steps":4}}'
step 3 "Qwen-Image-Edit bf16, 4 steps" "${EDIT/UPLOAD/$(upload $P $WORK/fox.png)}"
check "2. Qwen-Image-Edit: the policy evicts Klein, then Z-Image (least recently used first), with its reason" ok 'succeeded 3 && [[ $(workers) == $Q ]] && grep -F "scheduler: evicting" $H.out | grep -F "qwen-image-edit bf16" | head -2 | grep -n . | tr "\n" " " | grep -q "1:.*flux2-klein.*2:.*z-image"'

step 4 "Z-Image Turbo int4 again" '{"operation":"image.generate","model":"z-image-turbo","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":1024,"height":1024},"seed":43}}'
check "3. Z-Image again: the idle Qwen worker is evicted" ok 'succeeded 4 && [[ $(workers) == $Z ]] && (( $(logged "evicting $Q to make room for z-image-turbo int4") == 1 ))'

step 5 "Qwen-Image Flash int8" '{"operation":"image.generate","model":"qwen-image-flash","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
step 6 "Qwen-Image-Edit beside Flash" "${EDIT/UPLOAD/$(upload $P $WORK/fox.png)}"
check "4a. Edit in Flash's worker: Flash is unloaded from it, and the idle Z-Image worker evicted" ok 'succeeded 5 && succeeded 6 && [[ $(workers) == $Q ]] && (( $(logged "unloading qwen-image-flash from $Q") == 1 )) && (( $(logged "evicting $Z to make room for qwen-image-edit bf16") == 2 ))'
step 7 "Qwen-Image Flash again" '{"operation":"image.generate","model":"qwen-image-flash","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":1024,"height":1024},"seed":43}}'
check "4b. Flash again: Edit is unloaded from the worker" ok 'succeeded 7 && (( $(logged "unloading qwen-image-edit from $Q") == 1 ))'

kill $SAMPLER 2>/dev/null
$CLI plugins logs $Q -n 5 > "$OUT/qwen-logs.txt"; $CLI plugins logs $Z -n 5 > "$OUT/z-image-logs.txt"; $CLI plugins logs $K -n 5 > "$OUT/klein-logs.txt"
check "5a. no OOM: every job succeeded, no worker died" ok 'for n in 1 2 3 4 5 6 7; do succeeded $n || return 1; done; ! grep -q worker_died $OUT/qwen-logs.txt $OUT/z-image-logs.txt $OUT/klein-logs.txt && (( $(logged "requeueing") == 0 ))'
check "5b. the sampled sum of the workers' phys_footprint stayed under the budget" py "
peak = max((int(l.split()[1]), l) for l in open('$OUT/footprint-samples.txt') if len(l.split()) >= 2)
print('peak', round(peak[0] / 1e9, 2), 'GB at', peak[1].strip()); assert peak[0] < $BUDGET"
check "5c. each ledger: what the workers report is what the host reads" py "
import json
for n in range(1, 8):
    for w in json.load(open(f'$OUT/ledger-{n}.json'))['workers']:
        host, own = w.get('physFootprintBytes'), w.get('reportedFootprintBytes')
        print(n, w['pluginID'].split('.')[-1], 'host', round((host or 0) / 1e9, 2), 'worker', round((own or 0) / 1e9, 2), 'charged', round(w['chargedBytes'] / 1e9, 2), 'declared', round(w['declaredBytes'] / 1e9, 2))
        assert host and own and abs(host - own) < max(host, own) * 0.1, w"
grep -F 'scheduler:' "$H.out" > "$OUT/scheduler.log"
stop $P

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
