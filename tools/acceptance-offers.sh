#!/bin/zsh
# AB-T-0364's acceptance, against a built Gaea.app and a locally built demo plugin (0.3.0 or later, which offers
# image.generate on demo-gradient):
#
#   1. a plugin's MES offer runs as itself: its options are MES extensions, its PNGs are the job's outputs, byte for
#      byte what the worker writes (checked against the same request sent straight to the worker);
#   2. a model without an offer of its own still runs through the G0 mock;
#   3. the models root is a setting: `gaea models root`, kept in gaea.sqlite across a restart, sent in `configure`;
#      `--models-root` overrides it for one launch;
#   4. the MES Base conformance suite still passes with the demo plugin.
#
#   tools/acceptance-offers.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh), DEMO_DIST (gaea-plugin-demo's dist/, default ../gaea-plugin-demo/dist) and
# MES_CONFORMANCE (media-engine-spec's mes-conformance). The demo's release is served by tools/release-standin.py, so
# this runs before the release is published.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
DEMO_DIST=${DEMO_DIST:-../gaea-plugin-demo/dist}
CONFORMANCE=${MES_CONFORMANCE:?path to mes-conformance}
ID=com.xocialize.gaea.demo
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
  for _ in 1 2 3 4 5 6; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
start() { # home, port, extra args… → waits for the operator socket
  local home=$1 port=$2; shift 2
  GAEA_HOME=$home "$GAEA" --headless --port $port --no-advertise "$@" > "$home.out" 2>&1 &
  for _ in {1..50}; do [[ -S $home/operator.sock ]] && return; sleep 0.2; done
  say "Gaea at $home didn't start:"; cat "$home.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }

VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$DEMO_DIST/manifest.json")
say "# Gaea offers acceptance (AB-T-0364) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), demo $VERSION"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"

# The demo's release, as GitHub would serve it.
REL=$WORK/standin/xocialize/gaea-plugin-demo/v$VERSION; mkdir -p "$REL"
cp "$DEMO_DIST/demo-$VERSION.gaeaplugin.zip" "$DEMO_DIST/demo-$VERSION.gaeaplugin.zip.sha256" "$DEMO_DIST/manifest.json" "$REL/"
python3 tools/release-standin.py "$WORK/standin" --port 8767 > "$WORK/standin.out" 2>&1 &
STANDIN=$!; sleep 1
export GAEA_GITHUB_API=http://127.0.0.1:8767
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN

H=$WORK/main; P=17640
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs demo $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize/gaea-plugin-demo | grep -q 'Installed .* $VERSION'"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.generate offers demo-gradient (default) and the mocked demo-matmul" python3 -c "
import json; ops = json.load(open('$OUT/operations.json'))['operations']; g = [o for o in ops if o['operation'] == 'image.generate'][0]
models = {m['id']: m for m in g['models']}; assert models['demo-gradient'].get('default') is True, models; assert 'demo-matmul' in models"
check "the offer's x- param is an MES extension, beside x-gaea.lane" python3 -c "
import json; g = [o for o in json.load(open('$OUT/operations.json'))['operations'] if o['operation'] == 'image.generate'][0]
names = [e['name'] for e in g['extensions']]; assert 'x-gaea.gradient_angle' in names and 'x-gaea.lane' in names, names"

# 1. The offer, run as itself.
BODY='{"operation":"image.generate","model":"demo-gradient","inputs":{"prompt":"a lighthouse at dusk"},"params":{"size":{"width":645,"height":480},"count":2,"seed":7},"extensions":{"x-gaea.gradient_angle":30}}'
job $P "$BODY" > "$OUT/job-gradient.json"
check "the job succeeds with two PNG images, 640×480 after size_snapped" python3 -c "
import json; j = json.load(open('$OUT/job-gradient.json')); r = j['result']; o = r['outputs']
assert j['outcome'] == 'succeeded', j; assert [x['media_type'] for x in o] == ['image/png'] * 2, o
assert all(x['width'] == 640 and x['height'] == 480 for x in o), o
assert any(w['code'] == 'size_snapped' for w in j.get('warnings', [])), j.get('warnings')"
check "effective carries the worker's own (size, the angle) and x-gaea.worker" python3 -c "
import json; e = json.load(open('$OUT/job-gradient.json'))['result']['effective']; w = e['model_params']['x-gaea.worker']
assert e['size'] == {'width': 640, 'height': 480}, e; assert e['x-gaea.gradient_angle'] == 30, e
assert w['plugin'] == '$ID' and w['version'] == '$VERSION' and w['operation'] == 'image.generate', w"
i=0; for href in $(python3 -c "import json; [print(o['href']) for o in json.load(open('$OUT/job-gradient.json'))['result']['outputs']]"); do
  mes -o "$OUT/gradient-$i.png" "http://127.0.0.1:$P$href"; i=$((i+1)); done
# The same request straight to the worker (GPP over stdio, no Gaea), then compare bytes.
python3 tools/gpp-run.py "$DEMO_DIST/demo.gaeaplugin" "$WORK/direct" demo-gradient fp32 image.generate \
  '{"size":{"width":645,"height":480},"count":2}' '{"x-gaea.gradient_angle":30}' 7 'a lighthouse at dusk' > "$OUT/direct.json" 2>> "$LOG"
check "the served PNGs are byte for byte what the worker writes" python3 -c "
import hashlib, json; direct = json.load(open('$OUT/direct.json'))
served = [hashlib.sha256(open(f'$OUT/gradient-{i}.png', 'rb').read()).hexdigest() for i in range(2)]
assert served == direct['sha256'], (served, direct['sha256']); print(served)"

# 2. The mock still covers a model without an offer.
job $P '{"operation":"image.generate","model":"demo-matmul","inputs":{"prompt":"mocked"},"extensions":{"x-gaea.demo_matmul":{"n":1024,"iterations":3}}}' > "$OUT/job-mock.json"
check "demo-matmul runs its GPU stage through the mock" zsh -c "grep -q '\"outcome\":\"succeeded\"' $OUT/job-mock.json && grep -q 'Device(gpu, 0)' $OUT/job-mock.json"

# 3. The models root.
check "the models root defaults to MLXEngine's store" zsh -c "$CLI models root | grep -q 'MLXEngine/Models (MLXEngine.s store, the default)'"
mkdir -p "$WORK/models"
check "a folder that doesn't exist is refused" zsh -c "! $CLI models root $WORK/nowhere"
check "gaea models root <folder> sets it" zsh -c "$CLI models root $WORK/models | grep -q '$WORK/models (set by the operator)'"
check "status shows it" zsh -c "$CLI status | grep -q 'Models:    $WORK/models'"
stop $P; start $H $P
check "it survives a restart" zsh -c "$CLI models root | grep -q '$WORK/models (set by the operator)'"
job $P "$BODY" > "$OUT/job-after-restart.json"
LAST=$(ls -t $H/Logs/sessions/*.gpp | head -1)
check "the next worker's configure carries it" zsh -c "grep '\"type\":\"configure\"' $LAST | grep -q '\"models_root\":\"$WORK/models\"'"
check "gaea models root default goes back to MLXEngine's store" zsh -c "$CLI models root default | grep -q '(MLXEngine.s store, the default)'"
stop $P
start $H $P --models-root "$WORK/models"
check "--models-root overrides it for one launch" zsh -c "$CLI models root | grep -q '$WORK/models (--models-root, for this launch)'"
stop $P

# 4. Base conformance with demo $VERSION installed (open mode; Base's shortest outputs TTL, 60 s, for BASE-071).
start $H $P --outputs-ttl 60
"$CONFORMANCE" engine "http://127.0.0.1:$P/mes/v0" --max-ttl-wait 75 -o "$OUT/conformance-open" > "$OUT/conformance-open.txt" 2>&1
check "MES Base conformance, open mode: Base 0.1 conforms" grep -q 'Base 0.1: conforms' "$OUT/conformance-open.txt"
say "      $(tail -2 "$OUT/conformance-open.txt" | head -1)"
stop $P

# Every recorded GPP session passes the validator.
for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
cp "$(ls -t $H/Logs/sessions/*.gpp | tail -1)" "$OUT/session-first.gpp"
kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
