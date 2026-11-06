#!/bin/zsh
# AB-T-0456's Lab run (G5's exit): Gaea Lab on the G5 audio, on media-engine-spec 0.10.1, against a fresh Gaea with
# IndexTTS 2.5, VoxCPM2, AuK and the demo installed from GitHub, AuK's two models enabled.
#
#   1. lab-run runs each operation the way the Lab does (RunSession over EnginePool):
#      - IndexTTS: a clone fitted to 4.0 s;
#      - VoxCPM2: its own voice at 48 kHz, and design_voice with two samples;
#      - AuK, refused without users' acceptance (lab-run names the licence to accept), then with --accept:
#        - a clone;
#        - edit_speech: dereverb, and a hum at the start with the edited transcript;
#        - separate: the second speaker of a mixture at the mixture's length, and Base's voices;
#      - an unnamed separate goes to the demo's separator, never AuK (named-only);
#   2. the Lab app renders AuK's edit and separation, with the terms shown and then accepted for the run, before and
#      after, light and dark (--snapshot);
#   3. every recorded GPP session passes the validator.
#
#   tools/lab-audio-g5.sh <short-work-dir> <evidence-dir>
#
# Needs: APP (default dist/Gaea.app, 1.1.1 or later); the Lab built (cd Apps/GaeaLab && swift build -c release); the
# fixtures in ../gaea-plugin-auk/scripts/fixtures; the weights in MODELS (default /Volumes/DEV_VOL1/Models/Models).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models/Models}
BIN=$(cd Apps/GaeaLab && swift build -c release --show-bin-path)
LR=$BIN/lab-run; LAB=$BIN/GaeaLabApp
FIX=../gaea-plugin-auk/scripts/fixtures
REF=$FIX/ref-en.wav; MIX=$FIX/mix-two.wav
REFTEXT='The morning train was late again, so I walked along the river and watched the boats come in.'
QWEN=LicenseRef-Qwen-Research
mkdir -p "$OUT" "$WORK"
LOG="$OUT/lab-audio-g5.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
py() { python3 -c "$1" }
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || return; sleep 0.2; done }
start() {
  GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" >> "$WORK/gaea.out" 2>&1 &
  for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
}

say "# Gaea Lab on the G5 audio (AB-T-0456) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), $(py "import json; p = {x['identity']: x['state'].get('version') for x in json.load(open('Apps/GaeaLab/Package.resolved'))['pins']}; print('pixel-agency-run', p['pixel-agency-run'] + ', media-engine-spec', p['media-engine-spec'])")"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/home; P=17694
start
for repo in indextts voxcpm2 auk demo; do
  check "add gaea-plugin-$repo by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-$repo | tee -a $OUT/plugins.txt | grep -q Installed"
done
for id in auk-flash auk; do GAEA_HOME=$H "$CLI" models enable $id | tee -a "$OUT/plugins.txt"; done
E=http://127.0.0.1:$P/mes/v0

# 1. The operations, as the Lab runs them.
lab() { local name=$1; shift; "$LR" --engine $E --out "$OUT/$name" --report "$OUT/$name.json" "$@" > "$OUT/$name.out" 2>&1; local s=$?; sed 's/^/      /' "$OUT/$name.out" | tee -a "$LOG"; return $s }
wavs() { py "import glob, wave; [print(f, wave.open(f).getframerate(), wave.open(f).getnframes()) for f in sorted(glob.glob('$OUT/$1/*.wav'))]" }
model() { py "import json; print(json.load(open('$OUT/$1.json'))['provenance']['model']['id'])" }

check "IndexTTS: a clone fitted to 4.0 s" lab indextts-fit --operation audio.speak --model indextts-2.5 --file voice_ref=$REF \
  --text "text=This line has to fit the cue. [pause 0.5s] Exactly." --param language=en --param target_duration_s=4.0 --param seed=7
check "the fit is 4.0 s at 22.05 kHz" py "
import glob, wave; [f] = glob.glob('$OUT/indextts-fit/*.wav'); w = wave.open(f)
assert w.getframerate() == 22050 and abs(w.getnframes() / 22050 - 4.0) <= 0.1, (w.getframerate(), w.getnframes())"
check "VoxCPM2: its own voice" lab voxcpm2-speak --operation audio.speak --model voxcpm2 \
  --text "text=Gaea Lab speaks through VoxCPM2, in a voice of its own." --param seed=42
