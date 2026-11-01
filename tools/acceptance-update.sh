#!/bin/zsh
# AB-T-0410's acceptance (G4 order 2, DST-3, G-24): Gaea updates itself from its releases and back, headless and as the
# app, with a job queued during the update finishing.
#
#   FROM=dist/Gaea.app TO=0.12.1-rc.1 tools/acceptance-update.sh
#
# FROM is the app to start from (0.12.0 or later), copied into a scratch Applications folder so it can replace
# itself. TO is the release to update to, a pre-release (so the stable channel must skip it). The releases come from
# GitHub, or from tools/release-standin.py when STANDIN_ZIP names a local `scripts/release.sh` build of TO (its dist/
# with the zip, the .sha256 and release.json): then an old release with a wrong digest is refused too.
#
#   1. headless: up to date with pre-releases skipped; TO offered with them on; `gaea update` while a cold Z-Image job
#      runs waits for it; a second job queued during the wait finishes and its output is fetched; Gaea execs TO in
#      place (same pid, port and folder), keeps FROM, and runs Z-Image again; `gaea update --rollback` goes back;
#   2. the app: `gaea update <TO>` by version with pre-releases off, a job during it, the app relaunched as TO (a new
#      pid, not headless), and rolled back.
#
# Z-Image Turbo's weights come from the models root (MLXEngine's store by default).
set -uo pipefail
cd ${0:A:h:h}
FROM=${FROM:-dist/Gaea.app}; TO=${TO:?TO names the release to update to}
FROM_VERSION=$(defaults read "${FROM:A}/Contents/Info" CFBundleShortVersionString)
OUT=${OUT:-Docs/Evidence/AB-T-0410}; mkdir -p "$OUT"
LOG=$OUT/acceptance${STANDIN_ZIP:+-standin}.log; : > "$LOG"
WORK=$(mktemp -d /tmp/gaea-up.XXXX)
APPS=$WORK/Applications; mkdir -p "$APPS"; ditto "$FROM" "$APPS/Gaea.app"
GAEA=$APPS/Gaea.app/Contents/MacOS/Gaea; CLI=$APPS/Gaea.app/Contents/Helpers/gaea
H=$WORK/h; P=17761; P2=17762
export GAEA_HOME=$H
Z=com.xocialize.gaea.z-image
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
py() { python3 -c "$1" }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
submit() { mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | py 'import json,sys; print(json.load(sys.stdin)["id"])' }
settle() { # port, job id → prints the settled job
  local j
  for _ in {1..90}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$2?wait=10")
    print -r -- "$j" | py 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' 2>/dev/null && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
succeeded() { py "import json,sys; j = json.load(open('$1')); assert j['outcome'] == 'succeeded', j" }
fetched() { # port, job file, file → the first output, downloaded and a PNG
  local href=$(py "import json; print(json.load(open('$2'))['result']['outputs'][0]['href'])")
  mes -o "$3" "http://127.0.0.1:$1$href" && [[ $(head -c 4 "$3" | xxd -p) == 89504e47 ]]
}
version_is() { $CLI status | tee -a "$LOG" | grep -q "^Gaea $1\$" }
wait_version() { # version, seconds → waits until the operator socket answers as that version
  for _ in $(seq 1 $(( $2 * 2 ))); do version_is $1 >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1
}
engine_version() { mes "http://127.0.0.1:$1/mes/v0/engine" | py "import json,sys; print(json.load(sys.stdin)['implementation']['version'])" }
pid_of() { pgrep -f "^$GAEA" | head -1 }
TURBO() { print -r -- '{"operation":"image.generate","model":"z-image-turbo","inputs":{"prompt":"a lighthouse at dusk, '$1'"},"params":{"size":{"width":512,"height":512},"seed":'$2'}}' }

say "# Update acceptance (AB-T-0410) $(date -u +%FT%TZ): Gaea $FROM_VERSION → $TO, releases from ${STANDIN_ZIP:+the stand-in (}${STANDIN_ZIP:-GitHub}${STANDIN_ZIP:+)}"
say "host: $(sysctl -n hw.model), macOS $(sw_vers -productVersion); app copied to $APPS/Gaea.app"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ -n ${STANDIN_ZIP:-} ]]; then
  REL=$WORK/standin/xocialize-code/gaea/v$TO; mkdir -p "$REL"
  cp "$STANDIN_ZIP/Gaea-$TO.zip" "$STANDIN_ZIP/Gaea-$TO.zip.sha256" "$STANDIN_ZIP/release.json" "$REL/"; touch "$REL/prerelease"
  # An old release whose zip isn't the one its digest names (old, so only naming it installs it).
  BAD=$WORK/standin/xocialize-code/gaea/v0.0.9; mkdir -p "$BAD"
  cp "$STANDIN_ZIP/Gaea-$TO.zip" "$BAD/Gaea-0.0.9.zip"
  print "0000000000000000000000000000000000000000000000000000000000000000  Gaea-0.0.9.zip" > "$BAD/Gaea-0.0.9.zip.sha256"
  py "import json; f = json.load(open('$STANDIN_ZIP/release.json')); f.update(version='0.0.9', tag='v0.0.9', zip='Gaea-0.0.9.zip', sha256='0'*64); json.dump(f, open('$BAD/release.json', 'w'))"
  ZREL=$WORK/standin/xocialize-code/gaea-plugin-z-image/v0.1.0; mkdir -p "$ZREL"
  cp ../gaea-plugin-z-image/dist/z-image-0.1.0.gaeaplugin.zip ../gaea-plugin-z-image/dist/z-image-0.1.0.gaeaplugin.zip.sha256 ../gaea-plugin-z-image/dist/manifest.json "$ZREL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8771 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8771
