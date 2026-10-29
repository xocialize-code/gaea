#!/bin/zsh
# AB-T-0368's acceptance: gaea-plugin-qwen-image installed in Gaea by repo URL and run through MES.
#
#   1. Gaea installs and enables the plugin: Qwen-Image-Edit 2511 offers image.edit (best, up to 3 images) and
#      Qwen-Image Flash offers image.generate under the NVIDIA Open Model License, with its notice;
#   2. through Gaea, for fixed seeds, the same image as qwen-image-edit-swift in-process (qwen-inproc, the plugin
#      repo's reference tool on the same dependency resolution), compared byte for byte: Flash int8 at 1024², and a
#      two-reference edit on Qwen-Image-Edit bf16;
#   3. a 1280×768 input is edited at about 1024² in its aspect (1312×800, size_snapped); count 2 gives two seeds;
#      Flash reports a negative prompt as ignored; four references are refused;
#   4. the ledger and qwen-inproc give each lane's resident footprint; every GPP session passes the validator.
#
#   tools/acceptance-qwen.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); PLUGIN_DIST (default ../gaea-plugin-qwen-image/dist); QWEN_INPROC
# (default ../gaea-plugin-qwen-image/.build/release/qwen-inproc). REPO_FROM=github installs the published release
# instead of serving PLUGIN_DIST through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-qwen-image/dist}
INPROC=${QWEN_INPROC:-../gaea-plugin-qwen-image/.build/release/qwen-inproc}
FOX="a red fox sitting in a snowy forest at sunrise, photorealistic"
CABIN="a cozy wooden cabin interior with a stone fireplace, warm evening light, a sign above the mantel reading GAEA, photorealistic"
EDIT="Put the fox from Picture 1 on the rug in the cabin from Picture 2, in front of the fireplace"
SNOW="Make it a snowy night outside the windows, keep everything else the same"
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
say "# Qwen-Image plugin acceptance (AB-T-0368) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), qwen-image $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-qwen-image/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/qwen-image-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/qwen-image-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --moved xocialize=xocialize-code --port 8771 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8771
fi

H=$WORK/main; P=17680
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs qwen-image $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-qwen-image | grep -q 'Installed .* $VERSION'"
$CLI models > "$OUT/models.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.edit offers Qwen-Image-Edit 2511 for standard and best, up to 3 images" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.edit']['models']}; q = m['qwen-image-edit']; assert {'standard', 'best'} <= set(q['quality_tiers']), q; assert [i for i in ops['image.edit']['inputs'] if i['name'] == 'images'][0]['max'] == 3
print(json.dumps(ops['image.edit'].get('limits') or q.get('limits')))"
check "image.generate offers Qwen-Image Flash under the NVIDIA Open Model License, with its notice" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.generate']['models']}; l = m['qwen-image-flash']['license']
assert l['spdx'] == 'LicenseRef-NVIDIA-Open-Model' and l['commercial_use'] is True and 'NVIDIA Open Model License' in l['notice'], l"

# 2. Flash: cold, warm, and the references for the edits.
FOXBODY='{"operation":"image.generate","model":"qwen-image-flash","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
t0=$(py 'import time; print(time.time())')
job $P "$FOXBODY" > "$OUT/job-flash-cold.json"
say "      flash cold: $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled (launch, prepare int8, generate); worker run $(worker $OUT/job-flash-cold.json) s"
t0=$(py 'import time; print(time.time())')
job $P "$FOXBODY" > "$OUT/job-flash-warm.json"
say "      flash warm: $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled; worker run $(worker $OUT/job-flash-warm.json) s"
fetch $P "$OUT/job-flash-cold.json" "$OUT/gaea-flash"
check "Flash int8 1024² seed 42 succeeds with one 1024² PNG, 4 steps" py "
import json; j = json.load(open('$OUT/job-flash-cold.json')); r = j['result']; o = r['outputs']
assert j['outcome'] == 'succeeded' and len(o) == 1 and o[0]['width'] == 1024 and o[0]['height'] == 1024, j
assert r['provenance']['model']['id'] == 'qwen-image-flash' and r['effective']['x-qwen.steps'] == 4, r
assert j['plan']['effective']['model_params']['x-gaea.worker']['lane'] == 'int8'"
check "a warm run gives the same bytes again" py "
import json; a, b = (json.load(open(f))['result']['outputs'][0]['sha256'] for f in ('$OUT/job-flash-cold.json', '$OUT/job-flash-warm.json')); assert a == b, (a, b)"
job $P '{"operation":"image.generate","model":"qwen-image-flash","inputs":{"prompt":"'$CABIN'"},"params":{"size":{"width":1280,"height":768},"seed":11}}' > "$OUT/job-cabin.json"
fetch $P "$OUT/job-cabin.json" "$OUT/gaea-cabin"
$CLI ledger > "$OUT/ledger-1-flash.txt"

