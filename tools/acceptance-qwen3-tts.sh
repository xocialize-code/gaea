#!/bin/zsh
# AB-T-0396's acceptance: gaea-plugin-qwen3-tts (Qwen3-TTS 1.7B) through Gaea 0.9.1, installed by repo URL beside
# gaea-plugin-kokoro, on MES Audio 0.1 (media-engine-spec v0.7.0).
#
#   1. audio.speak lists qwen3-tts (nine voices, emotions, a delivery description, ten languages) beside kokoro-82m, and
#      audio.design_voice lists qwen3-tts-design;
#   2. speak: ryan, ryan angry, aiden with a delivery description and vivian in Chinese with a pause are qwen3-inproc's
#      WAVs byte for byte; an emotion's intensity is ignored with a warning;
#   3. routing with no model named: a Qwen voice goes to qwen3-tts and a Kokoro voice to kokoro-82m, an emotion or French
#      to qwen3-tts (Kokoro has neither), and plain English to the default;
#   4. design_voice: two samples at seed 7 and 8, effective.seed and effective.text, each qwen3-inproc's; five is 422;
#   5. cloning (qwen3-tts-clone): the first designed sample kept as an asset clones back with its text, qwen3-inproc's
#      byte for byte; a second job on the asset is the same WAV; the run carries the asset id; deleting the asset sends
#      asset_removed; without the text it clones from the embedding alone; 24-bit WAV, float WAV and FLAC references
#      are accepted; a stereo one is mixed down and a 40 s one trimmed, with warnings;
#   6. refusals: an emotion outside the list, Dutch, a voice with the wrong model, a voice with a voice_ref,
#      voice_ref_text without voice_ref;
#   7. every recorded GPP session passes the validator.
#
#   tools/acceptance-qwen3-tts.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; PLUGIN_DIST (default ../gaea-plugin-qwen3-tts/dist); QWEN3_INPROC (default: the plugin repo's
# release qwen3-inproc, built with --build-system swiftbuild). REPO_FROM=github installs the published releases instead
# of serving the dist folder through tools/release-standin.py (Kokoro always comes from GitHub).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-qwen3-tts/dist}
INPROC=${QWEN3_INPROC:-$(cd ../gaea-plugin-qwen3-tts && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/qwen3-inproc}
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
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
body() { # python dict literal → JSON
  python3 -c "import json,sys; print(json.dumps($1))"
}
refused() { py "import json; e=json.load(open('$1')).get('error', {}); assert (e.get('code'), e.get('param')) == ('$3', '$4'), e" && grep -q "^$2\$" "$1.status" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
ok() { py "import json; j=json.load(open('$1')); assert j.get('outcome') == 'succeeded', j" }
model() { py "import json; print(json.load(open('$1'))['result']['provenance']['model']['id'])" }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# Qwen3-TTS acceptance (AB-T-0396) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), qwen3-tts $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  # Gaea reads GitHub through the stand-in for every repo, so it serves Kokoro's published release too.
  REL=$WORK/standin/xocialize-code/gaea-plugin-qwen3-tts/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/qwen3-tts-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/qwen3-tts-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  KREL=$WORK/standin/xocialize-code/gaea-plugin-kokoro/v0.1.0; mkdir -p "$KREL"
  gh release download v0.1.0 --repo xocialize-code/gaea-plugin-kokoro --dir "$KREL" > /dev/null
  python3 tools/release-standin.py "$WORK/standin" --port 8777 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8777
fi
H=$WORK/main; P=17688
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs kokoro" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-kokoro | grep -q Installed"
check "add by repo URL installs qwen3-tts $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-qwen3-tts | grep -q 'Installed .* $VERSION'"

# 1. The offers.
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
mes "http://127.0.0.1:$P/mes/v0/operations/audio.speak/models/qwen3-tts/voices" > "$OUT/voices.json"
check "audio.speak lists qwen3-tts (9 voices, emotions, descriptions, 10 languages) and qwen3-tts-clone beside kokoro-82m" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['audio.speak']['models']}; q = m['qwen3-tts']['supports']
assert set(m) == {'kokoro-82m', 'qwen3-tts', 'qwen3-tts-clone'}, m.keys()
c = m['qwen3-tts-clone']; assert c['supports']['voice_ref'] is True and c['supports']['voice_ref_text'] == 'optional' and c['limits']['max_voice_ref_s'] == 30, c
assert q['voices'] == 9 and q['emotion_description'] is True and len(q['languages']) == 10 and 'angry' in q['emotions'], q
assert 'stream' not in q, q"
check "audio.design_voice lists qwen3-tts-design, at most 4 samples" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['audio.design_voice']; m = d['models'][0]; assert m['id'] == 'qwen3-tts-design' and m['limits']['max_count'] == 4, d"
check "GET …/voices lists the nine speakers" py "
import json; v = [x['id'] for x in json.load(open('$OUT/voices.json'))['voices']]; assert len(v) == 9 and 'vivian' in v and 'ryan' in v, v"

# 2. Speak.
T1='Gaea speaks. This sentence came from a signed plugin, over its own protocol.'
T2='I told you three times already. Put it back where you found it.'
T3='Fine. I will do it tomorrow morning, first thing.'
T4='今天天气很好，我们去公园散步吧。[pause 1s] 你觉得怎么样？'
D3='tired, as if after a very long day'
t0=$(py 'import time; print(time.time())')
job "$(body "{'operation':'audio.speak','model':'qwen3-tts','inputs':{'text':'$T1'},'params':{'voice':'ryan','seed':42}}")" > "$OUT/job-ryan.json"
say "      ryan, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare int8, speak)"
job "$(body "{'operation':'audio.speak','model':'qwen3-tts','inputs':{'text':'$T2'},'params':{'voice':'ryan','seed':42,'emotion':{'label':'angry'}}}")" > "$OUT/job-angry.json"
job "$(body "{'operation':'audio.speak','model':'qwen3-tts','inputs':{'text':'$T3'},'params':{'voice':'aiden','seed':3,'emotion':{'description':'$D3','intensity':0.5}}}")" > "$OUT/job-described.json"
job "$(body "{'operation':'audio.speak','model':'qwen3-tts','inputs':{'text':'$T4'},'params':{'voice':'vivian','seed':1,'language':'zh'}}")" > "$OUT/job-vivian.json"
for n in ryan angry described vivian; do fetch "$OUT/job-$n.json" "$OUT/gaea-$n"; done
check "ryan: a 24 kHz mono 16-bit WAV, effective voice, language and seed" py "
import json; r = json.load(open('$OUT/job-ryan.json'))['result']; o = r['outputs'][0]
assert (o['sample_rate'], o['channels'], o['bit_depth']) == (24000, 1, 16), o
e = r['effective']; assert (e['voice'], e['language'], e['seed']) == ('ryan', 'en', 42), e"
check "an emotion's intensity is ignored with emotion_intensity_ignored" py "
import json; j = json.load(open('$OUT/job-described.json')); assert j['outcome'] == 'succeeded', j
assert 'emotion_intensity_ignored' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"

# 3. Routing with no model named.
route() { job "$(body "$1")" > "$OUT/route-$2.json"; check "$3 → $4" test "$(model "$OUT/route-$2.json")" = "$4" }
route "{'operation':'audio.speak','inputs':{'text':'Hello there.'},'params':{'voice':'sohee'}}" sohee "a Qwen voice (sohee)" qwen3-tts
route "{'operation':'audio.speak','inputs':{'text':'Hello there.'},'params':{'voice':'bm_lewis'}}" lewis "a Kokoro voice (bm_lewis)" kokoro-82m
route "{'operation':'audio.speak','inputs':{'text':'Hello there.'},'params':{'emotion':{'label':'happy'}}}" happy "an emotion" qwen3-tts
route "{'operation':'audio.speak','inputs':{'text':'Bonjour à tous.'},'params':{'language':'fr'}}" fr "French" qwen3-tts
route "{'operation':'audio.speak','inputs':{'text':'Hello there.'},'params':{}}" plain "plain English, the default" kokoro-82m

# 4. Design.
DESC='A warm, low voice of a woman in her forties, unhurried, with a slight rasp.'
job "$(body "{'operation':'audio.design_voice','inputs':{'description':'$DESC'},'params':{'count':2,'seed':7,'language':'en'}}")" > "$OUT/job-design.json"
fetch "$OUT/job-design.json" "$OUT/gaea-design"
check "design_voice: two samples, effective seed 7 and the sample text" py "
import json; j = json.load(open('$OUT/job-design.json')); assert j['outcome'] == 'succeeded', j; r = j['result']
assert [o['name'] for o in r['outputs']] == ['samples', 'samples'], r['outputs']
assert r['effective']['seed'] == 7 and r['effective']['text'].startswith('Hello!'), r['effective']"
refuse "$(body "{'operation':'audio.design_voice','inputs':{'description':'$DESC'},'params':{'count':5}}")" "$WORK/r-count.json"
check "five samples is 422 out_of_limits" refused "$WORK/r-count.json" 422 out_of_limits count

# 5. Cloning the designed voice.
SAMPLE=$(py "import json; print(json.load(open('$OUT/job-design.json'))['result']['effective']['text'])")
CT='The clone reads a new line now, in the voice it was given.'
asset() { mes -X POST "http://127.0.0.1:$P/mes/v0/assets?ttl_s=3600" -H "Content-Type: $2" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['asset_id'])" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: $2" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
clonebody() { # voice_ref value as JSON, with the sample's text
  python3 -c "import json,sys; print(json.dumps({'operation':'audio.speak','inputs':{'text':sys.argv[1],'voice_ref':json.loads(sys.argv[2]),'voice_ref_text':sys.argv[3]},'params':{'seed':9}}))" "$CT" "$1" "$SAMPLE"
}
refbody() { # model, voice_ref JSON, text
  python3 -c "import json,sys; print(json.dumps({'operation':'audio.speak','model':sys.argv[1],'inputs':{'text':sys.argv[3],'voice_ref':json.loads(sys.argv[2])},'params':{'seed':9}}))" "$@"
}
A=$(asset "$OUT/gaea-design-0.wav" audio/wav)
say "      asset: $A"
job "$(clonebody '{"asset":"'$A'"}')" > "$OUT/job-clone.json"; fetch "$OUT/job-clone.json" "$OUT/gaea-clone"
job "$(clonebody '{"asset":"'$A'"}')" > "$OUT/job-clone2.json"; fetch "$OUT/job-clone2.json" "$OUT/gaea-clone2"
check "a voice_ref with no model named goes to qwen3-tts-clone, in context (icl)" py "
import json; r = json.load(open('$OUT/job-clone.json'))['result']
assert r['provenance']['model']['id'] == 'qwen3-tts-clone' and r['effective']['x-qwen3.clone'] == 'icl', r"
check "the second job on the asset is the same WAV" cmp "$OUT/gaea-clone-0.wav" "$OUT/gaea-clone2-0.wav"
say "      clone worker runs: first $(py "import json; print(json.load(open('$OUT/job-clone.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])") s, second (cached features) $(py "import json; print(json.load(open('$OUT/job-clone2.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])") s"
check "the clone's run carried the asset id to the worker" zsh -c "grep -h '\"type\":\"run\"' $H/Logs/sessions/com.xocialize.gaea.qwen3-tts-*.gpp | grep -q '\"voice_ref\":\[\"$A\"\]'"
mes -X DELETE "http://127.0.0.1:$P/mes/v0/assets/$A" -o /dev/null -w '%{http_code}\n' > "$WORK/delete.status"
sleep 2
check "deleting the asset (204) sends asset_removed to the worker" zsh -c "grep -q '^204' $WORK/delete.status && grep -h asset_removed $H/Logs/sessions/com.xocialize.gaea.qwen3-tts-*.gpp | grep -q '$A'"
U=$(upload "$OUT/gaea-design-0.wav" audio/wav)
job "$(refbody qwen3-tts-clone '{"upload":"'$U'"}' "$CT")" > "$OUT/job-xvector.json"; fetch "$OUT/job-xvector.json" "$OUT/gaea-xvector"
check "without the text it clones from the embedding alone (x-vector)" py "
import json; r = json.load(open('$OUT/job-xvector.json'))['result']; assert r['effective']['x-qwen3.clone'] == 'xvector', r"
afconvert -f WAVE -d LEI24 "$OUT/gaea-design-0.wav" "$WORK/ref24.wav"; afconvert -f WAVE -d LEF32 "$OUT/gaea-design-0.wav" "$WORK/reff32.wav"
afconvert -f flac -d flac "$OUT/gaea-design-0.wav" "$WORK/ref.flac"; afconvert -f WAVE -d LEI16 -c 2 "$OUT/gaea-design-0.wav" "$WORK/refstereo.wav"
py "
import wave; w = wave.open('$OUT/gaea-design-0.wav'); p = w.getparams(); f = w.readframes(p.nframes)
o = wave.open('$WORK/ref40.wav', 'wb'); o.setparams(p); o.writeframes(f * (int(40 * p.framerate / p.nframes) + 1)); o.close()"
for f in ref24.wav:audio/wav reff32.wav:audio/wav ref.flac:audio/flac refstereo.wav:audio/wav ref40.wav:audio/wav; do
  n=${f%%:*}; U=$(upload "$WORK/$n" ${f#*:})
  job "$(refbody qwen3-tts-clone '{"upload":"'$U'"}' 'Short line.')" > "$OUT/job-ref-$n.json"
done
for n in ref24.wav reff32.wav ref.flac; do check "a $n reference is accepted" ok "$OUT/job-ref-$n.json"; done
check "a stereo reference is mixed down, with audio_downmixed" py "
import json; j = json.load(open('$OUT/job-ref-refstereo.wav.json')); assert j['outcome'] == 'succeeded', j
assert 'audio_downmixed' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"
check "a 40 s reference is trimmed to 30 s, with voice_ref_trimmed" py "
import json; j = json.load(open('$OUT/job-ref-ref40.wav.json')); assert j['outcome'] == 'succeeded', j
assert 'voice_ref_trimmed' in [w['code'] for w in j.get('warnings', [])] and j['result']['effective']['x-qwen3.voice_ref_s'] == 30, j"

# 6. Refusals.
U=$(upload "$OUT/gaea-design-0.wav" audio/wav)
refuse "$(python3 -c "import json; print(json.dumps({'operation':'audio.speak','inputs':{'text':'hi','voice_ref':{'upload':'$U'}},'params':{'voice':'ryan'}}))")" "$WORK/r-both.json"
check "a voice with a voice_ref is 400" refused "$WORK/r-both.json" 400 invalid_request voice
refuse '{"operation":"audio.speak","inputs":{"text":"hi","voice_ref_text":"hello"},"params":{}}' "$WORK/r-text.json"
check "voice_ref_text without voice_ref is 400" refused "$WORK/r-text.json" 400 invalid_request voice_ref_text
refuse "$(body "{'operation':'audio.speak','model':'qwen3-tts','inputs':{'text':'hi'},'params':{'emotion':{'label':'excited'}}}")" "$WORK/r-emotion.json"
check "an emotion outside the list is 422" refused "$WORK/r-emotion.json" 422 unsupported_parameter emotion
refuse "$(body "{'operation':'audio.speak','inputs':{'text':'hallo'},'params':{'language':'nl'}}")" "$WORK/r-nl.json"
check "Dutch is 422" refused "$WORK/r-nl.json" 422 unsupported_parameter language
refuse "$(body "{'operation':'audio.speak','model':'kokoro-82m','inputs':{'text':'hi'},'params':{'voice':'ryan'}}")" "$WORK/r-wrong.json"
check "a Qwen voice on kokoro-82m is 422" refused "$WORK/r-wrong.json" 422 unsupported_parameter voice
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status) $(py "import json; e=json.load(open('$f'))['error']; print(e['code'], e.get('param'), '-', e['message'][:90])")"; done

$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side.
inproc() { "$INPROC" "$@" 2>> "$LOG" | tail -1 }
inproc speak --voice ryan --seed 42 --text "$T1" --out "$OUT/inproc-ryan.wav" > "$OUT/inproc-ryan.json"
inproc speak --voice ryan --seed 42 --emotion angry --text "$T2" --out "$OUT/inproc-angry.wav" > /dev/null
inproc speak --voice aiden --seed 3 --emotion-description "$D3" --text "$T3" --out "$OUT/inproc-described.wav" > /dev/null
inproc speak --voice vivian --seed 1 --language zh --text "$T4" --out "$OUT/inproc-vivian.wav" > /dev/null
inproc design --description "$DESC" --count 2 --seed 7 --language en --out-dir "$OUT/inproc-design" > "$OUT/inproc-design.json"
for n in ryan angry described vivian; do check "$n through Gaea is qwen3-inproc's WAV, byte for byte" cmp "$OUT/gaea-$n-0.wav" "$OUT/inproc-$n.wav"; done
for i in 0 1; do check "design sample $i through Gaea is qwen3-inproc's, byte for byte" cmp "$OUT/gaea-design-$i.wav" "$OUT/inproc-design/samples-$i.wav"; done
inproc clone --ref "$OUT/gaea-design-0.wav" --ref-text "$SAMPLE" --seed 9 --text "$CT" --out "$OUT/inproc-clone.wav" > "$OUT/inproc-clone.json"
inproc clone --ref "$OUT/gaea-design-0.wav" --seed 9 --text "$CT" --out "$OUT/inproc-xvector.wav" > /dev/null
check "the clone through Gaea (from an asset) is qwen3-inproc's, byte for byte" cmp "$OUT/gaea-clone-0.wav" "$OUT/inproc-clone.wav"
check "the x-vector clone through Gaea is qwen3-inproc's, byte for byte" cmp "$OUT/gaea-xvector-0.wav" "$OUT/inproc-xvector.wav"
say "      in-process clone: $(cat "$OUT/inproc-clone.json")"
say "      in-process ryan: $(cat "$OUT/inproc-ryan.json")"
say "      in-process design: $(cat "$OUT/inproc-design.json")"

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
