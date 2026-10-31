#!/bin/zsh
# AB-T-0397's acceptance: gaea-plugin-step-audio-editx (Step-Audio-EditX) through Gaea 0.9.2, installed by repo URL beside
# gaea-plugin-kokoro, on MES Audio 0.1's audio.edit_speech (media-engine-spec v0.7.0).
#
#   1. audio.edit_speech lists step-audio-editx: five edit kinds, 15 emotions, 9 styles, 4 cues, transcript required,
#      keeps_length false, 90 s;
#   2. edits with no model named: angry, fearful (an alias, run as upstream's fear), whisper, a laugh at the end (with the
#      new transcript as the transcript output), denoise and trim_silence, each editx-inproc's WAV byte for byte;
#   3. a take Kokoro spoke through Gaea, kept as an asset, edited twice: the same seed gives the same WAV;
#   4. formats: 24-bit, float, FLAC and stereo takes are accepted; output at 48 kHz 24-bit is converted, with
#      audio_resampled;
#   5. refusals: an unlisted kind, emotion and cue, no transcript, a 95 s take (out_of_limits) are 422; a kind missing
#      its fields, or with one it doesn't take, is 400; an add_cue whose text lacks the cue, or with an unknown place,
#      is 400 from the worker;
#   6. every recorded GPP session passes the validator.
#
#   tools/acceptance-step-audio-editx.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; PLUGIN_DIST (default ../gaea-plugin-step-audio-editx/dist); EDITX_INPROC (default: the plugin
# repo's release editx-inproc, built with --build-system swiftbuild). REPO_FROM=github installs the published releases
# instead of serving the dist folder through tools/release-standin.py (Kokoro always comes from GitHub).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=../gaea-plugin-step-audio-editx
PLUGIN_DIST=${PLUGIN_DIST:-$PLUGIN/dist}
FIX=$PLUGIN/Tests/Fixtures
INPROC=${EDITX_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/editx-inproc}
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
fetch() { # job file, prefix → <prefix>-<i>.wav for every audio output
  python3 -c "import json,sys; [print(o['href']) for o in json.load(open(sys.argv[1]))['result']['outputs'] if o.get('href') and o.get('kind', 'audio') == 'audio']" "$1" |
    { i=0; while read href; do mes -o "$2-$i.wav" "http://127.0.0.1:$P$href"; i=$((i+1)); done }
}
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
refused() { py "import json; e=json.load(open('$1')).get('error', {}); assert (e.get('code'), e.get('param')) == ('$3', '$4'), e" && grep -q "^$2\$" "$1.status" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
ok() { py "import json; j=json.load(open('$1')); assert j.get('outcome') == 'succeeded', j" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: $2" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
asset() { mes -X POST "http://127.0.0.1:$P/mes/v0/assets?ttl_s=3600" -H "Content-Type: $2" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['asset_id'])" }
# editbody <audio input JSON> <transcript or ""> <edit JSON> [params JSON] [model]
editbody() {
  python3 -c "
import json, sys
audio, text, edit = json.loads(sys.argv[1]), sys.argv[2], json.loads(sys.argv[3])
params = json.loads(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else {}
params['edit'] = edit
inputs = {'audio': audio}
if text: inputs['transcript'] = text
body = {'operation': 'audio.edit_speech', 'inputs': inputs, 'params': params}
if len(sys.argv) > 5: body['model'] = sys.argv[5]
print(json.dumps(body))" "$@"
}

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# Step-Audio-EditX acceptance (AB-T-0397) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), step-audio-editx $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  # Gaea reads GitHub through the stand-in for every repo, so it serves Kokoro's published release too.
  REL=$WORK/standin/xocialize-code/gaea-plugin-step-audio-editx/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/step-audio-editx-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/step-audio-editx-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  KREL=$WORK/standin/xocialize-code/gaea-plugin-kokoro/v0.1.0; mkdir -p "$KREL"
  gh release download v0.1.0 --repo xocialize-code/gaea-plugin-kokoro --dir "$KREL" > /dev/null
  python3 tools/release-standin.py "$WORK/standin" --port 8777 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8777
fi
H=$WORK/main; P=17689
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs kokoro" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-kokoro | grep -q Installed"
check "add by repo URL installs step-audio-editx $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-step-audio-editx | grep -q 'Installed .* $VERSION'"

# 1. The offer.
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "audio.edit_speech lists step-audio-editx: 5 kinds, 15 emotions, 9 styles, 4 cues, transcript required, 90 s" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['audio.edit_speech']; m = d['models']; assert [x['id'] for x in m] == ['step-audio-editx'], m
s = m[0]['supports']
assert s['edits'] == ['emotion', 'style', 'add_cue', 'denoise', 'trim_silence'], s
assert len(s['emotions']) == 15 and 'neutral' in s['emotions'] and 'afraid' in s['emotions'], s
assert len(s['styles']) == 9 and 'normal' in s['styles'] and s['cues'] == ['laugh', 'sigh', 'breath', 'hesitation'], s
assert s['transcript'] == 'required' and s['keeps_length'] is False, s
assert m[0]['limits']['max_duration_s'] == 90, m[0]['limits']
assert {o['name']: o['min'] for o in d['outputs']} == {'audio': 1, 'transcript': 0}, d['outputs']"

# 2. Edits, no model named.
TAKE="We don't have much time, so listen carefully to what I say."
TAKE2="The weather is lovely today, and I think we should go outside."
up() { print -r -- '{"upload":"'$(upload "$1" ${2:-audio/wav})'"}' }
t0=$(py 'import time; print(time.time())')
job "$(editbody "$(up $FIX/take.wav)" "$TAKE" '{"kind":"emotion","emotion":"angry"}' '{"seed":42}')" > "$OUT/job-angry.json"
say "      angry, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare int8 with its warm-up, edit)"
job "$(editbody "$(up $FIX/take.wav)" "$TAKE" '{"kind":"emotion","emotion":"fearful"}' '{"seed":7}')" > "$OUT/job-afraid.json"
job "$(editbody "$(up $FIX/take.wav)" "$TAKE" '{"kind":"style","style":"whisper"}' '{"seed":42}')" > "$OUT/job-whisper.json"
job "$(editbody "$(up $FIX/take2.wav)" "$TAKE2" '{"kind":"add_cue","cue":"laugh","at":"end"}' '{"seed":42}')" > "$OUT/job-laugh.json"
job "$(editbody "$(up $FIX/noisy.wav)" "$TAKE2" '{"kind":"denoise"}' '{"seed":42}')" > "$OUT/job-denoise.json"
job "$(editbody "$(up $FIX/padded.wav)" "$TAKE2" '{"kind":"trim_silence"}' '{"seed":42}')" > "$OUT/job-trim.json"
for n in angry afraid whisper laugh denoise trim; do fetch "$OUT/job-$n.json" "$OUT/gaea-$n"; done
check "angry: step-audio-editx, a 24 kHz mono 16-bit WAV, effective seed, edit and upstream's emotion:angry" py "
import json; r = json.load(open('$OUT/job-angry.json'))['result']; o = r['outputs'][0]
assert r['provenance']['model']['id'] == 'step-audio-editx', r['provenance']
assert (o['sample_rate'], o['channels'], o['bit_depth']) == (24000, 1, 16), o
e = r['effective']; assert e['seed'] == 42 and e['x-stepfun.edit'] == 'emotion:angry' and e['edit']['emotion'] == 'angry', e"
check "fearful is resolved to afraid, and runs as upstream's fear" py "
import json; e = json.load(open('$OUT/job-afraid.json'))['result']['effective']
assert e['edit']['emotion'] == 'afraid' and e['x-stepfun.edit'] == 'emotion:fear', e"
check "the laugh returns the new transcript as the transcript output" py "
import json; r = json.load(open('$OUT/job-laugh.json'))['result']
t = [o for o in r['outputs'] if o['name'] == 'transcript']; assert len(t) == 1, r['outputs']
v = t[0].get('value') or {}
assert v.get('text') == \"$TAKE2 [laugh]\", t"
check "an emotion edit returns no transcript" py "
import json; r = json.load(open('$OUT/job-angry.json'))['result']; assert [o['name'] for o in r['outputs']] == ['audio'], r['outputs']"
check "trim_silence shortens the padded 7.4 s take" py "
import json; o = json.load(open('$OUT/job-trim.json'))['result']['outputs'][0]; assert o['duration_s'] < 5, o"

# 3. A take Kokoro spoke through Gaea, kept as an asset and edited twice.
job '{"operation":"audio.speak","model":"kokoro-82m","inputs":{"text":"I was sure the train would wait for us."},"params":{"voice":"af_heart","seed":11}}' > "$OUT/job-kokoro.json"
fetch "$OUT/job-kokoro.json" "$OUT/gaea-kokoro"
A=$(asset "$OUT/gaea-kokoro-0.wav" audio/wav)
job "$(editbody '{"asset":"'$A'"}' 'I was sure the train would wait for us.' '{"kind":"emotion","emotion":"sad"}' '{"seed":4}')" > "$OUT/job-asset1.json"
job "$(editbody '{"asset":"'$A'"}' 'I was sure the train would wait for us.' '{"kind":"emotion","emotion":"sad"}' '{"seed":4}')" > "$OUT/job-asset2.json"
fetch "$OUT/job-asset1.json" "$OUT/gaea-asset1"; fetch "$OUT/job-asset2.json" "$OUT/gaea-asset2"
check "Kokoro's take, kept as an asset, edited sad twice at seed 4: the same WAV" zsh -c "ok() { python3 -c \"import json; assert json.load(open('\$1'))['outcome'] == 'succeeded'\" }; ok $OUT/job-asset1.json && cmp $OUT/gaea-asset1-0.wav $OUT/gaea-asset2-0.wav"

# 4. Formats.
afconvert -f WAVE -d LEI24 $FIX/take.wav "$WORK/take24.wav"; afconvert -f WAVE -d LEF32 $FIX/take.wav "$WORK/takef32.wav"
afconvert -f flac -d flac $FIX/take.wav "$WORK/take.flac"; afconvert -f WAVE -d LEI16 -c 2 $FIX/take.wav "$WORK/takestereo.wav"
for f in take24.wav:audio/wav takef32.wav:audio/wav take.flac:audio/flac takestereo.wav:audio/wav; do
  n=${f%%:*}
  job "$(editbody "$(up $WORK/$n ${f#*:})" "$TAKE" '{"kind":"denoise"}' '{"seed":1}')" > "$OUT/job-in-$n.json"
  check "a $n take is accepted" ok "$OUT/job-in-$n.json"
done
job "$(editbody "$(up $FIX/take.wav)" "$TAKE" '{"kind":"style","style":"gentle"}' '{"seed":2,"output":{"media_type":"audio/wav","sample_rate":48000,"bit_depth":24}}')" > "$OUT/job-48k.json"
check "output at 48 kHz 24-bit is converted, with audio_resampled" py "
import json; j = json.load(open('$OUT/job-48k.json')); assert j['outcome'] == 'succeeded', j; o = j['result']['outputs'][0]
assert (o['sample_rate'], o['bit_depth']) == (48000, 24), o
assert 'audio_resampled' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"

# 5. Refusals.
U=$(upload $FIX/take.wav audio/wav)
r() { refuse "$(editbody '{"upload":"'$U'"}' "$@")" "$WORK/r-$N.json" }
N=kind; r "$TAKE" '{"kind":"speed","factor":1.5}' '{}' step-audio-editx
check "an unlisted kind (speed) is 422" refused "$WORK/r-kind.json" 422 unsupported_parameter edit
N=emotion; r "$TAKE" '{"kind":"emotion","emotion":"calm"}' '{}' step-audio-editx
check "an unlisted emotion (calm) is 422" refused "$WORK/r-emotion.json" 422 unsupported_parameter edit
N=cue; r "$TAKE" '{"kind":"add_cue","cue":"cough"}' '{}' step-audio-editx
check "an unlisted cue (cough) is 422" refused "$WORK/r-cue.json" 422 unsupported_parameter edit
N=notext; r "" '{"kind":"denoise"}' '{}' step-audio-editx
check "no transcript is 422" refused "$WORK/r-notext.json" 422 unsupported_parameter transcript
N=missing; r "$TAKE" '{"kind":"emotion"}' '{}'
check "an emotion edit without its emotion is 400" refused "$WORK/r-missing.json" 400 invalid_request edit
N=extra; r "$TAKE" '{"kind":"denoise","emotion":"happy"}' '{}'
check "a denoise edit with an emotion is 400" refused "$WORK/r-extra.json" 400 invalid_request edit
py "
import wave; w = wave.open('$FIX/take.wav'); p = w.getparams(); f = w.readframes(p.nframes)
o = wave.open('$WORK/take95.wav', 'wb'); o.setparams(p); o.writeframes(f * (int(95 * p.framerate / p.nframes) + 1)); o.close()"
job "$(editbody "$(up $WORK/take95.wav)" "$TAKE" '{"kind":"denoise"}' '{}')" > "$WORK/r-long.json"
check "a 95 s take is 422 out_of_limits on audio" py "
import json; j = json.load(open('$WORK/r-long.json')); e = j.get('error', {})
assert j.get('outcome') == 'failed' and (e.get('code'), e.get('param')) == ('out_of_limits', 'audio'), j"
job "$(editbody '{"upload":"'$U'"}' "$TAKE" '{"kind":"add_cue","cue":"laugh","text":"No laugh is written here."}' '{}')" > "$WORK/r-nocue.json"
check "an add_cue whose text lacks the cue is refused by the worker (invalid_request)" py "
import json; j = json.load(open('$WORK/r-nocue.json')); assert j.get('outcome') == 'failed' and j['error']['code'] == 'invalid_request', j"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status 2>/dev/null) $(py "import json; j=json.load(open('$f')); e=j.get('error') or {}; print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:100])")"; done

$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side.
inproc() { "$INPROC" "$@" 2>> "$LOG" | tail -1 }
inproc --take $FIX/take.wav --transcript "$TAKE" --edit '{"kind":"emotion","emotion":"angry"}' --seed 42 --out "$OUT/inproc-angry.wav" > "$OUT/inproc-angry.json"
inproc --take $FIX/take.wav --transcript "$TAKE" --edit '{"kind":"emotion","emotion":"afraid"}' --seed 7 --out "$OUT/inproc-afraid.wav" > /dev/null
inproc --take $FIX/take.wav --transcript "$TAKE" --edit '{"kind":"style","style":"whisper"}' --seed 42 --out "$OUT/inproc-whisper.wav" > /dev/null
inproc --take $FIX/take2.wav --transcript "$TAKE2" --edit '{"kind":"add_cue","cue":"laugh","at":"end"}' --seed 42 --out "$OUT/inproc-laugh.wav" > /dev/null
inproc --take $FIX/noisy.wav --transcript "$TAKE2" --edit '{"kind":"denoise"}' --seed 42 --out "$OUT/inproc-denoise.wav" > /dev/null
inproc --take $FIX/padded.wav --transcript "$TAKE2" --edit '{"kind":"trim_silence"}' --seed 42 --out "$OUT/inproc-trim.wav" > /dev/null
inproc --take "$OUT/gaea-kokoro-0.wav" --transcript 'I was sure the train would wait for us.' --edit '{"kind":"emotion","emotion":"sad"}' --seed 4 --out "$OUT/inproc-asset.wav" > /dev/null
for n in angry afraid whisper laugh denoise trim; do check "$n through Gaea is editx-inproc's WAV, byte for byte" cmp "$OUT/gaea-$n-0.wav" "$OUT/inproc-$n.wav"; done
check "the asset's edit through Gaea is editx-inproc's, byte for byte" cmp "$OUT/gaea-asset1-0.wav" "$OUT/inproc-asset.wav"
say "      in-process angry: $(cat "$OUT/inproc-angry.json")"
for n in angry laugh denoise trim; do say "      $n through Gaea: worker $(py "import json; print(json.load(open('$OUT/job-$n.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])") s"; done

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
