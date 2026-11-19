#!/bin/zsh
# gaea-plugin-sensenova 0.2.0's acceptance: the TailSteer model (sensenova-u1-swift 0.7.0's fast8V2TailSteer, for pictures
# that get edited again) through Gaea 1.8.0, beside the three SenseNova models it must leave alone.
#
#   1. The plugin by repo URL. image.generate and image.edit offer sensenova-u1-tailsteer by name only, Apache-2.0 with
#      TailSteer's own terms page, one lane (int8); the three earlier models are still offered, each named-only.
#   2. TailSteer by name at 768², seed 42: eight steps without CFG, pixel for pixel sensenova-inproc's (Gaea re-encodes
#      PNGs; the plugin's golden checks bytes).
#   3. A chain of three edits of a photo, each turn's result uploaded as the next turn's input: the first three turns
#      of the vendor's cafe-20turn demo, with its seeds (CHAIN, mlx-image's tailsteer-gate tasks). Every turn runs
#      TailSteer at the photo's size; the first is pixel for pixel sensenova-inproc's edit of the same photo; and all
#      three are pixel for pixel the pictures mlx-image's own driver made (CHAIN_REF, AB-R-0842), so a chain through
#      Gaea's uploads loses nothing. The same chain by sensenova-u1-fast is run for comparison; how far each chain's
#      last picture is from the photo is reported, not judged (three turns are too few to show the drift mlx-image
#      measured over ten, AB-R-0841). Without CHAIN the chain starts from the generated fox and has no reference.
#   4. A negative prompt is reported ignored and think mode isn't run; an int4 lane, which TailSteer doesn't have,
#      fails the job.
#   5. sensenova-u1-fast by name still gives sensenova-inproc's picture.
#   6. Every recorded GPP session passes the validator.
#
#   tools/acceptance-tailsteer.sh <short-work-dir> <evidence-dir>
#
# Needs APP (default dist/Gaea.app, 1.8.0 or later), GAEA_GITHUB_TOKEN, ../gaea-plugin-sensenova with sensenova-inproc
# built (INPROC), MODELS (default /Volumes/DEV_VOL1/Models) with SenseNova-U1.5-8B-MoT-8step-v2-8bit and
# -TailSteer-8step-v2-8bit, and PY, a python with numpy and PIL. REPO_FROM=standin serves ../gaea-plugin-sensenova/dist
# through tools/release-standin.py instead of GitHub.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
SN=../gaea-plugin-sensenova
INPROC=${INPROC:-$SN/.build/out/Products/Release/sensenova-inproc}
PY=${PY:-/Volumes/DEV_VOL1/flow-upscaler-eval/.venv/bin/python}
PROMPT="a red fox sitting in a snowy forest at sunrise, photorealistic"
TS=sensenova-u1-tailsteer; FAST=sensenova-u1-fast
GATE=${GATE:-../mlxengine-image/WIP/tailsteer-gate}
CHAIN=${CHAIN:-$GATE/tasks/cafe.json}; CHAIN_REF=${CHAIN_REF:-$GATE/runs/cafe/ts8q8/cafe-20turn}
if [[ -f $CHAIN ]]; then
  SOURCE=${CHAIN:h}/$(python3 -c "import json; print(json.load(open('$CHAIN'))['tasks'][0]['image'])")
  TURNS=("${(@f)$(python3 -c "import json; [print(r['prompt']) for r in json.load(open('$CHAIN'))['tasks'][0]['rounds'][:3]]")}")
  SEEDS=(${(@f)$(python3 -c "import json; [print(r['seed']) for r in json.load(open('$CHAIN'))['tasks'][0]['rounds'][:3]]")})
else
  SOURCE=""; SEEDS=(42 42 42)
  TURNS=("Add a red knitted scarf around the fox's neck. Keep everything else the same."
         "Add a small bird perched on a branch behind the fox. Keep everything else the same."
         "Make it snow lightly. Keep everything else the same.")
