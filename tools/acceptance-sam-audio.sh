#!/bin/zsh
# AB-T-0473's acceptance for gaea-plugin-sam-audio (SAM-Audio base, Meta's SAM License): audio.separate by description
# (MES Audio 0.1 with RFC 0008) through Gaea, installed from GitHub beside gaea-plugin-demo.
#
#   1. Restricted: sam-audio-base is off until the operator enables it; then audio.separate offers it with the SAM
#      licence (commercial use allowed, accepted_required, user_accept_required, a notice) and its supports:
#      described_target, spans, the target and residual stems, regenerated, an AudioSeal watermark, at most 30 s. It is
#      not named-only: the licence allows commercial use, so only the opt-in and users' acceptance apply.
#   2. Users' acceptance: a job without policy.accepted is 422 policy_unmet (terms_not_accepted), named or not. A
#      separate job with no description and no model runs on the demo's separator (labelled stems); one with a
#      description and no model runs on SAM-Audio, the only offer that takes one.
#   3. Described separations, each stem the mixture's length at 48 kHz mono, each byte for byte sam-audio-inproc's:
#      - "speech": target and residual, effective.describe echoed;
#      - the target alone, asked with untrimmed mixed-case text: one output, effective.describe "speech";
#      - "music" with two spans, echoed in effective.spans;
#      - the same seed again gives the same bytes.
#   4. Refusals: no describe; a description of 201 characters; 33 spans; a span that ends before it starts; a span
#      past the mixture's end (out_of_limits, at submit or when the job runs); a stem SAM-Audio doesn't make; a mixture
#      over 30 s (out_of_limits).
#   5. Every recorded GPP session passes the validator.
#
#   tools/acceptance-sam-audio.sh <short-work-dir> <evidence-dir>
#
# Needs: APP (default dist/Gaea.app, 1.6.0 or later); GAEA_GITHUB_TOKEN; the plugin repo at ../gaea-plugin-sam-audio for
# its fixture and sam-audio-inproc (release, --build-system swiftbuild); the weights
# (mlx-community/sam-audio-base-swift-fp16) in MODELS (default /Volumes/DEV_VOL1/Models/Models), which Gaea uses as its
# models root.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=${PLUGIN_REPO:-../gaea-plugin-sam-audio}
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models/Models}
INPROC=${SAM_INPROC:-$PLUGIN/.build/out/Products/Release/sam-audio-inproc}
MIX=$PLUGIN/scripts/fixtures/mixture.wav
SAM=sam-audio-base; SPDX=LicenseRef-SAM
mkdir -p "$OUT"; rm -rf "$WORK" "$OUT/sessions"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
settle() {
  local j
  for _ in {1..90}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$1?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: audio/wav" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
body() { # mixture file, params JSON, model ('' for none), accepted (yes|no)
  python3 - "$(upload $1)" "$2" "$3" "$4" <<'PY'
import json, sys
up, params, model, accepted = sys.argv[1:5]
b = {'operation': 'audio.separate', 'inputs': {'audio': {'upload': up}}, 'params': json.loads(params)}
if model: b['model'] = model
if accepted == 'yes': b['policy'] = {'accepted': ['LicenseRef-SAM']}
print(json.dumps(b))
PY
}
# sep <name> <mixture> <params> [model] [accepted]: submit; a 201 is settled. $OUT/<name>.json is the job or the refusal,
# <name>.status the HTTP status, and each stem is fetched to <name>-<stem>.wav.
sep() {
  local name=$1 b; b=$(body "$2" "$3" "${4-$SAM}" "${5:-yes}")
  mes -o "$OUT/$name.json" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$b" > "$OUT/$name.status"
  if [[ $(cat "$OUT/$name.status") == 201 ]]; then
    settle "$(py "import json; print(json.load(open('$OUT/$name.json'))['id'])")" > "$OUT/$name.json"
    python3 -c "import json,sys; [print(o['name'], o['href']) for o in (json.load(open(sys.argv[1])).get('result') or {}).get('outputs', []) if o.get('href')]" "$OUT/$name.json" |
      while read stem href; do mes -o "$OUT/$name-$stem.wav" "http://127.0.0.1:$P$href"; done
  fi
  say "      $name: HTTP $(cat "$OUT/$name.status") $(py "import json; j=json.load(open('$OUT/$name.json')); r=j.get('result') or {}; e=j.get('error') or {}; w=(r.get('effective') or {}).get('model_params',{}).get('x-gaea.worker',{}); print(j.get('outcome', ''), (r.get('provenance') or {}).get('model',{}).get('id', ''), w.get('seconds', ''), [o['name'] for o in r.get('outputs', [])], e.get('code', ''), e.get('param', ''), e.get('message','')[:140])")"
}
ok() { py "import json; j=json.load(open('$OUT/$1.json')); assert j.get('outcome') == 'succeeded', j.get('error') or j" }
# refused <name> <code>: a 4xx with that code, or a job that failed with it and returned nothing.
refused() { py "
import json; j=json.load(open('$OUT/$1.json')); s=open('$OUT/$1.status').read().strip(); e=j.get('error') or {}; print(s, j.get('outcome'), e)
assert e.get('code') == '$2' and (s.startswith('4') or (j.get('outcome') == 'failed' and not (j.get('result') or {}).get('outputs')))" }
inproc() { # name, seed, params → $OUT/inproc-<name>/<stem>.wav
  $INPROC --mixture $MIX --params "$3" --seed $2 --models-root "$MODELS" --out-dir "$OUT/inproc-$1" 2>> "$LOG" | tail -1 > "$OUT/inproc-$1.json"
}
same() { cmp "$1" "$2" }
facts() { python3 -c "import wave,sys; w=wave.open(sys.argv[1]); print(w.getnframes(), w.getframerate(), w.getnchannels())" "$1" }

say "# SAM-Audio acceptance (AB-T-0473) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), sam-audio from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/main; P=17695
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" > "$H.out" 2>&1 &
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
export GAEA_HOME=$H
check "add by repo URL installs the demo" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-demo | grep -q Installed"
check "add by repo URL installs SAM-Audio" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-sam-audio | tee -a $LOG | grep -q 'Installed SAM-Audio'"

# 1. Restricted and opt-in.
$CLI models list > "$OUT/models-before.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations-before.json"
check "the model starts off, and SAM-Audio offers nothing until the operator enables it" py "
import json; lines = [l for l in open('$OUT/models-before.txt') if '$SAM' in l]; assert len(lines) == 1 and lines[0].startswith('off'), lines
ops = json.load(open('$OUT/operations-before.json'))['operations']
assert not any(m['id'] == '$SAM' for o in ops for m in o['models'])"
$CLI models enable $SAM >> "$LOG" 2>&1
$CLI models list > "$OUT/models.txt"; grep "$SAM" "$OUT/models.txt" | sed 's/^/      /' | tee -a "$LOG"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "enabled, audio.separate offers it: the SAM licence, users' acceptance, described_target, spans, target and residual, a watermark, 30 s" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['audio.separate']['models']}['$SAM']; l = m['license']; s = m['supports']; print(l, s, m.get('limits'))
assert not m.get('named_only'), 'the SAM licence allows commercial use: Gaea makes only non-commercial offers named-only'
assert l['spdx'] == '$SPDX' and l['commercial_use'] is True and l['accepted_required'] is True and l['user_accept_required'] is True and l['notice']
assert s['described_target'] is True and s['spans'] is True and s['stems'] == ['target', 'residual'] and s['stem_method'] == 'regenerated' and s['watermark'] == 'audioseal'
assert m['limits']['max_duration_s'] == 30
assert {'target', 'residual'} <= {o['name'] for o in ops['audio.separate']['outputs']}"

# 2. Users' acceptance, and named-only.
sep terms $MIX '{"describe":"speech","seed":42}' $SAM no
check "a named job without policy.accepted is 422 policy_unmet, terms_not_accepted" py "
import json; e = json.load(open('$OUT/terms.json'))['error']; assert (e['code'], e.get('reason')) == ('policy_unmet', 'terms_not_accepted'), e
assert open('$OUT/terms.status').read().strip() == '422'"
sep route $MIX '{}' '' yes
check "a separate job with no description and no model runs on the demo's separator (labelled stems)" py "
import json; j = json.load(open('$OUT/route.json')); assert j['outcome'] == 'succeeded' and j['result']['provenance']['model']['id'] == 'demo-separator', j"
sep route-terms $MIX '{"describe":"speech","seed":42}' '' no
check "a described job naming no model, without policy.accepted, is 422 policy_unmet too" py "
import json; e = json.load(open('$OUT/route-terms.json')).get('error') or {}; s = open('$OUT/route-terms.status').read().strip(); print(s, e)
assert s == '422' and (e.get('code'), e.get('reason')) == ('policy_unmet', 'terms_not_accepted')"
sep route-described $MIX '{"describe":"speech","seed":42}' '' yes
check "a described job naming no model runs on SAM-Audio, the only offer that takes a description" py "
import json; j = json.load(open('$OUT/route-described.json')); assert j['outcome'] == 'succeeded' and j['result']['provenance']['model']['id'] == '$SAM', j"

# 3. Described separations.
FRAMES=$(facts $MIX | cut -d' ' -f1)
say "      mixture: $(facts $MIX) (frames, rate, channels)"
SPANS='[{"start_s":0.0,"end_s":0.5,"present":true},{"start_s":5.5,"end_s":8.0,"present":true}]'
t0=$(py 'import time; print(time.time())')
sep speech $MIX '{"describe":"speech","seed":42}'
say "      speech, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare, separate)"
sep speech-again $MIX '{"describe":"speech","seed":42}'
sep target-only $MIX '{"describe":"  Speech ","stems":["target"],"seed":7}'
sep music-spans $MIX '{"describe":"music","spans":'$SPANS',"seed":9}'
for n in speech speech-again target-only music-spans; do check "$n succeeds on $SAM" py "
import json; j=json.load(open('$OUT/$n.json')); assert j.get('outcome') == 'succeeded' and j['result']['provenance']['model']['id'] == '$SAM', j.get('error') or j"; done
check "speech returns target and residual, each the mixture's length at 48 kHz mono" py "
import json, wave
j = json.load(open('$OUT/speech.json')); assert [o['name'] for o in j['result']['outputs']] == ['target', 'residual'], j['result']['outputs']
for s in ('target', 'residual'):
    w = wave.open('$OUT/speech-%s.wav' % s); assert (w.getnframes(), w.getframerate(), w.getnchannels()) == ($FRAMES * 48000 // wave.open('$MIX').getframerate(), 48000, 1), (s, w.getnframes(), w.getframerate(), w.getnchannels())"
check "effective.describe is what the model got: \"speech\", for the untrimmed mixed-case text too" py "
import json
for n in ('speech', 'target-only'):
    e = json.load(open('$OUT/%s.json' % n))['result']['effective']; assert e.get('describe') == 'speech', (n, e)"
check "the target alone is one output" py "
import json; j = json.load(open('$OUT/target-only.json')); assert [o['name'] for o in j['result']['outputs']] == ['target'], j['result']['outputs']"
check "effective.spans echoes the two spans" py "
import json; e = json.load(open('$OUT/music-spans.json'))['result']['effective']; s = e.get('spans'); print(s)
assert [(x['start_s'], x['end_s'], x['present']) for x in s] == [(0.0, 0.5, True), (5.5, 8.0, True)]"
check "the same seed gives the same bytes" zsh -c "cmp $OUT/speech-target.wav $OUT/speech-again-target.wav && cmp $OUT/speech-residual.wav $OUT/speech-again-residual.wav"
check "the target and the residual differ, and neither is the mixture" zsh -c "! cmp -s $OUT/speech-target.wav $OUT/speech-residual.wav && ! cmp -s $OUT/speech-target.wav $MIX"
if [[ -x $INPROC ]]; then
  inproc speech 42 '{"describe":"speech"}'
  inproc target-only 7 '{"describe":"  Speech ","stems":["target"]}'
  inproc music-spans 9 '{"describe":"music","spans":'$SPANS'}'
  for pair in speech:target speech:residual target-only:target music-spans:target music-spans:residual; do
    n=${pair%%:*}; s=${pair##*:}
    check "$n's $s is sam-audio-inproc's, byte for byte" same "$OUT/$n-$s.wav" "$OUT/inproc-$n/$s.wav"
  done
else say "SKIP  in-process comparison: no $INPROC"; fi

# 4. Refusals.
LONGTEXT=$(py "print('a' * 201)")
MANY=$(py "import json; print(json.dumps([{'start_s': i * 0.2, 'end_s': i * 0.2 + 0.1, 'present': True} for i in range(33)]))")
sep no-describe $MIX '{"seed":1}'
sep long-describe $MIX '{"describe":"'$LONGTEXT'","seed":1}'
sep many-spans $MIX '{"describe":"speech","spans":'$MANY',"seed":1}'
sep backwards $MIX '{"describe":"speech","spans":[{"start_s":2.0,"end_s":1.0,"present":true}],"seed":1}'
sep past-end $MIX '{"describe":"speech","spans":[{"start_s":1.0,"end_s":600.0,"present":true}],"seed":1}'
sep stem $MIX '{"describe":"speech","stems":["vocals"],"seed":1}'
check "no describe is refused (4xx) and runs nothing" py "
import json; s=open('$OUT/no-describe.status').read().strip(); j=json.load(open('$OUT/no-describe.json')); print(s, j.get('error')); assert s.startswith('4')"
check "a description of 201 characters is refused (4xx)" py "
import json; s=open('$OUT/long-describe.status').read().strip(); j=json.load(open('$OUT/long-describe.json')); print(s, j.get('error')); assert s.startswith('4')"
check "33 spans are refused (4xx)" py "
import json; s=open('$OUT/many-spans.status').read().strip(); j=json.load(open('$OUT/many-spans.json')); print(s, j.get('error')); assert s.startswith('4')"
check "a span that ends before it starts is 400 invalid_request" py "
import json; s=open('$OUT/backwards.status').read().strip(); e=json.load(open('$OUT/backwards.json')).get('error') or {}; print(s, e); assert s == '400' and e.get('code') == 'invalid_request'"
check "a span past the mixture's end is out_of_limits" refused past-end out_of_limits
check "a stem SAM-Audio doesn't make is refused (4xx)" py "
import json; s=open('$OUT/stem.status').read().strip(); j=json.load(open('$OUT/stem.json')); print(s, j.get('error')); assert s.startswith('4')"
python3 - "$MIX" "$WORK/long.wav" <<'PY'
import sys, wave
src = wave.open(sys.argv[1]); frames = src.readframes(src.getnframes()); n = src.getnframes() / src.getframerate()
out = wave.open(sys.argv[2], 'wb'); out.setparams(src.getparams())
for _ in range(int(31 / n) + 1): out.writeframes(frames)
out.close()
PY
say "      long mixture: $(facts $WORK/long.wav)"
sep too-long $WORK/long.wav '{"describe":"speech","seed":1}'
check "a mixture over 30 s is out_of_limits" refused too-long out_of_limits

pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || break; sleep 0.2; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