# The edits: two references at the first image's 1024², then one 1280×768 reference. An MES upload is used once.
U1=$(upload $P "$OUT/gaea-flash-0.png"); U2=$(upload $P "$OUT/gaea-cabin-0.png")
t0=$(py 'import time; print(time.time())')
job $P '{"operation":"image.edit","model":"qwen-image-edit","inputs":{"images":[{"upload":"'$U1'"},{"upload":"'$U2'"}],"instruction":"'$EDIT'"},"params":{"seed":7}}' > "$OUT/job-edit.json"
say "      edit cold: $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled (prepare bf16 beside Flash, 20 steps CFG 4); worker run $(worker $OUT/job-edit.json) s"
fetch $P "$OUT/job-edit.json" "$OUT/gaea-edit"
check "image.edit on Qwen-Image-Edit: two references, 1024² from the first, 20 steps, guidance 4" py "
import json; j = json.load(open('$OUT/job-edit.json')); r = j['result']; e = r['effective']
assert j['outcome'] == 'succeeded', j; assert r['provenance']['model']['id'] == 'qwen-image-edit', r['provenance']
assert r['outputs'][0]['width'] == 1024 and r['outputs'][0]['height'] == 1024, r['outputs']
assert e['x-qwen.steps'] == 20 and e['x-qwen.guidance'] == 4 and e['references'] == 2, e"
U3=$(upload $P "$OUT/gaea-cabin-0.png")
t0=$(py 'import time; print(time.time())')
job $P '{"operation":"image.edit","inputs":{"images":[{"upload":"'$U3'"}],"instruction":"'$SNOW'"},"params":{"seed":3}}' > "$OUT/job-edit-wide.json"
say "      edit, one 1280×768 reference (warm): $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled; worker run $(worker $OUT/job-edit-wide.json) s"
fetch $P "$OUT/job-edit-wide.json" "$OUT/gaea-edit-wide"
check "a 1280×768 input is edited at 1312×800 (about 1024² at its aspect), reported size_snapped" py "
import json; j = json.load(open('$OUT/job-edit-wide.json')); o = j['result']['outputs'][0]
assert j['outcome'] == 'succeeded' and (o['width'], o['height']) == (1312, 800), o
assert any(x['code'] == 'size_snapped' for x in j.get('warnings', [])), j.get('warnings')"
$CLI ledger > "$OUT/ledger-2-both.txt"

# 3. Count, warnings, limits.
job $P '{"operation":"image.generate","model":"qwen-image-flash","inputs":{"prompt":"'$FOX'"},"params":{"size":{"width":768,"height":512},"count":2,"seed":7,"negative_prompt":"fog"}}' > "$OUT/job-count.json"
check "count 2 gives two different 768×512 images, seeds 7 and 8" py "
import json; o = json.load(open('$OUT/job-count.json'))['result']['outputs']
assert len(o) == 2 and o[0]['sha256'] != o[1]['sha256'] and all(x['width'] == 768 and x['height'] == 512 for x in o), o"
check "Flash reports the negative prompt as ignored" py "
import json; w = json.load(open('$OUT/job-count.json')).get('warnings', []); assert any(x['code'] == 'negative_prompt_ignored' for x in w), w"
F=($(for _ in 1 2 3 4; do upload $P "$OUT/gaea-flash-0.png"; done))
FOUR='{"operation":"image.edit","model":"qwen-image-edit","inputs":{"images":[{"upload":"'$F[1]'"},{"upload":"'$F[2]'"},{"upload":"'$F[3]'"},{"upload":"'$F[4]'"}],"instruction":"'$EDIT'"},"params":{"seed":7}}'
mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$FOUR" > "$OUT/job-four.json"
check "four references are refused out_of_limits at submit" py "
import json; j = json.load(open('$OUT/job-four.json')); e = j.get('error') or {}
assert e.get('code') == 'out_of_limits' and e.get('param') == 'images', j; print(e)"
stop $P

# The in-process side, after Gaea has stopped: same requests, same lanes, same input bytes.
"$INPROC" --model qwen-image-flash --prompt "$FOX" --seed 42 --out "$OUT/inproc-flash.png" > "$OUT/inproc-flash.json" 2>> "$LOG"
check "Flash through Gaea is byte for byte the in-process image" same "$OUT/gaea-flash-0.png" "$OUT/inproc-flash.png"
"$INPROC" --model qwen-image-edit --prompt "$EDIT" --seed 7 --image "$OUT/gaea-flash-0.png" --image "$OUT/gaea-cabin-0.png" --runs 1 --out "$OUT/inproc-edit.png" > "$OUT/inproc-edit.json" 2>> "$LOG"
check "the two-reference edit through Gaea is byte for byte the in-process image" same "$OUT/gaea-edit-0.png" "$OUT/inproc-edit.png"

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
