#!/bin/zsh
# AB-T-0405's acceptance: the governor on LTX 2.5's tiers at 32, 64 and 128 GB, staged with --budget-bytes on this Mac
# (the operator's call, 2026-10-31). Gaea's budget is three quarters of memory: 25.77, 51.54 and 103.08 GB.
#
#   For each budget, a Gaea with gaea-plugin-ltx from GitHub and all four tiers enabled:
#   1. the descriptors offer exactly the tiers whose lane fits the budget (Gaea 0.11.1), and `gaea models` says why the
#      others aren't offered; a request only those could serve is refused at submit;
#   2. each admitted tier runs at its envelope on a fresh worker, and the worker's lifetime peak phys_footprint
#      (ri_lifetime_max_phys_footprint, read by Gaea) stays under the budget; where it passes the lane's declared need,
#      Gaea has learned it (Gaea 0.11.2) and charges the lane at least that:
#        32 GB: compact24 at its measured pixel-frame ceiling, 704×512×49 and 512×288×121, and from a first frame
#               512×288×121 (704×512×121 is refused); an extend to 121 frames and a retake at 512×288; balanced32
#               576×320×161;
#        64 GB: standard64 1280×704×161, and 704×512 from a 5 s soundtrack;
#        128 GB: max128 1920×1088×121 (CORNER=1 adds 1920×1088×481, the tier's own corner).
#
#   tools/acceptance-tiers.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; ffmpeg; LTX 2.5's weights in MODELS_ROOT (default DEV_VOL1's models folder); network access to
# GitHub for the plugin.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
F=../gaea-plugin-ltx/Tests/Fixtures
MODELS=${MODELS_ROOT:-/Volumes/DEV_VOL1/Models/Models}
PROMPT="A red kite flies over a green hill on a sunny day, the camera slowly following it."
SPDX=LicenseRef-LTX-2-Community
PLUGIN=com.xocialize.gaea.ltx
TIERS=(compact24 balanced32 standard64 max128)
rm -rf "$OUT" "$WORK"; mkdir -p "$OUT" "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
post() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
settle() {
  local j
  for _ in {1..720}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$1?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
job() { local r id; r=$(post "$1"); id=$(print -r -- "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))'); [[ -n $id ]] && settle $id || print -r -- "$r" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: ${2:-video/mp4}" --data-binary @"$1" | python3 -c "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
py() { python3 -c "$1" }
# body <operation> <inputs JSON, without the prompt> <params JSON> [model]
body() {
  python3 -c "import json,sys; i=json.loads(sys.argv[2]); i['prompt']=sys.argv[5]; b={'operation':sys.argv[1],'inputs':i,'params':json.loads(sys.argv[3]),'policy':{'accepted':['$SPDX']}}
b.update({'model':sys.argv[4]} if sys.argv[4] else {}); print(json.dumps(b))" "$1" "$2" "$3" "${4:-}" "$PROMPT"
}
start() {
  local budget=(); [[ -n $BUDGET ]] && budget=(--budget-bytes $BUDGET)
  GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" $budget > "$H.out" 2>&1 &
  for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"
}
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || return; sleep 0.2; done }
offered() { mes "http://127.0.0.1:$P/mes/v0/operations" | py "import json,sys; print(' '.join(m['id'].split('-')[-1] for o in json.load(sys.stdin)['operations'] if o['operation'] == 'video.generate' for m in o['models']))" }
need() { py "import json; m={x['id']: x for x in json.load(open('$PLUGIN_MANIFEST'))['models']}['ltx-2.5-$1']; l=m['lanes'][0]['resolved']; print(l['persistentBytes'] + l['peakTransientBytes'])" }

# envelope <label> <tier> <operation> <inputs JSON> <params JSON> <want "w,h,frames">: on a fresh worker, so its lifetime
# peak is this job's.
envelope() {
  local label=$1 tier=$2 op=$3 inputs=$4 params=$5 want=$6
  $CLI plugins disable $PLUGIN > /dev/null; $CLI plugins enable $PLUGIN > /dev/null
  local t0=$(py 'import time; print(time.time())')
  job "$(body $op $inputs $params ltx-2.5-$tier)" > "$OUT/$PHASE-$label.json"
  local secs=$(py "import time; print(round(time.time()-$t0, 1))")
  $CLI ledger --json > "$OUT/$PHASE-$label.ledger.json"
  local peak=$(py "import json; w=[w for w in json.load(open('$OUT/$PHASE-$label.ledger.json'))['workers'] if w['pluginID']=='$PLUGIN']; print(w[0].get('peakFootprintBytes') or 0 if w else 0)")
  local declared=$(py "import json; w=[w for w in json.load(open('$OUT/$PHASE-$label.ledger.json'))['workers'] if w['pluginID']=='$PLUGIN']; print(w[0].get('declaredBytes') or 0 if w else 0)")
  local n=$(need $tier) budget=$(py "import json; print(json.load(open('$OUT/$PHASE-$label.ledger.json'))['budgetBytes'])")
  local got=$(py "import json; j=json.load(open('$OUT/$PHASE-$label.json')); o=(j.get('result') or {}).get('outputs') or [{}]; o=o[0]
print(f\"{o.get('width')},{o.get('height')},{o.get('frames')}\" if j.get('outcome')=='succeeded' else 'failed: ' + json.dumps(j.get('error')))")
  say "      $PHASE $label ($tier): $got in $secs s; peak $(py "print(round($peak/1e9, 2))") GB, lane need $(py "print(round($n/1e9, 2))") GB, now charged $(py "print(round($declared/1e9, 2))") GB, budget $(py "print(round($budget/1e9, 2))") GB"
  print -r -- "$PHASE $label $tier $got $secs $peak $n $declared $budget" >> "$OUT/peaks.txt"
  check "$PHASE: $label on $tier makes $want, its peak under the budget, and Gaea charging the lane at least what it held" \
    py "assert '$got' == '$want', '$got'; assert 0 < $peak <= $budget, ($peak, $budget); assert $peak <= $n or $declared >= $peak, ($peak, $n, $declared)"
}

say "# LTX tiers under the governor (AB-T-0405) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), models $MODELS"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
# The media: a 512×288 source on the 8k + 1 grid (105 frames, so an extend of 16 reaches compact24's 121), a 5 s
# soundtrack.
ffmpeg -v error -y -f lavfi -i "testsrc2=size=512x288:rate=24" -f lavfi -i "sine=frequency=330:sample_rate=48000" -frames:v 105 -t 4.375 \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -ac 2 -shortest $WORK/source.mp4
ffmpeg -v error -y -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=5" -ac 2 $WORK/tone.wav
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
P=17710

# phase <name> <budget bytes, or empty for the Mac's own> <tiers offered>
phase() {
  PHASE=$1; BUDGET=$2; local want=$3
  H=$WORK/$PHASE; start
  export GAEA_HOME=$H
  $CLI plugins add https://github.com/xocialize-code/gaea-plugin-ltx > /dev/null
  PLUGIN_MANIFEST=$(ls $H/Plugins/*/*/manifest.json $H/Plugins/*/manifest.json 2>/dev/null | head -1)
  [[ -f ${PLUGIN_MANIFEST:-} ]] || PLUGIN_MANIFEST=../gaea-plugin-ltx/dist/manifest.json
  for t in $TIERS; do $CLI models enable ltx-2.5-$t > /dev/null; done
  $CLI models > "$OUT/$PHASE-models.txt"; $CLI status > "$OUT/$PHASE-status.txt"
  local got=$(offered)
  say "      $PHASE: budget $(grep -o 'budget [0-9.]* GB' "$OUT/$PHASE-status.txt" | head -1 || true); generate offers: $got"
  check "$PHASE: generate offers exactly the tiers that fit ($want)" test "$got" = "$want"
  for t in $TIERS; do
    if [[ " $want " != *" $t "* ]]; then
      check "$PHASE: gaea models says ltx-2.5-$t isn't offered, no lane fitting the budget" grep -q "ltx-2.5-$t .*not offered: no lane fits" "$OUT/$PHASE-models.txt"
    fi
  done
}

# 32 GB.
phase 32GB 25769803776 "compact24 balanced32"
refuse "$(body video.generate '{}' '{"size":{"width":256,"height":256},"quality":"best"}')" "$WORK/r-32-best.json"
check "32GB: quality best, which only the larger tiers give, is refused at submit (4xx)" zsh -c "grep -q '^4' $WORK/r-32-best.json.status"
refuse "$(body video.generate '{"last_frame":{"upload":"'$(upload $F/kite-last.png image/png)'"}}' '{"size":{"width":256,"height":256}}')" "$WORK/r-32-last.json"
check "32GB: a last frame, which only the two-stage tiers take, is 422 at submit" zsh -c "grep -q '^422' $WORK/r-32-last.json.status"
job "$(body video.generate '{}' '{"size":{"width":704,"height":512},"duration_s":5.04,"fps":24}' ltx-2.5-compact24)" > "$WORK/r-32-ceiling.json"
check "32GB: 704×512×121 on compact24, past its measured 17.8 M pixel-frames, is out_of_limits on duration_s" \
  py "import json; e=json.load(open('$WORK/r-32-ceiling.json')).get('error') or {}; assert (e.get('code'), e.get('param')) == ('out_of_limits', 'duration_s'), e"
envelope t2v-wide compact24 video.generate '{}' '{"size":{"width":704,"height":512},"duration_s":2.04,"fps":24,"seed":7}' 704,512,49
envelope t2v-long compact24 video.generate '{}' '{"size":{"width":512,"height":288},"duration_s":5.04,"fps":24,"seed":7}' 512,288,121
envelope i2v compact24 video.generate '{"first_frame":{"upload":"'$(upload $F/kite-first.png image/png)'"}}' '{"size":{"width":512,"height":288},"duration_s":5.04,"fps":24,"seed":7}' 512,288,121
envelope extend compact24 video.extend '{"video":{"upload":"'$(upload $WORK/source.mp4)'"}}' '{"after_s":0.6667,"seed":7}' 512,288,121
envelope retake compact24 video.retake '{"video":{"upload":"'$(upload $WORK/source.mp4)'"}}' '{"start_s":1,"end_s":2,"seed":7}' 512,288,105
envelope t2v balanced32 video.generate '{}' '{"size":{"width":576,"height":320},"duration_s":6.7083,"fps":24,"seed":7}' 576,320,161
stop

# 64 GB.
phase 64GB 51539607552 "compact24 balanced32 standard64"
refuse "$(body video.generate '{}' '{"size":{"width":256,"height":256}}' ltx-2.5-max128)" "$WORK/r-64-max.json"
check "64GB: max128 by name, which no lane of fits, is refused at submit (4xx)" zsh -c "grep -q '^4' $WORK/r-64-max.json.status"
envelope t2v standard64 video.generate '{}' '{"size":{"width":1280,"height":704},"duration_s":6.7083,"fps":24,"seed":7}' 1280,704,161
envelope a2v standard64 video.generate '{"soundtrack":{"upload":"'$(upload $WORK/tone.wav audio/wav)'"}}' '{"size":{"width":704,"height":512},"fps":24,"seed":7}' 704,512,121
stop

# 128 GB, the Mac's own budget.
phase 128GB "" "compact24 balanced32 standard64 max128"
envelope t2v max128 video.generate '{}' '{"size":{"width":1920,"height":1088},"duration_s":5.04,"fps":24,"seed":7}' 1920,1088,121
if [[ -n ${CORNER:-} ]]; then
  envelope corner max128 video.generate '{}' '{"size":{"width":1920,"height":1088},"duration_s":20.04,"fps":24,"seed":7}' 1920,1088,481
fi
stop

for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status 2>/dev/null) $(py "import json; e=json.load(open('$f')).get('error') or {}; print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:140])")"; done
for s in $WORK/*/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $WORK/*/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
