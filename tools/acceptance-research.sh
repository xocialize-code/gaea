#!/bin/zsh
# AB-T-0374's acceptance: the research image plugins installed in Gaea by repo URL, opt-in and named-only, each model
# run once by name, and each run compared byte for byte with the plugin's own in-process reference.
#
#   1. Gaea installs every research plugin from its GitHub release (REPO_FROM=github, anonymous) or from
#      tools/release-standin.py serving the local dist/ folders, plus gaea-plugin-flux2-klein as the default to show
#      that a request naming no model never reaches a research model;
#   2. /mes/v0/operations lists every research model as named_only and never default; the restricted ones (Qwen
#      Research, FLUX Kommunity) are off until the operator enables them (opt-in), and carry commercial_use false;
#   3. each research model runs one seeded job by name, through Gaea's normalizer and scheduler;
#   4. after Gaea stops, each plugin's <x>-inproc tool runs the same request in-process (the same lane, the same
#      input bytes), and the bundle Gaea installed, driven by gaea-plugin-check with the request Gaea sent its worker,
#      must give the same bytes; Gaea's own output, re-encoded by the normalizer, is compared by bytes and pixels;
#   5. the reference engine, pixel-agency-image-engine v0.9.1 with --allow-research on the same models root, runs the
#      same requests by name, and each is compared with Gaea's by bytes and pixels (reported, not counted);
#   6. every recorded GPP session passes the validator.
#
#   tools/acceptance-research.sh <short-work-dir> <evidence-dir> [family …]
#
# Families: mage-flow sensenova moss-image qwen-image-21 flux3-klein (default: all). MODELS_ROOT defaults to the
# research store on DEV_VOL1. Each family's in-process tool is ../gaea-plugin-<family>/.build/release/<x>-inproc.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}; shift 2
FAMILIES=(mage-flow sensenova moss-image qwen-image-21 flux3-klein); (( $# )) && FAMILIES=($@)
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
MODELS_ROOT=${MODELS_ROOT:-/Volumes/DEV_VOL1/Models/gaea-research-store}
DEV=/Volumes/Satechi/Development
# The reference engine; ENGINE= (empty) skips that comparison.
ENGINE=${ENGINE-$DEV/pixel-agency-image-engine/.claude/worktrees/parity-v0.9.1/.build/release/pixel-agency-image-engine}
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { # name, then a command whose exit status decides
  local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
job() { # port, json body → prints the settled job
  local id j; id=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id") or "")')
  [[ -z $id ]] && { print -r -- '{"state":"refused","outcome":"refused"}'; return }
  for _ in {1..180}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
fetch() { # port, job file, prefix → downloads the job's outputs as <prefix>-<i>.png
  local i=0
  for href in $(python3 -c "import json,sys; [print(o['href']) for o in json.load(open(sys.argv[1])).get('result', {}).get('outputs', [])]" "$2"); do
    mes -o "$3-$i.png" "http://127.0.0.1:$1$href"; i=$((i+1)); done
}
upload() { mes -X POST "http://127.0.0.1:$1/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @"$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["upload_id"])' }
start() { # home, port, extra args… → waits for the operator socket
  local home=$1 port=$2; shift 2
  GAEA_HOME=$home "$GAEA" --headless --port $port --no-advertise --models-root "$MODELS_ROOT" "$@" > "$home.out" 2>&1 &
  for _ in {1..50}; do [[ -S $home/operator.sock ]] && return; sleep 0.2; done
  say "Gaea at $home didn't start:"; cat "$home.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 2 }
py() { python3 -c "$1" }
same() { # two PNGs → passes when their bytes are identical
  py "import hashlib; a, b = (hashlib.sha256(open(f, 'rb').read()).hexdigest() for f in ('$1', '$2')); print(a, b); assert a == b"
}
quiet() { # waits until no other heavy GPU job runs on this shared Mac
  while pgrep -fl "gaeaplugin|Gaea --headless|pixel-agency-image-engine|-inproc|TierBench" | grep -v -e claude.app -e disclaimer -e "zsh -c" | grep -q .; do
    say "      waiting: another GPU job is running"; sleep 30; done
}

# Each family: its plugin repo, bundle name, inproc tool, and its jobs. A job is
#   <label> <model> <operation> <params json> <prompt> <input label or -> <inproc args…>
# where the input label names an earlier job's first output (uploaded as the edit's image).
typeset -A REPO BUNDLE INPROC
REPO[mage-flow]=gaea-plugin-mage-flow; BUNDLE[mage-flow]=mage-flow; INPROC[mage-flow]=mage-inproc
REPO[sensenova]=gaea-plugin-sensenova; BUNDLE[sensenova]=sensenova; INPROC[sensenova]=sensenova-inproc
REPO[moss-image]=gaea-plugin-moss-image; BUNDLE[moss-image]=moss-image; INPROC[moss-image]=moss-inproc
REPO[qwen-image-21]=gaea-plugin-qwen-image-21; BUNDLE[qwen-image-21]=qwen-image-21; INPROC[qwen-image-21]=qwen21-inproc
REPO[flux3-klein]=gaea-plugin-flux3-klein; BUNDLE[flux3-klein]=flux3-klein; INPROC[flux3-klein]=flux3-inproc
JOBS=$OUT/jobs.tsv
[[ -f ${JOBS_FILE:-tools/acceptance-research.jobs} ]] || { say "no jobs file"; exit 1 }

VERSION() { py "import json; print(json.load(open('$DEV/${REPO[$1]}/dist/manifest.json'))['version'])" }
say "# Research plugins acceptance (AB-T-0374) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion); models root $MODELS_ROOT"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  for f in $FAMILIES flux2-klein; do
    repo=${REPO[$f]:-gaea-plugin-$f}; name=${BUNDLE[$f]:-$f}
    v=$(py "import json; print(json.load(open('$DEV/$repo/dist/manifest.json'))['version'])")
    REL=$WORK/standin/xocialize/$repo/v$v; mkdir -p "$REL"
    cp "$DEV/$repo/dist/$name-$v.gaeaplugin.zip" "$DEV/$repo/dist/$name-$v.gaeaplugin.zip.sha256" "$DEV/$repo/dist/manifest.json" "$REL/"
  done
  python3 tools/release-standin.py "$WORK/standin" --moved xocialize=xocialize-code --port 8771 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8771
fi

quiet
H=$WORK/main; P=17680
start $H $P
export GAEA_HOME=$H
check "add gaea-plugin-flux2-klein (the default image.generate)" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-flux2-klein | grep -q 'Installed'"
for f in $FAMILIES; do
  check "add ${REPO[$f]} by repo URL" zsh -c "$CLI plugins add https://github.com/xocialize/${REPO[$f]} | tee -a $LOG | grep -q 'Installed'"
done
$CLI models > "$OUT/models-before.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations-before.json"

# The restricted models are opt-in: off until enabled, then on and still named-only.
for id in $(py "
import re; [print(l.split()[1]) for l in open('$OUT/models-before.txt') if l.startswith('off')]"); do
  say "      opt-in: $id is off until enabled"
  $CLI models enable $id >> "$LOG" 2>&1
done
$CLI models > "$OUT/models.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
RESEARCH=$(py "
import json; ids = set()
for line in open('tools/acceptance-research.jobs'):
    p = line.rstrip('\n').split('\t')
    if len(p) > 2 and p[0] in '$FAMILIES'.split(): ids.add(p[2])
print(' '.join(sorted(ids)))")
check "every research model is listed named_only and never default" py "
import json; ops = json.load(open('$OUT/operations.json'))['operations']; want = set('$RESEARCH'.split()); seen = set()
for o in ops:
    for m in o['models']:
        if m['id'] in want:
            seen.add(m['id']); assert m.get('named_only') is True and not m.get('default'), (o['operation'], m)
assert want <= seen, want - seen; print(sorted(seen))"
check "restricted models were off (opt-in), and say commercial_use false" py "
import json; before = open('$OUT/models-before.txt').read(); ops = json.load(open('$OUT/operations.json'))['operations']
lic = {m['id']: m['license'] for o in ops for m in o['models']}
for id in [i for i in '$RESEARCH'.split() if i.startswith(('qwen-image-2.1', 'flux-3'))]:
    assert ('off ' + id) in before, id; assert lic[id].get('commercial_use') is False, (id, lic[id])
print({k: v.get('spdx') for k, v in lic.items() if k in '$RESEARCH'.split()})"

job $P '{"operation":"image.generate","inputs":{"prompt":"a lighthouse on a rocky coast at dusk, photorealistic"},"params":{"size":{"width":512,"height":512},"seed":42}}' > "$OUT/job-default.json"
check "image.generate naming no model reaches FLUX.2 Klein, not a research model" py "
import json; j = json.load(open('$OUT/job-default.json')); r = j['result']; m = r['provenance']['model']['id']
p = j['plan']['effective']['model_params']['x-gaea.worker']['plugin']; print(m, p)
assert p == 'com.xocialize.gaea.flux2-klein' and m not in '$RESEARCH'.split()"

typeset -A FIRST
while IFS=$'\t' read -r fam label model op params prompt input rest; do
  [[ -z $fam || $fam == \#* ]] && continue
  (( ${FAMILIES[(Ie)$fam]} )) || continue
  inputs='"prompt":'$(py "import json; print(json.dumps('''$prompt'''))")
  [[ $op == image.edit ]] && inputs='"instruction":'$(py "import json; print(json.dumps('''$prompt'''))")',"images":[{"upload":"'$(upload $P "$OUT/gaea-$input-0.png")'"}]'
  body='{"operation":"'$op'","model":"'$model'","inputs":{'$inputs'},"params":'$params'}'
  t0=$(py 'import time; print(time.time())')
  job $P "$body" > "$OUT/job-$label.json"
  secs=$(py "import time; print(round(time.time()-$t0,2))")
  fetch $P "$OUT/job-$label.json" "$OUT/gaea-$label"
  check "$label: $model runs by name ($op), ${secs} s submit to settled" py "
import json; j = json.load(open('$OUT/job-$label.json')); r = j.get('result') or {}
assert j.get('outcome') == 'succeeded', json.dumps(j)[:800]
assert r['provenance']['model']['id'] == '$model', r['provenance']; w = j['plan']['effective']['model_params']['x-gaea.worker']
print(w.get('lane'), w.get('seconds'), r['outputs'][0]['width'], r['outputs'][0]['height'], r['outputs'][0]['sha256'][:16])"
done < tools/acceptance-research.jobs
$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side, after Gaea has stopped: the same requests, the same lanes, the same input bytes.
#   - the plugin's own bytes: the bundle Gaea installed from GitHub, driven by gaea-plugin-check with the request the
#     worker got from Gaea, against <x>-inproc. This is the acceptance;
#   - Gaea's output, which the image normalizer re-encodes (an RGB PNG comes back RGBA, alpha is handled), compared by
#     bytes and by decoded pixels: reported, not counted.
# Each plugin repo's gaea-plugin-check, built by its scripts/check-plugin.sh from the kit it resolved (0.3.0).
xcrun swiftc -O tools/png-pixels.swift -o $WORK/png-pixels 2>> "$LOG"
pixels() { $WORK/png-pixels "$1" "$2" 2>&1 }
while IFS=$'\t' read -r fam label model op params prompt input rest; do
  [[ -z $fam || $fam == \#* ]] && continue
  (( ${FAMILIES[(Ie)$fam]} )) || continue
  [[ -f $OUT/gaea-$label-0.png ]] || { say "SKIP  $label: no Gaea output to compare"; continue }
  extra=(${(z)rest}); [[ $input != - ]] && extra+=(--image "$OUT/gaea-$input-0.png")
  quiet
  "$DEV/${REPO[$fam]}/.build/release/${INPROC[$fam]}" --model $model --prompt "$prompt" --models-root "$MODELS_ROOT" --runs 1 \
    --out "$OUT/inproc-$label.png" $extra > "$OUT/inproc-$label.json" 2>> "$LOG" < /dev/null
  # The worker's request as Gaea sent it: its params and model_params, its lane, its seed.
  wargs=("${(@f)$(py "
import json; j = json.load(open('$OUT/job-$label.json')); w = j['plan']['effective']['model_params']['x-gaea.worker']
e = w['effective']; p = {k: v for k, v in e.items() if not k.startswith('x-') and k != 'seed'}; m = {k: v for k, v in e.items() if k.startswith('x-')}
print(w['lane']); print(json.dumps(p)); print(json.dumps(m)); print(e['seed'])")}")
  bundle=($H/Plugins/*/*/${BUNDLE[$fam]}.gaeaplugin(N))
  text=$([[ $op == image.edit ]] && print instruction || print prompt)
  inputs=(); [[ $input != - ]] && inputs=(--input "images=$OUT/gaea-$input-0.png")
  "$DEV/${REPO[$fam]}/.build/release/gaea-plugin-check" $bundle[1] --operation $op --model $model --lane $wargs[1] --params $wargs[2] --model-params $wargs[3] \
    --seed $wargs[4] --text "$text=$prompt" $inputs --models-root "$MODELS_ROOT" --budget 100000000000 --timeout 1800 \
    > "$OUT/worker-$label.log" 2>&1 < /dev/null
  out=$(grep -o '"path":"[^"]*"' "$OUT/worker-$label.log" | head -1 | sed 's/"path":"//; s/"$//; s#\\/#/#g')
  [[ -f $out ]] && cp "$out" "$OUT/worker-$label.png"
  check "$label: $model, the installed plugin's output is byte for byte the in-process image" same "$OUT/worker-$label.png" "$OUT/inproc-$label.png"
  say "      Gaea's normalized output against in-process: $(cmp -s "$OUT/gaea-$label-0.png" "$OUT/inproc-$label.png" && print same bytes || print different bytes), $(pixels "$OUT/gaea-$label-0.png" "$OUT/inproc-$label.png")"
done < tools/acceptance-research.jobs

# The reference engine: pixel-agency-image-engine v0.9.1 with --allow-research on the same models root, the same MES
# requests by name, the same input bytes. Its catalog's defaults are the plugins' default lanes.
if [[ -x $ENGINE ]]; then
  quiet
  EP=17681; mkdir -p "$WORK/engine"
  "$ENGINE" --port $EP --no-advertise --allow-research --store "$MODELS_ROOT" --spool "$WORK/engine/spool" \
    --state "$WORK/engine/state" > "$WORK/engine.out" 2>&1 &
  ENGINE_PID=$!
  for _ in {1..100}; do mes -sf "http://127.0.0.1:$EP/mes/v0/operations" > /dev/null && break; sleep 0.3; done
  mes "http://127.0.0.1:$EP/mes/v0/operations" > "$OUT/engine-operations.json"
  while IFS=$'\t' read -r fam label model op params prompt input rest; do
    [[ -z $fam || $fam == \#* ]] && continue
    (( ${FAMILIES[(Ie)$fam]} )) || continue
    [[ -f $OUT/gaea-$label-0.png ]] || continue
    inputs='"prompt":'$(py "import json; print(json.dumps('''$prompt'''))")
    [[ $op == image.edit ]] && inputs='"instruction":'$(py "import json; print(json.dumps('''$prompt'''))")',"images":[{"upload":"'$(upload $EP "$OUT/gaea-$input-0.png")'"}]'
    job $EP '{"operation":"'$op'","model":"'$model'","inputs":{'$inputs'},"params":'$params'}' > "$OUT/engine-$label.json"
    fetch $EP "$OUT/engine-$label.json" "$OUT/engine-$label"
    if [[ -f $OUT/engine-$label-0.png ]]; then
      say "INFO  $label: $model through Gaea against v0.9.1: $(cmp -s "$OUT/gaea-$label-0.png" "$OUT/engine-$label-0.png" && print same bytes || print different bytes), $(pixels "$OUT/gaea-$label-0.png" "$OUT/engine-$label-0.png")"
    else
      say "INFO  $label: v0.9.1 returned no image ($(py "import json; j = json.load(open('$OUT/engine-$label.json')); print((j.get('error') or j)['message'] if 'error' in j else j.get('state'))" 2>/dev/null))"
    fi
  done < tools/acceptance-research.jobs
  kill $ENGINE_PID 2>/dev/null; wait $ENGINE_PID 2>/dev/null
fi

for s in $H/Logs/sessions/*.gpp(N); do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp(N) "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
