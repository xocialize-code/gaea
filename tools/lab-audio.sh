#!/bin/zsh
# AB-T-0395's Lab run: Gaea Lab on audio, against a fresh Gaea with the five audio plugins installed from GitHub
# (Kokoro, Qwen3-TTS, Step-Audio-EditX, MOSS-SoundEffect, ACE-Step), on pixel-agency-run 0.2.0 and media-engine-spec 0.8.0.
#
#   1. lab-run runs each Audio 0.1 operation the way the Lab does (RunSession over EnginePool):
#      - speak on Kokoro, streamed: the chunks written as they arrive are the final file's samples, and the first chunk
#        comes before the job ends;
#      - speak on Qwen3-TTS with a voice, design_voice, edit_speech (with its transcript output), generate (two sounds)
#        and compose (with its timestamps output);
#   2. the pool's voices: Kokoro's and Qwen's lists through EnginePool, and a voice's sample;
#   3. the Lab app renders a streamed speak and a compose, before and after, light and dark (--snapshot).
#
#   tools/lab-audio.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; the Lab built (cd Apps/GaeaLab && swift build -c release).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
BIN=$(cd Apps/GaeaLab && swift build -c release --show-bin-path)
LR=$BIN/lab-run; LAB=$BIN/GaeaLabApp
TAKE=../gaea-plugin-step-audio-editx/Tests/Fixtures/take.wav
rm -rf "$OUT" "$WORK"; mkdir -p "$OUT" "$WORK"
LOG="$OUT/lab-audio.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
py() { python3 -c "$1" }
# Stops the server and waits for it to exit, so every worker's session is closed before it is copied.
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || return; sleep 0.2; done }

say "# Gaea Lab on audio (AB-T-0395) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), $(py "import json; p = {x['identity']: x['state'].get('version') for x in json.load(open('Apps/GaeaLab/Package.resolved'))['pins']}; print('pixel-agency-run', p['pixel-agency-run'] + ', media-engine-spec', p['media-engine-spec'])")"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/home; P=17693
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise > "$WORK/gaea.out" 2>&1 &
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
for repo in kokoro qwen3-tts step-audio-editx moss-soundeffect ace-step; do
  check "add gaea-plugin-$repo by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-$repo | tee -a $OUT/plugins.txt | grep -q Installed"
done
E=http://127.0.0.1:$P/mes/v0

# 1. The five operations, as the Lab runs them.
lab() { local name=$1; shift; "$LR" --engine $E --out "$OUT/$name" --report "$OUT/$name.json" "$@" > "$OUT/$name.out" 2>&1; local s=$?; sed 's/^/      /' "$OUT/$name.out" | tee -a "$LOG"; return $s }
check "speak on Kokoro, streamed" lab speak-stream --operation audio.speak --model kokoro-82m \
  --text "text=Gaea Lab speaks through Kokoro, streamed as it is made. Then the whole take is saved." --param voice=af_heart --param seed=1 --stream audio
check "the streamed chunks are the final file's samples" py "
import glob, wave
s = wave.open('$OUT/speak-stream/audio-stream.wav'); f = wave.open(sorted(glob.glob('$OUT/speak-stream/speak-*.wav'))[0])
a, b = s.readframes(s.getnframes()), f.readframes(f.getnframes())
assert (s.getframerate(), s.getnchannels()) == (f.getframerate(), f.getnchannels()) and a == b, (len(a), len(b))"
check "the first chunk came before the job ended" py "
import re; t = open('$OUT/speak-stream.out').read(); n = int(re.search(r'streamed (\d+) chunk', t).group(1)); ms = int(re.search(r'first chunk after (\d+) ms', t).group(1))
assert n >= 2 and ms > 0, (n, ms)"
check "speak on Qwen3-TTS with a voice and an emotion" lab speak-qwen --operation audio.speak --model qwen3-tts \
  --text "text=I told you three times already. Put it back where you found it." --param voice=ryan --param 'emotion={"label":"angry"}' --param seed=42
check "design_voice: two samples" lab design --operation audio.design_voice \
  --text "description=A warm, low voice of a woman in her forties, unhurried, with a slight rasp." --param count=2 --param seed=7 --param language=en
check "edit_speech: a laugh added, with the new transcript" lab edit --operation audio.edit_speech --file audio=$TAKE \
  --text "transcript=We don't have much time, so listen carefully to what I say." --param 'edit={"kind":"add_cue","cue":"laugh","at":"end"}' --param seed=42
check "edit_speech saved the transcript output" zsh -c "ls $OUT/edit/*.json >/dev/null && grep -q '\[laugh\]' $OUT/edit/*.json"
check "generate: two sounds of 1.5 s" lab generate --operation audio.generate --text "prompt=A dog barks twice in the distance." \
  --param duration_s=1.5 --param count=2 --param quality=draft --param seed=7
check "generate saved two WAVs of 72 000 frames" py "
import glob, wave; fs = sorted(glob.glob('$OUT/generate/*.wav')); assert len(fs) == 2 and all(wave.open(f).getnframes() == 72000 for f in fs), fs"
check "compose: a 10 s song with timestamps" lab compose --operation audio.compose --text "caption=Upbeat synth-pop with a bright female vocal and a driving beat." \
  --text $'lyrics=[verse]\nLights on the water\nWe follow the line\n[chorus]\nRun all night' --param duration_s=10 --param language=en --param timestamps=true --param seed=5
check "compose saved the song and its timed lines" py "
import glob, json, wave; w = [wave.open(f) for f in glob.glob('$OUT/compose/*.wav')]; t = glob.glob('$OUT/compose/*.json')
assert len(w) == 1 and w[0].getnframes() == 480000 and w[0].getnchannels() == 2 and t, (w, t)
assert 'water' in open(t[0]).read()"
for n in speak-stream speak-qwen design edit generate compose; do
  say "      $n: $(py "import json; r = json.load(open('$OUT/$n.json')); p = r.get('provenance') or {}; print(r.get('engine'), '·', (p.get('model') or {}).get('id'))" 2>/dev/null)"
done

# 2. The pool's voices.
check "the pool lists Kokoro's 28 voices" lab voices-kokoro --operation audio.speak --model kokoro-82m --voices
check "the pool lists Qwen3-TTS's 9 voices" lab voices-qwen --operation audio.speak --model qwen3-tts --voices
check "28 and 9 voices" zsh -c "grep -q '^28 voices' $OUT/voices-kokoro.out && grep -q '^9 voices' $OUT/voices-qwen.out"
check "a voice's sample came from the server that lists it, when it has one" zsh -c "! grep -q 'saved' $OUT/voices-kokoro.out || ls $OUT/voices-kokoro/*-sample.wav"
stop

# 3. The app.
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise >> "$WORK/gaea.out" 2>&1 &
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
for op in audio.speak audio.compose; do
  "$LAB" --snapshot "$OUT/app" --engine $E --operation $op > "$OUT/app-$op.out" 2>&1
  sed 's/^/      /' "$OUT/app-$op.out" | tee -a "$LOG"
  check "the Lab app ran $op on Every server and rendered it" zsh -c "grep -q 'run: finished' $OUT/app-$op.out && ls $OUT/app/lab-$op-after-light.png $OUT/app/lab-$op-after-dark.png"
done
check "the app's speak streamed" zsh -c "grep -q 'streamed [0-9][0-9]* chunks' $OUT/app-audio.speak.out"
stop
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
