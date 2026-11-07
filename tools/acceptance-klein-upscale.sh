#!/bin/zsh
# AB-T-0464's acceptance: FLUX.2 Klein (gaea-plugin-flux2-klein 0.3.0) and FLUX 3 Klein (gaea-plugin-flux3-klein 0.2.0)
# at 2048² and 4096² through Gaea 1.2.0, by latent upscaling with FlowUpscaler (AB-R-0795, AB-R-0797).
#
#   1. The offers reach 4096² of area.
#   2. FLUX.2 Klein 4B, seed 44: 1024² as before, and 2048² and 4096² (one and two passes from a 1024² draw).
#      - Each is the asked size, and effective says how it was made.
#      - 2048² and 4096² are pixel for pixel klein-inproc's (Gaea re-encodes PNGs; the goldens check bytes).
#      - Each keeps the 1024² draw's picture: DISTS of the image Lanczos'd to 1024² against the 1024² image, within
#        AB-R-0797's band.
#   3. FLUX.2 cases:
#      - Klein 4B Base at 1792×1024 (one pass);
#      - an edit asked at 2048² (one pass);
#      - 1536×1000 snapped to 1536×992 (size_snapped);
#      - 4096×200 refused cleanly (Gaea raises the short side to the offer's 256; the plugin refuses that draw).
#   4. FLUX 3 Klein (enabled, upsampler off), seed 44:
#      - 2048² drawn natively, as before;
#      - 4096² from a 1024² draw ×4, pixel for pixel flux3-inproc's, keeping its own 1024² draw's picture.
#   5. Memory, Gaea 1.2.0 charging each job on the lane's ActivationScaling:
#      - a 4096² Klein job is charged its line's 4096² point while it runs, and a 1024² job ~16 GB less;
#      - nothing learns a single peak;
#      - with the budget cut to fit a 1024² job, the 1024² job runs and a 4096² job is refused (no_capacity).
#   6. Every recorded GPP session passes the validator.
#
#   tools/acceptance-klein-upscale.sh <short-work-dir> <evidence-dir>
#
# Needs:
# - APP (default dist/Gaea.app, 1.2.0 or later);
# - the two plugin repos at ../gaea-plugin-flux2-klein and ../gaea-plugin-flux3-klein, with their dist/ and
#   .build/release/{klein,flux3}-inproc;
# - MODELS (default /Volumes/DEV_VOL1/Models): FLUX.2 Klein 4B and Base, FLUX 3 Klein and FlowUpscaler-bf16;
# - PY, a python with piq (default the FlowUpscaler eval's venv).
# REPO_FROM=github installs the published releases instead of serving dist/ through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
K2=../gaea-plugin-flux2-klein; K3=../gaea-plugin-flux3-klein
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
PY=${PY:-/Volumes/DEV_VOL1/flow-upscaler-eval/.venv/bin/python}
FOXPNG=$K2/scripts/fixtures/fox-256.png
PROMPT="An enamel shop sign on a brick wall that reads 'BAKERY - FRESH BREAD DAILY', a tabby cat asleep on the windowsill beside it, soft morning light"
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
submit() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
job() { # json body, out file → the settled job
  local id j; id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  [[ -z $id ]] && { print -r -- '{"outcome":"refused"}' > "$2"; return }
  for _ in {1..180}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
  done
  print -r -- "$j" > "$2"
}
fetch() { local href=$(py "import json; print(json.load(open('$1'))['result']['outputs'][0]['href'])"); mes -o "$2" "http://127.0.0.1:$P$href" }
gen() { # name, model, w, h, seed, [extensions JSON object]
  local ext=""; [[ -n ${6:-} ]] && ext=',"extensions":'$6
  job '{"operation":"image.generate","model":"'$2'","inputs":{"prompt":'"$(py "import json; print(json.dumps('''$PROMPT'''))")"'},"params":{"size":{"width":'$3',"height":'$4'},"seed":'$5'}'$ext'}' "$OUT/job-$1.json"
  [[ $(py "import json; print(json.load(open('$OUT/job-$1.json')).get('outcome'))") == succeeded ]] && fetch "$OUT/job-$1.json" "$OUT/gaea-$1.png"
}
eff() { py "import json; e=json.load(open('$OUT/job-$1.json'))['result']['effective']['model_params']['x-gaea.worker']['effective']; print(json.dumps(e.get('$2')))" }
dims() { sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}' }
samepx() { # two PNGs → passes when their RGB pixels are identical (Gaea re-encodes PNGs; the golden checks bytes at the worker)
  $PY -c "import sys, numpy as np; from PIL import Image; Image.MAX_IMAGE_PIXELS = None
a, b = (np.asarray(Image.open(f).convert('RGB')) for f in sys.argv[1:3]); d = int((a != b).any(-1).sum()) if a.shape == b.shape else -1
print(a.shape, b.shape, 'differing pixels', d); assert d == 0" "$1" "$2" 2>/dev/null
}
drift() { # big png, small png → DISTS of big Lanczos'd to the small's size, against the small (2x2 grid of 512² crops)
  $PY - "$1" "$2" <<'PYEOF' 2>/dev/null | tail -1
import sys, numpy as np, torch, piq
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
torch.set_grad_enabled(False)
small = Image.open(sys.argv[2]).convert("RGB"); big = Image.open(sys.argv[1]).convert("RGB").resize(small.size, Image.LANCZOS)
a, b = (np.asarray(x, dtype=np.float32) / 255 for x in (big, small))
D = piq.DISTS(reduction="none"); v = []
for y in range(0, a.shape[0] - 511, 512):
    for x in range(0, a.shape[1] - 511, 512):
        ta, tb = (torch.from_numpy(z[y:y+512, x:x+512]).permute(2, 0, 1)[None] for z in (a, b)); v.append(D(ta, tb).item())
print(round(float(np.mean(v)), 4))
PYEOF
}
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise --models-root "$MODELS" "${@:3}" > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea at $1 didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $1" > /dev/null || return; sleep 0.2; done }
sampler() { # plugin id, out file: the largest chargedBytes the ledger shows for the plugin's worker, every 0.5 s
  local id=$1 out=$2; : > $out
  while true; do GAEA_HOME=$H "$CLI" ledger --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(max([w['chargedBytes'] for w in d['workers'] if w['pluginID']=='$id' and w.get('busy')] or [0]))" >> $out; sleep 0.5; done
}

