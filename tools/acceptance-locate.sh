#!/bin/zsh
# AB-T-0483's acceptance: MES image.locate (Image §3.4, RFC 0010, media-engine-spec v0.15.0) through Gaea 1.9.0 with
# gaea-plugin-locate (Qwen3-VL-4B on mlx-locate-swift).
#
#   1. The plugin by repo URL. image.locate offers qwen3-vl-locate as its default: Apache-2.0, at most 16 boxes, no
#      seed, lanes int8 (default) and int4; the descriptor takes an image and a prompt and returns boxes.
#   2. The fox (the plugin's fixture): one box that covers the fox, with the prompt as its label and a score;
#      effective.count 1; the same boxes as locate-inproc's, number for number.
#   3. `count`: "the fox's ears" with count 4 returns at most 4 boxes, best first.
#   4. Nothing there: "a bicycle" succeeds with an empty list and the warning nothing_found.
#   5. The upright image: the fox sent as a JPEG turned on its side with an orientation tag gives the box of the upright
#      picture (it overlaps the plain run's box).
#   6. Lanes and refusals: int4 by name runs on int4; no prompt is 400; count 17 is 422 out_of_limits.
#   7. The yardstick (YARD, the 12 pictures mlx-3d measured HairDeck's head crop on): the hair and the face located in
#      each, the head crop built from the two boxes as HairDeck builds it, and counted when it is within the tolerance
#      AB-R-0851 measured (-10 % to +15 % in side, 8 % in centre shift) of the reference crop. mlx-image measured 12 of
#      12 in-process (AB-R-0879); at least 11 must hold through Gaea.
#   8. Every recorded GPP session passes the validator.
#
#   tools/acceptance-locate.sh <short-work-dir> <evidence-dir>
#
# Needs APP (default dist/Gaea.app, 1.9.0 or later), GAEA_GITHUB_TOKEN, ../gaea-plugin-locate with locate-inproc built
# (INPROC), MODELS (default /Volumes/DEV_VOL1/Models) with mlx-community/Qwen3-VL-4B-Instruct-8bit and -4bit, and PY, a
# python with PIL. REPO_FROM=standin serves ../gaea-plugin-locate/dist through tools/release-standin.py instead of GitHub.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
LP=../gaea-plugin-locate
INPROC=${INPROC:-$LP/.build/out/Products/Release/locate-inproc}
PY=${PY:-/Volumes/DEV_VOL1/flow-upscaler-eval/.venv/bin/python}
FOX=$LP/Tests/Fixtures/fox.png
YARD=${YARD:-/Volumes/Satechi/charm/HairDeck/data/demo_examples}
YARD_REF=${YARD_REF:-../mlxengine-3d/PROD/mlx-hairdeck-swift/Fixtures/p4b}
M=qwen3-vl-locate
mkdir -p "$OUT"; rm -rf "$WORK" "$OUT/sessions"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: ${2:-image/png}" --data-binary @$1 | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
# locate <name> <image> <prompt or ''> <params JSON> [extensions JSON] [media type]: $OUT/<name>.json is the settled job
# or the refusal, <name>.status the HTTP status.
locate() {
  local name=$1 up; up=$(upload $2 ${6:-image/png})
  python3 - "$up" "$3" "$4" "${5:-}" > "$OUT/body-$name.json" <<'PYEOF'
import json, sys
up, prompt, params, ext = sys.argv[1:5]
b = {"operation": "image.locate", "inputs": {"image": {"upload": up}}, "params": json.loads(params)}
if prompt: b["inputs"]["prompt"] = prompt
if ext: b["extensions"] = json.loads(ext)
print(json.dumps(b))
PYEOF
  mes -o "$OUT/$name.json" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' --data-binary @"$OUT/body-$name.json" > "$OUT/$name.status"
  if [[ $(cat "$OUT/$name.status") == 201 ]]; then
    local id j; id=$(py "import json; print(json.load(open('$OUT/$name.json'))['id'])")
    for _ in {1..60}; do
      j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
      print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
    done
    print -r -- "$j" > "$OUT/$name.json"
  fi
}
# The job's boxes: the `boxes` output's value (inline), or fetched from its href.
boxes() { python3 - "$OUT/$1.json" "http://127.0.0.1:$P" <<'PYEOF'
import json, sys, urllib.request
j = json.load(open(sys.argv[1])); o = [x for x in (j.get('result') or {}).get('outputs', []) if x['name'] == 'boxes']
if not o: print('null'); sys.exit()
o = o[0]
if 'value' in o: print(json.dumps(o['value']))
else:
    r = urllib.request.Request(sys.argv[2] + o['href'], headers={'MES-Version': '0.1'}); print(json.dumps(json.load(urllib.request.urlopen(r))))
PYEOF
}
line() { say "      $1: HTTP $(cat "$OUT/$1.status") $(py "import json; j=json.load(open('$OUT/$1.json')); r=j.get('result') or {}; e=j.get('error') or {}; w=(r.get('effective') or {}).get('model_params',{}).get('x-gaea.worker',{}); print(j.get('outcome',''), (r.get('provenance') or {}).get('model',{}).get('id',''), w.get('lane',''), w.get('seconds',''), [x['code'] for x in j.get('warnings', [])], e.get('code',''), e.get('message','')[:140])") $(boxes $1 | cut -c1-260)" }

