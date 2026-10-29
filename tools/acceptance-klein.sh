#!/bin/zsh
# AB-T-0367's acceptance: gaea-plugin-flux2-klein installed in Gaea by repo URL and run through MES.
#
#   1. Gaea installs and enables the plugin: both models offer image.generate (the base for `best`), and Klein 4B is
#      image.edit's default, with up to 4 images;
#   2. through Gaea, for fixed seeds, the same image as flux2-klein-swift in-process (klein-inproc, the plugin repo's
#      reference tool on the same dependency resolution), compared byte for byte: Klein 4B bf16 generate at 1024²,
#      Klein 4B Base generate (28 steps, CFG 4, a negative prompt), and a two-reference edit;
#   3. count 2 gives two seeds; the distilled model reports a negative prompt as ignored; a named lane runs that
#      lane; five references are refused;
#   4. every recorded GPP session passes the validator.
#
#   tools/acceptance-klein.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); PLUGIN_DIST (default ../gaea-plugin-flux2-klein/dist); KLEIN_INPROC
# (default ../gaea-plugin-flux2-klein/.build/release/klein-inproc). REPO_FROM=github installs the published release
# instead of serving PLUGIN_DIST through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-flux2-klein/dist}
INPROC=${KLEIN_INPROC:-../gaea-plugin-flux2-klein/.build/release/klein-inproc}
FOX="a red fox sitting in a snowy forest at sunrise, photorealistic"
CABIN="a cozy wooden cabin interior with a stone fireplace, warm evening light, photorealistic"
NEGATIVE="blurry, oversaturated"
EDIT="the fox from image 1 sitting on the rug in the cabin from image 2, in front of the fireplace"
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
  local id j; id=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  for _ in {1..60}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
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
same() { # two PNGs → passes when their bytes are identical
  py "import hashlib; a, b = (hashlib.sha256(open(f, 'rb').read()).hexdigest() for f in ('$1', '$2')); print(a, b); assert a == b"
}
worker() { py "import json; print(json.load(open('$1'))['plan']['effective']['model_params']['x-gaea.worker']['seconds'])" }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# FLUX.2 Klein plugin acceptance (AB-T-0367) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), flux2-klein $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-flux2-klein/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/flux2-klein-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/flux2-klein-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --moved xocialize=xocialize-code --port 8770 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8770
fi

H=$WORK/main; P=17670
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs flux2-klein $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-flux2-klein | grep -q 'Installed .* $VERSION'"
$CLI models > "$OUT/models.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.generate offers Klein 4B and Klein 4B Base (best)" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.generate']['models']}; assert 'klein-4b' in m and 'best' in m['klein-4b-base']['quality_tiers'], m"
check "image.edit: Klein 4B is the default, not named-only, up to 4 images" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.edit']['models']}; k = m['klein-4b']
assert k.get('default') is True and not k.get('named_only'), k; print(json.dumps(ops['image.edit'].get('limits') or k.get('limits')))"

# 2. Generate, both models, and an edit from two references.
FOXBODY='{"operation":"image.generate","model":"klein-4b","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
t0=$(py 'import time; print(time.time())')
job $P "$FOXBODY" > "$OUT/job-klein-cold.json"
say "      cold: $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled (launch, prepare bf16, generate)"
t0=$(py 'import time; print(time.time())')
job $P "$FOXBODY" > "$OUT/job-klein-warm.json"
say "      warm: $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled; worker run $(worker $OUT/job-klein-warm.json) s"
fetch $P "$OUT/job-klein-cold.json" "$OUT/gaea-klein"
check "Klein 4B bf16 1024² seed 42 succeeds with one 1024² PNG, 4 steps" py "
import json; j = json.load(open('$OUT/job-klein-cold.json')); r = j['result']; o = r['outputs']
assert j['outcome'] == 'succeeded' and len(o) == 1 and o[0]['width'] == 1024 and o[0]['height'] == 1024, j
assert r['provenance']['model']['id'] == 'klein-4b' and r['effective']['x-klein.steps'] == 4, r
assert j['plan']['effective']['model_params']['x-gaea.worker']['lane'] == 'bf16'"
check "a warm run gives the same bytes again" py "
import json; a, b = (json.load(open(f))['result']['outputs'][0]['sha256'] for f in ('$OUT/job-klein-cold.json', '$OUT/job-klein-warm.json')); assert a == b, (a, b)"

t0=$(py 'import time; print(time.time())')
job $P '{"operation":"image.generate","inputs":{"prompt":"'$CABIN'"},"params":{"quality":"best","size":{"width":1024,"height":1024},"seed":42,"negative_prompt":"'$NEGATIVE'"}}' > "$OUT/job-base.json"
say "      base: $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled (launch base, prepare bf16, 28 steps CFG)"
fetch $P "$OUT/job-base.json" "$OUT/gaea-base"
check "quality best reaches Klein 4B Base (28 steps, guidance 4, the negative prompt honoured)" py "
import json; r = json.load(open('$OUT/job-base.json'))['result']; e = r['effective']
assert r['provenance']['model']['id'] == 'klein-4b-base', r['provenance']; assert e['x-klein.steps'] == 28 and e['x-klein.guidance'] == 4, e
assert e['negative_prompt'] == '$NEGATIVE', e"

