#!/bin/zsh
# AB-T-0387's acceptance: gaea-plugin-boogu installed in Gaea by repo URL and run through MES.
#
#   1. Gaea installs and enables the plugin beside Z-Image: image.generate offers Boogu and Boogu Turbo, image.edit
#      offers Boogu Edit for one image, and none of them is a default, so a request naming no model still reaches
#      Z-Image Turbo (the normalizer's default routes don't change);
#   2. through Gaea, for fixed seeds, the same image as boogu-image-swift in-process (boogu-inproc, the plugin repo's
#      reference tool on the same dependency resolution), compared pixel for pixel (Gaea re-encodes the PNG): Boogu bf16 generate at 1024² with
#      its 30 steps, CFG and a negative prompt; Boogu Turbo int8; an edit drawn at the package's 768²; and the int4
#      lane on a snapped size;
#   3. count 2 gives two seeds; Turbo reports a negative prompt as ignored; a named lane runs that lane; an edit asking
#      more than 1024² is drawn at 1024² and says so; a 400² request is drawn at 512² and returned at 400²; two images
#      on an edit are refused;
#   4. every recorded GPP session passes the validator.
#
#   tools/acceptance-boogu.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); PLUGIN_DIST (default ../gaea-plugin-boogu/dist); ZIMAGE_DIST (default
# ../gaea-plugin-z-image/dist); BOOGU_INPROC (default ../gaea-plugin-boogu/.build/release/boogu-inproc). REPO_FROM=github
# installs the published releases instead of serving the dist folders through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-boogu/dist}
ZIMAGE_DIST=${ZIMAGE_DIST:-../gaea-plugin-z-image/dist}
INPROC=${BOOGU_INPROC:-../gaea-plugin-boogu/.build/release/boogu-inproc}
PLUGIN_MANIFEST=$PLUGIN_DIST/manifest.json
HOUSE="a lighthouse on a rocky coast at dusk, warm light in the windows, photorealistic"
NEGATIVE="blurry, oversaturated"
BIKE="a red bicycle leaning against a brick wall, morning light, photorealistic"
EDIT="make it night with falling snow"
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
PIXDIFF=$WORK/pixdiff; swiftc -O -o $PIXDIFF ../gaea-plugin-boogu/scripts/pixdiff.swift
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
  for _ in {1..90}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