V2=$(py "import json; print(json.load(open('$K2/dist/manifest.json'))['version'])"); V3=$(py "import json; print(json.load(open('$K3/dist/manifest.json'))['version'])")
say "# Klein latent upscale acceptance (AB-T-0464) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), flux2-klein $V2, flux3-klein $V3, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
if [[ ${REPO_FROM:-} != github ]]; then
  unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
  for pair in "flux2-klein $K2 $V2" "flux3-klein $K3 $V3"; do
    set -- ${=pair}; REL=$WORK/standin/xocialize-code/gaea-plugin-$1/v$3; mkdir -p "$REL"
    cp "$2/dist/$1-$3.gaeaplugin.zip" "$2/dist/$1-$3.gaeaplugin.zip.sha256" "$2/dist/manifest.json" "$REL/"
  done
  python3 tools/release-standin.py "$WORK/standin" --port 8771 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8771
fi

H=$WORK/main; P=17672
start $H $P
check "add flux2-klein $V2 by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-flux2-klein | tee -a $OUT/plugins.txt | grep -q 'Installed .* $V2'"
check "add flux3-klein $V3 by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-flux3-klein | tee -a $OUT/plugins.txt | grep -q 'Installed .* $V3'"
GAEA_HOME=$H "$CLI" models enable flux-3-klein | tee -a "$OUT/plugins.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "the image.generate offers reach 4096² of area" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
lim = ops['image.generate'].get('limits') or {}; print(lim); assert (lim.get('max_megapixels') or 0) >= 16.777216, lim"

