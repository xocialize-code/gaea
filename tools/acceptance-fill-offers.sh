#!/bin/zsh
# AB-A-0267's acceptance (Gaea 1.7.1): image.fill, image.extend and image.erase are offered only with models this
# server can finish them with.
#
#   A. Only Z-Image 0.2.1 (its edit offers say supports.image_to_image):
#      - image.fill and image.extend aren't offered, and a fill naming z-image-turbo is refused when it arrives;
#      - image.generate and image.edit by name still run.
#   B. Only Z-Image 0.2.0 from GitHub (no flag): image.extend isn't offered (no inpainter); image.fill still lists it,
#      and the job's failure now says the inpainting model is what's missing.
#   C. Z-Image 0.2.1, FLUX.2 Klein and the Forge pack:
#      - fill offers LaMa and Klein and not Z-Image; extend is offered;
#      - a fill by Klein with a prompt changes only the masked area;
#      - an extend by Klein grows the canvas and keeps the original's pixels;
#      - a fill naming z-image-turbo is refused when it arrives.
#   D. Every recorded GPP session passes the validator.
#
#   tools/acceptance-fill-offers.sh <short-work-dir> <evidence-dir>
#
# Needs APP (default dist/Gaea.app, 1.7.1 or later), GAEA_GITHUB_TOKEN, MODELS (default /Volumes/DEV_VOL1/Models) with
# Z-Image Turbo, FLUX.2 Klein 4B and LaMa, and PY, a python with numpy and PIL. The plugins come from GitHub.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
PY=${PY:-/Volumes/DEV_VOL1/flow-upscaler-eval/.venv/bin/python}
ORG=https://github.com/xocialize-code
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
start() { H=$WORK/$1; P=$2; GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" > "$H.out" 2>&1 &; for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || break; sleep 0.2; done
         mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null }
