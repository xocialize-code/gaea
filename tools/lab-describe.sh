#!/bin/zsh
# AB-T-0473's Lab run: Gaea Lab on media-engine-spec 0.14.0 separating by description (MES 0.13, RFC 0008) against a
# fresh Gaea with SAM-Audio and the demo from GitHub, sam-audio-base enabled.
#
#   1. lab-run, the way the Lab runs it (RunSession over EnginePool): refused without users' acceptance, naming the
#      licence; with --accept, "speech" gives a target and a residual; with spans it runs too.
#   2. The Lab app renders the form with the description and runs it, the terms shown and then accepted for the run,
#      before and after, light and dark (--snapshot … --describe).
#   3. Every recorded GPP session passes the validator.
#
#   tools/lab-describe.sh <short-work-dir> <evidence-dir>
#
# Needs: APP (default dist/Gaea.app, 1.6.0 or later); the Lab built (cd Apps/GaeaLab && swift build -c release); the
# fixture in ../gaea-plugin-sam-audio/scripts/fixtures; the weights in MODELS (default MLXEngine's store).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
MODELS=${MODELS:-$HOME/Library/Application Support/MLXEngine/Models}
BIN=$(cd Apps/GaeaLab && swift build -c release --show-bin-path)
LR=$BIN/lab-run; LAB=$BIN/GaeaLabApp
MIX=../gaea-plugin-sam-audio/scripts/fixtures/mixture.wav
SAM=sam-audio-base; SPDX=LicenseRef-SAM
mkdir -p "$OUT"; rm -rf "$WORK" "$OUT/sessions" "$OUT/app"; mkdir -p "$WORK"
LOG="$OUT/lab-describe.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
say "# Gaea Lab, separation by description $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), Lab on media-engine-spec $(python3 -c "
import json; print([p['state']['version'] for p in json.load(open('Apps/GaeaLab/Package.resolved'))['pins'] if p['identity'] == 'media-engine-spec'][0])")"
unset GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/home; P=17696; E=http://127.0.0.1:$P/mes/v0
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" > "$H.out" 2>&1 &
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
export GAEA_HOME=$H
for repo in gaea-plugin-demo gaea-plugin-sam-audio; do $CLI plugins add https://github.com/xocialize-code/$repo | tail -1 | tee -a "$LOG"; done
$CLI models enable $SAM | tee -a "$LOG"

# 1. lab-run.
lab() { local name=$1; shift; "$LR" --engine $E --operation audio.separate --model $SAM --file audio=$MIX --out "$OUT/$name" --report "$OUT/$name.json" "$@" > "$OUT/$name.out" 2>&1; local s=$?; sed 's/^/      /' "$OUT/$name.out" | tail -4 | cut -c1-240 | tee -a "$LOG"; return $s }
lab refused --param describe=speech --param seed=5
check "without users' acceptance lab-run doesn't run it and names the licence to accept" zsh -c "! ls $OUT/refused/*.wav > /dev/null 2>&1 && grep -q '$SPDX' $OUT/refused.out"
lab speech --param describe=speech --param seed=5 --accept $SPDX
check "with --accept, \"speech\" ran on $SAM and saved its two stems" zsh -c "[[ \$(python3 -c \"import json; print(json.load(open('$OUT/speech.json'))['provenance']['model']['id'])\") == $SAM ]] && (( \$(ls $OUT/speech/*.wav | wc -l) == 2 ))"
lab spans --param describe=music --param 'spans=[{"start_s":0.0,"end_s":0.5,"present":true},{"start_s":5.5,"end_s":8.0,"present":true}]' --param seed=9 --accept $SPDX
check "with two spans it runs too, two stems" zsh -c "(( \$(ls $OUT/spans/*.wav | wc -l) == 2 ))"

# 2. The app.
"$LAB" --snapshot "$OUT/app" --engine $E --operation audio.separate --input $MIX --describe speech > "$OUT/app.out" 2>&1
sed 's/^/      /' "$OUT/app.out" | tee -a "$LOG"
check "the Lab app showed SAM-Audio's terms, then ran the described separation and rendered it" zsh -c "grep -q 'needs acceptance: $SPDX' $OUT/app.out && grep -q 'run: finished' $OUT/app.out && ls $OUT/app/lab-audio.separate-after-light.png $OUT/app/lab-audio.separate-after-dark.png"
check "the app's separation saved the target and the residual" zsh -c "grep -q 'results: target (audio), residual (audio)' $OUT/app.out"

pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || break; sleep 0.2; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