# 2. FLUX.2 Klein 4B: 1024², 2048², 4096²; with the ledger sampled for the 1024² and 4096² jobs.
sampler com.xocialize.gaea.flux2-klein $WORK/charge-1024.txt & S1=$!
gen k1024 klein-4b 1024 1024 44
kill $S1 2>/dev/null
gen k2048 klein-4b 2048 2048 44
sampler com.xocialize.gaea.flux2-klein $WORK/charge-4096.txt & S2=$!
gen k4096 klein-4b 4096 4096 44
kill $S2 2>/dev/null
for n in k1024 k2048 k4096; do say "      $n: $(py "import json; j=json.load(open('$OUT/job-$n.json')); w=j['result']['effective']['model_params']['x-gaea.worker']; print(j['outcome'], w['lane'], w['seconds'], 's')" 2>/dev/null) $(dims $OUT/gaea-$n.png 2>/dev/null)"; done
check "1024², 2048² and 4096² come back at their sizes" test "$(dims $OUT/gaea-k1024.png) $(dims $OUT/gaea-k2048.png) $(dims $OUT/gaea-k4096.png)" = "1024x1024 2048x2048 4096x4096"
check "effective: 1024² drawn as it is; 2048² one pass and 4096² two from a 1024² draw" py "
import json
def up(n): return json.load(open('$OUT/job-%s.json' % n))['result']['effective']['model_params']['x-gaea.worker']['effective'].get('x-klein.upscaled')
assert up('k1024') is None, up('k1024'); a, b = up('k2048'), up('k4096'); print(a, b)
assert a['passes'] == 1 and b['passes'] == 2 and a['from'] == b['from'] == {'width': 1024, 'height': 1024}"
INPROC2=$K2/.build/release/klein-inproc
for n in 2048 4096; do $INPROC2 --model klein-4b --lane bf16 --prompt "$PROMPT" --width $n --height $n --seed 44 --models-root "$MODELS" --out $OUT/inproc-k$n.png > $OUT/inproc-k$n.json 2>> $LOG; done
check "2048² through Gaea is klein-inproc's, pixel for pixel" samepx $OUT/gaea-k2048.png $OUT/inproc-k2048.png
check "4096² through Gaea is klein-inproc's, pixel for pixel" samepx $OUT/gaea-k4096.png $OUT/inproc-k4096.png
D2=$(drift $OUT/gaea-k2048.png $OUT/gaea-k1024.png); D4=$(drift $OUT/gaea-k4096.png $OUT/gaea-k1024.png)
say "      drift vs the 1024² image: 2048² $D2, 4096² $D4"
check "2048² keeps the 1024² picture (DISTS ≤ 0.04)" py "assert 0 < $D2 <= 0.04"
check "4096² keeps the 1024² picture (DISTS ≤ 0.07)" py "assert 0 < $D4 <= 0.07"

# 3. More FLUX.2 cases.
gen base1792 klein-4b-base 1792 1024 9
check "Klein 4B Base at 1792×1024, one pass from 896×512" py "
import json; e=json.load(open('$OUT/job-base1792.json'))['result']['effective']['model_params']['x-gaea.worker']['effective']
print(e['size'], e.get('x-klein.upscaled')); assert e['size'] == {'width': 1792, 'height': 1024} and e['x-klein.upscaled']['from'] == {'width': 896, 'height': 512}"
UP=$(mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @$FOXPNG | py "import json,sys; print(json.load(sys.stdin)['upload_id'])")
job '{"operation":"image.edit","model":"klein-4b","inputs":{"images":[{"upload":"'$UP'"}],"instruction":"the fox from image 1 sitting in a sunny meadow"},"params":{"size":{"width":2048,"height":2048},"seed":7}}' "$OUT/job-edit2048.json"
check "an edit asked at 2048² is drawn at 1024² and upscaled once" py "
import json; j=json.load(open('$OUT/job-edit2048.json')); e=j['result']['effective']['model_params']['x-gaea.worker']['effective']
print(j['outcome'], e.get('x-klein.upscaled')); assert j['outcome'] == 'succeeded' and e['x-klein.upscaled']['passes'] == 1"
gen snap klein-4b 1536 1000 3
check "1536×1000 is made at 1536×992 (one pass, multiples of 32), with size_snapped" py "
import json; j=json.load(open('$OUT/job-snap.json')); e=j['result']['effective']['model_params']['x-gaea.worker']['effective']
codes=[w['code'] for w in j.get('warnings', [])]; print(e['size'], codes); assert e['size'] == {'width': 1536, 'height': 992} and 'size_snapped' in codes"
job '{"operation":"image.generate","model":"klein-4b","inputs":{"prompt":"a sign"},"params":{"size":{"width":4096,"height":200}}}' "$OUT/job-thin.json"
check "4096×200 is refused cleanly: invalid_request naming the draw it would need" py "
import json; j=json.load(open('$OUT/job-thin.json')); e=j.get('error') or {}; print(j.get('outcome'), e.get('code'), (e.get('message') or '')[:200])
assert j.get('outcome') == 'failed' and e.get('code') == 'invalid_request' and 'draw' in e.get('message', '')"

