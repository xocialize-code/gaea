#!/bin/zsh
# AB-T-0398's acceptance: gaea-plugin-moss-soundeffect (MOSS-SoundEffect v2.0) through Gaea 0.9.2, installed by repo URL,
# on MES Audio 0.1's audio.generate (media-engine-spec v0.7.0).
#
#   1. audio.generate lists moss-soundeffect: draft, standard and best, 0.5 to 30 s, up to 8 sounds, 48 kHz mono;
#   2. sounds with no model named, each exact to the frame and moss-sfx-inproc's WAV byte for byte: rain at 1.5 s
#      (draft), two barks (count 2, seeds 7 and 8), a street with a negative prompt, a door at 2.3 s (standard);
#   3. effective values: duration_s, seed, quality and x-moss.steps; no duration gives the default 10 s; an unseeded
#      request reports the seed it used; the run reports its denoise steps, then decode;
#   4. output at 44.1 kHz 24-bit is converted, with audio_resampled, and keeps the duration;
#   5. refusals: 0.4 s, 31 s, 9 sounds and a seed of 2³² are 422 out_of_limits; no prompt is 400;
#   6. every recorded GPP session passes the validator.
#
#   tools/acceptance-moss-soundeffect.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; PLUGIN_DIST (default ../gaea-plugin-moss-soundeffect/dist); MOSS_SFX_INPROC (default: the plugin
# repo's release moss-sfx-inproc, built with --build-system swiftbuild). REPO_FROM=github installs the published release
# instead of serving the dist folder through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=../gaea-plugin-moss-soundeffect
PLUGIN_DIST=${PLUGIN_DIST:-$PLUGIN/dist}
INPROC=${MOSS_SFX_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/moss-sfx-inproc}
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
fetch() { # job file, prefix → <prefix>-<i>.wav for every output
  python3 -c "import json,sys; [print(o['href']) for o in json.load(open(sys.argv[1]))['result']['outputs']]" "$1" |
    { i=0; while read href; do mes -o "$2-$i.wav" "http://127.0.0.1:$P$href"; i=$((i+1)); done }
}
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
refused() { py "import json; e=json.load(open('$1')).get('error', {}); assert (e.get('code'), e.get('param')) == ('$3', '$4'), e" && grep -q "^$2\$" "$1.status" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
frames() { python3 -c "import wave,sys; print(wave.open(sys.argv[1]).getnframes())" "$1" }
gen() { # prompt, params JSON → job body
  python3 -c "import json,sys; print(json.dumps({'operation':'audio.generate','inputs':{'prompt':sys.argv[1]},'params':json.loads(sys.argv[2])}))" "$@"
}

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# MOSS-SoundEffect acceptance (AB-T-0398) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), moss-soundeffect $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-moss-soundeffect/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/moss-soundeffect-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/moss-soundeffect-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8777 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8777
fi
H=$WORK/main; P=17691
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs moss-soundeffect $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-moss-soundeffect | grep -q 'Installed .* $VERSION'"

# 1. The offer.
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "audio.generate lists moss-soundeffect: draft/standard/best, 0.5–30 s, 8 sounds, 48 kHz mono" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['audio.generate']; m = d['models']; assert [x['id'] for x in m] == ['moss-soundeffect'], m
assert m[0]['quality_tiers'] == ['draft', 'standard', 'best'], m[0]
l = m[0]['limits']; assert (l['min_duration_s'], l['max_duration_s'], l['max_count']) == (0.5, 30, 8), l
s = m[0]['supports']; assert (s['sample_rate'], s['channels']) == (48000, 1), s
o = d['outputs'][0]; assert (o['name'], o['max']) == ('sounds', 8), o"

# 2. Sounds, no model named.
t0=$(py 'import time; print(time.time())')
job "$(gen 'Rain on a tin roof, steady, with distant thunder.' '{"duration_s":1.5,"quality":"draft","seed":11}')" > "$OUT/job-rain.json"
say "      rain, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare bf16, 25 steps, decode)"
job "$(gen 'A dog barks twice in the distance.' '{"duration_s":1.2,"quality":"draft","count":2,"seed":7}')" > "$OUT/job-barks.json"
job "$(gen 'Busy city street ambience.' '{"duration_s":2.0,"quality":"draft","negative_prompt":"car horns","seed":5}')" > "$OUT/job-street.json"
job "$(gen 'A heavy wooden door creaks open slowly.' '{"duration_s":2.3,"seed":3}')" > "$OUT/job-door.json"
for n in rain barks street door; do fetch "$OUT/job-$n.json" "$OUT/gaea-$n"; done
check "rain: moss-soundeffect, 48 kHz mono 16-bit, 72 000 frames; effective duration, seed, quality and 25 steps" py "
import json; r = json.load(open('$OUT/job-rain.json'))['result']; o = r['outputs'][0]
assert r['provenance']['model']['id'] == 'moss-soundeffect', r['provenance']
assert (o['sample_rate'], o['channels'], o['bit_depth'], o['duration_s']) == (48000, 1, 16, 1.5), o
e = r['effective']; assert (e['duration_s'], e['seed'], e['quality'], e['x-moss.steps']) == (1.5, 11, 'draft', 25), e"
check "rain's WAV has 72 000 frames" test "$(frames $OUT/gaea-rain-0.wav)" = 72000
check "two barks: two sounds of 57 600 frames, effective seed 7" py "
import json; r = json.load(open('$OUT/job-barks.json'))['result']
assert [o['name'] for o in r['outputs']] == ['sounds', 'sounds'] and r['effective']['seed'] == 7 and r['effective']['count'] == 2, r"
check "the barks differ (seeds 7 and 8)" zsh -c "! cmp -s $OUT/gaea-barks-0.wav $OUT/gaea-barks-1.wav"
check "the street reports its negative prompt" py "
import json; e = json.load(open('$OUT/job-street.json'))['result']['effective']; assert e['negative_prompt'] == 'car horns', e"
check "the door at 2.3 s, standard (50 steps), has 110 400 frames" zsh -c "test \$(python3 -c \"import json; print(json.load(open('$OUT/job-door.json'))['result']['effective']['x-moss.steps'])\") = 50 && test $(frames $OUT/gaea-door-0.wav) = 110400"
check "the run reported 25 denoise steps, then decode" zsh -c "s=\$(ls $H/Logs/sessions/com.xocialize.gaea.moss-soundeffect-*.gpp | head -1); test \$(grep -c '\"stage\":\"denoise\"' \$s) -ge 25 && grep -q '\"stage\":\"decode\"' \$s"

# 3. Defaults and seeds.
job "$(gen 'Wind through tall grass.' '{"quality":"draft","seed":1}')" > "$OUT/job-default.json"
check "no duration gives the default 10 s, reported" py "
import json; r = json.load(open('$OUT/job-default.json'))['result']
assert r['effective']['duration_s'] == 10 and r['outputs'][0]['duration_s'] == 10, r"
job "$(gen 'A single hand clap.' '{"duration_s":0.5,"quality":"draft"}')" > "$OUT/job-unseeded.json"
check "an unseeded request reports the seed it used" py "
import json; r = json.load(open('$OUT/job-unseeded.json'))['result']; assert isinstance(r['effective']['seed'], int), r"

# 4. Output conversion.
job "$(gen 'Rain on a tin roof, steady, with distant thunder.' '{"duration_s":1.5,"quality":"draft","seed":11,"output":{"media_type":"audio/wav","sample_rate":44100,"bit_depth":24}}')" > "$OUT/job-44k.json"
check "output at 44.1 kHz 24-bit is converted with audio_resampled, still 1.5 s" py "
import json; j = json.load(open('$OUT/job-44k.json')); assert j['outcome'] == 'succeeded', j; o = j['result']['outputs'][0]
assert (o['sample_rate'], o['bit_depth']) == (44100, 24) and abs(o['duration_s'] - 1.5) < 0.001, o
assert 'audio_resampled' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"

# 5. Refusals.
r() { refuse "$(gen "$2" "$3")" "$WORK/r-$1.json"; print -r -- "$WORK/r-$1.json" }
check "0.4 s is 422 out_of_limits" refused "$(r short 'A click.' '{"duration_s":0.4}')" 422 out_of_limits duration_s
check "31 s is 422 out_of_limits" refused "$(r long 'A click.' '{"duration_s":31}')" 422 out_of_limits duration_s
check "9 sounds is 422 out_of_limits" refused "$(r count 'A click.' '{"count":9}')" 422 out_of_limits count
check "a seed of 2^32 is 422 out_of_limits" refused "$(r seed 'A click.' '{"seed":4294967296}')" 422 out_of_limits seed
refuse '{"operation":"audio.generate","inputs":{},"params":{"duration_s":1}}' "$WORK/r-noprompt.json"
check "no prompt is 400" zsh -c "grep -q '^400' $WORK/r-noprompt.json.status"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status) $(py "import json; e=json.load(open('$f')).get('error') or {}; print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:100])")"; done

