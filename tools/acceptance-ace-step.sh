#!/bin/zsh
# AB-T-0399's acceptance: gaea-plugin-ace-step (ACE-Step 1.5) through Gaea 0.9.3, installed by repo URL, on MES Audio 0.1's
# audio.compose (media-engine-spec v0.7.0).
#
#   1. audio.compose lists ace-step-1.5: 50 languages, instrumental, reference, cover/repaint/extend, anchors, timestamps,
#      the eight sections, 48 kHz stereo, 10 to 600 s; no score;
#   2. songs with no model named: a 10 s song with timestamps (ace-step-inproc's WAV byte for byte, its lines timed), an
#      instrumental, pinned anchors reported back, a reference from an asset, an unknown section tag dropped with
#      section_unsupported;
#   3. edits on an uploaded 2 s source: extend to 4.5 s and repaint at 2 s, each ace-step-inproc's byte for byte, and cover;
#   4. refusals: a score, planning, a 5 s song, a language it can't sing, and a repaint past the source's end are 422; an
#      edit without a source and a source without an edit are 400;
#   5. every recorded GPP session passes the validator.
#
#   tools/acceptance-ace-step.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; PLUGIN_DIST (default ../gaea-plugin-ace-step/dist); ACE_INPROC (default: the plugin repo's release
# ace-step-inproc, built with --build-system swiftbuild). REPO_FROM=github installs the published release instead of
# serving the dist folder through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=../gaea-plugin-ace-step
PLUGIN_DIST=${PLUGIN_DIST:-$PLUGIN/dist}
SRC=$PLUGIN/Tests/Fixtures/source.wav
INPROC=${ACE_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/ace-step-inproc}
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
post() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
settle() {
  local j
  for _ in {1..120}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$1?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
job() { local r id; r=$(post "$1"); id=$(print -r -- "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))'); [[ -n $id ]] && settle $id || print -r -- "$r" }
fetch() { # job file, prefix → <prefix>-0.wav for the song
  local href=$(python3 -c "import json,sys; print(next(o['href'] for o in json.load(open(sys.argv[1]))['result']['outputs'] if o['name'] == 'song'))" "$1")
  mes -o "$2-0.wav" "http://127.0.0.1:$P$href"
}
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
refused() { py "import json; e=json.load(open('$1')).get('error', {}); assert (e.get('code'), e.get('param')) == ('$3', '$4'), e" && grep -q "^$2\$" "$1.status" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
ok() { py "import json; j=json.load(open('$1')); assert j.get('outcome') == 'succeeded', j" }
frames() { python3 -c "import wave,sys; print(wave.open(sys.argv[1]).getnframes())" "$1" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: audio/wav" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
asset() { mes -X POST "http://127.0.0.1:$P/mes/v0/assets?ttl_s=3600" -H "Content-Type: audio/wav" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['asset_id'])" }
# songbody <caption> <lyrics or ""> <params JSON> [extra inputs JSON]
songbody() {
  python3 -c "
import json, sys
inputs = {'caption': sys.argv[1]}
if sys.argv[2]: inputs['lyrics'] = sys.argv[2]
if len(sys.argv) > 4 and sys.argv[4]: inputs.update(json.loads(sys.argv[4]))
print(json.dumps({'operation': 'audio.compose', 'inputs': inputs, 'params': json.loads(sys.argv[3])}))" "$@"
}

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# ACE-Step acceptance (AB-T-0399) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), ace-step $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-ace-step/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/ace-step-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/ace-step-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8777 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8777
fi
H=$WORK/main; P=17692
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs ace-step $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-ace-step | grep -q 'Installed .* $VERSION'"

# 1. The offer.
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "audio.compose lists ace-step-1.5: 50 languages, instrumental, reference, 3 edits, anchors, timestamps, 8 sections, 48 kHz stereo, 10–600 s" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['audio.compose']; m = d['models']; assert [x['id'] for x in m] == ['ace-step-1.5'], m
s = m[0]['supports']
assert len(s['languages']) == 50 and s['instrumental'] is True and s['reference'] is True, s
assert s['edits'] == ['cover', 'repaint', 'extend'] and s['anchors'] == ['bpm', 'key', 'time_signature'] and s['timestamps'] is True, s
assert len(s['sections']) == 8 and (s['sample_rate'], s['channels']) == (48000, 2) and 'score' not in s, s
l = m[0]['limits']; assert (l['min_duration_s'], l['max_duration_s'], l['max_source_s']) == (10, 600, 600), l
assert {o['name']: o['min'] for o in d['outputs']} == {'song': 1, 'score': 0, 'timestamps': 0}, d['outputs']"

# 2. Songs.
CAPTION='Upbeat synth-pop with a bright female vocal and a driving beat.'
LYRICS=$'[verse]\nLights on the water\nWe follow the line\n[chorus]\nRun all night\n'
t0=$(py 'import time; print(time.time())')
job "$(songbody "$CAPTION" "$LYRICS" '{"duration_s":10,"language":"en","seed":5,"timestamps":true}')" > "$OUT/job-song.json"
say "      song, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare int8, plan, 8 steps, decode)"
fetch "$OUT/job-song.json" "$OUT/gaea-song"
check "the song: ace-step-1.5, 48 kHz stereo 16-bit, 10 s; effective seed, duration, language and anchors" py "
import json; r = json.load(open('$OUT/job-song.json'))['result']; o = r['outputs'][0]
assert r['provenance']['model']['id'] == 'ace-step-1.5', r['provenance']
assert (o['name'], o['sample_rate'], o['channels'], o['bit_depth'], o['duration_s']) == ('song', 48000, 2, 16, 10), o
e = r['effective']; assert (e['seed'], e['duration_s'], e['language']) == (5, 10, 'en') and set(e['anchors']) == {'bpm', 'key', 'time_signature'}, e"
check "timestamps: true returns the sung lines, timed in order" py "
import json; r = json.load(open('$OUT/job-song.json'))['result']
t = [o for o in r['outputs'] if o['name'] == 'timestamps']; assert len(t) == 1, r['outputs']
lines = (t[0].get('value') or {})['lines']; assert len(lines) >= 3, lines
starts = [l['start_s'] for l in lines]; assert starts == sorted(starts) and all(0 <= s <= 10 for s in starts), lines
assert any('water' in l['text'] for l in lines), lines"
job "$(songbody 'Lo-fi hip-hop instrumental, mellow keys, vinyl crackle.' '' '{"duration_s":15,"seed":3}')" > "$OUT/job-instrumental.json"
check "no lyrics make a 15 s instrumental" py "
import json; r = json.load(open('$OUT/job-instrumental.json'))['result']; assert r['outputs'][0]['duration_s'] == 15, r"
job "$(songbody 'A slow waltz, piano and cello, a tender male vocal.' "$LYRICS" '{"duration_s":30,"language":"en","seed":9,"anchors":{"bpm":96,"key":"F# minor","time_signature":"3/4"}}')" > "$OUT/job-anchored.json"
check "pinned anchors come back as effective.anchors (96 bpm, F# minor, 3/4)" py "
import json; a = json.load(open('$OUT/job-anchored.json'))['result']['effective']['anchors']
assert (a['bpm'], a['key'], a['time_signature']) == (96, 'F# minor', '3/4'), a"
A=$(asset $SRC)
job "$(songbody "$CAPTION" "$LYRICS" '{"duration_s":10,"language":"en","seed":4}' '{"reference":{"asset":"'$A'"}}')" > "$OUT/job-reference.json"
check "a reference from an asset lends its timbre (the job runs)" ok "$OUT/job-reference.json"
job "$(songbody "$CAPTION" $'[S1]\nLights on the water\n[chorus]\nRun all night' '{"duration_s":10,"language":"en","seed":1}')" > "$OUT/job-section.json"
check "an unknown section tag is dropped with section_unsupported" py "
import json; j = json.load(open('$OUT/job-section.json')); assert j['outcome'] == 'succeeded', j
assert 'section_unsupported' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"

# 3. Edits on an uploaded 2 s source.
src() { print -r -- '{"source":{"upload":"'$(upload $SRC)'"}}' }
job "$(songbody "$CAPTION" "$LYRICS" '{"language":"en","seed":8,"edit":{"kind":"extend","before_s":1,"after_s":1.5}}' "$(src)")" > "$OUT/job-extend.json"
job "$(songbody "$CAPTION" "$LYRICS" '{"language":"en","seed":7,"edit":{"kind":"repaint","start_s":0.5,"end_s":1.5}}' "$(src)")" > "$OUT/job-repaint.json"
job "$(songbody 'Acoustic folk, guitar and voice.' "$LYRICS" '{"language":"en","seed":6,"edit":{"kind":"cover","strength":0.7}}' "$(src)")" > "$OUT/job-cover.json"
for n in extend repaint cover; do fetch "$OUT/job-$n.json" "$OUT/gaea-$n"; done
check "extend: 1 s + the 2 s source + 1.5 s is 216 000 frames" test "$(frames $OUT/gaea-extend-0.wav)" = 216000
check "repaint and cover keep the source's 2 s (96 000 frames)" zsh -c "test $(frames $OUT/gaea-repaint-0.wav) = 96000 && test $(frames $OUT/gaea-cover-0.wav) = 96000"

# 4. Refusals.
r() { refuse "$(songbody "$CAPTION" "$LYRICS" "$2" "${3:-}")" "$WORK/r-$1.json"; print -r -- "$WORK/r-$1.json" }
check "a score is 422 unsupported_parameter" refused "$(r score '{"duration_s":10}' '{"score":"X:1\nK:C\nCDEF|"}')" 422 unsupported_parameter score
check "planning is 422 unsupported_parameter" refused "$(r planning '{"duration_s":10,"planning":"full"}')" 422 unsupported_parameter planning
check "a 5 s song is 422 out_of_limits" refused "$(r short '{"duration_s":5}')" 422 out_of_limits duration_s
check "Klingon is 422 unsupported_parameter" refused "$(r tlh '{"duration_s":10,"language":"tlh"}')" 422 unsupported_parameter language
check "an edit without a source is 400" refused "$(r nosource '{"edit":{"kind":"cover"}}')" 400 invalid_request edit
check "a source without an edit is 400" refused "$(r noedit '{"duration_s":10}' "$(src)")" 400 invalid_request source
job "$(songbody "$CAPTION" "$LYRICS" '{"language":"en","edit":{"kind":"repaint","start_s":1,"end_s":3}}' "$(src)")" > "$WORK/r-past.json"
check "a repaint past the 2 s source's end is 422 out_of_limits on edit" py "
import json; j = json.load(open('$WORK/r-past.json')); e = j.get('error', {})
assert j.get('outcome') == 'failed' and (e.get('code'), e.get('param')) == ('out_of_limits', 'edit'), j"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status 2>/dev/null) $(py "import json; j=json.load(open('$f')); e=j.get('error') or {}; print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:100])")"; done

$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side.
inproc() { "$INPROC" "$@" 2>> "$LOG" | tail -1 }
inproc --caption "$CAPTION" --lyrics "$LYRICS" --language en --duration 10 --seed 5 --out "$OUT/inproc-song.wav" > "$OUT/inproc-song.json"
inproc --caption "$CAPTION" --lyrics "$LYRICS" --language en --edit '{"kind":"extend","before_s":1,"after_s":1.5}' --source $SRC --seed 8 --out "$OUT/inproc-extend.wav" > /dev/null
inproc --caption "$CAPTION" --lyrics "$LYRICS" --language en --edit '{"kind":"repaint","start_s":0.5,"end_s":1.5}' --source $SRC --seed 7 --out "$OUT/inproc-repaint.wav" > /dev/null
inproc --caption "$CAPTION" --lyrics "$LYRICS" --language en --duration 10 --reference $SRC --seed 4 --out "$OUT/inproc-reference.wav" > /dev/null
fetch "$OUT/job-reference.json" "$OUT/gaea-reference" 2>/dev/null || true
check "the song through Gaea is ace-step-inproc's WAV, byte for byte" cmp "$OUT/gaea-song-0.wav" "$OUT/inproc-song.wav"
check "the extend through Gaea is ace-step-inproc's, byte for byte" cmp "$OUT/gaea-extend-0.wav" "$OUT/inproc-extend.wav"
check "the repaint through Gaea is ace-step-inproc's, byte for byte" cmp "$OUT/gaea-repaint-0.wav" "$OUT/inproc-repaint.wav"
say "      in-process song: $(cat "$OUT/inproc-song.json")"
for n in song instrumental anchored extend cover; do say "      $n through Gaea: worker $(py "import json; print(json.load(open('$OUT/job-$n.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])") s"; done

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