# 4. FLUX 3 Klein: 1024², 2048² native, 4096² from a 1024² draw.
NOUP='{"x-flux3.upsample":false}'
gen f1024 flux-3-klein 1024 1024 44 "$NOUP"
gen f2048 flux-3-klein 2048 2048 44 "$NOUP"
gen f4096 flux-3-klein 4096 4096 44 "$NOUP"
for n in f1024 f2048 f4096; do say "      $n: $(py "import json; j=json.load(open('$OUT/job-$n.json')); w=j['result']['effective']['model_params']['x-gaea.worker']; print(j['outcome'], w['lane'], w['seconds'], 's')" 2>/dev/null) $(dims $OUT/gaea-$n.png 2>/dev/null)"; done
check "FLUX 3: 2048² is drawn natively and 4096² from 1024² ×4, at their sizes" py "
import json
def e(n): return json.load(open('$OUT/job-%s.json' % n))['result']['effective']['model_params']['x-gaea.worker']['effective']
assert e('f2048').get('x-flux3.upscaled') is None and e('f2048')['size'] == {'width': 2048, 'height': 2048}
u = e('f4096')['x-flux3.upscaled']; print(u); assert u['passes'] == 2 and u['from'] == {'width': 1024, 'height': 1024} and e('f4096')['size'] == {'width': 4096, 'height': 4096}"
$K3/.build/release/flux3-inproc --lane bf16 --prompt "$PROMPT" --width 4096 --height 4096 --seed 44 --no-upsample --runs 1 --models-root "$MODELS" --out $OUT/inproc-f4096.png > $OUT/inproc-f4096.json 2>> $LOG
check "FLUX 3's 4096² through Gaea is flux3-inproc's, pixel for pixel" samepx $OUT/gaea-f4096.png $OUT/inproc-f4096.png
F4=$(drift $OUT/gaea-f4096.png $OUT/gaea-f1024.png); say "      FLUX 3 drift vs its 1024² image: 4096² $F4"
check "FLUX 3's 4096² keeps its 1024² picture (DISTS ≤ 0.07)" py "assert 0 < $F4 <= 0.07"

# 5. Memory.
MAN=$K2/dist/manifest.json
read PERSIST NEED1K NEED4K MIN4K <<< "$(py "
import json; m=[x for x in json.load(open('$MAN'))['models'] if x['id']=='klein-4b'][0]
def need(l, px):
    r=l['resolved']; s=r.get('activationScaling')
    return r['persistentBytes'] + (round(s['baseBytes'] + s['bytesPerUnit'] * px) if s else r['peakTransientBytes'])
bf=[l for l in m['lanes'] if l['id']=='bf16'][0]
print(bf['resolved']['persistentBytes'], need(bf, 1024*1024), need(bf, 4096*4096), min(need(l, 4096*4096) for l in m['lanes']))")"
C1=$(sort -n $WORK/charge-1024.txt | tail -1); C4=$(sort -n $WORK/charge-4096.txt | tail -1)
say "      Klein 4B bf16: declared need at 1024² $(py "print(round($NEED1K/1e9,2))") GB, at 4096² $(py "print(round($NEED4K/1e9,2))") GB; charged while running: 1024² $(py "print(round(${C1:-0}/1e9,2))") GB, 4096² $(py "print(round(${C4:-0}/1e9,2))") GB"
check "a 4096² job is charged its line's 4096² point while it runs" py "assert ${C4:-0} >= $NEED4K - 1e9, (${C4:-0}, $NEED4K)"
check "a 1024² job is charged at least 10 GB less than a 4096² one" py "assert 0 < ${C1:-0} <= ${C4:-0} - 10e9, (${C1:-0}, ${C4:-0})"
check "no Klein lane learned a single peak or overran its declaration" zsh -c "! grep -E 'held .* past|runs at .* past its declared' $H.out | grep -iE 'klein'"
stop $P
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null

BUDGET=$(py "print(int($NEED1K + 2e9))")
say "      budget for the refusal: $(py "print(round($BUDGET/1e9,2))") GB (the smallest lane's 4096² need is $(py "print(round($MIN4K/1e9,2))") GB)"
H2=$WORK/tight; P=17673
start $H2 $P --budget-bytes $BUDGET
GAEA_HOME=$H2 "$CLI" plugins add https://github.com/xocialize-code/gaea-plugin-flux2-klein > /dev/null 2>&1
gen t1024 klein-4b 1024 1024 44
gen t4096 klein-4b 4096 4096 44
check "under a budget that fits a 1024² job: the 1024² job runs" py "import json; assert json.load(open('$OUT/job-t1024.json'))['outcome'] == 'succeeded'"
check "and a 4096² job is refused, no_capacity (every lane's 4096² need is past the budget)" py "
import json; j=json.load(open('$OUT/job-t4096.json')); e=j.get('error') or {}; print(j.get('outcome'), e.get('code'), (e.get('message') or '')[:160])
assert $MIN4K > $BUDGET and j.get('outcome') == 'failed' and e.get('code') == 'no_capacity'"
stop $P
cp $H2/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
