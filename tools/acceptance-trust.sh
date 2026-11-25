#!/bin/zsh
# The plugin trust rule's acceptance (G-32, which loosens G-7 and AB-T-0411's trust list): a plugin runs when it is
# signed with a Developer ID and notarized by Apple, whoever its team is; the trust list is for builds that aren't
# notarized. Gaea's own team is treated as unknown (GAEA_UNTRUST_OWN_TEAM=1) so our own plugins stand in for a
# stranger's: the demo's release on GitHub is the notarized build, and its local build (../gaea-plugin-demo/dist,
# served by tools/release-standin.py) is the same plugin signed and not notarized.
#
#   tools/acceptance-trust.sh            (APP=dist/Gaea.app by default)
#
#   1. no team trusted, the notarized release from GitHub: it installs at once, nothing is held, a job runs, and it
#      still runs after a restart; approving and then removing its team stops nothing;
#   2. no team trusted, the build that isn't notarized: it is held, saying so, and installs and offers nothing;
#      declined, the download goes; held again and approved, the team joins the list and a job runs; the team removed,
#      the plugin stops and stays installed; trusted again, it runs;
#   3. without the injected set, Gaea's own team is built in: the build that isn't notarized installs at once.
#
# Not covered here: an update signed by another team than the plugin (it needs one plugin id signed by two teams).
# `PluginManager.holdReason` decides it and TrustTests covers the decision.
set -uo pipefail
cd ${0:A:h:h}
APP=${APP:-dist/Gaea.app}
GAEA=$APP/Contents/MacOS/Gaea; CLI=$APP/Contents/Helpers/gaea
OUT=${OUT:-Docs/Evidence/G-32}; mkdir -p "$OUT"
LOG=$OUT/acceptance.log; : > "$LOG"
WORK=$(mktemp -d /tmp/gaea-trust.XXXX)
H=$WORK/h; P=17771
DEMO=https://github.com/xocialize-code/gaea-plugin-demo
D=com.xocialize.gaea.demo; TEAM=CFZS6RXUCP
LOCAL=${LOCAL:-../gaea-plugin-demo/dist}
V=$(python3 -c "import json; print(json.load(open('$LOCAL/manifest.json'))['version'])")
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
py() { python3 -c "$1" }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
job() { # port, json body → prints the settled job, or the refusal
  local r id j
  r=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2")
  id=$(print -r -- "$r" | py 'import json,sys; print(json.load(sys.stdin).get("id", ""))')
  [[ -z $id ]] && { print -r -- "$r"; return }
  for _ in {1..12}; do
    j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | py 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' 2>/dev/null && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
start() { # home, port → waits for the operator socket
  GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise >> "$1.out" 2>&1 &
  for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done
  say "Gaea at $1 didn't start:"; cat "$1.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $1"; for _ in {1..30}; do pgrep -f "$GAEA --headless --port $1" >/dev/null || return 0; sleep 0.2; done }
gaea() { print -r -- "\$ gaea $*" >> "$LOG"; GAEA_HOME=$H $CLI "$@" 2>&1 | tee -a "$LOG" }
held_id() { GAEA_HOME=$H $CLI trust --json | py 'import json,sys; h = json.load(sys.stdin)["held"]; print(h[-1]["id"] if h else "")' }
offered() { # model → exit 0 if any operation offers it
  mes "http://127.0.0.1:$P/mes/v0/operations" | py "import json,sys; sys.exit(0 if any(m['id'] == '$1' for o in json.load(sys.stdin)['operations'] for m in o['models']) else 1)"
}
GRADIENT='{"operation":"image.generate","model":"demo-gradient","inputs":{"prompt":"a lighthouse at dusk"},"params":{"size":{"width":512,"height":384},"seed":11}}'
succeeded() { py "import json; j = json.load(open('$1')); assert j['outcome'] == 'succeeded', j; print(j['result']['effective']['model_params']['x-gaea.worker'])" }
refused() { job $P "$GRADIENT" | tee -a "$LOG" | grep -q '"error"' }
not_offered() { for m in "$@"; do offered $m && return 1; done; return 0 }
cleanup() { pkill -TERM -f "^$GAEA" 2>/dev/null; pkill -f "release-standin.py $WORK/standin" 2>/dev/null; true }
trap cleanup EXIT

say "# Plugin trust acceptance (G-32) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), demo $V"
say "host: $(sysctl -n hw.model), macOS $(sw_vers -productVersion); GAEA_HOME $H"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
export GAEA_UNTRUST_OWN_TEAM=1

# ---- 1. no team trusted: the notarized release from GitHub ----
start $H $P
check "status states the rule, and that no team is trusted" zsh -c "GAEA_HOME=$H $CLI status | tee -a $LOG | grep -q \"^Trust:     any notarized plugin; builds that aren't, from no team\""
gaea plugins add $DEMO $V > "$WORK/add1.txt"
check "the notarized demo installs at once, with no question" grep -q "^Installed Gaea demo worker $V ($D), enabled." "$WORK/add1.txt"
check "nothing is held and no team was added" zsh -c "GAEA_HOME=$H $CLI trust --json | python3 -c \"import json,sys; t = json.load(sys.stdin); assert t['held'] == [] and t['trusted'] == [], t\""
check "its install records the Developer ID and the notarization" zsh -c "sqlite3 -readonly $H/gaea.sqlite \"SELECT signature FROM plugin_version WHERE plugin_id = '$D'\" | tee -a $LOG | grep -q 'Developer ID Application: .* ($TEAM).*, notarized'"
check "demo-gradient is offered" offered demo-gradient
job $P "$GRADIENT" > "$WORK/job1.json"
check "a job runs on it" succeeded "$WORK/job1.json"
cp "$WORK/job1.json" "$OUT/job-notarized.json"
stop $P; start $H $P
job $P "$GRADIENT" > "$WORK/job1b.json"
check "after a restart it is offered and runs" zsh -c "offered() { curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/operations | grep -q demo-gradient }; offered && python3 -c \"import json; assert json.load(open('$WORK/job1b.json'))['outcome'] == 'succeeded'\""
check "its team can be approved from the installed plugin" zsh -c "GAEA_HOME=$H $CLI trust approve $TEAM | tee -a $LOG | grep -q 'Trusted $TEAM'"
check "removing the team stops nothing: the build is notarized" zsh -c "GAEA_HOME=$H $CLI trust remove $TEAM | tee -a $LOG | grep -q 'Nothing stopped: its notarized plugins run as before'"
job $P "$GRADIENT" > "$WORK/job1c.json"
check "a job still runs" succeeded "$WORK/job1c.json"
check "the plugin list marks nothing stopped" zsh -c "! GAEA_HOME=$H $CLI plugins | tee -a $LOG | grep -q 'stopped:'"
stop $P
sqlite3 -readonly "$H/gaea.sqlite" "SELECT at, plugin_id, version, kind, message FROM event ORDER BY id" > "$OUT/events-notarized.txt"

# ---- 2. no team trusted: the build that isn't notarized ----
mkdir -p "$WORK/standin/xocialize-code/gaea-plugin-demo/v$V"
cp "$LOCAL/demo-$V.gaeaplugin.zip" "$LOCAL/demo-$V.gaeaplugin.zip.sha256" "$LOCAL/manifest.json" "$WORK/standin/xocialize-code/gaea-plugin-demo/v$V/"
python3 tools/release-standin.py "$WORK/standin" --port 8773 > "$WORK/standin.out" 2>&1 &
for _ in {1..50}; do curl -s -o /dev/null http://127.0.0.1:8773/repos/xocialize-code/gaea-plugin-demo/releases && break; sleep 0.1; done
export GAEA_GITHUB_API=http://127.0.0.1:8773
H=$WORK/u; P=17772
start $H $P
gaea plugins add $DEMO > "$WORK/held1.txt"
check "the build that isn't notarized is held, and says why" grep -q "^Held h-.*Gaea demo worker $V ($D) isn't notarized by Apple, and its team isn't one Gaea trusts yet" "$WORK/held1.txt"
check "the hold names the certificate, team, notarization, repo and models" zsh -c "
  grep -q 'Signed by:  Developer ID Application: .* ($TEAM)' $WORK/held1.txt && grep -q 'Team:       $TEAM' $WORK/held1.txt &&
  grep -q 'Notarized:  no' $WORK/held1.txt && grep -q 'Repo:       $DEMO (v$V)' $WORK/held1.txt && grep -q 'Models:     .*demo-gradient' $WORK/held1.txt"
H1=$(held_id)
check "nothing is installed" zsh -c "GAEA_HOME=$H $CLI plugins | grep -q '^No plugins'"
check "nothing is offered, and a job for its model is refused" zsh -c "! curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/operations | grep -q demo-gradient"
check "the held bundle is kept aside in Held/$H1" test -d "$H/Held/$H1"
gaea trust decline $H1
check "declining drops the download" zsh -c "[[ -z \$(ls $H/Held) ]] && GAEA_HOME=$H $CLI trust | grep -q '^Held: none'"
gaea plugins add $DEMO > "$WORK/held2.txt"
H2=$(held_id)
check "approving it trusts the team and installs the demo" zsh -c "GAEA_HOME=$H $CLI trust approve $H2 | tee -a $LOG | grep -q 'Trusted its team. Installed Gaea demo worker $V ($D), enabled.'"
check "the team is on the list, approved by the operator" zsh -c "GAEA_HOME=$H $CLI trust | tee -a $LOG | grep -q '^  $TEAM  .*, approved .*plugins: $D'"
job $P "$GRADIENT" > "$WORK/job2.json"
check "a job runs on the build that isn't notarized" succeeded "$WORK/job2.json"
cp "$WORK/job2.json" "$OUT/job-approved.json"
check "removing the team stops the plugin and keeps it" zsh -c "GAEA_HOME=$H $CLI trust remove $TEAM | tee -a $LOG | grep -q 'Stopped, and kept installed until it.s trusted again: $D'"
check "it is no longer offered" zsh -c "! curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/operations | grep -q demo-gradient"
check "a job for it is refused" refused
check "it stays installed, marked stopped" zsh -c "GAEA_HOME=$H $CLI plugins | tee -a $LOG | grep -q \"stopped: this build isn't notarized and its team $TEAM isn't trusted\" && [[ -d $H/Plugins/$D/$V ]]"
check "trust lists it as not notarized and not trusted" zsh -c "GAEA_HOME=$H $CLI trust | tee -a $LOG | grep -q '^  $TEAM  plugins: $D  (gaea trust approve $TEAM)'"
stop $P; start $H $P
check "after a restart, still not offered" zsh -c "! curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/operations | grep -q demo-gradient"
check "trusted again by team id, it runs" zsh -c "GAEA_HOME=$H $CLI trust approve $TEAM | tee -a $LOG | grep -q 'Trusted $TEAM. Its plugins run again: $D.'"
job $P "$GRADIENT" > "$WORK/job3.json"
check "a job runs again" succeeded "$WORK/job3.json"
stop $P
sqlite3 -readonly "$H/gaea.sqlite" "SELECT at, plugin_id, version, kind, message FROM event ORDER BY id" > "$OUT/events-not-notarized.txt"

# ---- 3. without the injected trust set ----
unset GAEA_UNTRUST_OWN_TEAM
H=$WORK/plain; P=17773
start $H $P
check "Gaea's own team is built in" zsh -c "GAEA_HOME=$H $CLI trust | tee -a $LOG | grep -q '^  $TEAM  Gaea.s own team (built in)'"
check "our own build that isn't notarized installs at once" zsh -c "GAEA_HOME=$H $CLI plugins add $DEMO | tee -a $LOG | grep -q '^Installed Gaea demo worker $V'"
check "the built-in team can't be removed" zsh -c "GAEA_HOME=$H $CLI trust remove $TEAM 2>&1 | tee -a $LOG | grep -q 'is Gaea.s own team, trusted always'"
stop $P

cp "$WORK/u/Logs/gaea.log" "$OUT/gaea.log" 2>/dev/null
say ""
say "$pass passed, $fail failed"
exit $(( fail > 0 ))