fi
cleanup() { pkill -TERM -f "^$GAEA" 2>/dev/null; [[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null; true }
trap cleanup EXIT

# ---- 1. headless ----
"$GAEA" --headless --port $P --no-advertise --update-grace 10 > "$H.out" 2>&1 &
PID=$!
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
say "headless Gaea $FROM_VERSION pid $PID on $P"
check "Gaea --version names its protocols" sh -c "'$GAEA' --version | tee -a '$LOG' | grep -q '\"gpp\":\\[1\\]'"
$CLI plugins add https://github.com/xocialize-code/gaea-plugin-z-image >> "$LOG" 2>&1
check "pre-releases skipped: up to date" sh -c "'$CLI' update --check | tee -a '$LOG' | grep -q 'up to date'"
check "pre-releases on: $TO offered" sh -c "'$CLI' update --prereleases on | tee -a '$LOG' | grep -q '$TO (pre-release) is available'"
if [[ -n ${STANDIN_ZIP:-} ]]; then
  check "a wrong digest is refused" sh -c "'$CLI' update 0.0.9 2>&1 | tee -a '$LOG' | grep -q 'sha256 mismatch'"
  check "and nothing is staged" sh -c "! '$CLI' update --check | grep -q installing"
fi

J1=$(submit $P "$(TURBO cold 1)")
sleep 1
check "gaea update waits for the running job" sh -c "'$CLI' update | tee -a '$LOG' | grep -q 'once no job is running or waiting (now: 1 '"
J2=$(submit $P "$(TURBO queued 2)")
check "status says what it waits for" sh -c "'$CLI' update --check | tee -a '$LOG' | grep -q 'installing $TO once quiet'"
check "still $FROM_VERSION while jobs run" version_is $FROM_VERSION
settle $P $J1 > $WORK/j1.json; settle $P $J2 > $WORK/j2.json
check "the running job finished" succeeded $WORK/j1.json
check "the job queued during the update finished" succeeded $WORK/j2.json
check "its output was fetched (PNG)" fetched $P $WORK/j2.json $OUT/queued-during-update.png
T0=$(date +%s)
check "Gaea relaunched as $TO" wait_version $TO 90
say "  relaunched $(( $(date +%s) - T0 ))s after the jobs settled (10 s grace)"
check "in place: the same pid $PID" sh -c "ps -p $PID -o command= | tee -a '$LOG' | grep -q -- '--headless --port $P'"
check "the same port answers as $TO" sh -c "[ \"\$(curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/engine | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"implementation\"][\"version\"])')\" = $TO ]"
check "$FROM_VERSION is kept for rollback" sh -c "'$CLI' update --check | tee -a '$LOG' | grep -q 'Kept:      $FROM_VERSION'"
check "the plugin is still installed" sh -c "'$CLI' plugins | tee -a '$LOG' | grep -q '^on  $Z'"
settle $P $(submit $P "$(TURBO after 3)") > $WORK/j3.json
check "Z-Image runs on $TO" succeeded $WORK/j3.json
check "the app on disk is $TO, signed and notarized" sh -c "[ \$(defaults read '$APPS/Gaea.app/Contents/Info' CFBundleShortVersionString) = $TO ] && codesign --verify --strict --deep '$APPS/Gaea.app' && spctl --assess --type execute '$APPS/Gaea.app'"
check "gaea update --rollback goes back" sh -c "'$CLI' update --rollback | tee -a '$LOG' | grep -q 'Rolling back to Gaea $FROM_VERSION'"
check "Gaea relaunched as $FROM_VERSION" wait_version $FROM_VERSION 60
check "still pid $PID" sh -c "ps -p $PID >/dev/null"
check "$TO is kept in turn" sh -c "'$CLI' update --check | tee -a '$LOG' | grep -q 'Kept:      $TO'"
kill -TERM $PID; for _ in {1..40}; do kill -0 $PID 2>/dev/null || break; sleep 0.25; done
cp "$H.out" $WORK/headless.out

# ---- 2. the app ----
"$GAEA" --port $P2 --no-advertise --update-grace 10 > "$H.app.out" 2>&1 &
APID=$!
for _ in {1..80}; do [[ -S $H/operator.sock ]] && $CLI status >/dev/null 2>&1 && break; sleep 0.25; done
say "app Gaea $FROM_VERSION pid $APID on $P2"
$CLI update --prereleases off >> "$LOG" 2>&1
J4=$(submit $P2 "$(TURBO app 4)")
sleep 1
check "gaea update $TO by version, pre-releases off, waits for the job" sh -c "'$CLI' update $TO | tee -a '$LOG' | grep -q 'once no job is running or waiting'"
settle $P2 $J4 > $WORK/j4.json
check "the job during the app's update finished" succeeded $WORK/j4.json
check "its output was fetched" fetched $P2 $WORK/j4.json $OUT/app-during-update.png
check "the app relaunched as $TO" wait_version $TO 90
NPID=$(pid_of)
check "a new process ($APID → $NPID), the app, not headless" sh -c "[ -n '$NPID' ] && [ '$NPID' != '$APID' ] && ! ps -p '$NPID' -o command= | tee -a '$LOG' | grep -q -- --headless"
check "the app answers MES on $P2 as $TO" sh -c "[ \"\$(curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P2/mes/v0/engine | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"implementation\"][\"version\"])')\" = $TO ]"
check "the app rolls back" sh -c "'$CLI' update --rollback | tee -a '$LOG' | grep -q 'Rolling back to Gaea $FROM_VERSION'"
check "the app relaunched as $FROM_VERSION" wait_version $FROM_VERSION 60
FPID=$(pid_of)
say "app pids: $APID → $NPID → $FPID"
$CLI plugins logs $Z -n 0 >> "$LOG" 2>&1
grep -E "update:" "$H/Logs/gaea.log" >> "$LOG"
cp "$H/Logs/gaea.log" "$OUT/gaea${STANDIN_ZIP:+-standin}.log" 2>/dev/null

say "== $pass passed, $fail failed =="
[[ $fail == 0 ]]
