#!/bin/zsh
# AB-T-0373: one TierBench run against Gaea or against pixel-agency-image-engine, on the same corpus and Mac, the engine
# alone on the machine while it runs. tools/parity-compare.swift then pairs two runs.
#
#   tools/parity-run.sh gaea|engine <out-dir> [suites…]     (default suites: tiers upscale restore segment generate edits erase)
#
# Needs: TIERBENCH (a Release tier-bench), and for `engine` ENGINE_BIN (a Release pixel-agency-image-engine); for `gaea`
# dist/Gaea.app and GAEA_HOME with the G1 plugins installed. TIERBENCH_CORPUS and TIERBENCH_GATE as TierBench reads them.
# MODELS limits generate (by model id) and erase (by arm) to the models both engines serve.
set -uo pipefail
cd "${0:A:h}/.."
WHICH=${1:?gaea or engine}; OUT=${2:?out dir}; shift 2
SUITES=("$@"); (( $#SUITES )) || SUITES=(tiers upscale restore segment generate edits erase)
TIERBENCH=${TIERBENCH:?a Release tier-bench}
mkdir -p "$OUT"
case $WHICH in
  gaea)
    PORT=17761
    GAEA_HOME=${GAEA_HOME:?Gaea home with the G1 plugins} dist/Gaea.app/Contents/MacOS/Gaea --headless --port $PORT --no-advertise > "$OUT/server.log" 2>&1 &
    ;;
  engine)
    PORT=17611
    "${ENGINE_BIN:?a Release pixel-agency-image-engine}" --port $PORT --no-advertise > "$OUT/server.log" 2>&1 &
    ;;
  *) print "gaea or engine"; exit 2 ;;
esac
SERVER=$!
for _ in {1..100}; do curl -sf -H 'MES-Version: 0.1' "http://127.0.0.1:$PORT/mes/v0/operations" > "$OUT/operations.json" && break; sleep 0.3; done
print "# $WHICH on :$PORT, pid $SERVER, $(date -u +%FT%TZ), suites: $SUITES" | tee "$OUT/run.log"
print "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)" | tee -a "$OUT/run.log"
"$TIERBENCH" --engine "http://127.0.0.1:$PORT/mes/v0" --out "$OUT" ${MODELS:+--models} ${MODELS:-} $SUITES >> "$OUT/run.log" 2>&1
STATUS=$?
kill -TERM $SERVER 2>/dev/null; wait $SERVER 2>/dev/null
print "# tier-bench exited $STATUS" | tee -a "$OUT/run.log"
exit $STATUS