submit() { # port, json body → prints the job as it stands after a short wait, or the refusal
  local r id; r=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2")
  id=$(print -r -- "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')
  [[ -n $id ]] && r=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=30")
  print -r -- "$r"
}
fetch() { # port, job file, prefix → downloads the job's outputs as <prefix>-<i>.png
  local i=0
  for href in $(python3 -c "import json,sys; [print(o['href']) for o in json.load(open(sys.argv[1]))['result']['outputs']]" "$2"); do
    mes -o "$3-$i.png" "http://127.0.0.1:$1$href"; i=$((i+1)); done
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
same() { # two PNGs → passes when their bytes are identical, or else their pixels (the normalizer re-encodes Boogu's RGBX PNGs)
  py "import hashlib; a, b = (hashlib.sha256(open(f, 'rb').read()).hexdigest() for f in ('$1', '$2')); print(a, b); exit(0 if a == b else 1)" && return
  "$PIXDIFF" "$1" "$2"
}
worker() { py "import json; print(json.load(open('$1'))['plan']['effective']['model_params']['x-gaea.worker']['seconds'])" }
elapsed() { py "import time; print(round(time.time()-$1,2))" }
now() { py 'import time; print(time.time())' }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
ZVERSION=$(py "import json; print(json.load(open('$ZIMAGE_DIST/manifest.json'))['version'])")
say "# Boogu plugin acceptance (AB-T-0387) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), boogu $VERSION, z-image $ZVERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  for pair in "boogu:$PLUGIN_DIST:$VERSION" "z-image:$ZIMAGE_DIST:$ZVERSION"; do
    name=${pair%%:*}; rest=${pair#*:}; dist=${rest%:*}; v=${rest##*:}
    REL=$WORK/standin/xocialize-code/gaea-plugin-$name/v$v; mkdir -p "$REL"
    cp "$dist/$name-$v.gaeaplugin.zip" "$dist/$name-$v.gaeaplugin.zip.sha256" "$dist/manifest.json" "$REL/"
  done
  python3 tools/release-standin.py "$WORK/standin" --moved xocialize=xocialize-code --port 8771 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8771
fi

H=$WORK/main; P=17680
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs boogu $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-boogu | grep -q 'Installed .* $VERSION'"
check "add by repo URL installs z-image $ZVERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-z-image | grep -q 'Installed .* $ZVERSION'"
$CLI models > "$OUT/models.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.generate offers Boogu and Boogu Turbo, neither a default" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.generate']['models']}
assert 'boogu' in m and 'boogu-turbo' in m, sorted(m); assert not m['boogu'].get('default') and not m['boogu-turbo'].get('default'), m"
check "image.edit offers Boogu Edit; the plugin's manifest marks no offer default" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.edit']['models']}; assert 'boogu-edit' in m, m
d = [x['id'] for x in ops['image.edit']['models'] if x.get('default')]; print('image.edit answers an unnamed request with', d)
assert not any(o['model'].get('default') for o in json.load(open('$PLUGIN_MANIFEST'))['offers'])"
say "      image.edit's default here: $(py "import json; print([x['id'] for o in json.load(open('$OUT/operations.json'))['operations'] if o['operation'] == 'image.edit' for x in o['models'] if x.get('default')])") (FLUX.2 Klein, the normalizer's first choice, isn't installed on this server)"

# 1. A request naming no model still reaches Z-Image Turbo.
job $P '{"operation":"image.generate","inputs":{"prompt":"'$HOUSE'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}' > "$OUT/job-unnamed.json"
check "image.generate naming no model still reaches Z-Image Turbo" py "
import json; j = json.load(open('$OUT/job-unnamed.json')); assert j['outcome'] == 'succeeded', j
assert j['result']['provenance']['model']['id'] == 'z-image-turbo', j['result']['provenance']"

# 2. Generate on Boogu at its defaults (bf16, 30 steps, CFG 3.5), with a negative prompt.
BODY='{"operation":"image.generate","model":"boogu","inputs":{"prompt":"'$HOUSE'"},"params":{"size":{"width":1024,"height":1024},"seed":42,"negative_prompt":"'$NEGATIVE'"}}'
t0=$(now); job $P "$BODY" > "$OUT/job-boogu-cold.json"
say "      cold: $(elapsed $t0) s from submit to settled (launch, prepare bf16, 30 steps)"
t0=$(now); job $P "$BODY" > "$OUT/job-boogu-warm.json"
say "      warm: $(elapsed $t0) s from submit to settled; worker run $(worker $OUT/job-boogu-warm.json) s"
fetch $P "$OUT/job-boogu-cold.json" "$OUT/gaea-boogu"
check "Boogu bf16 1024² seed 42: one 1024² PNG, 30 steps, guidance 3.5, the negative prompt honoured" py "
import json; j = json.load(open('$OUT/job-boogu-cold.json')); r = j['result']; o = r['outputs']; e = r['effective']
assert j['outcome'] == 'succeeded' and len(o) == 1 and o[0]['width'] == 1024 and o[0]['height'] == 1024, j
assert r['provenance']['model']['id'] == 'boogu' and e['x-boogu.steps'] == 30 and e['x-boogu.guidance'] == 3.5, r
assert e['negative_prompt'] == '$NEGATIVE', e; assert j['plan']['effective']['model_params']['x-gaea.worker']['lane'] == 'bf16'"
check "a warm run gives the same bytes again" py "
import json; a, b = (json.load(open(f))['result']['outputs'][0]['sha256'] for f in ('$OUT/job-boogu-cold.json', '$OUT/job-boogu-warm.json')); assert a == b, (a, b)"

# Turbo on its int8 lane: count 2 at 768², and the negative prompt it ignores.
t0=$(now)
job $P '{"operation":"image.generate","model":"boogu-turbo","inputs":{"prompt":"'$BIKE'"},"params":{"size":{"width":768,"height":768},"count":2,"seed":7,"negative_prompt":"fog"},"extensions":{"x-gaea.lane":"int8"}}' > "$OUT/job-turbo.json"
say "      turbo: $(elapsed $t0) s from submit to settled (launch Turbo, prepare int8, two images)"
fetch $P "$OUT/job-turbo.json" "$OUT/gaea-turbo"
check "Boogu Turbo int8: count 2 gives two different 768² images, 4 steps, seeds 7 and 8" py "
import json; j = json.load(open('$OUT/job-turbo.json')); o = j['result']['outputs']
assert len(o) == 2 and o[0]['sha256'] != o[1]['sha256'] and all(x['width'] == 768 and x['height'] == 768 for x in o), o
assert j['result']['effective']['x-boogu.steps'] == 4, j['result']['effective']
assert j['plan']['effective']['model_params']['x-gaea.worker']['lane'] == 'int8'"
check "Boogu Turbo reports the negative prompt as ignored" py "
import json; w = json.load(open('$OUT/job-turbo.json')).get('warnings', []); assert any(x['code'] == 'negative_prompt_ignored' for x in w), w"

# Edit the first Turbo image (768², the size the package draws an edit at when none is asked, so nothing is resized).
U1=$(upload $P "$OUT/gaea-turbo-0.png")
t0=$(now)
job $P '{"operation":"image.edit","model":"boogu-edit","inputs":{"images":[{"upload":"'$U1'"}],"instruction":"'$EDIT'"},"params":{"seed":7}}' > "$OUT/job-edit.json"
say "      edit: $(elapsed $t0) s from submit to settled (launch Edit, prepare bf16, 50 steps); worker run $(worker $OUT/job-edit.json) s"
fetch $P "$OUT/job-edit.json" "$OUT/gaea-edit"
check "Boogu Edit bf16: one 768² image, 50 steps, guidance 4" py "
import json; j = json.load(open('$OUT/job-edit.json')); r = j['result']
assert j['outcome'] == 'succeeded', j; assert r['provenance']['model']['id'] == 'boogu-edit', r['provenance']
assert r['outputs'][0]['width'] == 768 and r['outputs'][0]['height'] == 768, r['outputs']
assert r['effective']['x-boogu.steps'] == 50 and r['effective']['x-boogu.guidance'] == 4, r['effective']"

# 3. Lanes and limits.
job $P '{"operation":"image.generate","model":"boogu","inputs":{"prompt":"'$HOUSE'"},"params":{"size":{"width":1000,"height":1000},"seed":42},"extensions":{"x-gaea.lane":"int4","x-boogu.steps":8}}' > "$OUT/job-int4.json"
fetch $P "$OUT/job-int4.json" "$OUT/gaea-int4"
check "x-gaea.lane int4 runs lane int4, and 1000² snaps to 992²" py "
import json; j = json.load(open('$OUT/job-int4.json')); w = j['plan']['effective']['model_params']['x-gaea.worker']
assert w['lane'] == 'int4', w; assert j['result']['outputs'][0]['width'] == 992, j['result']['outputs']
assert any(x['code'] == 'size_snapped' for x in j.get('warnings', [])), j.get('warnings')"
U2=$(upload $P "$OUT/gaea-turbo-0.png") # an upload is used up by the job that takes it
job $P '{"operation":"image.edit","model":"boogu-edit","inputs":{"images":[{"upload":"'$U2'"}],"instruction":"'$EDIT'"},"params":{"seed":7,"size":{"width":1536,"height":1536}},"extensions":{"x-gaea.lane":"int4","x-boogu.steps":4}}' > "$OUT/job-edit-big.json"
check "an edit asking 1536² is drawn at 1024² and reported size_snapped" py "
import json; j = json.load(open('$OUT/job-edit-big.json')); assert j['outcome'] == 'succeeded', j
assert j['result']['effective']['size'] == {'width': 1024, 'height': 1024}, j['result']['effective']
assert any(x['code'] == 'size_snapped' for x in j.get('warnings', [])), j.get('warnings')"
job $P '{"operation":"image.generate","model":"boogu","inputs":{"prompt":"'$HOUSE'"},"params":{"size":{"width":400,"height":400},"seed":1},"extensions":{"x-gaea.lane":"int4","x-boogu.steps":4}}' > "$OUT/job-small.json"
check "a 400² generate is drawn at Boogu's smallest 512² and returned at 400²" py "
import json; j = json.load(open('$OUT/job-small.json')); assert j['outcome'] == 'succeeded', j
assert j['plan']['effective']['model_params']['x-gaea.worker']['effective']['size'] == {'width': 512, 'height': 512}, j['plan']
assert [(o['width'], o['height']) for o in j['result']['outputs']] == [(400, 400)], j['result']['outputs']"
U3=$(upload $P "$OUT/gaea-turbo-1.png")
submit $P '{"operation":"image.edit","model":"boogu-edit","inputs":{"images":[{"upload":"'$U3'"},{"upload":"'$U3'"}],"instruction":"'$EDIT'"},"params":{"seed":7}}' > "$OUT/job-two.json"
check "two images on a Boogu edit are refused" py "
import json; j = json.load(open('$OUT/job-two.json')); e = j.get('error') or {}
assert j.get('outcome') != 'succeeded' and e, j; print(e)"
$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side, after Gaea has stopped: same requests, same lanes, same input bytes.
"$INPROC" --model boogu --lane bf16 --prompt "$HOUSE" --negative "$NEGATIVE" --seed 42 --out "$OUT/inproc-boogu.png" > "$OUT/inproc-boogu.json" 2>> "$LOG"
check "Boogu through Gaea is the in-process image, pixel for pixel" same "$OUT/gaea-boogu-0.png" "$OUT/inproc-boogu.png"
"$INPROC" --model boogu-turbo --lane int8 --prompt "$BIKE" --width 768 --height 768 --seed 7 --out "$OUT/inproc-turbo.png" > "$OUT/inproc-turbo.json" 2>> "$LOG"
check "Boogu Turbo through Gaea is the in-process image, pixel for pixel" same "$OUT/gaea-turbo-0.png" "$OUT/inproc-turbo.png"
"$INPROC" --model boogu-edit --lane bf16 --prompt "$EDIT" --seed 7 --image "$OUT/gaea-turbo-0.png" --out "$OUT/inproc-edit.png" > "$OUT/inproc-edit.json" 2>> "$LOG"
check "the edit through Gaea is the in-process image, pixel for pixel" same "$OUT/gaea-edit-0.png" "$OUT/inproc-edit.png"
"$INPROC" --model boogu --lane int4 --prompt "$HOUSE" --width 992 --height 992 --steps 8 --seed 42 --out "$OUT/inproc-int4.png" > "$OUT/inproc-int4.json" 2>> "$LOG"
check "the int4 lane through Gaea is the in-process image, pixel for pixel" same "$OUT/gaea-int4-0.png" "$OUT/inproc-int4.png"

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
