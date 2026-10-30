#!/bin/zsh
# AB-T-0390's acceptance: MES image.decompose (Image §3.2, RFC 0004) through Gaea, served by gaea-plugin-ming-image's
# ming-image-layer (Ming-Image 0.1 Design-Layer) installed by repo URL, on pixel-agency-normalizer's decompose route.
#
#   1. image.decompose is offered with ming-image-layer: layer_count up to 12, and composite among the outputs;
#   2. the 1024² poster into 4 layers with the composite: 4 straight-alpha PNGs at the input's size, front-most first,
#      effective.layer_count 4, and every file ming-inproc's pixel for pixel. The poster is one Gaea wrote
#      (poster-gaea-1024.png): the normalizer re-encodes every input, and only a PNG it wrote comes through byte for byte
#      (the worker's own PNG changes in 922 samples by 1, enough to move a decomposition);
#   3. the 1280×720 poster: every layer at 1280×720; a 3-layer plan without layer_count gives 3 layers; quality draft
#      runs the 512 bucket and still returns the input's size;
#   4. refusals: layer_count 13 (422 out_of_limits), a plan contradicting layer_count (400), outputs without layers (400);
#   5. an input with transparency: no layer is more opaque than the input anywhere;
#   6. every recorded GPP session passes the validator.
#
#   tools/acceptance-ming-layer.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); PLUGIN_DIST (default ../gaea-plugin-ming-image/dist); MING_INPROC
# (default ../gaea-plugin-ming-image/.build/release/ming-inproc).
# REPO_FROM=github installs the published release instead of serving the dist folder through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-ming-image/dist}
INPROC=${MING_INPROC:-../gaea-plugin-ming-image/.build/release/ming-inproc}
FIX=../gaea-plugin-ming-image/fixtures
PLAN='Decompose this image into 3 layers. Layer 1: the words \"BLUE NOTE NIGHTS\". Layer 2: the gold saxophone. Layer 3: the deep blue background.'
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
PIXDIFF=$WORK/pixdiff; swiftc -O -o $PIXDIFF ../gaea-plugin-ming-image/scripts/pixdiff.swift
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { # name, then a command whose exit status decides
  local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
job() { # port, json body → prints the settled job
  local id j; id=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  for _ in {1..120}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
submit() { # port, json body → the refusal, or the job as it stands after a short wait
  local r id; r=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2")
  id=$(print -r -- "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')
  [[ -n $id ]] && r=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=30")
  print -r -- "$r"
}
fetch() { # port, job file, dir → downloads the job's outputs as <dir>/<name>-<i>.png, i counting within each name
  mkdir -p "$3"
  python3 -c "
import json, sys, collections; n = collections.Counter()
for o in json.load(open(sys.argv[1]))['result']['outputs']: print(o['href'], o['name'], n[o['name']]); n[o['name']] += 1" "$2" |
    while read href name index; do mes -o "$3/$name-$index.png" "http://127.0.0.1:$1$href"; done
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
worker() { py "import json; print(json.load(open('$1'))['plan']['effective']['model_params']['x-gaea.worker']['seconds'])" }
elapsed() { py "import time; print(round(time.time()-$1,2))" }
now() { py 'import time; print(time.time())' }
outs() { py "import json; print([(o['name'], o['width'], o['height']) for o in json.load(open('$1'))['result']['outputs']])" }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# Ming-Image Design-Layer acceptance (AB-T-0390) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), ming-image $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-ming-image/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/ming-image-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/ming-image-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8773 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8773
fi

H=$WORK/main; P=17686
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs ming-image $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-ming-image | grep -q 'Installed .* $VERSION'"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.decompose is offered with ming-image-layer, layer_count up to 12, composite an output" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['image.decompose']; assert 'ming-image-layer' in [m['id'] for m in d['models']], d['models']
p = d['params']['properties']; assert p['layer_count']['maximum'] == 12, p['layer_count']
assert 'composite' in d['params']['properties']['outputs']['items']['enum'], p['outputs']"

# 2. The 1024² poster into 4 layers, with the composite: the in-process stack, file by file.
U=$(upload $P "$FIX/poster-gaea-1024.png")
t0=$(now)
job $P '{"operation":"image.decompose","model":"ming-image-layer","inputs":{"image":{"upload":"'$U'"}},"params":{"layer_count":4,"outputs":["layers","composite"],"seed":7}}' > "$OUT/job-4.json"
say "      4 layers at 1024: $(elapsed $t0) s from submit to settled (launch, prepare int8, decompose); worker run $(worker $OUT/job-4.json) s"
fetch $P "$OUT/job-4.json" "$OUT/gaea-4"
check "4 layers and the composite, each 1024², effective.layer_count 4" py "
import json; j = json.load(open('$OUT/job-4.json')); assert j['outcome'] == 'succeeded', j; r = j['result']
o = [(x['name'], x['width'], x['height']) for x in r['outputs']]
assert o == [('layers', 1024, 1024)] * 4 + [('composite', 1024, 1024)], o
assert r['effective']['layer_count'] == 4, r['effective']; assert r['provenance']['model']['id'] == 'ming-image-layer'"

# 3. Other sizes, a plan, draft.
U=$(upload $P "$FIX/poster-1280x720.png")
job $P '{"operation":"image.decompose","model":"ming-image-layer","inputs":{"image":{"upload":"'$U'"}},"params":{"layer_count":4,"seed":7}}' > "$OUT/job-wide.json"
say "      1280×720: worker drew $(py "import json; print(json.load(open('$OUT/job-wide.json'))['plan']['effective']['model_params']['x-gaea.worker']['effective'].get('size'))"); outputs $(outs $OUT/job-wide.json)"
check "the 1280×720 poster gives 4 layers at 1280×720, and no composite unless asked" py "
import json; j = json.load(open('$OUT/job-wide.json')); assert j['outcome'] == 'succeeded', j
assert [(x['name'], x['width'], x['height']) for x in j['result']['outputs']] == [('layers', 1280, 720)] * 4, j['result']['outputs']"
U=$(upload $P "$FIX/poster-1024.png")
job $P '{"operation":"image.decompose","model":"ming-image-layer","inputs":{"image":{"upload":"'$U'"},"prompt":"'$PLAN'"},"params":{"seed":7}}' > "$OUT/job-plan.json"
fetch $P "$OUT/job-plan.json" "$OUT/gaea-plan"
check "a 3-layer plan without layer_count gives 3 layers, effective.layer_count 3" py "
import json; j = json.load(open('$OUT/job-plan.json')); assert j['outcome'] == 'succeeded', j
assert len(j['result']['outputs']) == 3 and j['result']['effective']['layer_count'] == 3, j['result']"
U=$(upload $P "$FIX/poster-1024.png")
job $P '{"operation":"image.decompose","model":"ming-image-layer","inputs":{"image":{"upload":"'$U'"}},"params":{"layer_count":4,"quality":"draft","seed":7}}' > "$OUT/job-draft.json"
say "      draft: worker run $(worker $OUT/job-draft.json) s, drew $(py "import json; print(json.load(open('$OUT/job-draft.json'))['plan']['effective']['model_params']['x-gaea.worker']['effective'].get('size'))")"
check "quality draft runs the 512 bucket and returns the input's size" py "
import json; j = json.load(open('$OUT/job-draft.json')); assert j['outcome'] == 'succeeded', j
w = j['plan']['effective']['model_params']['x-gaea.worker']['effective']; assert w['resolution'] == 512, w
assert all((x['width'], x['height']) == (1024, 1024) for x in j['result']['outputs']), j['result']['outputs']"

# 4. Refusals, before anything runs.
U=$(upload $P "$FIX/poster-1024.png")
submit $P '{"operation":"image.decompose","model":"ming-image-layer","inputs":{"image":{"upload":"'$U'"}},"params":{"layer_count":13}}' > "$OUT/refuse-13.json"
check "layer_count 13 is 422 out_of_limits" py "
import json; r = json.load(open('$OUT/refuse-13.json')); e = r.get('error') or r; assert e.get('code') == 'out_of_limits', r"
submit $P '{"operation":"image.decompose","model":"ming-image-layer","inputs":{"image":{"upload":"'$U'"},"prompt":"'$PLAN'"},"params":{"layer_count":4}}' > "$OUT/refuse-contradiction.json"
check "a plan of 3 layers with layer_count 4 is 400 invalid_request" py "
import json; r = json.load(open('$OUT/refuse-contradiction.json')); e = r.get('error') or r; assert e.get('code') == 'invalid_request', r"
submit $P '{"operation":"image.decompose","model":"ming-image-layer","inputs":{"image":{"upload":"'$U'"}},"params":{"outputs":["composite"]}}' > "$OUT/refuse-outputs.json"
check "outputs without layers is 400" py "
import json; r = json.load(open('$OUT/refuse-outputs.json')); e = r.get('error') or r; assert e.get('code') == 'invalid_request', r"

# 5. An input with transparency (AB-T-0389's sticker): no layer is more opaque than the input.
U=$(upload $P "$FIX/sticker-alpha-1024.png")
job $P '{"operation":"image.decompose","model":"ming-image-layer","inputs":{"image":{"upload":"'$U'"}},"params":{"layer_count":2,"quality":"draft","seed":7}}' > "$OUT/job-alpha.json"
fetch $P "$OUT/job-alpha.json" "$OUT/gaea-alpha"
say "      transparent input: warnings $(py "import json; print([w['code'] for w in json.load(open('$OUT/job-alpha.json')).get('warnings', [])])")"
check "a transparent input's clear pixels stay clear in every layer" swift ../gaea-plugin-ming-image/scripts/alphacap.swift "$FIX/sticker-alpha-1024.png" $OUT/gaea-alpha/layers-*.png

$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side, after Gaea has stopped: the same request on the same lane.
"$INPROC" --decompose "$FIX/poster-gaea-1024.png" --lane int8 --layers 4 --seed 7 --once --out-dir "$OUT/inproc-4" 2>> "$LOG" | tail -1 > "$OUT/inproc-4.json"
for f in layers-0 layers-1 layers-2 layers-3 composite-0; do
  check "$f through Gaea is the in-process one, pixel for pixel" $PIXDIFF "$OUT/gaea-4/$f.png" "$OUT/inproc-4/$f.png"
done

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