U1=$(upload $P "$OUT/gaea-klein-0.png"); U2=$(upload $P "$OUT/gaea-base-0.png")
t0=$(py 'import time; print(time.time())')
job $P '{"operation":"image.edit","inputs":{"images":[{"upload":"'$U1'"},{"upload":"'$U2'"}],"instruction":"'$EDIT'"},"params":{"seed":7}}' > "$OUT/job-edit.json"
say "      edit: $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled; worker run $(worker $OUT/job-edit.json) s"
fetch $P "$OUT/job-edit.json" "$OUT/gaea-edit"
check "image.edit with no model reaches Klein 4B: two references, the first image's 1024²" py "
import json; j = json.load(open('$OUT/job-edit.json')); r = j['result']
assert j['outcome'] == 'succeeded', j; assert r['provenance']['model']['id'] == 'klein-4b', r['provenance']
assert r['outputs'][0]['width'] == 1024 and r['outputs'][0]['height'] == 1024, r['outputs']"

# 3. Count, warnings, lanes, limits.
job $P '{"operation":"image.generate","model":"klein-4b","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":768,"height":512},"count":2,"seed":7,"negative_prompt":"fog"}}' > "$OUT/job-count.json"
check "count 2 gives two different 768×512 images, seeds 7 and 8" py "
import json; o = json.load(open('$OUT/job-count.json'))['result']['outputs']
assert len(o) == 2 and o[0]['sha256'] != o[1]['sha256'] and all(x['width'] == 768 and x['height'] == 512 for x in o), o"
check "Klein 4B reports the negative prompt as ignored" py "
import json; w = json.load(open('$OUT/job-count.json')).get('warnings', []); assert any(x['code'] == 'negative_prompt_ignored' for x in w), w"
job $P '{"operation":"image.generate","model":"klein-4b","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":1000,"height":1000},"seed":42},"extensions":{"x-gaea.lane":"int4"}}' > "$OUT/job-int4.json"
fetch $P "$OUT/job-int4.json" "$OUT/gaea-int4"
check "x-gaea.lane int4 runs lane int4, and 1000² snaps to 992²" py "
import json; j = json.load(open('$OUT/job-int4.json')); w = j['result']['effective']['model_params']['x-gaea.worker'] if 'model_params' in j['result']['effective'] else j['plan']['effective']['model_params']['x-gaea.worker']
assert w['lane'] == 'int4', w; assert j['result']['outputs'][0]['width'] == 992, j['result']['outputs']
assert any(x['code'] == 'size_snapped' for x in j.get('warnings', [])), j.get('warnings')"
FIVE='{"operation":"image.edit","model":"klein-4b","inputs":{"images":[{"upload":"'$U1'"},{"upload":"'$U2'"},{"upload":"'$U1'"},{"upload":"'$U2'"},{"upload":"'$U1'"}],"instruction":"'$EDIT'"},"params":{"seed":7}}'
mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$FIVE" > "$OUT/job-five.json"
FIVE_ID=$(py "import json; print(json.load(open('$OUT/job-five.json')).get('id', ''))")
[[ -n $FIVE_ID ]] && mes "http://127.0.0.1:$P/mes/v0/jobs/$FIVE_ID?wait=30" > "$OUT/job-five.json"
check "five references are refused out_of_limits at submit" py "
import json; j = json.load(open('$OUT/job-five.json')); e = j.get('error') or {}
assert j.get('outcome') != 'succeeded' and e.get('code') == 'out_of_limits' and e.get('param') == 'images', j; print(e)"
$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side, after Gaea has stopped: same requests, same lanes, same input bytes.
"$INPROC" --model klein-4b --lane bf16 --prompt "$FOX" --seed 42 --out "$OUT/inproc-klein.png" > "$OUT/inproc-klein.json" 2>> "$LOG"
check "Klein 4B through Gaea is byte for byte the in-process image" same "$OUT/gaea-klein-0.png" "$OUT/inproc-klein.png"
"$INPROC" --model klein-4b-base --lane bf16 --prompt "$CABIN" --negative "$NEGATIVE" --seed 42 --out "$OUT/inproc-base.png" > "$OUT/inproc-base.json" 2>> "$LOG"
check "Klein 4B Base through Gaea is byte for byte the in-process image" same "$OUT/gaea-base-0.png" "$OUT/inproc-base.png"
"$INPROC" --model klein-4b --lane bf16 --prompt "$EDIT" --seed 7 --image "$OUT/gaea-klein-0.png" --image "$OUT/gaea-base-0.png" --out "$OUT/inproc-edit.png" > "$OUT/inproc-edit.json" 2>> "$LOG"
check "the two-reference edit through Gaea is byte for byte the in-process image" same "$OUT/gaea-edit-0.png" "$OUT/inproc-edit.png"
"$INPROC" --model klein-4b --lane int4 --prompt "$FOX" --width 992 --height 992 --seed 42 --out "$OUT/inproc-int4.png" > "$OUT/inproc-int4.json" 2>> "$LOG"
check "the int4 lane through Gaea is byte for byte the in-process image" same "$OUT/gaea-int4-0.png" "$OUT/inproc-int4.png"

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