$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side.
inproc() { "$INPROC" "$@" 2>> "$LOG" | tail -1 }
inproc --prompt 'Rain on a tin roof, steady, with distant thunder.' --duration 1.5 --quality draft --seed 11 --out-dir "$OUT/inproc-rain" > "$OUT/inproc-rain.json"
inproc --prompt 'A dog barks twice in the distance.' --duration 1.2 --quality draft --count 2 --seed 7 --out-dir "$OUT/inproc-barks" > /dev/null
inproc --prompt 'Busy city street ambience.' --duration 2.0 --quality draft --negative 'car horns' --seed 5 --out-dir "$OUT/inproc-street" > /dev/null
inproc --prompt 'A heavy wooden door creaks open slowly.' --duration 2.3 --seed 3 --out-dir "$OUT/inproc-door" > "$OUT/inproc-door.json"
check "rain through Gaea is moss-sfx-inproc's WAV, byte for byte" cmp "$OUT/gaea-rain-0.wav" "$OUT/inproc-rain/sounds-0.wav"
for i in 0 1; do check "bark $i through Gaea is moss-sfx-inproc's, byte for byte" cmp "$OUT/gaea-barks-$i.wav" "$OUT/inproc-barks/sounds-$i.wav"; done
check "the street (negative prompt) through Gaea is moss-sfx-inproc's, byte for byte" cmp "$OUT/gaea-street-0.wav" "$OUT/inproc-street/sounds-0.wav"
check "the door (standard) through Gaea is moss-sfx-inproc's, byte for byte" cmp "$OUT/gaea-door-0.wav" "$OUT/inproc-door/sounds-0.wav"
say "      in-process rain (draft): $(cat "$OUT/inproc-rain.json")"
say "      in-process door (standard): $(cat "$OUT/inproc-door.json")"
for n in rain barks street door default; do say "      $n through Gaea: worker $(py "import json; print(json.load(open('$OUT/job-$n.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])") s"; done

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