add() { GAEA_HOME=$H "$CLI" plugins add "$@" | tail -1 | tee -a "$LOG" }
ops() { mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/$1.json" }
models_of() { py "import json; d={o['operation']: o for o in json.load(open('$OUT/$1.json'))['operations']}; print(' '.join(sorted(m['id'] for m in d.get('$2', {}).get('models', []))) or '-')" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @$1 | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
submit() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
job() {
  local id j; id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  [[ -z $id ]] && { print -r -- '{"outcome":"refused"}' > "$2"; return }
  for _ in {1..120}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
  done
  print -r -- "$j" > "$2"
  if [[ $(py "import json; print(json.load(open('$2')).get('outcome'))") == succeeded ]]; then
    mes -o "${2%.json}.png" "http://127.0.0.1:$P$(py "import json; print(json.load(open('$2'))['result']['outputs'][0]['href'])")"
  fi
  say "      ${2:t:r}: $(py "import json; j=json.load(open('$2')); r=j.get('result') or {}; print(j.get('outcome'), (r.get('provenance') or {}).get('model',{}).get('id'), [w['code'] for w in j.get('warnings', [])], (j.get('error') or {}).get('message','')[:200])")"
}

say "# Fill offers acceptance (AB-A-0267) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), plugins from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
# A 768×512 picture (a lit gradient with a dark disc) and a mask over the disc.
$PY - "$WORK" <<'PYEOF'
import sys, numpy as np
from PIL import Image, ImageDraw
w, h = 768, 512
y, x = np.mgrid[0:h, 0:w]
img = np.stack([60 + x * 120 // w, 110 + y * 90 // h, 150 + (x + y) * 60 // (w + h)], -1).astype(np.uint8)
im = Image.fromarray(img); d = ImageDraw.Draw(im); d.ellipse([330, 200, 450, 320], fill=(30, 30, 40)); im.save(sys.argv[1] + '/image.png')
m = Image.new('L', (w, h), 0); ImageDraw.Draw(m).rectangle([300, 170, 480, 350], fill=255); m.convert('RGB').save(sys.argv[1] + '/mask.png')
PYEOF
FILL() { print -r -- '{"operation":"image.fill","model":"'$1'","inputs":{"image":{"upload":"'$2'"},"mask":{"upload":"'$3'"},"prompt":"a bright red apple"},"params":{"seed":3}}' }

# A. Only Z-Image 0.2.1.
start a 17681
add $ORG/gaea-plugin-z-image
check "A: Z-Image 0.2.1 is installed" zsh -c "GAEA_HOME=$H $CLI plugins | grep -q 'com.xocialize.gaea.z-image 0.2.1'"
ops ops-a
check "A: with only Z-Image, image.fill, image.extend and image.erase aren't offered" test "$(models_of ops-a image.fill) $(models_of ops-a image.extend) $(models_of ops-a image.erase)" = "- - -"
check "A: image.edit still offers both models by name" test "$(models_of ops-a image.edit)" = "z-image z-image-turbo"
I=$(upload $WORK/image.png); K=$(upload $WORK/mask.png)
submit "$(FILL z-image-turbo $I $K)" "$OUT/a-refuse-fill.json"; { cat "$OUT/a-refuse-fill.json"; print } >> "$LOG"
check "A: a fill naming z-image-turbo is refused when it arrives (4xx)" zsh -c "grep -q '^4' $OUT/a-refuse-fill.json.status"
I=$(upload $WORK/image.png)
job '{"operation":"image.edit","model":"z-image-turbo","inputs":{"images":[{"upload":"'$I'"}],"instruction":"the same scene at sunset"},"params":{"seed":3}}' "$OUT/a-edit.json"
check "A: image.edit by name still runs" py "import json; assert json.load(open('$OUT/a-edit.json'))['outcome'] == 'succeeded'"
stop

# B. Only Z-Image 0.2.0, the release without the flag.
start b 17682
add $ORG/gaea-plugin-z-image 0.2.0
ops ops-b
check "B: with Z-Image 0.2.0 and no inpainter, image.extend isn't offered" test "$(models_of ops-b image.extend)" = "-"
check "B: image.fill still lists it (the release says nothing about its edit)" test "$(models_of ops-b image.fill)" = "z-image z-image-turbo"
I=$(upload $WORK/image.png); K=$(upload $WORK/mask.png)
job "$(FILL z-image-turbo $I $K)" "$OUT/b-fill.json"
check "B: the fill fails saying the inpainting model is what's missing, and where it comes from" py "
import json; j=json.load(open('$OUT/b-fill.json')); e=j.get('error') or {}; print(e)
assert j['outcome'] == 'failed' and 'inpainting model' in e['message'] and 'gaea-plugin-forge' in e['message']"
stop

# C. Z-Image 0.2.1, Klein and Forge.
start c 17683
add $ORG/gaea-plugin-z-image
add $ORG/gaea-plugin-flux2-klein
add $ORG/gaea-plugin-forge
ops ops-c
say "      fill: $(models_of ops-c image.fill); extend: $(models_of ops-c image.extend)"
check "C: fill offers LaMa and Klein, and not Z-Image" py "
m='$(models_of ops-c image.fill)'.split(); print(m); assert 'lama-inpaint' in m and 'klein-4b' in m and not any(x.startswith('z-image') for x in m)"
check "C: extend is offered, without Z-Image" py "
m='$(models_of ops-c image.extend)'.split(); print(m); assert 'klein-4b' in m and not any(x.startswith('z-image') for x in m)"
I=$(upload $WORK/image.png); K=$(upload $WORK/mask.png)
job "$(FILL klein-4b $I $K)" "$OUT/c-fill.json"
check "C: a fill by Klein succeeds and changes only the masked area" $PY -c "
import json, numpy as np; from PIL import Image
j = json.load(open('$OUT/c-fill.json')); assert j['outcome'] == 'succeeded', j.get('error')
a = np.asarray(Image.open('$WORK/image.png').convert('RGB')).astype(int); b = np.asarray(Image.open('$OUT/c-fill.png').convert('RGB')).astype(int)
m = np.asarray(Image.open('$WORK/mask.png').convert('L')) > 127; d = np.abs(a - b).max(-1)
print('outside max', d[~m].max(), 'inside mean', d[m].mean()); assert d[~m].max() <= 2 and d[m].mean() > 5"
I=$(upload $WORK/image.png)   # an upload is the job's once it is used
job '{"operation":"image.extend","model":"klein-4b","inputs":{"image":{"upload":"'$I'"}},"params":{"canvas":{"left":0,"top":0,"right":256,"bottom":0},"seed":3}}' "$OUT/c-extend.json"
check "C: an extend by Klein is 1024×512 and keeps the original's pixels" $PY -c "
import json, numpy as np; from PIL import Image
j = json.load(open('$OUT/c-extend.json')); assert j['outcome'] == 'succeeded', j.get('error')
a = np.asarray(Image.open('$WORK/image.png').convert('RGB')).astype(int); im = Image.open('$OUT/c-extend.png').convert('RGB'); b = np.asarray(im).astype(int)
print(im.size, 'kept max diff', np.abs(a[:, :700] - b[:, :700]).max()); assert im.size == (1024, 512) and np.abs(a[:, :700] - b[:, :700]).max() <= 2"
I=$(upload $WORK/image.png); K=$(upload $WORK/mask.png)
submit "$(FILL z-image-turbo $I $K)" "$OUT/c-refuse-fill.json"
check "C: a fill naming z-image-turbo is refused when it arrives (4xx)" zsh -c "grep -q '^4' $OUT/c-refuse-fill.json.status"
stop

for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
