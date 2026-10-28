#!/bin/zsh
# AB-T-0365's acceptance: gaea-plugin-z-image installed in Gaea by repo URL and run through MES.
#
#   1. Gaea installs and enables the plugin: Turbo is image.generate's default, Z-Image is there for `best`, and both
#      offer image.edit named-only;
#   2. Turbo int4, 1024², seed 42 through Gaea gives the image z-image-swift gives in-process for the same request
#      (bench-inproc, AB-T-0356's in-process harness), compared byte for byte;
#   3. quality `best` reaches the base model; `count` 2 gives two seeds; a named lane runs that lane; Turbo reports a
#      negative prompt as ignored; image.edit re-generates an image;
#   4. every recorded GPP session passes the validator.
#
#   tools/acceptance-z-image.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); PLUGIN_DIST (gaea-plugin-z-image's dist/, default
# ../gaea-plugin-z-image/dist); BENCH_INPROC (Benchmarks/AB-T-0356's bench-inproc, Release). REPO_FROM=github installs the
# published release instead of serving PLUGIN_DIST through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-z-image/dist}
INPROC=${BENCH_INPROC:?path to bench-inproc}
ID=com.xocialize.gaea.z-image
PROMPT="A lighthouse on a rocky coast at dusk, photorealistic, 35mm film"
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { # name, then a command whose exit status decides
  local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
job() { # port, json body → prints the settled job (a cold base-model run can take minutes)
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
start() { # home, port, extra args… → waits for the operator socket
  local home=$1 port=$2; shift 2
  GAEA_HOME=$home "$GAEA" --headless --port $port --no-advertise "$@" > "$home.out" 2>&1 &
  for _ in {1..50}; do [[ -S $home/operator.sock ]] && return; sleep 0.2; done
  say "Gaea at $home didn't start:"; cat "$home.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# Z-Image plugin acceptance (AB-T-0365) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), z-image $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize/gaea-plugin-z-image/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/z-image-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/z-image-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8768 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8768
fi

H=$WORK/main; P=17650
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs z-image $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize/gaea-plugin-z-image | grep -q 'Installed .* $VERSION'"
$CLI models > "$OUT/models.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.generate: Turbo is the default, Z-Image is offered for best" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.generate']['models']}
assert m['z-image-turbo'].get('default') is True and 'best' in m['z-image']['quality_tiers'], m"
check "image.edit: both, named-only" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
assert all(x.get('named_only') for x in ops['image.edit']['models']) and len(ops['image.edit']['models']) == 2"

# 2. Parity with in-process z-image-swift.
BODY='{"operation":"image.generate","inputs":{"prompt":"'$PROMPT'"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
t0=$(py 'import time; print(time.time())')
job $P "$BODY" > "$OUT/job-turbo-cold.json"
say "      cold: $(py "import time; print(round(time.time()-$t0,2))") s from submit to settled (launch, prepare int4, generate)"
job $P "$BODY" > "$OUT/job-turbo-warm.json"
fetch $P "$OUT/job-turbo-cold.json" "$OUT/gaea-turbo"
check "Turbo int4 1024² seed 42 through Gaea succeeds with one 1024² PNG" py "
import json; j = json.load(open('$OUT/job-turbo-cold.json')); o = j['result']['outputs']
assert j['outcome'] == 'succeeded' and len(o) == 1 and o[0]['width'] == 1024 and o[0]['height'] == 1024, j
assert j['result']['provenance']['model']['id'] == 'z-image-turbo', j['result']['provenance']"
"$INPROC" --prompt "$PROMPT" --size 1024 --steps 8 --seed 42 --out "$OUT/inproc-turbo.png" > "$OUT/inproc.json" 2>> "$LOG"
check "…and it is byte for byte the image z-image-swift makes in-process" py "
import hashlib; a, b = (hashlib.sha256(open(f, 'rb').read()).hexdigest() for f in ('$OUT/gaea-turbo-0.png', '$OUT/inproc-turbo.png'))
print(a, b); assert a == b"
check "a warm run gives the same bytes again" py "
import json; a, b = (json.load(open(f))['result']['outputs'][0]['sha256'] for f in ('$OUT/job-turbo-cold.json', '$OUT/job-turbo-warm.json')); assert a == b, (a, b)"

# 3. Routing, count, lanes, warnings, edit.
job $P '{"operation":"image.generate","inputs":{"prompt":"'$PROMPT'"},"params":{"quality":"best","size":{"width":1024,"height":1024},"seed":42,"negative_prompt":"blurry, oversaturated"}}' > "$OUT/job-best.json"
check "quality best reaches Z-Image (28 steps, guidance 4, the negative prompt honoured)" py "
import json; r = json.load(open('$OUT/job-best.json'))['result']; e = r['effective']
assert r['provenance']['model']['id'] == 'z-image', r['provenance']; assert e['x-zimage.steps'] == 28 and e['x-zimage.guidance'] == 4, e
assert e['negative_prompt'] == 'blurry, oversaturated', e"
fetch $P "$OUT/job-best.json" "$OUT/gaea-base"
job $P '{"operation":"image.generate","inputs":{"prompt":"'$PROMPT'"},"params":{"size":{"width":768,"height":512},"count":2,"seed":7,"negative_prompt":"fog"}}' > "$OUT/job-count.json"
check "count 2 gives two different 768×512 images, seeds 7 and 8" py "
import json; j = json.load(open('$OUT/job-count.json')); o = j['result']['outputs']
assert len(o) == 2 and o[0]['sha256'] != o[1]['sha256'] and all(x['width'] == 768 and x['height'] == 512 for x in o), o"
check "Turbo reports the negative prompt as ignored" py "
import json; w = json.load(open('$OUT/job-count.json')).get('warnings', []); assert any(x['code'] == 'negative_prompt_ignored' for x in w), w"
job $P '{"operation":"image.generate","inputs":{"prompt":"'$PROMPT'"},"params":{"size":{"width":1000,"height":1000},"seed":42},"extensions":{"x-gaea.lane":"int8"}}' > "$OUT/job-int8.json"
check "x-gaea.lane int8 runs lane int8, and 1000² snaps to 992²" py "
import json; j = json.load(open('$OUT/job-int8.json')); w = j['result']['effective']['model_params']['x-gaea.worker']
assert w['lane'] == 'int8', w; assert j['result']['outputs'][0]['width'] == 992, j['result']['outputs']
assert any(x['code'] == 'size_snapped' for x in j.get('warnings', [])), j.get('warnings')"
UPLOAD=$(mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @"$OUT/gaea-turbo-0.png" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])")
job $P '{"operation":"image.edit","model":"z-image-turbo","inputs":{"images":[{"upload":"'$UPLOAD'"}],"instruction":"the same lighthouse in a snowstorm at night"},"params":{"strength":0.8,"seed":3}}' > "$OUT/job-edit.json"
check "image.edit on Turbo re-generates the 1024² input at strength 0.8" py "
import json; j = json.load(open('$OUT/job-edit.json')); r = j['result']
assert j['outcome'] == 'succeeded', j; assert r['outputs'][0]['width'] == 1024 and r['effective']['strength'] == 0.8, r"
fetch $P "$OUT/job-edit.json" "$OUT/gaea-edit"
$CLI ledger > "$OUT/ledger.txt"
stop $P

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
