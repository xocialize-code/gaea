#!/bin/zsh
# AB-T-0369's acceptance through Gaea: gaea-plugin-forge installed by repo URL from its GitHub release, and every model
# it serves run by name through Gaea's image normalizer (AB-T-0366) as an MES job:
#
#   1. Gaea installs the pack; fill, erase, extend, upscale, matte, segment and restore are offered, each defaulting to
#      the model the normalizer's table prefers;
#   2. every model runs: LaMa and MI-GAN (fill, draft), NERVE ×2, RealPLKSR ×4 and HEART ×4 (exactly input × scale),
#      BiRefNet (an 8-bit grey mask), EdgeTAM and SAM 2.1 (at a point), NAFNet, Restormer ×3, SCUNet, GFPGAN and
#      RestoreFormer++ (restore, the input's size), and restore `kind: faces` picks GFPGAN;
#   3. the worker's footprint with one model loaded, then with all fourteen; no worker died;
#   4. every recorded GPP session passes the validator.
#
#   tools/acceptance-forge.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); FIXTURES (default ../gaea-plugin-forge/scripts/fixtures); network access.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
FIX=${FIXTURES:-../gaea-plugin-forge/scripts/fixtures}
F=com.xocialize.gaea.forge
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
  local id j; id=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id") or d)')
  for _ in {1..60}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' 2>/dev/null && { print -r -- "$j"; return }
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
# name, json body → runs it, keeps the job; then checks it succeeded on the named model with outputs of the given size
run() {
  local name=$1 body=$2 model=$3 w=$4 h=$5
  job $P "$body" > "$OUT/job-$name.json"
  check "$name: $model, ${w}×${h}" py "
import json; j = json.load(open('$OUT/job-$name.json')); r = j.get('result') or {}
assert j['outcome'] == 'succeeded', (j.get('outcome'), j.get('error')); assert r['provenance']['model']['id'] == '$model', r['provenance']
o = r['outputs'][0]; assert (o['width'], o['height']) == ($w, $h), o
w = (r['effective'].get('model_params') or {}).get('x-gaea.worker', {}); print(w.get('lane'), w.get('seconds'), [x['code'] for x in j.get('warnings', [])])"
}

say "# Forge pack acceptance (AB-T-0369) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/main; P=17730
start $H $P
export GAEA_HOME=$H
check "add the pack by repo URL" zsh -c "$CLI plugins add https://github.com/xocialize/gaea-plugin-forge | grep -q 'Installed .*0.1'"
$CLI models > "$OUT/models.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "fill, erase, extend, upscale, matte, segment and restore are offered, with the table's defaults" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = {op: next(m['id'] for m in o['models'] if m.get('default')) for op, o in ops.items()}; print(d)
assert d == {'image.fill': 'lama-inpaint', 'image.erase': 'lama-inpaint', 'image.extend': 'lama-inpaint', 'image.upscale': 'realplksr-upscale',
             'image.matte': 'birefnet-matte', 'image.segment': 'sam21-segment', 'image.restore': 'nafnet-restore'}, d"

FOX=$FIX/fox-256.png; MASK=$FIX/mask-256.png; FACE=$FIX/face-512.png
img() { print -r -- "{\"upload\":\"$(upload $P $1)\"}" }
run nafnet '{"operation":"image.restore","model":"nafnet-restore","inputs":{"image":'$(img $FOX)'}}' nafnet-restore 256 256
$CLI ledger > "$OUT/ledger-one.txt"; $CLI ledger --json > "$OUT/ledger-one.json"
run lama '{"operation":"image.fill","model":"lama-inpaint","inputs":{"image":'$(img $FOX)',"mask":'$(img $MASK)'}}' lama-inpaint 256 256
run migan '{"operation":"image.fill","model":"lama-inpaint","inputs":{"image":'$(img $FOX)',"mask":'$(img $MASK)'},"params":{"quality":"draft"}}' lama-inpaint 256 256
check "…draft runs MI-GAN, LaMa's fast mode" py "
import json; w = json.load(open('$OUT/job-migan.json'))['result']['effective']['model_params']['x-gaea.worker']; print(w['effective']); assert w['effective']['mode'] == 'fast', w"
run nerve '{"operation":"image.upscale","model":"nerve-upscale","inputs":{"image":'$(img $FOX)'},"params":{"scale":2}}' nerve-upscale 512 512
run realplksr '{"operation":"image.upscale","model":"realplksr-upscale","inputs":{"image":'$(img $FOX)'},"params":{"scale":4}}' realplksr-upscale 1024 1024
run heart '{"operation":"image.upscale","model":"heart-upscale","inputs":{"image":'$(img $FOX)'},"params":{"scale":4}}' heart-upscale 1024 1024
run birefnet '{"operation":"image.matte","model":"birefnet-matte","inputs":{"image":'$(img $FOX)'}}' birefnet-matte 256 256
POINT='{"data":[{"x":0.58,"y":0.47,"label":"include"}]}'
run edgetam '{"operation":"image.segment","model":"edgetam-segment","inputs":{"image":'$(img $FOX)',"points":'$POINT'}}' edgetam-segment 256 256
run sam21 '{"operation":"image.segment","model":"sam21-segment","inputs":{"image":'$(img $FOX)',"points":'$POINT'}}' sam21-segment 256 256
for m in restormer-motion restormer-defocus restormer-denoise scunet-denoise; do
  run $m '{"operation":"image.restore","model":"'$m'","inputs":{"image":'$(img $FOX)'}}' $m 256 256
done
for m in gfpgan-face restoreformer-face; do
  run $m '{"operation":"image.restore","model":"'$m'","inputs":{"image":'$(img $FACE)'}}' $m 512 512
done
job $P '{"operation":"image.restore","inputs":{"image":'$(img $FACE)'},"params":{"kind":"faces"}}' > "$OUT/job-faces.json"
check "restore kind faces with no model picks GFPGAN" py "
import json; j = json.load(open('$OUT/job-faces.json')); assert j['outcome'] == 'succeeded' and j['result']['provenance']['model']['id'] == 'gfpgan-face', j.get('result', j)"
$CLI ledger > "$OUT/ledger-all.txt"; $CLI ledger --json > "$OUT/ledger-all.json"
check "one worker holds all fourteen models' lanes" py "
import json; w = json.load(open('$OUT/ledger-all.json'))['workers']; assert len(w) == 1 and len(w[0]['lanes']) == 14, [(x['pluginID'], x['lanes']) for x in w]
print('all loaded: phys', round(w[0]['physFootprintBytes'] / 1e9, 2), 'GB, declared', round(w[0]['declaredBytes'] / 1e9, 2), 'GB')"
$CLI plugins logs $F -n 20 > "$OUT/forge-logs.txt"
check "no worker died" zsh -c "! grep -q worker_died $OUT/forge-logs.txt && ! grep -q 'requeueing' $H.out"
grep -F 'scheduler:' "$H.out" > "$OUT/scheduler.log"
stop $P

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