say "# Locate acceptance (AB-T-0483) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), locate from ${REPO_FROM:-github}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
H=$WORK/home; P=17698
URL=https://github.com/xocialize-code/gaea-plugin-locate
if [[ ${REPO_FROM:-github} == standin ]]; then
  unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
  V=$(py "import json; print(json.load(open('$LP/dist/manifest.json'))['version'])")
  REL=$WORK/standin/xocialize-code/gaea-plugin-locate/v$V; mkdir -p "$REL"
  cp "$LP/dist/locate-$V.gaeaplugin.zip" "$LP/dist/locate-$V.gaeaplugin.zip.sha256" "$LP/dist/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8776 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8776
fi
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" > "$H.out" 2>&1 &
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
check "add the locate plugin by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add $URL | tee $OUT/plugins.txt | grep -q 'Installed '"
GAEA_HOME=$H "$CLI" models > "$OUT/models.txt"; sed 's/^/      /' "$OUT/models.txt" | tee -a "$LOG"
check "gaea models finds the weights under the models root, lanes int8 (default) and int4" zsh -c "grep '$M' $OUT/models.txt | grep -v 'weights not under' | grep 'int8\*' | grep -q 'int4'"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.locate takes an image and a prompt, returns boxes, and offers $M as its default: Apache-2.0, at most 16 boxes, no seed" py "
import json; ops={o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}; d=ops['image.locate']
m={x['id']: x for x in d['models']}['$M']; print(m)
assert [(i['name'], i['kind'], i['required']) for i in d['inputs']] == [('image', 'image', True), ('prompt', 'text', True)]
assert [(o['name'], o['kind']) for o in d['outputs']] == [('boxes', 'data')] and d['profile'] == 'image'
assert m.get('default') is True and not m.get('named_only') and m['license']['spdx'] == 'Apache-2.0' and m['license']['commercial_use'] is True
assert m['limits']['max_count'] == 16 and m['supports']['seed'] is False and d['params']['properties']['count']['maximum'] == 16"

