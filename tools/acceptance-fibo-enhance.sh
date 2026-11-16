#!/bin/zsh
# AB-A-0300's acceptance through Gaea: gaea-plugin-prompt-enhance with prompt-enhance-kit's `fibo2` profile, beside
# gaea-plugin-fibo2 (Fibo 2.0 Dev, named-only, opt-in, CC BY-NC with users' acceptance), both by repo URL:
#
#   1. fibo-2-dev is offered once the operator enables it, and image.generate declares prompt_enhance;
#   2. a short prompt under auto: enhanced on qwen3.5-9b with the fibo2 profile; what ran (effective.prompt) is one
#      VGL caption, a JSON object with short_description and objects; the backbone is listed as a helper;
#   3. that caption sent as the prompt: passed through, the helper not called, and the same picture as 2;
#   4. prompt_enhance off: the text as typed, the helper not called;
#   5. prompt_enhance on: enhanced, the helper called;
#   6. image.enhance_prompt for fibo-2-dev: the caption as data, the helper called;
#   7. an edit's instruction: EDIT (needs_vision by default, the helper not called; enhanced once Gaea and the
#      normalizer send a text-only edit to the helper, AB-A-0303);
#   8. every recorded GPP session passes the validator.
#
#   tools/acceptance-fibo-enhance.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (or APP); PLUGIN_DIST (default ../gaea-plugin-prompt-enhance/dist) unless REPO_FROM=github;
# the Fibo plugin's release on GitHub; Fibo 2.0 Dev's and the Qwen3.5 9B's weights under MODELS (default
# /Volumes/DEV_VOL1/Models). STEPS (default 8) and SIZE (default 512) keep Fibo's runs short.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-prompt-enhance/dist}
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
STEPS=${STEPS:-8}; SIZE=${SIZE:-512}; EDIT=${EDIT:-needs_vision}
MODEL=fibo-2-dev; SPDX=CC-BY-NC-4.0
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @$1 | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
job() { # body file, out file
  local id j; id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' --data-binary @$1 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))')
  [[ -z $id ]] && { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' --data-binary @$1 > "$2"; return }
  for _ in {1..360}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
  done
  print -r -- "$j" > "$2"
}
calls() { cat /dev/null $H/Logs/sessions/com.xocialize.gaea.prompt-enhance-*.gpp(N) | grep -c '^H .*"operation":"x-gaea.prompt.enhance"' }
body() { python3 - "$@" <<'PYEOF'
import json, sys
kind, model, spdx, text, params, ext, upload = (sys.argv[1:] + [''] * 7)[:7]
b = {"operation": "image." + kind, "model": model, "params": json.loads(params or '{}'), "policy": {"accepted": [spdx]}}
if ext: b["extensions"] = json.loads(ext)
b["inputs"] = {"prompt": text} if kind == "generate" else {"images": [{"upload": upload}], "instruction": text}
print(json.dumps(b))
PYEOF
}
# name, body, expected outcome, whether the helper runs (1 or 0)
run() {
  local name=$1 outcome=$3 called=$4 before=$(calls)
  print -r -- "$2" > "$OUT/body-$name.json"
  job "$OUT/body-$name.json" "$OUT/job-$name.json"
  local after=$(calls)
  if [[ $(py "import json; print(json.load(open('$OUT/job-$name.json')).get('outcome'))") == succeeded ]]; then
    mes -o "$OUT/$name.png" "http://127.0.0.1:$P$(py "import json; print(json.load(open('$OUT/job-$name.json'))['result']['outputs'][0]['href'])")"
  fi
  say "      $name: $(py "import json; j=json.load(open('$OUT/job-$name.json')); r=j.get('result') or {}; e=(r.get('effective') or {}); p=(e.get('model_params') or {}).get('prompt_enhancement') or {}; print(j.get('outcome'), p.get('outcome'), p.get('profile'), p.get('backbone'), 'attempts', p.get('attempts'), [x['code'] for x in j.get('warnings', [])], (j.get('error') or {}).get('message','')[:200])")"
  check "$name: $outcome, the helper $([[ $called == 1 ]] && print called || print 'not called')" py "
import json; j = json.load(open('$OUT/job-$name.json')); assert j['outcome'] == 'succeeded', (j['outcome'], j.get('error'))
e = (j['result']['effective'].get('model_params') or {}).get('prompt_enhancement'); print(json.dumps(e)[:400])
assert e and e.get('outcome') == '$outcome', e
assert $after - $before == $called, ('helper runs', $after - $before)"
}
PARAMS='{"size":{"width":'$SIZE',"height":'$SIZE'},"seed":42'
EXT='{"x-fibo2.steps":'$STEPS'}'
gen() { run $1 "$(body generate $MODEL $SPDX "$2" "$PARAMS${5:-}}" "$EXT")" $3 $4 }   # name, prompt, outcome, called, [more params]

