#!/bin/zsh
# AB-T-0388's and AB-T-0389's acceptance: gaea-plugin-ming-image installed in Gaea by repo URL and run through MES.
#
#   1. Gaea installs and enables the plugin beside Z-Image: image.generate offers Ming-Image Design, not as a default,
#      so a request naming no model still reaches Z-Image Turbo (the normalizer's default routes don't change);
#   2. through Gaea, for fixed seeds, the same image as ming-image-swift in-process (ming-inproc, the plugin repo's
#      reference tool on the same dependency resolution), compared pixel for pixel: the int8 default lane at 1024², and
#      the int4 and bf16 lanes;
#   3. a 768×512 request is drawn in the 1024² bucket at 3:2 (the size the worker reports, and ming-inproc's) and
#      returned at 768×512; count 2 gives two seeds; a negative prompt is reported ignored; a named lane runs that lane;
#   4. x-ming.background: transparent (AB-T-0389) returns a PNG with native alpha, the in-process image pixel for pixel
#      (premultiplied, as the normalizer works), effective says so, a size Gaea resizes keeps its alpha, and a full-bleed
#      scene warns background_opaque exactly when the in-process image has no alpha;
#   5. every recorded GPP session passes the validator.
#
#   tools/acceptance-ming-image.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); PLUGIN_DIST (default ../gaea-plugin-ming-image/dist); ZIMAGE_DIST
# (default ../gaea-plugin-z-image/dist); MING_INPROC (default ../gaea-plugin-ming-image/.build/release/ming-inproc).
# REPO_FROM=github installs the published releases instead of serving the dist folders through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-ming-image/dist}
ZIMAGE_DIST=${ZIMAGE_DIST:-../gaea-plugin-z-image/dist}
INPROC=${MING_INPROC:-../gaea-plugin-ming-image/.build/release/ming-inproc}
PLUGIN_MANIFEST=$PLUGIN_DIST/manifest.json
POSTER='a minimalist poster for a jazz festival, deep blue background, a gold saxophone, the words \"BLUE NOTE NIGHTS\" in bold white type at the top'
POSTER_PLAIN='a minimalist poster for a jazz festival, deep blue background, a gold saxophone, the words "BLUE NOTE NIGHTS" in bold white type at the top'
SIGN='a hand-lettered wooden shop sign for a bakery called Rise and Shine, warm morning light'
STICKER='a cute cartoon fox mascot sticker with a thick white outline, the word \"FOXY\" below it, isolated'
STICKER_PLAIN='a cute cartoon fox mascot sticker with a thick white outline, the word "FOXY" below it, isolated'
SCENE='a full-bleed landscape photograph of a mountain lake at sunrise, the scene filling the whole frame edge to edge'
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
PIXDIFF=$WORK/pixdiff; swiftc -O -o $PIXDIFF ../gaea-plugin-ming-image/scripts/pixdiff.swift
ALPHA=$WORK/alpha; swiftc -O -o $ALPHA ../gaea-plugin-ming-image/scripts/alpha.swift
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
same() { # two PNGs → passes when their bytes are identical, or else their pixels (the normalizer re-encodes the RGBA PNGs)
  py "import hashlib; a, b = (hashlib.sha256(open(f, 'rb').read()).hexdigest() for f in ('$1', '$2')); print(a, b); exit(0 if a == b else 1)" && return
  "$PIXDIFF" "$1" "$2"
}
worker() { py "import json; print(json.load(open('$1'))['plan']['effective']['model_params']['x-gaea.worker']['seconds'])" }
elapsed() { py "import time; print(round(time.time()-$1,2))" }
now() { py 'import time; print(time.time())' }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
ZVERSION=$(py "import json; print(json.load(open('$ZIMAGE_DIST/manifest.json'))['version'])")
say "# Ming-Image plugin acceptance (AB-T-0388) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), ming-image $VERSION, z-image $ZVERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  for pair in "ming-image:$PLUGIN_DIST:$VERSION" "z-image:$ZIMAGE_DIST:$ZVERSION"; do
    name=${pair%%:*}; rest=${pair#*:}; dist=${rest%:*}; v=${rest##*:}
    REL=$WORK/standin/xocialize-code/gaea-plugin-$name/v$v; mkdir -p "$REL"
    cp "$dist/$name-$v.gaeaplugin.zip" "$dist/$name-$v.gaeaplugin.zip.sha256" "$dist/manifest.json" "$REL/"
  done
  python3 tools/release-standin.py "$WORK/standin" --moved xocialize=xocialize-code --port 8772 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8772
fi
wsize() { py "import json; s = json.load(open('$1'))['plan']['effective']['model_params']['x-gaea.worker']['effective']['size']; print(s['width'], s['height'])" }

H=$WORK/main; P=17685
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs ming-image $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-ming-image | grep -q 'Installed .* $VERSION'"
check "add by repo URL installs z-image $ZVERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-z-image | grep -q 'Installed .* $ZVERSION'"
$CLI models > "$OUT/models.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.generate offers Ming-Image Design, not a default" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.generate']['models']}; assert 'ming-image' in m and not m['ming-image'].get('default'), m"

# 1. A request naming no model still reaches Z-Image Turbo.
job $P '{"operation":"image.generate","inputs":{"prompt":"'$SIGN'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}' > "$OUT/job-unnamed.json"
check "image.generate naming no model still reaches Z-Image Turbo" py "
import json; j = json.load(open('$OUT/job-unnamed.json')); assert j['outcome'] == 'succeeded', j
assert j['result']['provenance']['model']['id'] == 'z-image-turbo', j['result']['provenance']"

# 2. The default lane (int8), 12 steps, 1024².
BODY='{"operation":"image.generate","model":"ming-image","inputs":{"prompt":"'$POSTER'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
t0=$(now); job $P "$BODY" > "$OUT/job-ming-cold.json"
say "      cold: $(elapsed $t0) s from submit to settled (launch, prepare int8, 12 steps)"
t0=$(now); job $P "$BODY" > "$OUT/job-ming-warm.json"
say "      warm: $(elapsed $t0) s from submit to settled; worker run $(worker $OUT/job-ming-warm.json) s"
fetch $P "$OUT/job-ming-cold.json" "$OUT/gaea-ming"
check "Ming-Image int8 1024² seed 42: one 1024² PNG, 12 steps, lane int8" py "
import json; j = json.load(open('$OUT/job-ming-cold.json')); r = j['result']; o = r['outputs']; w = j['plan']['effective']['model_params']['x-gaea.worker']
assert j['outcome'] == 'succeeded' and len(o) == 1 and o[0]['width'] == 1024 and o[0]['height'] == 1024, j
assert r['provenance']['model']['id'] == 'ming-image' and w['effective']['x-ming.steps'] == 12 and w['lane'] == 'int8', w"
check "a warm run gives the same bytes again" py "
import json; a, b = (json.load(open(f))['result']['outputs'][0]['sha256'] for f in ('$OUT/job-ming-cold.json', '$OUT/job-ming-warm.json')); assert a == b, (a, b)"

# 3. A size outside the buckets, count, the negative prompt.
job $P '{"operation":"image.generate","model":"ming-image","inputs":{"prompt":"'$SIGN'"},"params":{"size":{"width":768,"height":512},"count":2,"seed":7,"negative_prompt":"blurry"}}' > "$OUT/job-wide.json"
fetch $P "$OUT/job-wide.json" "$OUT/gaea-wide"
say "      768×512 was drawn at $(wsize $OUT/job-wide.json)"
check "768×512 is drawn in the 1024² bucket at 3:2, and Gaea returns the 768×512 asked" py "
import json; j = json.load(open('$OUT/job-wide.json')); assert j['outcome'] == 'succeeded', j
s = j['plan']['effective']['model_params']['x-gaea.worker']['effective']['size']; o = j['result']['outputs']
assert s['width'] > 768 and abs(s['width'] / s['height'] - 1.5) < 0.02, s
assert all(x['width'] == 768 and x['height'] == 512 for x in o), o"
check "count 2 gives two different images, seeds 7 and 8" py "
import json; o = json.load(open('$OUT/job-wide.json'))['result']['outputs']; assert len(o) == 2 and o[0]['sha256'] != o[1]['sha256'], o"
check "the negative prompt is reported ignored" py "
import json; j = json.load(open('$OUT/job-wide.json')); w = j.get('warnings', []) + j['plan']['effective']['model_params']['x-gaea.worker'].get('warnings', [])
assert any(x['code'] == 'negative_prompt_ignored' for x in w), w"

# 4. The other lanes.
for lane in int4 bf16; do
  t0=$(now)
  job $P '{"operation":"image.generate","model":"ming-image","inputs":{"prompt":"'$POSTER'"},"params":{"size":{"width":1024,"height":1024},"seed":42},"extensions":{"x-gaea.lane":"'$lane'"}}' > "$OUT/job-$lane.json"
  say "      $lane: $(elapsed $t0) s from submit to settled; worker run $(worker $OUT/job-$lane.json) s"
  fetch $P "$OUT/job-$lane.json" "$OUT/gaea-$lane"
  check "x-gaea.lane $lane runs lane $lane" py "
import json; j = json.load(open('$OUT/job-$lane.json')); assert j['outcome'] == 'succeeded', j
assert j['plan']['effective']['model_params']['x-gaea.worker']['lane'] == '$lane'"
done
# 5. Transparent backgrounds (AB-T-0389).
TBG='"extensions":{"x-ming.background":"transparent"}'
job $P '{"operation":"image.generate","model":"ming-image","inputs":{"prompt":"'$STICKER'"},"params":{"size":{"width":1024,"height":1024},"seed":7},'$TBG'}' > "$OUT/job-alpha.json"
fetch $P "$OUT/job-alpha.json" "$OUT/gaea-alpha"
check "x-ming.background transparent: one 1024² PNG, the option in effective" py "
import json; j = json.load(open('$OUT/job-alpha.json')); assert j['outcome'] == 'succeeded', j
w = j['plan']['effective']['model_params']['x-gaea.worker']; assert w['effective'].get('x-ming.background') == 'transparent', w
assert j['plan']['effective'].get('x-ming.background') == 'transparent', j['plan']['effective']"
check "the PNG Gaea returns has native alpha" "$ALPHA" "$OUT/gaea-alpha-0.png"
job $P '{"operation":"image.generate","model":"ming-image","inputs":{"prompt":"'$STICKER'"},"params":{"size":{"width":768,"height":512},"seed":8},'$TBG'}' > "$OUT/job-alpha-wide.json"
fetch $P "$OUT/job-alpha-wide.json" "$OUT/gaea-alpha-wide"
# Seed 8: at 3:2 this sticker comes back with alpha for seeds 8, 11 and 12, and opaque for 7 and 9 (ming-inproc).
check "a transparent 768×512, drawn larger and resized by Gaea, keeps its alpha" zsh -c "
python3 -c \"import json; j = json.load(open('$OUT/job-alpha-wide.json')); o = j['result']['outputs']; assert (o[0]['width'], o[0]['height']) == (768, 512), o; assert not any(w['code'] == 'background_opaque' for w in j.get('warnings', [])), j['warnings']\" && $ALPHA $OUT/gaea-alpha-wide-0.png"
job $P '{"operation":"image.generate","model":"ming-image","inputs":{"prompt":"'$SCENE'"},"params":{"size":{"width":1024,"height":1024},"seed":7},'$TBG'}' > "$OUT/job-alpha-scene.json"
fetch $P "$OUT/job-alpha-scene.json" "$OUT/gaea-alpha-scene"
submit $P '{"operation":"image.generate","model":"ming-image","inputs":{"prompt":"'$STICKER'"},"params":{"size":{"width":1024,"height":1024},"seed":7},"extensions":{"x-ming.background":"checkerboard"}}' > "$OUT/job-alpha-bad.json"
check "an unknown background is refused" py "
import json; j = json.load(open('$OUT/job-alpha-bad.json')); assert j.get('outcome') != 'succeeded', j"
$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side, after Gaea has stopped: same requests, same lanes.
"$INPROC" --lane int8 --prompt "$POSTER_PLAIN" --seed 42 --out "$OUT/inproc-ming.png" > "$OUT/inproc-ming.json" 2>> "$LOG"
check "int8 through Gaea is the in-process image, pixel for pixel" same "$OUT/gaea-ming-0.png" "$OUT/inproc-ming.png"
"$INPROC" --lane int8 --prompt "$SIGN" --width 768 --height 512 --seed 7 --out "$OUT/inproc-wide.png" > "$OUT/inproc-wide.json" 2>> "$LOG"
check "ming-inproc draws 768×512 at the size the worker reported" py "
import json; i = json.loads(open('$OUT/inproc-wide.json').read().strip().splitlines()[-1]); s = json.load(open('$OUT/job-wide.json'))['plan']['effective']['model_params']['x-gaea.worker']['effective']['size']
assert (i['out_width'], i['out_height']) == (s['width'], s['height']), (i, s)"
for lane in int4 bf16; do
  "$INPROC" --lane $lane --prompt "$POSTER_PLAIN" --seed 42 --out "$OUT/inproc-$lane.png" > "$OUT/inproc-$lane.json" 2>> "$LOG"
  check "$lane through Gaea is the in-process image, pixel for pixel" same "$OUT/gaea-$lane-0.png" "$OUT/inproc-$lane.png"
done

"$INPROC" --lane int8 --prompt "$STICKER_PLAIN" --seed 7 --background transparent --out "$OUT/inproc-alpha.png" 2>> "$LOG" | tail -1 > "$OUT/inproc-alpha.json"
check "transparent through Gaea is the in-process image, pixel for pixel (premultiplied)" same "$OUT/gaea-alpha-0.png" "$OUT/inproc-alpha.png"
"$INPROC" --lane int8 --prompt "$SCENE" --seed 7 --background transparent --out "$OUT/inproc-alpha-scene.png" 2>> "$LOG" | tail -1 > "$OUT/inproc-alpha-scene.json"
say "      scene: in-process alpha $(py "import json; print(json.load(open('$OUT/inproc-alpha-scene.json'))['transparent'])"), Gaea's warnings $(py "import json; print([w['code'] for w in json.load(open('$OUT/job-alpha-scene.json')).get('warnings', [])])")"
check "the full-bleed scene warns background_opaque exactly when the in-process image has no alpha" py "
import json; alpha = json.load(open('$OUT/inproc-alpha-scene.json'))['transparent']
codes = [w['code'] for w in json.load(open('$OUT/job-alpha-scene.json')).get('warnings', [])]
assert ('background_opaque' in codes) == (not alpha), (alpha, codes)"
check "the scene through Gaea is the in-process image, pixel for pixel" same "$OUT/gaea-alpha-scene-0.png" "$OUT/inproc-alpha-scene.png"

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
