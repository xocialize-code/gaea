#!/bin/zsh
# AB-T-0453's acceptance (G5 order 2): gaea-plugin-voxcpm2 (OpenBMB's VoxCPM2) through Gaea, installed from GitHub beside
# gaea-plugin-kokoro and gaea-plugin-indextts, on MES Audio 0.1.
#
#   1. audio.speak lists voxcpm2 (a default voice, voice_ref, voice_ref_text optional, 30 languages, emotions and
#      descriptions, 48 kHz) beside kokoro-82m and indextts-2.5; audio.design_voice lists voxcpm2;
#   2. speak: the default voice, happy with a pause, a delivery description, Chinese, a clone of the fixture and its
#      continuation clone, each voxcpm2-inproc's WAV byte for byte; intensity is ignored with a warning;
#   3. design_voice: two samples at seed 7 and 8 with effective seed and text, voxcpm2-inproc's; five is 422; the first
#      sample kept as an asset clones back with its text (a continuation), voxcpm2-inproc's byte for byte, the same WAV
#      a second time; deleting the asset sends asset_removed;
#   4. routing with no model named: a description with no reference, and a reference with a description, go to voxcpm2;
#      a reference with target_duration_s to indextts-2.5; design_voice to voxcpm2;
#   5. reference formats: 24-bit, float and FLAC accepted; stereo mixed down and 30 s trimmed to 20, with warnings;
#   6. refusals: an emotion outside the list, Ukrainian, a design language without a sample, target_duration_s on voxcpm2;
#   7. every recorded GPP session passes the validator.
#
#   tools/acceptance-voxcpm2.sh <short-work-dir> <evidence-dir>
#
# Needs: APP (default dist/Gaea.app); GAEA_GITHUB_TOKEN; the plugin repo at ../gaea-plugin-voxcpm2 for its fixture and
# voxcpm2-inproc (release, --build-system swiftbuild); VoxCPM2's and IndexTTS 2.5's weights in MODELS (default
# /Volumes/DEV_VOL1/Models/Models), which Gaea uses as its models root.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=${PLUGIN_REPO:-../gaea-plugin-voxcpm2}
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models/Models}
INPROC=${VOXCPM2_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/voxcpm2-inproc}
REF=$PLUGIN/scripts/fixtures/ref-en.wav
REFTEXT='The morning train was late again, so I walked along the river and watched the boats come in.'
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
body() { # operation, inputs JSON, params JSON, [model]
  python3 -c "
import json,sys
b = {'operation': sys.argv[1], 'inputs': json.loads(sys.argv[2]), 'params': json.loads(sys.argv[3])}
if len(sys.argv) > 4 and sys.argv[4]: b['model'] = sys.argv[4]
print(json.dumps(b))" "$@"
}
jtext() { python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1" }

say "# VoxCPM2 acceptance (AB-T-0453) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), voxcpm2 from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/main; P=17691
start $H $P
export GAEA_HOME=$H
for r in kokoro indextts voxcpm2; do
  check "add by repo URL installs $r" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-$r | tee -a $LOG | grep -q Installed"
done
say "      voxcpm2 $($CLI plugins | awk '/com.xocialize.gaea.voxcpm2/ {print $3}')"

# 1. The offers.
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "audio.speak lists voxcpm2 beside kokoro-82m and indextts-2.5, with its supports" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['audio.speak']['models']}; assert {'kokoro-82m', 'indextts-2.5', 'voxcpm2'} <= set(m), m.keys()
s = m['voxcpm2']['supports']
assert s['default_voice'] is True and s['voice_ref'] is True and s['voice_ref_text'] == 'optional', s
assert len(s['languages']) == 30 and len(s['emotions']) == 9 and s['emotion_description'] is True and s['sample_rate'] == 48000, s
assert not s.get('target_duration') and not s.get('speed'), s"
check "audio.design_voice lists voxcpm2, at most 4 samples, 12 languages" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['audio.design_voice']['models']}['voxcpm2']
assert m['limits']['max_count'] == 4 and len(m['supports']['languages']) == 12, m"

