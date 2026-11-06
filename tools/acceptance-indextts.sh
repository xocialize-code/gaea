#!/bin/zsh
# AB-T-0452's acceptance (G5 order 1): gaea-plugin-indextts (IndexTTS 2.5) through Gaea, installed from GitHub beside
# gaea-plugin-kokoro, on MES Audio 0.1.
#
#   1. audio.speak lists indextts-2.5 beside kokoro-82m: voice_ref only, five languages, the nine emotion labels with
#      intensity, speed and target_duration, 22.05 kHz;
#   2. speak, each cloning the plugin's fixture kept as an asset: plain English (fp16 and the int8 lane), happy at 0.8,
#      the emotion vector, a 4 s fit around a pause, speed 1.3, Chinese and Spanish; byte for byte against
#      indextts-inproc; the effective values; Japanese and Arabic detected from their script;
#   3. routing with no model named: a voice_ref goes to indextts-2.5, plain text to kokoro-82m;
#   4. the reference cache (MES Base §13 rule 6): a second job on the asset is the same WAV; the run carries the asset
#      id; deleting the asset sends asset_removed to the worker;
#   5. reference formats: 24-bit, float and FLAC accepted; stereo mixed down and 30 s trimmed to 20, with warnings;
#   6. refusals: no voice_ref, French, an emotion outside the list, a malformed vector, a label with a vector, a target
#      too short for its pauses;
#   7. every recorded GPP session passes the validator.
#
#   tools/acceptance-indextts.sh <short-work-dir> <evidence-dir>
#
# Needs: APP (default dist/Gaea.app); GAEA_GITHUB_TOKEN (GitHub's anonymous 60 calls an hour may not last); the plugin
# repo at ../gaea-plugin-indextts for its fixture and indextts-inproc (release, --build-system swiftbuild); IndexTTS 2.5's
# weights in MODELS (default /Volumes/DEV_VOL1/Models/Models), which Gaea uses as its models root.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=${PLUGIN_REPO:-../gaea-plugin-indextts}
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models/Models}
INPROC=${INDEXTTS_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/indextts-inproc}
REF=$PLUGIN/scripts/fixtures/ref-en.wav
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
post() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
settle() {
  local j
  for _ in {1..90}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$1?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
job() { local r id; r=$(post "$1"); id=$(print -r -- "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))'); [[ -n $id ]] && settle $id || print -r -- "$r" }
fetch() { # job file, prefix → <prefix>-<i>.wav for every output
  python3 -c "import json,sys; [print(o['href']) for o in json.load(open(sys.argv[1]))['result']['outputs']]" "$1" |
    { i=0; while read href; do mes -o "$2-$i.wav" "http://127.0.0.1:$P$href"; i=$((i+1)); done }
}
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise --models-root "$MODELS" > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
refused() { py "import json; e=json.load(open('$1')).get('error', {}); assert (e.get('code'), e.get('param')) == ('$3', '$4'), e" && grep -q "^$2\$" "$1.status" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
ok() { py "import json; j=json.load(open('$1')); assert j.get('outcome') == 'succeeded', j" }
model() { py "import json; print(json.load(open('$1'))['result']['provenance']['model']['id'])" }
asset() { mes -X POST "http://127.0.0.1:$P/mes/v0/assets?ttl_s=3600" -H "Content-Type: $2" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['asset_id'])" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: $2" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
speakbody() { # text, voice_ref JSON (or ''), params JSON, [model], [extensions JSON] (Base §6.2: beside params, not in them)
  python3 -c "
import json,sys
b = {'operation': 'audio.speak', 'inputs': {'text': sys.argv[1]}, 'params': json.loads(sys.argv[3])}
if sys.argv[2]: b['inputs']['voice_ref'] = json.loads(sys.argv[2])
if len(sys.argv) > 4 and sys.argv[4]: b['model'] = sys.argv[4]
if len(sys.argv) > 5 and sys.argv[5]: b['extensions'] = json.loads(sys.argv[5])
print(json.dumps(b))" "$@"
}

say "# IndexTTS 2.5 acceptance (AB-T-0452) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), indextts from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/main; P=17689
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs kokoro" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-kokoro | grep -q Installed"
check "add by repo URL installs IndexTTS 2.5" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-indextts | tee -a $LOG | grep -q 'Installed IndexTTS 2.5'"
VERSION=$($CLI plugins | awk '/com.xocialize.gaea.indextts/ {print $3}')
say "      indextts $VERSION"

# 1. The offer.
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "audio.speak lists indextts-2.5 beside kokoro-82m, with its supports" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['audio.speak']['models']}; assert {'kokoro-82m', 'indextts-2.5'} <= set(m), m.keys()
s = m['indextts-2.5']['supports']
assert s['voice_ref'] is True and s['voice_ref_text'] == 'unused' and not s.get('default_voice'), s
assert s['languages'] == ['zh', 'en', 'ja', 'es', 'ar'] and len(s['emotions']) == 9 and s['emotion_intensity'] is True, s
assert s['speed'] is True and s['target_duration'] is True and s['sample_rate'] == 22050, s
assert m['indextts-2.5']['limits']['max_voice_ref_s'] == 20, m['indextts-2.5']['limits']"

# 2. Speak, cloning the fixture kept as an asset.
A=$(asset "$REF" audio/wav); say "      asset: $A"
REFA='{"asset":"'$A'"}'
EN='Gaea speaks. This sentence came from a signed plugin, over its own protocol.'
typeset -A TEXT PARAMS EXT
TEXT=(plain "$EN" plain-int8 "$EN" happy 'We won! I still can not believe it.' vector 'Put it back where you found it.'
      fitted 'This line has to fit the cue. [pause 0.5s] Exactly.' fast "$EN" chinese '今天天气很好，我们去公园散步吧。'
      spanish 'Hoy hace buen tiempo, vamos a dar un paseo por el parque.')
PARAMS=(plain '{"language":"en","seed":42}' plain-int8 '{"language":"en","seed":42}'
        happy '{"language":"en","seed":3,"emotion":{"label":"happy","intensity":0.8}}'
        vector '{"language":"en","seed":5}'
        fitted '{"language":"en","seed":7,"target_duration_s":4.0}' fast '{"language":"en","seed":9,"speed":1.3}'
        chinese '{"language":"zh","seed":11}' spanish '{"language":"es","seed":13}')
EXT=(plain-int8 '{"x-gaea.lane":"int8"}' vector '{"x-indextts.emotion_vector":[0,0.9,0,0,0.3,0,0,0]}')
CASES=(plain plain-int8 happy vector fitted fast chinese spanish)
t0=$(py 'import time; print(time.time())')
for n in $CASES; do
  job "$(speakbody "${TEXT[$n]}" "$REFA" "${PARAMS[$n]}" indextts-2.5 "${EXT[$n]:-}")" > "$OUT/job-$n.json"
  [[ $n == plain ]] && say "      plain, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare fp16, speak)"
  fetch "$OUT/job-$n.json" "$OUT/gaea-$n"
done
for n in $CASES; do check "$n succeeds" ok "$OUT/job-$n.json"; done
check "plain: a 22.05 kHz mono 16-bit WAV, effective language and seed, the fp16 lane" py "
import json; r = json.load(open('$OUT/job-plain.json'))['result']; o = r['outputs'][0]
assert (o['sample_rate'], o['channels'], o['bit_depth']) == (22050, 1, 16), o
e = r['effective']; assert (e['language'], e['seed']) == ('en', 42) and e['model_params']['x-gaea.worker']['lane'] == 'fp16', e"
check "plain-int8 ran on the int8 lane" py "
import json; e = json.load(open('$OUT/job-plain-int8.json'))['result']['effective']; assert e['model_params']['x-gaea.worker']['lane'] == 'int8', e"
check "happy: effective emotion and emo_alpha 0.8" py "
import json; e = json.load(open('$OUT/job-happy.json'))['result']['effective']
assert e['emotion']['label'] == 'happy' and e['x-indextts.emo_alpha'] == 0.8, e"
check "fitted: 4.0 s within a tenth of a second, no duration_missed" py "
import json; j = json.load(open('$OUT/job-fitted.json')); o = j['result']['outputs'][0]
assert abs(o['duration_s'] - 4.0) <= 0.1, o; assert 'duration_missed' not in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"
for lang in 'ja:東京の夜景はとてもきれいです。' 'ar:مرحبا بكم في جايا.'; do
  job "$(speakbody "${lang#*:}" "$REFA" '{"seed":1}' indextts-2.5)" > "$OUT/job-detect-${lang%%:*}.json"
  check "${lang%%:*} is detected from its script (effective.language)" py "
import json; j = json.load(open('$OUT/job-detect-${lang%%:*}.json')); assert j['outcome'] == 'succeeded' and j['result']['effective']['language'] == '${lang%%:*}', j"
done

# 3. Routing.
job "$(speakbody 'Hello there.' "$REFA" '{"seed":2}')" > "$OUT/route-ref.json"
check "a voice_ref with no model named → indextts-2.5" test "$(model "$OUT/route-ref.json")" = indextts-2.5
job "$(speakbody 'Hello there.' '' '{}')" > "$OUT/route-plain.json"
check "plain text with no model named → kokoro-82m" test "$(model "$OUT/route-plain.json")" = kokoro-82m

# 4. The reference cache.
job "$(speakbody "$EN" "$REFA" '{"language":"en","seed":42}' indextts-2.5)" > "$OUT/job-plain2.json"; fetch "$OUT/job-plain2.json" "$OUT/gaea-plain2"
check "a second job on the asset is the same WAV" cmp "$OUT/gaea-plain-0.wav" "$OUT/gaea-plain2-0.wav"
secs() { py "import json; print(json.load(open('$1'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])" }
say "      worker runs on the asset: first (warm model, new reference) $(secs "$OUT/job-happy.json") s, repeat of plain $(secs "$OUT/job-plain2.json") s"
check "the runs carried the asset id to the worker" zsh -c "grep -h '\"type\":\"run\"' $H/Logs/sessions/com.xocialize.gaea.indextts-*.gpp | grep -q '\"voice_ref\":\[\"$A\"\]'"
mes -X DELETE "http://127.0.0.1:$P/mes/v0/assets/$A" -o /dev/null -w '%{http_code}\n' > "$WORK/delete.status"
sleep 2
check "deleting the asset (204) sends asset_removed to the worker" zsh -c "grep -q '^204' $WORK/delete.status && grep -h asset_removed $H/Logs/sessions/com.xocialize.gaea.indextts-*.gpp | grep -q '$A'"
U=$(upload "$REF" audio/wav)
job "$(speakbody "$EN" '{"upload":"'$U'"}' '{"language":"en","seed":42}' indextts-2.5)" > "$OUT/job-upload.json"; fetch "$OUT/job-upload.json" "$OUT/gaea-upload"
check "the same reference as an upload (keyed by the job, evicted after) gives the same WAV" cmp "$OUT/gaea-plain-0.wav" "$OUT/gaea-upload-0.wav"

# 5. Reference formats.
afconvert -f WAVE -d LEI24 "$REF" "$WORK/ref24.wav"; afconvert -f WAVE -d LEF32 "$REF" "$WORK/reff32.wav"
afconvert -f flac -d flac "$REF" "$WORK/ref.flac"; afconvert -f WAVE -d LEI16 -c 2 "$REF" "$WORK/refstereo.wav"
py "
import wave; w = wave.open('$REF'); p = w.getparams(); f = w.readframes(p.nframes)
o = wave.open('$WORK/ref30.wav', 'wb'); o.setparams(p); o.writeframes(f * (int(30 * p.framerate / p.nframes) + 1)); o.close()"
for f in ref24.wav:audio/wav reff32.wav:audio/wav ref.flac:audio/flac refstereo.wav:audio/wav ref30.wav:audio/wav; do
  n=${f%%:*}; U=$(upload "$WORK/$n" ${f#*:})
  job "$(speakbody 'Short line.' '{"upload":"'$U'"}' '{"language":"en","seed":4}' indextts-2.5)" > "$OUT/job-ref-$n.json"
done
for n in ref24.wav reff32.wav ref.flac; do check "a $n reference is accepted" ok "$OUT/job-ref-$n.json"; done
check "a stereo reference is mixed down, with audio_downmixed" py "
import json; j = json.load(open('$OUT/job-ref-refstereo.wav.json')); assert j['outcome'] == 'succeeded', j
assert 'audio_downmixed' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"
check "a 30 s reference is trimmed to 20 s, with voice_ref_trimmed" py "
import json; j = json.load(open('$OUT/job-ref-ref30.wav.json')); assert j['outcome'] == 'succeeded', j
assert 'voice_ref_trimmed' in [w['code'] for w in j.get('warnings', [])] and j['result']['effective']['x-indextts.voice_ref_s'] == 20, j"

# 6. Refusals.
U=$(upload "$REF" audio/wav); RU='{"upload":"'$U'"}'
refuse "$(speakbody 'hi' '' '{}' indextts-2.5)" "$WORK/r-noref.json"
refuse "$(speakbody 'bonjour' "$RU" '{"language":"fr"}' indextts-2.5)" "$WORK/r-fr.json"
refuse "$(speakbody 'hi' "$RU" '{"emotion":{"label":"excited"}}' indextts-2.5)" "$WORK/r-emotion.json"
refuse "$(speakbody 'hi' "$RU" '{}' indextts-2.5 '{"x-indextts.emotion_vector":[0,1,0]}')" "$WORK/r-vector.json"
job "$(speakbody 'hi' "$RU" '{"emotion":{"label":"sad"}}' indextts-2.5 '{"x-indextts.emotion_vector":[0,1,0,0,0,0,0,0]}')" > "$WORK/f-both.json"
U=$(upload "$REF" audio/wav)   # an upload is used once: the job before took the last one
job "$(speakbody 'a [pause 5s] b' '{"upload":"'$U'"}' '{"target_duration_s":5}' indextts-2.5)" > "$WORK/f-fit.json"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status) $(py "import json; e=json.load(open('$f')).get('error', {}); print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:100])")"; done
check "no voice_ref on indextts-2.5 is 422 (neither voice nor voice_ref)" refused "$WORK/r-noref.json" 422 unsupported_parameter voice
check "French is 422" refused "$WORK/r-fr.json" 422 unsupported_parameter language
check "an emotion outside the list is 422" refused "$WORK/r-emotion.json" 422 unsupported_parameter emotion
check "a vector of three weights is refused at submit by its declared schema (422 out_of_limits)" refused "$WORK/r-vector.json" 422 out_of_limits x-indextts.emotion_vector
failed() { py "import json; j=json.load(open('$1')); e=j.get('error') or {}; assert j.get('outcome') == 'failed' and (e.get('code'), e.get('param')) == ('$2', '$3'), j" }
check "a label with a vector fails as invalid_request" failed "$WORK/f-both.json" invalid_request x-indextts.emotion_vector
check "a 5 s target with a 5 s pause fails as out_of_limits" failed "$WORK/f-fit.json" out_of_limits target_duration_s
for f in $WORK/f-*.json; do say "      $(basename $f .json): $(py "import json; j=json.load(open('$f')); e=j.get('error') or {}; print(j.get('outcome'), e.get('code'), e.get('param'), '-', (e.get('message') or '')[:100])")"; done

$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side.
inproc() { "$INPROC" --ref "$REF" --models-root "$MODELS" "$@" 2>> "$LOG" | tail -1 }
inproc --language en --seed 42 --text "$EN" --out "$OUT/inproc-plain.wav" > "$OUT/inproc-plain.json"
inproc --lane int8 --language en --seed 42 --text "$EN" --out "$OUT/inproc-plain-int8.wav" > /dev/null
inproc --language en --seed 3 --emotion happy --intensity 0.8 --text "${TEXT[happy]}" --out "$OUT/inproc-happy.wav" > /dev/null
inproc --language en --seed 5 --vector 0,0.9,0,0,0.3,0,0,0 --text "${TEXT[vector]}" --out "$OUT/inproc-vector.wav" > /dev/null
inproc --language en --seed 7 --target-duration 4.0 --text "${TEXT[fitted]}" --out "$OUT/inproc-fitted.wav" > /dev/null
inproc --language en --seed 9 --speed 1.3 --text "$EN" --out "$OUT/inproc-fast.wav" > /dev/null
inproc --language zh --seed 11 --text "${TEXT[chinese]}" --out "$OUT/inproc-chinese.wav" > /dev/null
inproc --language es --seed 13 --text "${TEXT[spanish]}" --out "$OUT/inproc-spanish.wav" > /dev/null
for n in $CASES; do check "$n through Gaea is indextts-inproc's WAV, byte for byte" cmp "$OUT/gaea-$n-0.wav" "$OUT/inproc-$n.wav"; done
say "      in-process plain: $(cat "$OUT/inproc-plain.json")"

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