# 2. The fox.
locate fox $FOX "the fox" '{}'; line fox
check "the fox: one box over the fox, labelled with the prompt, scored; effective.count 1" py "
import json; j=json.load(open('$OUT/fox.json')); b=json.loads('''$(boxes fox)'''); print(b, j['result']['effective'])
assert j['outcome']=='succeeded' and j['result']['provenance']['model']['id']=='$M' and len(b)==1
x=b[0]; assert x['width']*x['height'] > 0.2 and x['label']=='the fox' and 0 < x['score'] <= 1 and x['x']+x['width'] <= 1 and x['y']+x['height'] <= 1
assert j['result']['effective']['count'] == 1"
if [[ -x $INPROC ]]; then
  $INPROC --image $FOX --prompt "the fox" --count 1 --runs 1 --models-root "$MODELS" --out $OUT/inproc-fox.json > $OUT/inproc-fox.line 2>> $LOG
  check "the boxes are locate-inproc's, number for number" py "
import json; a=json.loads('''$(boxes fox)'''); b=json.load(open('$OUT/inproc-fox.json')); print(a, b); assert a == b"
else say "SKIP  in-process comparison: no $INPROC"; fi

# 3. count.
locate ears $FOX "the fox's ears" '{"count":4}'; line ears
check "\"the fox's ears\" with count 4: at most 4 boxes, best first, effective.count 4" py "
import json; j=json.load(open('$OUT/ears.json')); b=json.loads('''$(boxes ears)''')
s=[x['score'] for x in b]; assert j['outcome']=='succeeded' and 1 <= len(b) <= 4 and s == sorted(s, reverse=True) and j['result']['effective']['count'] == 4"

# 4. Nothing there.
locate nothing $FOX "a bicycle" '{}'; line nothing
check "\"a bicycle\" succeeds with an empty list and the warning nothing_found" py "
import json; j=json.load(open('$OUT/nothing.json')); b=json.loads('''$(boxes nothing)'''); c=[w['code'] for w in j.get('warnings', [])]; print(b, c)
assert j['outcome']=='succeeded' and b == [] and 'nothing_found' in c"

# 5. The upright image: the fox turned a quarter clockwise in the file, with the tag that turns it back.
$PY -c "
from PIL import Image
im = Image.open('$FOX').convert('RGB').resize((768, 768), Image.LANCZOS).transpose(Image.ROTATE_270)
ex = Image.Exif(); ex[0x0112] = 8   # the picture is shown turned a quarter counter-clockwise: upright again
im.save('$WORK/fox-turned.jpg', quality=95, exif=ex)
Image.open('$FOX').convert('RGB').resize((768, 768), Image.LANCZOS).save('$WORK/fox-768.png')"
locate plain768 $WORK/fox-768.png "the fox" '{}'; line plain768
locate turned $WORK/fox-turned.jpg "the fox" '{}' '' image/jpeg; line turned
check "a JPEG turned by its orientation tag gives the upright picture's box (IoU ≥ 0.8 with the plain run's)" py "
import json
a=json.loads('''$(boxes plain768)''')[0]; b=json.loads('''$(boxes turned)''')[0]
def iou(a, b):
    x0=max(a['x'],b['x']); y0=max(a['y'],b['y']); x1=min(a['x']+a['width'],b['x']+b['width']); y1=min(a['y']+a['height'],b['y']+b['height'])
    i=max(0,x1-x0)*max(0,y1-y0); return i/(a['width']*a['height']+b['width']*b['height']-i)
print(a, b, iou(a, b)); assert iou(a, b) >= 0.8"

# 6. Lanes and refusals.
locate int4 $FOX "the fox" '{}' '{"x-gaea.lane":"int4"}'; line int4
check "the int4 lane, named, runs on int4 and finds the fox" py "
import json; j=json.load(open('$OUT/int4.json')); b=json.loads('''$(boxes int4)''')
assert j['outcome']=='succeeded' and j['result']['effective']['model_params']['x-gaea.worker']['lane']=='int4' and len(b)==1 and b[0]['width']*b[0]['height'] > 0.2"
locate noprompt $FOX "" '{}'; line noprompt
check "no prompt is 400" zsh -c "[[ \$(cat $OUT/noprompt.status) == 400 ]]"
locate toomany $FOX "the fox" '{"count":17}'; line toomany
check "count 17 is 422 out_of_limits" py "
import json; s=open('$OUT/toomany.status').read().strip(); e=json.load(open('$OUT/toomany.json')).get('error') or {}; print(s, e); assert s=='422' and e.get('code')=='out_of_limits'"