# 2. Speak.
EN='Gaea speaks. This sentence came from a signed plugin, over its own protocol.'
U() { print -r -- '{"upload":"'$(upload "$REF" audio/wav)'"}' }
t0=$(py 'import time; print(time.time())')
job "$(body audio.speak '{"text":'"$(jtext "$EN")"'}' '{"seed":42}' voxcpm2)" > "$OUT/job-zero.json"
say "      zero, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare, speak)"
job "$(body audio.speak '{"text":"We won! [pause 0.5s] I still can not believe it."}' '{"seed":3,"emotion":{"label":"happy"}}' voxcpm2)" > "$OUT/job-happy.json"
job "$(body audio.speak '{"text":"Come closer. Nobody else can know."}' '{"seed":5,"emotion":{"description":"whispering, as if telling a secret","intensity":0.5}}' voxcpm2)" > "$OUT/job-described.json"
job "$(body audio.speak '{"text":"今天天气很好，我们去公园散步吧。"}' '{"seed":11,"language":"zh"}' voxcpm2)" > "$OUT/job-chinese.json"
job "$(body audio.speak '{"text":'"$(jtext "$EN")"',"voice_ref":'"$(U)"'}' '{"seed":9}' voxcpm2)" > "$OUT/job-clone.json"
job "$(body audio.speak '{"text":'"$(jtext "$EN")"',"voice_ref":'"$(U)"',"voice_ref_text":'"$(jtext "$REFTEXT")"'}' '{"seed":9}' voxcpm2)" > "$OUT/job-continuation.json"
SPEAK=(zero happy described chinese clone continuation)
for n in $SPEAK; do check "$n succeeds" ok "$OUT/job-$n.json"; fetch "$OUT/job-$n.json" "$OUT/gaea-$n"; done
check "zero: a 48 kHz mono 16-bit WAV, the default voice, seed 42" py "
import json; r = json.load(open('$OUT/job-zero.json'))['result']; o = r['outputs'][0]
assert (o['sample_rate'], o['channels'], o['bit_depth']) == (48000, 1, 16), o
assert r['effective']['x-voxcpm2.voice'] == 'default' and r['effective']['seed'] == 42, r['effective']"
check "the clone and the continuation report their mode" py "
import json
assert json.load(open('$OUT/job-clone.json'))['result']['effective']['x-voxcpm2.voice'] == 'clone'
assert json.load(open('$OUT/job-continuation.json'))['result']['effective']['x-voxcpm2.voice'] == 'continuation'"
check "intensity is ignored with emotion_intensity_ignored" py "
import json; j = json.load(open('$OUT/job-described.json')); assert 'emotion_intensity_ignored' in [w['code'] for w in j.get('warnings', [])], j"