check "VoxCPM2's take is 48 kHz" py "
import glob, wave; [f] = glob.glob('$OUT/voxcpm2-speak/*.wav'); assert wave.open(f).getframerate() == 48000"
check "VoxCPM2: design_voice, two samples" lab voxcpm2-design --operation audio.design_voice --model voxcpm2 \
  --text "description=A warm, low voice of a woman in her forties, unhurried, with a slight rasp." --param count=2 --param seed=7 --param language=en
check "the design saved two samples" py "import glob; fs = glob.glob('$OUT/voxcpm2-design/*.wav'); assert len(fs) == 2, fs"

"$LR" --engine $E --out "$OUT/auk-refused" --operation audio.speak --model auk-flash --file voice_ref=$REF \
  --text "text=Not yet." > "$OUT/auk-refused.out" 2>&1; refused=$?
sed 's/^/      /' "$OUT/auk-refused.out" | tee -a "$LOG"
check "AuK without users' acceptance fails, naming the licence to accept" zsh -c "(( $refused != 0 )) && grep -q 'needs acceptance' $OUT/auk-refused.out && grep -q -- '--accept $QWEN' $OUT/auk-refused.out"
check "AuK-Flash: a clone, accepted" lab auk-clone --operation audio.speak --model auk-flash --accept $QWEN --file voice_ref=$REF \
  --text "voice_ref_text=$REFTEXT" --text "text=Gaea Lab speaks through AuK, in a voice it has just heard." --param seed=42
check "AuK-Flash: dereverb" lab auk-dereverb --operation audio.edit_speech --model auk-flash --accept $QWEN --file audio=$REF \
  --param 'edit={"kind":"dereverb"}' --param seed=6
check "AuK-Flash: a hum at the start, with the transcript" lab auk-hum --operation audio.edit_speech --model auk-flash --accept $QWEN \
  --file audio=$REF --text "transcript=$REFTEXT" --param 'edit={"kind":"add_cue","cue":"hum","at":"start"}' --param seed=4
check "the hum's transcript output starts with the cue" zsh -c "grep -rq '\[hum\] The morning' $OUT/auk-hum/"
check "AuK-Flash: separate the second speaker" lab auk-separate --operation audio.separate --model auk-flash --accept $QWEN \
  --file audio=$MIX --param 'stems=["speaker"]' --param 'speaker={"ordinal":2}' --param seed=5
check "AuK Base: separate every voice" lab auk-voices --operation audio.separate --model auk --accept $QWEN \
  --file audio=$MIX --param 'stems=["voices"]' --param seed=9
check "each stem is one WAV at the mixture's length" py "
import glob, wave
m = wave.open('$MIX'); mix = m.getnframes() / m.getframerate()
for d in ['auk-separate', 'auk-voices']:
    [f] = glob.glob('$OUT/%s/*.wav' % d); w = wave.open(f)
    assert w.getnframes() == round(mix * w.getframerate()), (d, w.getnframes(), mix)"
check "an unnamed separate goes to the demo's separator" lab separate-unnamed --operation audio.separate --file audio=$MIX
check "the unnamed separate ran on demo-separator, two stems" zsh -c "[[ \$(python3 -c \"import json; print(json.load(open('$OUT/separate-unnamed.json'))['provenance']['model']['id'])\") == demo-separator ]] && (( \$(ls $OUT/separate-unnamed/*.wav | wc -l) == 2 ))"
for n in indextts-fit voxcpm2-speak voxcpm2-design auk-clone auk-dereverb auk-hum auk-separate auk-voices separate-unnamed; do
  say "      $n: $(model $n 2>/dev/null) · $(wavs $n | sed "s#$OUT/##" | tr '\n' ' ')"
done
stop

# 2. The app.
start
for op in audio.edit_speech audio.separate; do
  input=$REF; [[ $op == audio.separate ]] && input=$MIX
  "$LAB" --snapshot "$OUT/app" --engine $E --operation $op --input $input > "$OUT/app-$op.out" 2>&1
  sed 's/^/      /' "$OUT/app-$op.out" | tee -a "$LOG"
  check "the Lab app showed AuK's terms for $op, then ran it on Every server and rendered it" zsh -c "grep -q 'needs acceptance: $QWEN' $OUT/app-$op.out && grep -q 'run: finished' $OUT/app-$op.out && ls $OUT/app/lab-$op-after-light.png $OUT/app/lab-$op-after-dark.png"
done
check "the app's separation saved the speaker stem" zsh -c "grep -q 'results: speaker (audio)' $OUT/app-audio.separate.out"
stop
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