say "# Fibo 2.0 prompt enhancement (AB-A-0300) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), prompt-enhance from ${REPO_FROM:-stand-in}, $STEPS steps at $SIZE²"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/home; P=17752
start() { GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" > "$H.out" 2>&1 &
  for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start:"; cat "$H.out" >> "$LOG" }
stop() { pkill -TERM -f "$GAEA --headless --port $P"; sleep 1 }
start
export GAEA_HOME=$H
check "add Fibo 2.0 from GitHub" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-fibo2 | grep -q Installed"
if [[ ${REPO_FROM:-} != github ]]; then
  stop
  VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
  REL=$WORK/standin/xocialize-code/gaea-plugin-prompt-enhance/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/prompt-enhance-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/prompt-enhance-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8775 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8775
  start
fi
check "add the prompt enhancer by repo URL" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-prompt-enhance | tee -a '$LOG' | grep -q Installed"
$CLI plugins > "$OUT/plugins.txt" 2>&1
$CLI models enable $MODEL >> "$LOG" 2>&1
$CLI models > "$OUT/models.txt" 2>&1
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "enabled, $MODEL is offered on image.generate and image.edit, and image.generate declares prompt_enhance" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
for op in ('image.generate', 'image.edit'): assert '$MODEL' in [m['id'] for m in ops[op]['models']], op
assert 'prompt_enhance' in ops['image.generate']['params']['properties']
assert 'qwen3.5-9b' in [m['id'] for m in ops['image.enhance_prompt']['models']]"

SHORT="a fox in the snow"
gen auto "$SHORT" enhanced 1
check "what ran is one VGL caption: a JSON object with short_description and objects, far longer than the prompt" py "
import json; j = json.load(open('$OUT/job-auto.json')); r = j['result']
c = json.loads(r['effective']['prompt']); print(len(r['effective']['prompt']), 'characters;', list(c)[:12])
assert isinstance(c, dict) and c.get('short_description') and c.get('objects'), list(c)
assert len(r['effective']['prompt']) > 1000
open('$OUT/caption.json', 'w').write(r['effective']['prompt'])
e = r['effective']['model_params']['prompt_enhancement']; assert e['profile'] == 'fibo2' and e['backbone'] == 'qwen3.5-9b', e
assert 'prompt_rewritten' in [w['code'] for w in j.get('warnings', [])]
helpers = [h for h in (r.get('provenance') or {}).get('helpers', []) if h.get('id') == 'qwen3.5-9b']; print(helpers); assert helpers"
if [[ -f $OUT/caption.json ]]; then
  run caption "$(python3 - "$OUT/caption.json" "$MODEL" "$SPDX" "$PARAMS}" "$EXT" <<'PYEOF'
import json, sys
caption, model, spdx, params, ext = sys.argv[1:]
print(json.dumps({"operation": "image.generate", "model": model, "params": json.loads(params), "policy": {"accepted": [spdx]},
                  "extensions": json.loads(ext), "inputs": {"prompt": open(caption).read()}}))
PYEOF
)" passed_through 0
  check "the caption as the prompt gives the picture the rewrite gave" cmp "$OUT/auto.png" "$OUT/caption.png"
fi
gen off "$SHORT" off 0 ',"prompt_enhance":"off"'
gen on "$SHORT" enhanced 1 ',"prompt_enhance":"on"'
before=$(calls)
print -r -- '{"operation":"image.enhance_prompt","inputs":{"prompt":"'$SHORT'"},"params":{"target_operation":"image.generate","target_model":"'$MODEL'","seed":42}}' > "$OUT/body-preview.json"
job "$OUT/body-preview.json" "$OUT/job-preview.json"
after=$(calls)
check "image.enhance_prompt for $MODEL: the caption as data, the helper called" py "
import json; j = json.load(open('$OUT/job-preview.json')); assert j['outcome'] == 'succeeded', j.get('error')
o = j['result']['outputs'][0]; print(json.dumps(o)[:300]); assert o.get('value', {}).get('applied') is True, o
assert $after - $before == 1"
if [[ -f $OUT/auto.png ]]; then
  run edit "$(body edit $MODEL $SPDX "make the sky a deep red sunset" '{"seed":42}' "$EXT" "$(upload $OUT/auto.png)")" $EDIT $([[ $EDIT == enhanced ]] && print 1 || print 0)
  say "      the instruction that ran: $(py "import json; print(json.load(open('$OUT/job-edit.json'))['result']['effective'].get('instruction') or 'as typed')")"
fi
$CLI ledger > "$OUT/ledger.txt" 2>&1
stop
for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