fi
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @$1 | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
job() { # body file, out file
  local id j; id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' --data-binary @$1 | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  [[ -z $id ]] && { print -r -- '{"outcome":"refused"}' > "$2"; return }
  for _ in {1..360}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
  done
  print -r -- "$j" > "$2"
}
run() { # name, body JSON (python dict literal built by the caller as JSON text)
  print -r -- "$2" > "$OUT/body-$1.json"
  job "$OUT/body-$1.json" "$OUT/job-$1.json"
  if [[ $(py "import json; print(json.load(open('$OUT/job-$1.json')).get('outcome'))") == succeeded ]]; then
    mes -o "$OUT/$1.png" "http://127.0.0.1:$P$(py "import json; print(json.load(open('$OUT/job-$1.json'))['result']['outputs'][0]['href'])")"
  fi
  say "      $1: $(py "import json; j=json.load(open('$OUT/job-$1.json')); r=j.get('result') or {}; w=(r.get('effective') or {}).get('model_params',{}).get('x-gaea.worker',{}); print(j.get('outcome'), (r.get('provenance') or {}).get('model',{}).get('id'), w.get('lane'), w.get('seconds'), [x['code'] for x in j.get('warnings', [])], (j.get('error') or {}).get('message','')[:160])")"
}
body() { python3 - "$@" <<'PYEOF'
import json, sys
kind, model, text, params, ext, upload = (sys.argv[1:] + [''] * 6)[:6]
b = {"operation": "image." + kind, "params": json.loads(params or '{}')}
if model: b["model"] = model
if ext: b["extensions"] = json.loads(ext)
b["inputs"] = {"prompt": text} if kind == "generate" else {"images": [{"upload": upload}], "instruction": text}
print(json.dumps(b))
PYEOF
}
gen() { run $1 "$(body generate "$2" "$PROMPT" "$3" "${4:-}")" }                      # name, model, params, [extensions]
edit() { run $1 "$(body edit "$2" "$4" '{"seed":'${5:-42}'}' "" "$(upload $3)")" }    # name, model, image, instruction, [seed]
effective() { py "import json; print(json.load(open('$OUT/job-$1.json'))['result']['effective']['model_params']['x-gaea.worker']['effective']$2)" }
samepx() { $PY -c "import sys, numpy as np; from PIL import Image
a, b = (np.asarray(Image.open(f).convert('RGB')) for f in sys.argv[1:3]); d = int((a != b).any(-1).sum()) if a.shape == b.shape else -1
print(a.shape, b.shape, 'differing pixels', d); assert d == 0" "$1" "$2" 2>/dev/null }
dims() { sips -g pixelWidth -g pixelHeight $1 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}' }

say "# TailSteer acceptance $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), sensenova from ${REPO_FROM:-github}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
H=$WORK/home; P=17684
URL=https://github.com/xocialize-code/gaea-plugin-sensenova
if [[ ${REPO_FROM:-github} == standin ]]; then
  unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
  V=$(py "import json; print(json.load(open('$SN/dist/manifest.json'))['version'])")
  REL=$WORK/standin/xocialize-code/gaea-plugin-sensenova/v$V; mkdir -p "$REL"
  cp "$SN/dist/sensenova-$V.gaeaplugin.zip" "$SN/dist/sensenova-$V.gaeaplugin.zip.sha256" "$SN/dist/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8774 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8774
fi
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" > "$H.out" 2>&1 &
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
V=${V:-0.2.0}  # the release the run expects to install (the latest full release)
check "add sensenova $V by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add $URL | tee $OUT/plugins.txt | grep -q 'Installed .* $V'"
GAEA_HOME=$H "$CLI" models > "$OUT/models.txt"; sed 's/^/      /' "$OUT/models.txt" | tee -a "$LOG"
check "gaea models finds TailSteer's weights under the models root" zsh -c "grep '$TS' $OUT/models.txt | grep -qv 'weights not under'"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.generate and image.edit offer TailSteer by name only, Apache-2.0 with its own terms page, beside the three earlier models" py "
import json; ops={o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
for op in ('image.generate', 'image.edit'):
    m={m['id']: m for m in ops[op]['models']}; t=m['$TS']; print(op, t)
    assert set(m) >= {'sensenova-u1', 'sensenova-u1-fast', 'sensenova-u1-fast-v1', '$TS'}
    assert all(x.get('named_only') is True and not x.get('default') for x in m.values() if x['id'].startswith('sensenova'))
    assert t['license']['spdx'] == 'Apache-2.0' and t['license']['terms_url'].endswith('-TailSteer')"
check "TailSteer has one lane, int8" zsh -c "grep '$TS' $OUT/models.txt | grep -q 'int8' && ! grep '$TS' $OUT/models.txt | grep -q 'int4'"

# 2. Generate by name.
gen tail $TS '{"size":{"width":768,"height":768},"seed":42}'
check "TailSteer by name draws 768² in eight steps on int8" py "
import json; j=json.load(open('$OUT/job-tail.json')); w=j['result']['effective']['model_params']['x-gaea.worker']; e=w['effective']; print(e)
assert j['outcome']=='succeeded' and j['result']['provenance']['model']['id']=='$TS' and w['lane']=='int8' and e['x-sensenova.steps']==8 and 'x-sensenova.guidance' not in e"
check "the picture is 768×768" test "$(dims $OUT/tail.png)" = 768x768
if [[ -x $INPROC ]]; then
  $INPROC --model $TS --lane int8 --width 768 --height 768 --seed 42 --prompt "$PROMPT" --runs 1 --models-root "$MODELS" --out $OUT/inproc-tail.png > $OUT/inproc-tail.json 2>> $LOG
  check "it is sensenova-inproc's, pixel for pixel" samepx $OUT/tail.png $OUT/inproc-tail.png
else say "SKIP  in-process comparison: no $INPROC"; fi

# 3. A chain of edits: each turn's result is the next turn's input.
[[ -z $SOURCE ]] && SOURCE=$OUT/tail.png
cp $SOURCE $OUT/chain-source.png; SIZE=$(dims $SOURCE)
say "      chain source: ${SOURCE:t} $SIZE, seeds $SEEDS"
chain() { # prefix, model
  local prev=$SOURCE i=0
  for t in "${TURNS[@]}"; do i=$((i+1)); edit $1-$i $2 $prev "$t" $SEEDS[$i]; prev=$OUT/$1-$i.png; done
}
chain turn $TS
check "three chained edits each ran TailSteer and kept the picture's size ($SIZE)" py "
import json
for i in (1, 2, 3):
    j=json.load(open('$OUT/job-turn-%d.json' % i)); assert j['outcome']=='succeeded', (i, j.get('error')); assert j['result']['provenance']['model']['id']=='$TS'
    e=j['result']['effective']['model_params']['x-gaea.worker']['effective']; assert '%dx%d' % (e['size']['width'], e['size']['height']) == '$SIZE', e"
if [[ -x $INPROC ]]; then
  $INPROC --model $TS --lane int8 --image $SOURCE --seed $SEEDS[1] --prompt "${TURNS[1]}" --runs 1 --models-root "$MODELS" --out $OUT/inproc-turn-1.png > $OUT/inproc-turn-1.json 2>> $LOG
  check "the first edit is sensenova-inproc's edit of the same picture, pixel for pixel" samepx $OUT/turn-1.png $OUT/inproc-turn-1.png
fi
if [[ -f $CHAIN && -f $CHAIN_REF/round-03.png ]]; then
  for i in 1 2 3; do check "turn $i is the picture mlx-image's own driver made, pixel for pixel" samepx $OUT/turn-$i.png $CHAIN_REF/round-0$i.png; done
else say "SKIP  comparison with mlx-image's chain: no $CHAIN_REF"; fi
check "each turn changed the picture" $PY -c "
import numpy as np; from PIL import Image
f=['$SOURCE','$OUT/turn-1.png','$OUT/turn-2.png','$OUT/turn-3.png']; a=[np.asarray(Image.open(x).convert('RGB')).astype(int) for x in f]
d=[float(np.abs(a[i+1]-a[i]).mean()) for i in range(3)]; print('mean abs change per turn', d); assert all(x > 0.5 for x in d)"
chain fast $FAST
say "      $($PY -c "
import numpy as np; from PIL import Image
o=np.asarray(Image.open('$SOURCE').convert('RGB')).astype(float)
def psnr(f):
    x=np.asarray(Image.open(f).convert('RGB')).astype(float); m=((x-o)**2).mean(); return 10*np.log10(255**2/m)
print('whole-picture PSNR against the source, turns 1 to 3 (reported, not judged): TailSteer %s dB, sensenova-u1-fast %s dB' % (
    ' '.join('%.2f' % psnr('$OUT/turn-%d.png' % i) for i in (1, 2, 3)), ' '.join('%.2f' % psnr('$OUT/fast-%d.png' % i) for i in (1, 2, 3))))" 2>&1)"
check "the TailSteer edit is another picture than sensenova-u1-fast's of the same input and seed" zsh -c "! cmp -s $OUT/turn-1.png $OUT/fast-1.png"

# 4. What TailSteer ignores and refuses.
gen ignore $TS '{"size":{"width":512,"height":512},"seed":42,"negative_prompt":"blurry"}' '{"x-sensenova.think":true}'
check "a negative prompt is reported ignored, and think mode, which its offer doesn't list, isn't run" py "
import json; j=json.load(open('$OUT/job-ignore.json')); c=[w['code'] for w in j.get('warnings', [])]; print(j.get('outcome'), c, j.get('error'))
e=j['result']['effective']['model_params']['x-gaea.worker']['effective']
assert j['outcome']=='succeeded' and 'negative_prompt_ignored' in c and 'x-sensenova.think' not in e and 'negative_prompt' not in e, e"
gen lane $TS '{"size":{"width":512,"height":512},"seed":42}' '{"x-gaea.lane":"int4"}'
check "an int4 lane, which TailSteer doesn't have, fails the job naming the lane and runs nothing" py "
import json; j=json.load(open('$OUT/job-lane.json')); e=j.get('error') or {}; print(j.get('outcome'), e)
assert j.get('outcome') in ('failed', 'refused') and (j.get('outcome') == 'refused' or 'int4' in e.get('message', ''))"

# 5. The earlier model is what it was.
gen fast $FAST '{"size":{"width":512,"height":512},"seed":42}'
if [[ -x $INPROC ]]; then
  $INPROC --model $FAST --lane int8 --width 512 --height 512 --seed 42 --prompt "$PROMPT" --runs 1 --models-root "$MODELS" --out $OUT/inproc-fast.png > $OUT/inproc-fast.json 2>> $LOG
  check "sensenova-u1-fast by name is sensenova-inproc's, pixel for pixel" samepx $OUT/fast.png $OUT/inproc-fast.png
fi

pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || break; sleep 0.2; done
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
