#!/bin/zsh
# The MES conformance suite (media-engine-spec's mes-conformance engine, open mode) against a fresh Gaea with every G1
# plugin installed from its GitHub release, plus the plugins named on the command line. Used to show a new plugin
# leaves Base 0.1 and Image 0.1 conforming (AB-T-0387 onwards).
#
#   tools/conformance-with.sh <short-work-dir> <evidence-dir> [gaea-plugin-<name> ...]
#
# Needs: dist/Gaea.app; MES_CONFORMANCE (default ../media-engine-spec/.build/release/mes-conformance).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}; shift 2
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
CONFORMANCE=${MES_CONFORMANCE:-../media-engine-spec/.build/release/mes-conformance}
G1=(gaea-plugin-z-image gaea-plugin-flux2-klein gaea-plugin-qwen-image gaea-plugin-forge gaea-plugin-prompt-enhance gaea-plugin-mage-vl)
P=${PORT:-17690}
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
export GAEA_HOME=$WORK/home
"$GAEA" --headless --port $P --no-advertise > "$WORK/gaea.out" 2>&1 &
for _ in {1..50}; do [[ -S $GAEA_HOME/operator.sock ]] && break; sleep 0.2; done
for repo in $G1 "$@"; do
  "$CLI" plugins add "https://github.com/xocialize-code/$repo" | tee -a "$OUT/plugins.txt"
done
"$CLI" plugins > "$OUT/plugins-list.txt"
"$CLI" models > "$OUT/models.txt"
"$CONFORMANCE" engine "http://127.0.0.1:$P/mes/v0" --out "$OUT/conformance-open" > "$OUT/conformance-open.txt" 2>&1
result=$?
pkill -TERM -f "$GAEA --headless --port $P"
tail -3 "$OUT/conformance-open.txt"
exit $result