# 7. The yardstick.
if [[ -d $YARD && -d $YARD_REF ]]; then
  for n in {01..12}; do
    locate y$n-hair $YARD/ex$n.png "the character's hair" '{}'
    locate y$n-face $YARD/ex$n.png "the character's face" '{}'
  done
  for n in {01..12}; do print -r -- "{\"name\":\"ex$n\",\"hair\":$(boxes y$n-hair),\"face\":$(boxes y$n-face),\"seconds\":[$(py "import json; print(json.load(open('$OUT/y$n-hair.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])"),$(py "import json; print(json.load(open('$OUT/y$n-face.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])")]}"; done > "$OUT/yardstick.jsonl"
  python3 - "$OUT/yardstick.jsonl" "$YARD_REF" > "$OUT/yardstick.txt" <<'PYEOF'
import json, statistics as st, sys
def px(b, size): return None if not b else [b[0]['x']*size[0], b[0]['y']*size[1], (b[0]['x']+b[0]['width'])*size[0], (b[0]['y']+b[0]['height'])*size[1]]
def iou(a, b):
    if not a or not b: return 0.0
    x0, y0, x1, y1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]); i = max(0, x1-x0)*max(0, y1-y0)
    u = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - i; return i/u if u > 0 else 0.0
def union(a, b): return b if a is None else a if b is None else [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
def square(b, margin=0.08):
    if b is None: return None
    cx, cy = (b[0]+b[2])/2, (b[1]+b[3])/2; s = max(b[2]-b[0], b[3]-b[1])*(1+2*margin); return [cx-s/2, cy-s/2, cx+s/2, cy+s/2]
def tol(c, r):
    if c is None: return False
    s, sr = c[2]-c[0], r[2]-r[0]
    return 0.90 <= s/sr <= 1.15 and abs((c[0]+c[2])/2-(r[0]+r[2])/2)/sr <= 0.08 and abs((c[1]+c[3])/2-(r[1]+r[3])/2)/sr <= 0.08
rows, ok, hair, face, crop, secs = [json.loads(l) for l in open(sys.argv[1])], 0, [], [], [], []
for r in rows:
    ref = json.load(open(f"{sys.argv[2]}/{r['name']}_box.json")); size = ref['size']
    h, f = px(r['hair'], size), px(r['face'], size); c = square(union(h, f)); t = tol(c, ref['box']); ok += t
    if ref.get('hair_box'): hair.append(iou(h, ref['hair_box']))
    if ref.get('face_box'): face.append(iou(f, ref['face_box']))
    crop.append(iou(c, ref['box'])); secs += r['seconds'][1:] if r['name'] == 'ex01' else r['seconds']
    print(f"{r['name']}: head crop IoU {crop[-1]:.3f} {'in tolerance' if t else 'OUT of tolerance'}; face found: {bool(r['face'])} (reference has one: {bool(ref.get('face_box'))})")
print(f"hair IoU median {st.median(hair):.3f}; face IoU median {st.median(face):.3f}; head crop IoU median {st.median(crop):.3f}; in tolerance {ok}/12; warm seconds per query median {st.median(secs):.2f}")
print(f"IN_TOLERANCE={ok}")
PYEOF
  sed 's/^/      /' "$OUT/yardstick.txt" | grep -v IN_TOLERANCE | tee -a "$LOG"
  check "the head crop built from Gaea's hair and face boxes is within tolerance on at least 11 of mlx-3d's 12 pictures" zsh -c "(( \$(grep -o 'IN_TOLERANCE=[0-9]*' $OUT/yardstick.txt | cut -d= -f2) >= 11 ))"
else say "SKIP  the yardstick: no $YARD or $YARD_REF"; fi

pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || break; sleep 0.2; done
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