# 3. Design, and the designed voice cloned back through an asset.
DESC='A warm, low voice of a woman in her forties, unhurried, with a slight rasp.'
job "$(body audio.design_voice '{"description":'"$(jtext "$DESC")"'}' '{"count":2,"seed":7,"language":"en"}' voxcpm2)" > "$OUT/job-design.json"
fetch "$OUT/job-design.json" "$OUT/gaea-design"
check "design_voice: two samples, effective seed 7 and the sample text" py "
import json; j = json.load(open('$OUT/job-design.json')); assert j['outcome'] == 'succeeded', j; r = j['result']
assert [o['name'] for o in r['outputs']] == ['samples', 'samples'] and r['effective']['seed'] == 7, r
assert r['effective']['text'].startswith('Hello!'), r['effective']"
refuse "$(body audio.design_voice '{"description":"x"}' '{"count":5}' voxcpm2)" "$WORK/r-count.json"
check "five samples is 422 out_of_limits" refused "$WORK/r-count.json" 422 out_of_limits count
SAMPLE=$(py "import json; print(json.load(open('$OUT/job-design.json'))['result']['effective']['text'])")
A=$(asset "$OUT/gaea-design-0.wav" audio/wav); say "      asset: $A"
CT='The clone reads a new line now, in the voice it was given.'
DBODY=$(body audio.speak '{"text":'"$(jtext "$CT")"',"voice_ref":{"asset":"'$A'"},"voice_ref_text":'"$(jtext "$SAMPLE")"'}' '{"seed":13}' voxcpm2)
job "$DBODY" > "$OUT/job-designed-clone.json"; fetch "$OUT/job-designed-clone.json" "$OUT/gaea-designed-clone"
job "$DBODY" > "$OUT/job-designed-clone2.json"; fetch "$OUT/job-designed-clone2.json" "$OUT/gaea-designed-clone2"
check "the designed voice cloned from its asset, a continuation" py "
import json; r = json.load(open('$OUT/job-designed-clone.json'))['result']; assert r['effective']['x-voxcpm2.voice'] == 'continuation', r"
check "a second job on the asset is the same WAV" cmp "$OUT/gaea-designed-clone-0.wav" "$OUT/gaea-designed-clone2-0.wav"
check "the run carried the asset id to the worker" zsh -c "grep -h '\"type\":\"run\"' $H/Logs/sessions/com.xocialize.gaea.voxcpm2-*.gpp | grep -q '\"voice_ref\":\[\"$A\"\]'"
mes -X DELETE "http://127.0.0.1:$P/mes/v0/assets/$A" -o /dev/null -w '%{http_code}\n' > "$WORK/delete.status"; sleep 2
check "deleting the asset (204) sends asset_removed to the worker" zsh -c "grep -q '^204' $WORK/delete.status && grep -h asset_removed $H/Logs/sessions/com.xocialize.gaea.voxcpm2-*.gpp | grep -q '$A'"

# 4. Routing with no model named.
route() { job "$1" > "$OUT/route-$2.json"; check "$3 → $4" test "$(model "$OUT/route-$2.json")" = "$4" }
route "$(body audio.speak '{"text":"Hello there."}' '{"emotion":{"description":"sleepy, yawning"}}')" described "a description with no reference" voxcpm2
route "$(body audio.speak '{"text":"Hello there.","voice_ref":'"$(U)"'}' '{"emotion":{"description":"cheerful"}}')" ref-described "a reference with a description" voxcpm2
route "$(body audio.speak '{"text":"Hello there.","voice_ref":'"$(U)"'}' '{"target_duration_s":2.0}')" ref-fit "a reference with target_duration_s" indextts-2.5
route "$(body audio.design_voice '{"description":"a bright young voice"}' '{"seed":1}')" design "design_voice" voxcpm2

