#!/bin/zsh
# AB-T-0363's acceptance: the scheduler's memory paths with real workers. gaea-plugin-z-image (int4, int8 and bf16
# lanes of 39.9, 43.0 and 48.5 GB) and the demo plugin (demo-matmul, 2.37 GB) under a 44 GB budget:
#
#   1. eviction: Turbo's default set to int8 by the operator (`gaea models lane`); with the demo's worker idle and
#      resident, int8 doesn't fit beside it, so the demo is stopped (LRU) and int8 runs; then the reverse, the idle
#      Z-Image worker stopped to admit the demo;
#   2. requeue once (SRV-8): the Z-Image worker SIGKILLed mid-run, the job completes on a relaunched worker with
#      `requeued: true` and the image a clean run gives;
#   3. lane fallback (G-23, MEM-7): Turbo's default set to bf16, which can't fit in 44 GB: a job without x-gaea.lane gets
#      int8 and a lane_fallback warning; one naming bf16 is refused no_capacity;
#   4. every recorded GPP session passes the validator.
#
#   tools/acceptance-scheduler.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); Z_DIST and DEMO_DIST (the plugins' dist/, default ../gaea-plugin-*/dist).
# REPO_FROM=github installs the published releases instead of serving the dist folders through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
Z_DIST=${Z_DIST:-../gaea-plugin-z-image/dist}
DEMO_DIST=${DEMO_DIST:-../gaea-plugin-demo/dist}
Z=com.xocialize.gaea.z-image; DEMO=com.xocialize.gaea.demo
BUDGET=44000000000
PROMPT="A lighthouse on a rocky coast at dusk, photorealistic, 35mm film"
TURBO='{"operation":"image.generate","model":"z-image-turbo","inputs":{"prompt":"'$PROMPT'"},"params":{"size":{"width":1024,"height":1024},"seed":42}'
MATMUL='{"operation":"image.generate","model":"demo-matmul","inputs":{"prompt":"mocked"},"extensions":{"x-gaea.demo_matmul":{"n":1024,"iterations":3}}}'
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { # name, then a command whose exit status decides
  local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
submit() { mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' }
settle() { # port, job id → prints the settled job
  local j
  for _ in {1..60}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$2?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
job() { settle $1 "$(submit $1 "$2")" }
start() { # home, port, extra args… → waits for the operator socket
  local home=$1 port=$2; shift 2
  GAEA_HOME=$home "$GAEA" --headless --port $port --no-advertise "$@" > "$home.out" 2>&1 &
  for _ in {1..50}; do [[ -S $home/operator.sock ]] && return; sleep 0.2; done
  say "Gaea at $home didn't start:"; cat "$home.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
workers() { $CLI ledger --json | py "import json,sys; print(' '.join(sorted(w['pluginID'] for w in json.load(sys.stdin)['workers'])))" }
zpid() { $CLI ledger --json | py "import json,sys; print(next((w['pid'] for w in json.load(sys.stdin)['workers'] if w['pluginID'] == '$Z'), ''))" }
logged() { grep -c -F -- "$1" "$H.out" }
ok() { eval "$1" } # a check written with this script's own functions

ZV=$(py "import json; print(json.load(open('$Z_DIST/manifest.json'))['version'])")
DV=$(py "import json; print(json.load(open('$DEMO_DIST/manifest.json'))['version'])")
say "# Scheduler acceptance (AB-T-0363) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), z-image $ZV, demo $DV, budget $BUDGET, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  for name dist version in z-image $Z_DIST $ZV demo $DEMO_DIST $DV; do
    REL=$WORK/standin/xocialize/gaea-plugin-$name/v$version; mkdir -p "$REL"
    cp "$dist/$name-$version.gaeaplugin.zip" "$dist/$name-$version.gaeaplugin.zip.sha256" "$dist/manifest.json" "$REL/"
  done
  python3 tools/release-standin.py "$WORK/standin" --port 8769 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8769
fi

H=$WORK/main; P=17660
start $H $P --budget-bytes $BUDGET
export GAEA_HOME=$H
check "add z-image $ZV and demo $DV by repo URL" zsh -c "$CLI plugins add https://github.com/xocialize/gaea-plugin-z-image | grep -q 'Installed .* $ZV' && $CLI plugins add https://github.com/xocialize/gaea-plugin-demo | grep -q 'Installed .* $DV'"
$CLI status > "$OUT/status.txt"
check "the budget is 44 GB" grep -q '44.00 GB' "$OUT/status.txt"

# 1. Eviction, both ways.
check "the operator sets Turbo's default lane to int8" zsh -c "$CLI models lane z-image-turbo int8 && $CLI models lane z-image-turbo | grep -q 'int8 (set by the operator)'"
job $P "$MATMUL" > "$OUT/job-demo-1.json"
check "demo-matmul runs, and the demo's worker stays resident and idle" ok 'grep -q "\"outcome\":\"succeeded\"" $OUT/job-demo-1.json && [[ $(workers) == $DEMO ]]'
$CLI ledger > "$OUT/ledger-1-demo.txt"
job $P "$TURBO}" > "$OUT/job-evict.json"
$CLI ledger > "$OUT/ledger-2-turbo.txt"
check "int8 (43.0 GB) doesn't fit beside the demo (2.37 GB): the demo is stopped and int8 runs" py "
import json; j = json.load(open('$OUT/job-evict.json')); w = j['plan']['effective']['model_params']['x-gaea.worker']
assert j['outcome'] == 'succeeded' and w['lane'] == 'int8', w; assert not any(x['code'] == 'lane_fallback' for x in j.get('warnings', [])), j.get('warnings')"
check "…the log says why, and only Z-Image's worker is left" ok '(( $(logged "evicting $DEMO to make room for z-image-turbo int8") == 1 )) && [[ $(workers) == $Z ]]'
job $P "$MATMUL" > "$OUT/job-demo-2.json"
check "the reverse: the idle Z-Image worker (43.0 GB charged) is stopped to admit demo-matmul" ok 'grep -q "\"outcome\":\"succeeded\"" $OUT/job-demo-2.json && (( $(logged "evicting $Z to make room for demo-matmul fp32") == 1 )) && [[ $(workers) == $DEMO ]]'

# 2. Requeue once: SIGKILL the worker while it generates.
ID=$(submit $P "$TURBO}")
pid=""; seen=""
for _ in {1..240}; do
  seen=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$ID" | py "import json,sys; j = json.load(sys.stdin); p = j.get('progress') or {}; print(p.get('fraction') or 0)")
  if py "import sys; sys.exit(0 if 0.15 < $seen < 0.85 else 1)"; then pid=$(zpid); break; fi
  sleep 0.25
done
[[ -n $pid ]] && kill -KILL $pid
say "      killed Z-Image's worker, pid ${pid:-none}, at progress $seen"
settle $P $ID > "$OUT/job-requeued.json"
$CLI plugins logs $Z -n 40 > "$OUT/z-image-logs.txt"
check "the job completes on a relaunched worker, with requeued: true" py "
import json; j = json.load(open('$OUT/job-requeued.json')); w = j['plan']['effective']['model_params']['x-gaea.worker']
assert j['outcome'] == 'succeeded' and w.get('requeued') is True and w['lane'] == 'int8', (j['outcome'], w)"
check "…on a new process, with worker_died recorded" ok '[[ -n $pid && $(zpid) != $pid && -n $(zpid) ]] && grep -q worker_died $OUT/z-image-logs.txt && (( $(logged "requeueing once") == 1 ))'
check "…and the image is the one the clean int8 run gave" py "
import json; a, b = (json.load(open(f))['result']['outputs'][0]['sha256'] for f in ('$OUT/job-evict.json', '$OUT/job-requeued.json')); assert a == b, (a, b)"

# 3. Lane fallback, and a named lane that never falls back.
check "the operator sets Turbo's default lane to bf16 (48.5 GB, more than the budget)" zsh -c "$CLI models lane z-image-turbo bf16 | grep -q 'bf16 (set by the operator)'"
job $P "$TURBO}" > "$OUT/job-fallback.json"
check "without x-gaea.lane: int8 runs, with a lane_fallback warning naming both lanes" py "
import json; j = json.load(open('$OUT/job-fallback.json')); w = j['plan']['effective']['model_params']['x-gaea.worker']
assert j['outcome'] == 'succeeded' and w['lane'] == 'int8', w
f = [x for x in j.get('warnings', []) if x['code'] == 'lane_fallback']; assert len(f) == 1 and 'bf16' in f[0]['message'] and 'int8' in f[0]['message'], j.get('warnings')
print(f[0])"
job $P "$TURBO"',"extensions":{"x-gaea.lane":"bf16"}}' > "$OUT/job-named-bf16.json"
check "x-gaea.lane bf16 is refused no_capacity, not fallen back" py "
import json; j = json.load(open('$OUT/job-named-bf16.json')); e = j.get('error') or {}
assert j['outcome'] == 'failed' and e.get('code') == 'no_capacity', j; print(e)"
check "the operator's default goes back to the manifest's int4" zsh -c "$CLI models lane z-image-turbo default | grep -q \"int4 (the manifest's default)\""
$CLI models > "$OUT/models.txt"
$CLI ledger > "$OUT/ledger-3-end.txt"
grep -F 'scheduler:' "$H.out" > "$OUT/scheduler.log"
stop $P

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
check "the killed worker's transcript ends at its exit, signal 9" ok 'grep -l -x "# exited: signal 9" $H/Logs/sessions/*.gpp | wc -l | grep -q -w 1'
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
