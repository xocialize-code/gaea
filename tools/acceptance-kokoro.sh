#!/bin/zsh
# AB-T-0393's acceptance: MES audio.speak (Audio 0.1, media-engine-spec v0.7.0) through Gaea 0.9.0, served by
# gaea-plugin-kokoro (Kokoro-82M) installed by repo URL, streamed over GPP chunks (GPP-1 §3.3.1, AB-T-0391/0392).
#
#   1. audio.speak is offered with kokoro-82m: 28 preset voices (GET …/voices), streaming, max_text_chars 4000;
#   2. a job in af_heart, seed 42, is kokoro-inproc's WAV byte for byte, at 24 kHz mono 16-bit; so are three other
#      voices, and every one of the 28 speaks;
#   3. streamed (pcm_s16le): the job.output_chunk events, in order, rebuild the job's WAV exactly, and the same request
#      unstreamed is that WAV byte for byte, which is kokoro-inproc's;
#   4. the client's format: a pcm_f32le stream at 48 kHz stereo, and a 16 kHz 24-bit file, both with audio_resampled;
#   5. text: [pause 2s] is two seconds of silence, an unsupported cue is dropped with cue_unsupported, a 2,000-character
#      text is drawn in pieces and is still kokoro-inproc's; a different seed gives different audio, none gives one;
#   6. refusals: a voice reference, an unknown voice, an emotion, French (422), 4,001 characters (422), no text (400);
#   7. barge-in: a streamed job deleted after its first chunk ends cancelled, the worker's run ends cancelled, and the
#      next job runs;
#   8. every recorded GPP session passes the validator.
#
#   tools/acceptance-kokoro.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app (scripts/build-app.sh); PLUGIN_DIST (default ../gaea-plugin-kokoro/dist); KOKORO_INPROC
# (default: ../gaea-plugin-kokoro's release kokoro-inproc, built with --build-system swiftbuild).
# REPO_FROM=github installs the published release instead of serving the dist folder through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN_DIST=${PLUGIN_DIST:-../gaea-plugin-kokoro/dist}
INPROC=${KOKORO_INPROC:-$(cd ../gaea-plugin-kokoro && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/kokoro-inproc}
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { # name, then a command whose exit status decides
  local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
post() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
settle() { # job id → prints the settled job
  local j
  for _ in {1..60}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$1?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
job() { # json body → prints the settled job, or the refusal
  local r id; r=$(post "$1")
  id=$(print -r -- "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')
  [[ -n $id ]] && settle $id || print -r -- "$r"
}
fetch() { # job file, wav → the job's first output
  mes -o "$2" "http://127.0.0.1:$P$(py "import json; print(json.load(open('$1'))['result']['outputs'][0]['href'])")"
}
events() { curl -s -N --max-time ${2:-20} -H 'MES-Version: 0.1' "http://127.0.0.1:$P/mes/v0/jobs/$1/events" }
start() { # home, port → waits for the operator socket
  GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise > "$1.out" 2>&1 &
  for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done
  say "Gaea at $1 didn't start:"; cat "$1.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
speak() { # voice, seed, text → a job body
  python3 -c "import json,sys; print(json.dumps({'operation':'audio.speak','model':'kokoro-82m','inputs':{'text':sys.argv[3]},'params':{'voice':sys.argv[1],'seed':int(sys.argv[2])}}))" "$@"
}
with() { # body, python expression on b → the body changed
  python3 -c "import json,sys; b=json.loads(sys.argv[1]); $2; print(json.dumps(b))" "$1"
}
ok() { py "import json; j=json.load(open('$1')); assert j.get('outcome') == 'succeeded', j" }
refused() { # file, http code, error code, param
  py "import json; e=json.load(open('$1')).get('error', {}); assert (e.get('code'), e.get('param')) == ('$3', '$4' or None), e" &&
    grep -q "^$2\$" "$1.status"
}
refuse() { # body, file → the refusal and its HTTP status
  mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status"
}

TEXT='Gaea speaks. This sentence came from a signed plugin, over its own protocol.'
STREAMTEXT='Gaea speaks. This sentence came from a signed plugin, over its own protocol. [pause 0.5s] And this one streamed, piece by piece, as it was drawn.'
LONG=$(py "print(' '.join(['Sentence %d of the long text runs on for a while, with a comma or two, so the plan has to cut it into pieces.' % i for i in range(1, 19)]))")
print -r -- "$LONG" > "$WORK/long.txt"

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# Kokoro acceptance (AB-T-0393) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), kokoro $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-kokoro/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/kokoro-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/kokoro-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8775 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8775
fi

H=$WORK/main; P=17687
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs kokoro $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-kokoro | grep -q 'Installed .* $VERSION'"

# 1. The offer.
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
mes "http://127.0.0.1:$P/mes/v0/operations/audio.speak/models/kokoro-82m/voices" > "$OUT/voices.json"
mes "http://127.0.0.1:$P/mes/v0/engine" > "$OUT/engine.json"
check "audio.speak offers kokoro-82m: stream, 28 voices, max_text_chars 4000, audio streamable" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['audio.speak']; m = {x['id']: x for x in d['models']}['kokoro-82m']
assert m['supports']['stream'] is True and m['supports']['voices'] == 28 and m['supports']['languages'] == ['en-US', 'en-GB'], m
assert m['limits']['max_text_chars'] == 4000 and m.get('default') is True, m
assert [o.get('stream') for o in d['outputs'] if o['name'] == 'audio'] == [{'encodings': ['pcm_s16le', 'pcm_f32le']}], d['outputs']"
check "GET …/voices lists the 28 voices, af_heart the default" py "
import json; v = json.load(open('$OUT/voices.json'))['voices']; ids = [x['id'] for x in v]
assert len(ids) == 28 and 'af_heart' in ids and 'bm_lewis' in ids, ids
assert [x for x in v if x['id'] == 'af_heart'][0]['notes'] == 'The default voice.'"
check "the engine reports Audio 0.1 and the streaming and assets features" py "
import json; e = json.load(open('$OUT/engine.json'))
assert {'id': 'audio', 'versions': ['0.1']} in e['profiles'] and {'streaming', 'assets'} <= set(e['features']), e"

# 2. Voices.
t0=$(py 'import time; print(time.time())')
job "$(speak af_heart 42 "$TEXT")" > "$OUT/job-af_heart.json"
say "      af_heart, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare, speak)"
fetch "$OUT/job-af_heart.json" "$OUT/gaea-af_heart.wav"
check "af_heart seed 42: a 24 kHz mono 16-bit WAV, effective seed 42 and voice af_heart" py "
import json; j = json.load(open('$OUT/job-af_heart.json')); assert j['outcome'] == 'succeeded', j; r = j['result']
o = r['outputs'][0]; assert (o['sample_rate'], o['channels'], o['bit_depth'], o['media_type']) == (24000, 1, 16, 'audio/wav'), o
assert r['effective']['seed'] == 42 and r['effective']['voice'] == 'af_heart' and r['provenance']['model']['id'] == 'kokoro-82m', r"
for v in am_adam bf_emma bm_lewis; do
  job "$(speak $v 42 "$TEXT")" > "$OUT/job-$v.json"; fetch "$OUT/job-$v.json" "$OUT/gaea-$v.wav"
done
check "four voices, four different recordings" py "
import hashlib; s = {hashlib.sha256(open('$OUT/gaea-%s.wav' % v, 'rb').read()).hexdigest() for v in ['af_heart','am_adam','bf_emma','bm_lewis']}
assert len(s) == 4, s"
all=0
for v in $(py "import json; print(' '.join(x['id'] for x in json.load(open('$OUT/voices.json'))['voices']))"); do
  job "$(speak $v 1 "Hello from $v.")" > "$WORK/v-$v.json"; ok "$WORK/v-$v.json" 2>/dev/null && all=$((all+1))
done
check "every one of the 28 voices speaks ($all of 28)" test $all -eq 28

# 3. Streamed.
r=$(post "$(with "$(speak bm_lewis 7 "$STREAMTEXT")" "b['stream'] = [{'output': 'audio', 'encoding': 'pcm_s16le'}]")")
SID=$(print -r -- "$r" | py "import json,sys; print(json.load(sys.stdin)['id'])")
events $SID 30 > "$OUT/stream-events.txt"
settle $SID > "$OUT/job-stream.json"
fetch "$OUT/job-stream.json" "$OUT/gaea-stream.wav"
check "streamed: chunks numbered in order, the last final, offsets rising, before job.ended" py "
import json
ev = [json.loads(l[5:]) for l in open('$OUT/stream-events.txt') if l.startswith('data:')]
c = [e['data'] for e in ev if e['type'] == 'job.output_chunk']
assert [x['index'] for x in c] == list(range(len(c))) and len(c) >= 3, c
assert [x['final'] for x in c] == [False] * (len(c) - 1) + [True], c
assert all(a['offset_s'] < b['offset_s'] for a, b in zip(c, c[1:])), c
types = [e['type'] for e in ev]; assert types.index('job.output_chunk') < types.index('job.ended') if 'job.ended' in types else True"
check "streamed: the chunks rebuild the job's WAV exactly" py "
import json, base64
c = [json.loads(l[5:])['data'] for l in open('$OUT/stream-events.txt') if l.startswith('data:') and 'job.output_chunk' in l]
pcm = b''.join(base64.b64decode(x.get('data', '')) for x in c); wav = open('$OUT/gaea-stream.wav', 'rb').read()
assert wav[44:] == pcm and len(pcm) > 0, (len(wav), len(pcm))"
say "      streamed: $(py "
import json
ev = [json.loads(l[5:]) for l in open('$OUT/stream-events.txt') if l.startswith('data:')]
c = [e for e in ev if e['type'] == 'job.output_chunk']; print(len(c), 'chunks;', 'audio', c[-1]['data']['offset_s'], 's +')") ($(py "import json; print(json.load(open('$OUT/job-stream.json'))['result']['effective']['x-kokoro.pieces'])") pieces)"
job "$(speak bm_lewis 7 "$STREAMTEXT")" > "$OUT/job-unstreamed.json"; fetch "$OUT/job-unstreamed.json" "$OUT/gaea-unstreamed.wav"
check "the same request unstreamed is the streamed WAV, byte for byte" cmp "$OUT/gaea-unstreamed.wav" "$OUT/gaea-stream.wav"

# 4. The client's format.
r=$(post "$(with "$(speak af_heart 42 "$TEXT")" "b['stream'] = [{'output': 'audio', 'encoding': 'pcm_f32le'}]; b['params']['output'] = {'sample_rate': 48000, 'channels': 2}")")
FID=$(print -r -- "$r" | py "import json,sys; print(json.load(sys.stdin)['id'])")
events $FID 30 > "$OUT/stream-f32-events.txt"; settle $FID > "$OUT/job-stream-f32.json"
check "a pcm_f32le stream at 48 kHz stereo: a 32-bit float WAV, as long as the 24 kHz one, with audio_resampled" py "
import json; j = json.load(open('$OUT/job-stream-f32.json')); assert j['outcome'] == 'succeeded', j; o = j['result']['outputs'][0]
a = json.load(open('$OUT/job-af_heart.json'))['result']['outputs'][0]
assert (o['sample_rate'], o['channels'], o['bit_depth']) == (48000, 2, 32), o
assert abs(o['duration_s'] - a['duration_s']) < 0.01, (o, a)
assert 'audio_resampled' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"
job "$(with "$(speak af_heart 42 "$TEXT")" "b['params']['output'] = {'sample_rate': 16000, 'bit_depth': 24}")" > "$OUT/job-16k.json"
check "a 16 kHz 24-bit file, with audio_resampled" py "
import json; j = json.load(open('$OUT/job-16k.json')); assert j['outcome'] == 'succeeded', j; o = j['result']['outputs'][0]
assert (o['sample_rate'], o['channels'], o['bit_depth']) == (16000, 1, 24), o
assert [w['code'] for w in j.get('warnings', [])] == ['audio_resampled'], j.get('warnings')"

# 5. Text.
job "$(speak af_heart 42 'One. [pause 2s] Two.')" > "$OUT/job-pause.json"; fetch "$OUT/job-pause.json" "$OUT/gaea-pause.wav"
job "$(speak af_heart 42 'One. Two.')" > "$OUT/job-nopause.json"; fetch "$OUT/job-nopause.json" "$OUT/gaea-nopause.wav"
check "[pause 2s] adds two seconds of digital silence between the words" py "
import array; a = array.array('h', open('$OUT/gaea-pause.wav', 'rb').read()[44:])
best = run = 0
for s in a:
    run = run + 1 if s == 0 else 0; best = max(best, run)
# Kokoro's own pieces end in a few tenths of a second of exact zeros, which join the pause's.
assert best >= 48000, best
print('longest silence', best / 24000, 's')"
job "$(speak af_heart 42 'Well [laugh] that is funny.')" > "$OUT/job-cue.json"
check "an unsupported cue is dropped with cue_unsupported" py "
import json; j = json.load(open('$OUT/job-cue.json')); assert j['outcome'] == 'succeeded', j
assert 'cue_unsupported' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"
job "$(py "import json; print(json.dumps({'operation':'audio.speak','model':'kokoro-82m','inputs':{'text':open('$WORK/long.txt').read().strip()},'params':{'voice':'bf_emma','seed':3}}))")" > "$OUT/job-long.json"
fetch "$OUT/job-long.json" "$OUT/gaea-long.wav"
check "a 2,000-character text is drawn in pieces" py "
import json; j = json.load(open('$OUT/job-long.json')); assert j['outcome'] == 'succeeded', j
assert j['result']['effective']['x-kokoro.pieces'] >= 7, j['result']['effective']"
job "$(speak af_heart 43 "$TEXT")" > "$OUT/job-seed43.json"; fetch "$OUT/job-seed43.json" "$OUT/gaea-seed43.wav"
check "a different seed gives different audio" zsh -c "! cmp -s '$OUT/gaea-seed43.wav' '$OUT/gaea-af_heart.wav'"
job "$(with "$(speak af_heart 0 "$TEXT")" "del b['params']['seed']")" > "$OUT/job-noseed.json"
check "a job without a seed reports the one it used" py "
import json; j = json.load(open('$OUT/job-noseed.json')); s = j['result']['effective']['seed']; assert isinstance(s, int) and 0 <= s < 2**32, s"

# 6. Refusals.
U=$(mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: audio/wav' --data-binary @"$OUT/gaea-af_heart.wav" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])")
refuse '{"operation":"audio.speak","model":"kokoro-82m","inputs":{"text":"hi","voice_ref":{"upload":"'$U'"}}}' "$WORK/r-ref.json"
check "a voice reference is 422 unsupported_parameter (Kokoro doesn't clone)" refused "$WORK/r-ref.json" 422 unsupported_parameter voice_ref
refuse "$(speak nope 1 hi)" "$WORK/r-voice.json"
check "an unknown voice is 422 unsupported_parameter" refused "$WORK/r-voice.json" 422 unsupported_parameter voice
refuse "$(with "$(speak af_heart 1 hi)" "b['params']['emotion'] = {'label': 'angry'}")" "$WORK/r-emotion.json"
check "an emotion is 422 unsupported_parameter" refused "$WORK/r-emotion.json" 422 unsupported_parameter emotion
refuse '{"operation":"audio.speak","inputs":{"text":"bonjour"},"params":{"language":"fr"}}' "$WORK/r-fr.json"
check "French is 422 unsupported_parameter" refused "$WORK/r-fr.json" 422 unsupported_parameter language
refuse "$(speak af_heart 1 "$(py "print('a' * 4001)")")" "$WORK/r-long.json"
check "4,001 characters is 422 out_of_limits" refused "$WORK/r-long.json" 422 out_of_limits text
refuse '{"operation":"audio.speak","model":"kokoro-82m","inputs":{},"params":{}}' "$WORK/r-none.json"
check "no text is 400 invalid_request" refused "$WORK/r-none.json" 400 invalid_request text
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status) $(py "import json; e=json.load(open('$f'))['error']; print(e['code'], e.get('param'), '-', e['message'][:90])")"; done

# 7. Barge-in: a streamed job of nearly 4,000 characters, deleted the moment its first chunk arrives.
py "print((open('$WORK/long.txt').read().strip() + ' ') * 2)" | cut -c1-3990 > "$WORK/longer.txt"
r=$(post "$(py "import json; print(json.dumps({'operation':'audio.speak','model':'kokoro-82m','inputs':{'text':open('$WORK/longer.txt').read().strip()},'params':{'voice':'am_adam','seed':5},'stream':[{'output':'audio'}]}))")")
BID=$(print -r -- "$r" | py "import json,sys; print(json.load(sys.stdin)['id'])")
events $BID 60 | while read -r line; do [[ $line == *job.output_chunk* ]] && break; done
t0=$(py 'import time; print(time.time())')
mes -X DELETE "http://127.0.0.1:$P/mes/v0/jobs/$BID" > /dev/null
settle $BID > "$OUT/job-bargein.json"
say "      barge-in: settled $(py "import time; print(round(time.time()-$t0, 2))") s after DELETE"
check "the deleted job ended cancelled" py "
import json; j = json.load(open('$OUT/job-bargein.json')); assert j['outcome'] == 'cancelled', j"
check "the worker's run ended cancelled" zsh -c "grep -h '\"code\":\"cancelled\"' $H/Logs/sessions/*.gpp | grep -q '\"$BID\"'"
job "$(speak af_heart 42 "$TEXT")" > "$OUT/job-after.json"; fetch "$OUT/job-after.json" "$OUT/gaea-after.wav"
check "the next job runs, and is the first af_heart WAV again" cmp "$OUT/gaea-after.wav" "$OUT/gaea-af_heart.wav"

$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side, after Gaea has stopped: the same requests through kokoro-inproc.
inproc() { "$INPROC" --once "$@" 2>> "$LOG" | tail -1 }
inproc --voice af_heart --seed 42 --text "$TEXT" --out "$OUT/inproc-af_heart.wav" > "$OUT/inproc-af_heart.json"
for v in am_adam bf_emma bm_lewis; do inproc --voice $v --seed 42 --text "$TEXT" --out "$OUT/inproc-$v.wav" > /dev/null; done
for v in af_heart am_adam bf_emma bm_lewis; do
  check "$v through Gaea is kokoro-inproc's WAV, byte for byte" cmp "$OUT/gaea-$v.wav" "$OUT/inproc-$v.wav"
done
inproc --voice bm_lewis --seed 7 --text "$STREAMTEXT" --out "$OUT/inproc-stream.wav" > /dev/null
check "the streamed job's WAV is kokoro-inproc's, byte for byte" cmp "$OUT/gaea-stream.wav" "$OUT/inproc-stream.wav"
inproc --voice af_heart --seed 42 --text 'One. [pause 2s] Two.' --out "$OUT/inproc-pause.wav" > /dev/null
check "the pause job is kokoro-inproc's, byte for byte" cmp "$OUT/gaea-pause.wav" "$OUT/inproc-pause.wav"
inproc --voice bf_emma --seed 3 --text-file "$WORK/long.txt" --out "$OUT/inproc-long.wav" > "$OUT/inproc-long.json"
check "the long text is kokoro-inproc's, byte for byte" cmp "$OUT/gaea-long.wav" "$OUT/inproc-long.wav"
say "      in-process af_heart: $(cat "$OUT/inproc-af_heart.json")"
say "      in-process long text: $(cat "$OUT/inproc-long.json")"

for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
