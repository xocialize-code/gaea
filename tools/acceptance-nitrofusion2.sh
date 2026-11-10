#!/bin/zsh
# gaea-plugin-z-image 0.2.0's acceptance: NitroFusion2 (Z-Image Turbo in 1–4 steps, z-image-swift 0.7.1) through Gaea,
# beside Turbo and base, which it must leave alone.
#
#   1. The plugin by repo URL. image.generate offers z-image-nitrofusion2 by name only; Turbo is still the default, and
#      the operation's quality tiers are what they were (the image normalizer's table sets them, not the plugin).
#   2. NitroFusion2 by name at 1024², seed 42: two steps by default, pixel for pixel zimage-inproc's (Gaea re-encodes
#      PNGs; the plugin's golden checks bytes), and faster than Turbo's 8 steps on the same request.
#   3. One step and four steps run as asked; five is refused; a negative prompt is reported ignored.
#   4. A request that names no model still runs Turbo, and its image is the same as before (pixel for pixel
#      zimage-inproc's Turbo).
#   5. NitroFusion2 offers no image.edit.
#   6. Every recorded GPP session passes the validator.
#
#   tools/acceptance-nitrofusion2.sh <short-work-dir> <evidence-dir>
#
# Needs APP (default dist/Gaea.app), GAEA_GITHUB_TOKEN, ../gaea-plugin-z-image with zimage-inproc built (INPROC), MODELS
# (default /Volumes/DEV_VOL1/Models) with Z-Image Turbo and ChenDY/NitroFusion2, and PY, a python with numpy and PIL.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
INPROC=${INPROC:-../gaea-plugin-z-image/.build/out/Products/Release/zimage-inproc}
PY=${PY:-/Volumes/DEV_VOL1/flow-upscaler-eval/.venv/bin/python}
PROMPT="a red fox sitting in a snowy forest at sunrise, photorealistic"
NF2=z-image-nitrofusion2
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
job() {
  local id j; id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  [[ -z $id ]] && { print -r -- '{"outcome":"refused"}' > "$2"; return }
  for _ in {1..120}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
  done
  print -r -- "$j" > "$2"
}
gen() { # name, extra JSON members (model, extensions…), params JSON
  job '{"operation":"image.generate",'$2'"inputs":{"prompt":"'$PROMPT'"},"params":'$3'}' "$OUT/job-$1.json"
  if [[ $(py "import json; print(json.load(open('$OUT/job-$1.json')).get('outcome'))") == succeeded ]]; then
    mes -o "$OUT/$1.png" "http://127.0.0.1:$P$(py "import json; print(json.load(open('$OUT/job-$1.json'))['result']['outputs'][0]['href'])")"
  fi
  say "      $1: $(py "import json; j=json.load(open('$OUT/job-$1.json')); r=j.get('result') or {}; w=(r.get('effective') or {}).get('model_params',{}).get('x-gaea.worker',{}); print(j.get('outcome'), (r.get('provenance') or {}).get('model',{}).get('id'), w.get('lane'), w.get('seconds'), 's', (w.get('effective') or {}).get('x-zimage.steps'), 'steps', (j.get('error') or {}).get('message',''))" 2>/dev/null)"
}
worker() { py "import json; w=json.load(open('$OUT/job-$1.json'))['result']['effective']['model_params']['x-gaea.worker']; print(w$2)" }
model_of() { py "import json; print(json.load(open('$OUT/job-$1.json'))['result']['provenance']['model']['id'])" }
samepx() { $PY -c "import sys, numpy as np; from PIL import Image
a, b = (np.asarray(Image.open(f).convert('RGB')) for f in sys.argv[1:3]); d = int((a != b).any(-1).sum()) if a.shape == b.shape else -1
print(a.shape, b.shape, 'differing pixels', d); assert d == 0" "$1" "$2" 2>/dev/null }

say "# NitroFusion2 acceptance $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), z-image from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
H=$WORK/home; P=17677
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" > "$H.out" 2>&1 &
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
check "add z-image 0.2.0 by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-z-image | tee $OUT/plugins.txt | grep -q 'Installed .* 0.2.0'"
GAEA_HOME=$H "$CLI" models > "$OUT/models.txt"; sed 's/^/      /' "$OUT/models.txt" | tee -a "$LOG"
check "gaea models finds NitroFusion2's weights under the models root" zsh -c "grep '$NF2' $OUT/models.txt | grep -qv 'weights not under'"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.generate offers NitroFusion2 by name only; Turbo is still the default, and the tiers are unchanged" py "
import json; ops={o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m={m['id']: m for m in ops['image.generate']['models']}; n=m['$NF2']; print(n)
assert n.get('named_only') is True and not n.get('default') and n['license']['spdx'] == 'Apache-2.0'
assert m['z-image-turbo'].get('default') is True and m['z-image-turbo']['quality_tiers'] == ['standard', 'best']
assert sorted(ops['image.generate']['quality_tiers']) == ['best', 'standard'], ops['image.generate']['quality_tiers']
steps=[e for e in ops['image.generate']['extensions'] if e['name']=='x-zimage.steps'][0]; print(steps['schema'])"
check "NitroFusion2 offers no image.edit" py "
import json; ops={o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
assert '$NF2' not in [m['id'] for m in ops.get('image.edit', {}).get('models', [])]"

# 2. By name, the default two steps; Turbo on the same request for the time.
SIZE='{"size":{"width":1024,"height":1024},"seed":42}'
gen nf2 '"model":"'$NF2'",' "$SIZE"
gen nf2-again '"model":"'$NF2'",' "$SIZE"
gen turbo '"model":"z-image-turbo",' "$SIZE"
gen turbo-again '"model":"z-image-turbo",' "$SIZE"
check "NitroFusion2 by name runs two steps by default" py "
import json; j=json.load(open('$OUT/job-nf2.json')); e=j['result']['effective']['model_params']['x-gaea.worker']['effective']
assert j['outcome']=='succeeded' and j['result']['provenance']['model']['id']=='$NF2' and e['x-zimage.steps']==2, e"
if [[ -x $INPROC ]]; then
  $INPROC --model $NF2 --lane int4 --width 1024 --height 1024 --seed 42 --prompt "$PROMPT" --models-root "$MODELS" --out $OUT/inproc-nf2.png > $OUT/inproc-nf2.json 2>> $LOG
  check "its image is zimage-inproc's, pixel for pixel" samepx $OUT/nf2.png $OUT/inproc-nf2.png
else say "SKIP  in-process comparison: no $INPROC"; fi
T_NF2=$(worker nf2-again "['seconds']"); T_TURBO=$(worker turbo-again "['seconds']")
say "      warm 1024² on int4: NitroFusion2 two steps $T_NF2 s, Turbo eight steps $T_TURBO s"
check "warm, NitroFusion2 takes under half of Turbo's time" py "assert $T_NF2 < $T_TURBO / 2, ($T_NF2, $T_TURBO)"

# 3. Step counts and the negative prompt.
SMALL='{"size":{"width":768,"height":512},"seed":42}'
gen nf2-1 '"model":"'$NF2'","extensions":{"x-zimage.steps":1},' "$SMALL"
gen nf2-4 '"model":"'$NF2'","extensions":{"x-zimage.steps":4},' "$SMALL"
check "one step and four steps run as asked" test "$(worker nf2-1 "['effective']['x-zimage.steps']") $(worker nf2-4 "['effective']['x-zimage.steps']")" = "1 4"
mes -o "$OUT/refuse-5.json" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' \
  -d '{"operation":"image.generate","model":"'$NF2'","inputs":{"prompt":"x"},"params":'$SMALL',"extensions":{"x-zimage.steps":5}}' > "$OUT/refuse-5.json.status"
gen nf2-5 '"model":"'$NF2'","extensions":{"x-zimage.steps":5},' "$SMALL"
check "five steps is refused" py "
import json; s=open('$OUT/refuse-5.json.status').read().strip(); j=json.load(open('$OUT/job-nf2-5.json')); print(s, j.get('outcome'), j.get('error'))
assert s.startswith('4') or j.get('outcome') in ('failed', 'refused')"
gen nf2-neg '"model":"'$NF2'",' '{"size":{"width":768,"height":512},"seed":42,"negative_prompt":"blurry"}'
check "a negative prompt is reported ignored" py "
import json; j=json.load(open('$OUT/job-nf2-neg.json')); print([w['code'] for w in j['warnings']]); assert any(w['code']=='negative_prompt_ignored' for w in j['warnings'])"

# 4. Unnamed requests still run Turbo.
gen standard '' "$SIZE"
gen best '' '{"size":{"width":1024,"height":1024},"seed":42,"quality":"best"}'
check "a request naming no model runs Turbo, at standard and at best" test "$(model_of standard) $(model_of best)" = "z-image-turbo z-image-turbo"
if [[ -x $INPROC ]]; then
  $INPROC --model z-image-turbo --lane int4 --width 1024 --height 1024 --seed 42 --prompt "$PROMPT" --models-root "$MODELS" --out $OUT/inproc-turbo.png > $OUT/inproc-turbo.json 2>> $LOG
  check "Turbo's image is zimage-inproc's Turbo, pixel for pixel" samepx $OUT/standard.png $OUT/inproc-turbo.png
fi

pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || break; sleep 0.2; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
