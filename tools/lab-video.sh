#!/bin/zsh
# AB-T-0406's Lab run: Gaea Lab on video, against a fresh Gaea with the three video plugins installed from GitHub
# (LTX 2.5, SeedVR2, RIFE), on pixel-agency-run 0.3.0 and media-engine-spec 0.9.0.
#
#   1. lab-run runs each Video 0.1 operation the way the Lab does (RunSession over EnginePool), each clip the next one's
#      input, and checks what came back (size, frames, rate, sound, the AI-generated comment):
#      - generate on LTX compact24 without accepting its terms: refused, and lab-run says which --accept to give;
#      - generate from a first frame with the terms accepted (policy.accepted): 256×256, 25 frames, duration_snapped;
#      - generate at quality standard with a first frame and a keyframe at a time: standard64;
#      - extend the standard64 clip on compact24: its comment names both models (Video §1.9);
#      - extend that first clip by 1/3 s, retake 0.4–0.7 s of the extension (span_snapped), upscale the retake ×2
#        (SeedVR2) and interpolate the upscale ×2 (RIFE);
#   2. the Lab app shows LTX's terms before a generate, accepts them for that run only, and plays the result (--snapshot).
#
#   tools/lab-video.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; the Lab built (cd Apps/GaeaLab && swift build -c release); ffprobe; LTX 2.5's, SeedVR2's and
# RIFE's weights in Gaea's default models root (LTX's are links to DEV_VOL1).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
BIN=$(cd Apps/GaeaLab && swift build -c release --show-bin-path)
LR=$BIN/lab-run; LAB=$BIN/GaeaLabApp
F=../gaea-plugin-ltx/Tests/Fixtures
SPDX=LicenseRef-LTX-2-Community
PROMPT="A red kite flies over a green hill on a sunny day, the camera slowly following it."
rm -rf "$OUT" "$WORK"; mkdir -p "$OUT" "$WORK"
LOG="$OUT/lab-video.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
py() { python3 -c "$1" }
# Stops the server and waits for it to exit, so every worker's session is closed before it is copied.
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || return; sleep 0.2; done }
start() { GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise >> "$WORK/gaea.out" 2>&1 &; for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start" }
# The one clip lab-run saved for a step.
clip() { ls "$OUT/$1"/*.mp4 2>/dev/null | head -1 }
# Checks a saved clip: width, height, frames, the rate (frames/s), sound (1 or 0), and a pattern its comment matches.
facts() { py "
import json, re, subprocess
f = '$(clip $1)'
p = json.loads(subprocess.run(['ffprobe', '-v', 'error', '-count_frames', '-show_streams', '-show_format', '-of', 'json', f], capture_output=True, text=True).stdout)
v = next(s for s in p['streams'] if s['codec_type'] == 'video'); a = [s for s in p['streams'] if s['codec_type'] == 'audio']
n, d = map(int, v['r_frame_rate'].split('/')); c = p['format'].get('tags', {}).get('comment', '')
got = (v['width'], v['height'], int(v['nb_read_frames']), n / d, len(a) > 0)
print('$1:', got, repr(c))
assert got == ($2, $3, $4, $5, bool($6)), got
assert re.search(r'''$7''', c), c"
}

say "# Gaea Lab on video (AB-T-0406) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), $(py "import json; p = {x['identity']: x['state'].get('version') for x in json.load(open('Apps/GaeaLab/Package.resolved'))['pins']}; print('pixel-agency-run', p['pixel-agency-run'] + ', media-engine-spec', p['media-engine-spec'])")"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/home; P=17694
start
for repo in ltx seedvr2 rife; do
  check "add gaea-plugin-$repo by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-$repo | tee -a $OUT/plugins.txt | grep -q Installed"
done
# LTX's tiers are opt-in (accepted_required): the operator enables the two this run uses.
for t in compact24 standard64; do GAEA_HOME=$H $CLI models enable ltx-2.5-$t >> "$LOG" 2>&1; done
E=http://127.0.0.1:$P/mes/v0

# 1. The five operations, as the Lab runs them.
lab() { local name=$1; shift; "$LR" --engine $E --out "$OUT/$name" --report "$OUT/$name.json" "$@" > "$OUT/$name.out" 2>&1; local s=$?; sed 's/^/      /' "$OUT/$name.out"; return $s }
check "generate without accepting LTX's terms is refused" zsh -c "! $LR --engine $E --out $OUT/refused --operation video.generate --model ltx-2.5-compact24 \
  --text 'prompt=$PROMPT' --param duration_s=1 --param seed=7 > $OUT/refused.out 2>&1"
sed 's/^/      /' "$OUT/refused.out" | tee -a "$LOG"
check "lab-run says the terms need accepting, and which --accept to give" grep -q "needs acceptance: .* --accept $SPDX" "$OUT/refused.out"
check "generate from a first frame, terms accepted" lab generate --operation video.generate --model ltx-2.5-compact24 --accept $SPDX \
  --text "prompt=$PROMPT" --file first_frame=$F/kite-first.png --param 'size={"width":256,"height":256}' --param duration_s=1 --param seed=7
check "generate made 256×256, 25 frames at 24 fps with sound, disclosed" facts generate 256 256 25 24 1 '^AI-generated by LTX 2\.5 \(compact24\)$'
check "generate reported duration_snapped and its licence" zsh -c "grep -q 'warning duration_snapped' $OUT/generate.out && grep -q 'model ltx-2.5-compact24 · $SPDX' $OUT/generate.out"
check "generate at standard with a first frame and a keyframe" lab keyframe --operation video.generate --param quality=standard --accept $SPDX \
  --text "prompt=$PROMPT" --file first_frame=$F/kite-first.png --file keyframes=$F/kite-last.png --param 'keyframe_times=[0.5]' \
  --param 'size={"width":256,"height":256}' --param duration_s=1 --param seed=7
check "the keyframe routed to standard64" zsh -c "grep -q 'model ltx-2.5-standard64' $OUT/keyframe.out && grep -q 'video 256×256' $OUT/keyframe.out"
check "extend the generated clip by 1/3 s" lab extend --operation video.extend --model ltx-2.5-compact24 --accept $SPDX \
  --text "prompt=The kite climbs higher into the clouds." --file video=$(clip generate) --param after_s=0.3333 --param seed=7
check "extend made 33 frames, the source's comment kept (the same model made it)" facts extend 256 256 33 24 1 '^AI-generated by LTX 2\.5 \(compact24\)$'
check "extend standard64's clip on compact24" lab extend-other --operation video.extend --model ltx-2.5-compact24 --accept $SPDX \
  --text "prompt=The kite climbs higher into the clouds." --file video=$(clip keyframe) --param after_s=0.3333 --param seed=7
check "its comment names both models (Video §1.9)" facts extend-other 256 256 33 24 1 '^AI-generated by LTX 2\.5 \(standard64\) — AI-generated in part by LTX 2\.5 \(compact24\)$'
check "retake 0.4–0.7 s of the extension" lab retake --operation video.retake --model ltx-2.5-compact24 --accept $SPDX \
  --text "prompt=The kite dips low over the grass." --file video=$(clip extend) --param start_s=0.4 --param end_s=0.7 --param seed=7
check "retake reported span_snapped" zsh -c "grep -q 'warning span_snapped' $OUT/retake.out"
check "retake's clip" facts retake 256 256 33 24 1 '^AI-generated by LTX 2\.5 \(compact24\)$'
check "upscale the retake ×2 on SeedVR2" lab upscale --operation video.upscale --file video=$(clip retake) --param scale=2 --param content=live_action
check "upscale made 512×512, the same 33 frames, sound and comment kept" facts upscale 512 512 33 24 1 '^AI-generated by LTX 2\.5 \(compact24\)$'
check "interpolate the upscale ×2 on RIFE" lab interpolate --operation video.interpolate --file video=$(clip upscale) --param factor=2
check "interpolate made 65 frames at exactly 48 fps, sound and comment kept" facts interpolate 512 512 65 48 1 '^AI-generated by LTX 2\.5 \(compact24\)$'
for n in generate keyframe extend-other extend retake upscale interpolate; do
  say "      $n: $(py "import json; r = json.load(open('$OUT/$n.json')); p = r.get('provenance') or {}; print(r.get('engine'), '·', (p.get('model') or {}).get('id'))" 2>/dev/null)"
done
stop

# 2. The app.
start
"$LAB" --snapshot "$OUT/app" --engine $E --operation video.generate > "$OUT/app-video.generate.out" 2>&1
sed 's/^/      /' "$OUT/app-video.generate.out" | tee -a "$LOG"
check "the Lab app showed LTX's terms before the run" zsh -c "grep -q 'needs acceptance: $SPDX' $OUT/app-video.generate.out && ls $OUT/app/lab-video.generate-before-light.png"
check "the Lab app ran video.generate on Every server and rendered the clip" zsh -c "grep -q 'run: finished' $OUT/app-video.generate.out && grep -q 'video (video 256×256' $OUT/app-video.generate.out && ls $OUT/app/lab-video.generate-after-light.png $OUT/app/lab-video.generate-after-dark.png"
check "the snapshot's acceptance stayed in that run (nothing in the user's defaults)" zsh -c "! defaults read GaeaLabApp MESFormsUI.acceptedLicenses 2>/dev/null | grep -q $SPDX"
stop
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
