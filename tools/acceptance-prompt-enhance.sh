#!/bin/zsh
# AB-T-0370's acceptance through Gaea: gaea-plugin-prompt-enhance (the LLM plugin) installed by repo URL beside the
# Klein and Z-Image plugins, and the image normalizer calling its helper, x-gaea.prompt.enhance, only where a profile
# asks for a rewrite:
#
#   1. the backbones are offered for image.enhance_prompt, and image.generate declares prompt_enhance;
#   2. Klein (recommended) with a short prompt under auto: enhanced, the helper called;
#   3. Klein with a 70-word prompt under auto: passed through, the helper not called;
#   4. Z-Image (optional) under auto: not recommended, the helper not called; with prompt_enhance on: enhanced, called;
#   5. prompt_enhance off: the text as typed (outcome off), the helper not called;
#   6. image.enhance_prompt for Klein: the rewrite as data, called;
#   7. the helper ran exactly three times (the plugin's recorded GPP sessions), and every session passes the validator.
#
#   tools/acceptance-prompt-enhance.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; PLUGIN_DIST (default ../gaea-plugin-prompt-enhance/dist); the Klein and Z-Image releases on
# GitHub; the backbones' and models' weights in MLXEngine's store. REPO_FROM=github installs the enhancer's published
# release instead of serving PLUGIN_DIST through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-prompt-enhance/dist}
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
  local id j; id=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id") or d)')
  for _ in {1..60}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' 2>/dev/null && { print -r -- "$j"; return }
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
py() { python3 -c "$1" }
calls() { cat $H/Logs/sessions/com.xocialize.gaea.prompt-enhance-*.gpp 2>/dev/null | grep -c '^H .*"operation":"x-gaea.prompt.enhance"' }
# name, json body, expected outcome (or "none" for no report), whether the helper runs (1 or 0)
gen() {
  local name=$1 body=$2 outcome=$3 called=$4 before=$(calls)
  job $P "$body" > "$OUT/job-$name.json"
  local after=$(calls)
  check "$name: $outcome, the helper $([[ $called == 1 ]] && print called || print 'not called')" py "
import json; j = json.load(open('$OUT/job-$name.json')); assert j['outcome'] == 'succeeded', (j['outcome'], j.get('error'))
e = (j['result']['effective'].get('model_params') or {}).get('prompt_enhancement'); print(json.dumps(e)[:400])
assert ('$outcome' == 'none' and not e) or (e and e.get('outcome') == '$outcome'), e
assert $after - $before == $called, ('helper runs', $after - $before)"
}

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# Prompt enhancer acceptance (AB-T-0370) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), prompt-enhance $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/main; P=17750
start $H $P
export GAEA_HOME=$H
check "add FLUX.2 Klein and Z-Image from GitHub" zsh -c "$CLI plugins add https://github.com/xocialize/gaea-plugin-flux2-klein | grep -q Installed && $CLI plugins add https://github.com/xocialize/gaea-plugin-z-image | grep -q Installed"
if [[ ${REPO_FROM:-} != github ]]; then
  stop $P
  REL=$WORK/standin/xocialize/gaea-plugin-prompt-enhance/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/prompt-enhance-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/prompt-enhance-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8773 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  GAEA_GITHUB_API=http://127.0.0.1:8773 GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise > "$H.out" 2>&1 &
  for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
fi
check "add the prompt enhancer $VERSION by repo URL" zsh -c "$CLI plugins add https://github.com/xocialize/gaea-plugin-prompt-enhance | grep -q 'Installed .* $VERSION'"
$CLI models > "$OUT/models.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "image.enhance_prompt offers the backbones; image.generate declares prompt_enhance" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
print([m['id'] for m in ops['image.enhance_prompt']['models']]); assert 'qwen3.5-4b' in [m['id'] for m in ops['image.enhance_prompt']['models']]
assert 'prompt_enhance' in ops['image.generate']['params']['properties']"

SHORT="a fox in the snow"
LONG="a red fox with a thick winter coat stands alert in deep fresh snow at the edge of a pine forest at dawn, low golden sunlight raking across the drifts, frost on its whiskers, breath visible in the cold air, shot on a telephoto lens with shallow depth of field, the background trees softly blurred, cool blue shadows and warm highlights, crisp detail in the fur, a quiet and still winter morning"
KLEIN='{"operation":"image.generate","model":"klein-4b","params":{"size":{"width":512,"height":512},"seed":42'
ZIMG='{"operation":"image.generate","model":"z-image-turbo","params":{"size":{"width":512,"height":512},"seed":42'
gen klein-auto "$KLEIN},\"inputs\":{\"prompt\":\"$SHORT\"}}" enhanced 1
gen klein-detailed "$KLEIN},\"inputs\":{\"prompt\":\"$LONG\"}}" passed_through 0
gen zimage-auto "$ZIMG},\"inputs\":{\"prompt\":\"$SHORT\"}}" not_recommended 0
gen zimage-on "$ZIMG,\"prompt_enhance\":\"on\"},\"inputs\":{\"prompt\":\"$SHORT\"}}" enhanced 1
gen klein-off "$KLEIN,\"prompt_enhance\":\"off\"},\"inputs\":{\"prompt\":\"$SHORT\"}}" off 0
before=$(calls)
job $P '{"operation":"image.enhance_prompt","inputs":{"prompt":"'$SHORT'"},"params":{"target_operation":"image.generate","target_model":"klein-4b","seed":42}}' > "$OUT/job-preview.json"
after=$(calls)
check "image.enhance_prompt for Klein: the rewrite as data, the helper called" py "
import json; j = json.load(open('$OUT/job-preview.json')); assert j['outcome'] == 'succeeded', j.get('error')
o = j['result']['outputs'][0]; print(json.dumps(o)[:400]); assert o.get('value', {}).get('applied') is True, o
assert $after - $before == 1"
check "the helper ran three times in all" zsh -c "(( \$(cat $H/Logs/sessions/com.xocialize.gaea.prompt-enhance-*.gpp | grep -c '^H .*\"operation\":\"x-gaea.prompt.enhance\"') == 3 ))"
$CLI ledger > "$OUT/ledger.txt"
grep -F 'scheduler:' "$H.out" > "$OUT/scheduler.log"
stop $P
for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