# 5. Reference formats.
afconvert -f WAVE -d LEI24 "$REF" "$WORK/ref24.wav"; afconvert -f WAVE -d LEF32 "$REF" "$WORK/reff32.wav"
afconvert -f flac -d flac "$REF" "$WORK/ref.flac"; afconvert -f WAVE -d LEI16 -c 2 "$REF" "$WORK/refstereo.wav"
py "
import wave; w = wave.open('$REF'); p = w.getparams(); f = w.readframes(p.nframes)
o = wave.open('$WORK/ref30.wav', 'wb'); o.setparams(p); o.writeframes(f * (int(30 * p.framerate / p.nframes) + 1)); o.close()"
for f in ref24.wav:audio/wav reff32.wav:audio/wav ref.flac:audio/flac refstereo.wav:audio/wav ref30.wav:audio/wav; do
  n=${f%%:*}; u=$(upload "$WORK/$n" ${f#*:})
  job "$(body audio.speak '{"text":"Short line.","voice_ref":{"upload":"'$u'"}}' '{"seed":4}' voxcpm2)" > "$OUT/job-ref-$n.json"
done
for n in ref24.wav reff32.wav ref.flac; do check "a $n reference is accepted" ok "$OUT/job-ref-$n.json"; done
check "a stereo reference is mixed down, with audio_downmixed" py "
import json; j = json.load(open('$OUT/job-ref-refstereo.wav.json')); assert j['outcome'] == 'succeeded', j
assert 'audio_downmixed' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"
check "a 30 s reference is trimmed to 20 s, with voice_ref_trimmed" py "
import json; j = json.load(open('$OUT/job-ref-ref30.wav.json')); assert j['outcome'] == 'succeeded', j
assert 'voice_ref_trimmed' in [w['code'] for w in j.get('warnings', [])] and j['result']['effective']['x-voxcpm2.voice_ref_s'] == 20, j"

# 6. Refusals.
refuse "$(body audio.speak '{"text":"hi"}' '{"emotion":{"label":"excited"}}' voxcpm2)" "$WORK/r-emotion.json"
refuse "$(body audio.speak '{"text":"привіт"}' '{"language":"uk"}' voxcpm2)" "$WORK/r-uk.json"
refuse "$(body audio.design_voice '{"description":"a calm voice"}' '{"language":"th"}' voxcpm2)" "$WORK/r-design-th.json"
refuse "$(body audio.speak '{"text":"hi"}' '{"target_duration_s":2}' voxcpm2)" "$WORK/r-fit.json"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status) $(py "import json; e=json.load(open('$f')).get('error', {}); print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:100])")"; done
check "an emotion outside the list is 422" refused "$WORK/r-emotion.json" 422 unsupported_parameter emotion
check "Ukrainian is 422" refused "$WORK/r-uk.json" 422 unsupported_parameter language
check "a design language without a sample (Thai) is 422" refused "$WORK/r-design-th.json" 422 unsupported_parameter language
check "target_duration_s on voxcpm2 is 422" refused "$WORK/r-fit.json" 422 unsupported_parameter target_duration_s

$CLI ledger > "$OUT/ledger.txt"
stop $P

# The in-process side.
inproc() { "$INPROC" "$@" --models-root "$MODELS" 2>> "$LOG" | tail -1 }
inproc speak --seed 42 --text "$EN" --out "$OUT/inproc-zero.wav" > "$OUT/inproc-zero.json"
inproc speak --seed 3 --emotion happy --text 'We won! [pause 0.5s] I still can not believe it.' --out "$OUT/inproc-happy.wav" > /dev/null
inproc speak --seed 5 --emotion-description 'whispering, as if telling a secret' --text 'Come closer. Nobody else can know.' --out "$OUT/inproc-described.wav" > /dev/null
inproc speak --seed 11 --language zh --text '今天天气很好，我们去公园散步吧。' --out "$OUT/inproc-chinese.wav" > /dev/null
inproc speak --seed 9 --ref "$REF" --text "$EN" --out "$OUT/inproc-clone.wav" > /dev/null
inproc speak --seed 9 --ref "$REF" --ref-text "$REFTEXT" --text "$EN" --out "$OUT/inproc-continuation.wav" > /dev/null
inproc design --description "$DESC" --count 2 --seed 7 --language en --out-dir "$OUT/inproc-design" > "$OUT/inproc-design.json"
inproc speak --seed 13 --ref "$OUT/gaea-design-0.wav" --ref-text "$SAMPLE" --text "$CT" --out "$OUT/inproc-designed-clone.wav" > /dev/null
for n in $SPEAK designed-clone; do check "$n through Gaea is voxcpm2-inproc's WAV, byte for byte" cmp "$OUT/gaea-$n-0.wav" "$OUT/inproc-$n.wav"; done
for i in 0 1; do check "design sample $i through Gaea is voxcpm2-inproc's, byte for byte" cmp "$OUT/gaea-design-$i.wav" "$OUT/inproc-design/samples-$i.wav"; done
say "      in-process zero: $(cat "$OUT/inproc-zero.json")"

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
