#!/bin/zsh
# AB-T-0429's second team (G4 order 7, G-25): a plugin signed and notarized by a real second Developer ID team,
# MOUNTAIN VIEW STAGING SERVICES INC (F84FKGN358), from its GitHub release, in Gaea with only its own team trusted.
#
#   tools/acceptance-second-team.sh            (APP=dist/Gaea.app by default; GAEA_GITHUB_TOKEN: the repo is private)
#
#   1. adding it holds the release: the hold names the certificate, the team, notarization, the repo and the models, and
#      nothing is installed, offered or runnable;
#   2. approving it trusts F84FKGN358 beside Gaea's own team and installs the plugin; a job runs, on a worker whose
#      signature is that team's, launched under the launch requirement pinned to it;
#   3. our own team's demo installs without asking, and both run side by side;
#   4. removing F84FKGN358 stops its plugin only, kept installed; approving the team again runs it;
#   5. every recorded GPP session passes the validator.
set -uo pipefail
cd ${0:A:h:h}
APP=${APP:-dist/Gaea.app}
GAEA=$APP/Contents/MacOS/Gaea; CLI=$APP/Contents/Helpers/gaea
OUT=${OUT:-Docs/Evidence/AB-T-0429/second-team}; mkdir -p "$OUT"
LOG=$OUT/acceptance.log; : > "$LOG"
WORK=$(mktemp -d /tmp/gaea-team2.XXXX)
H=$WORK/h; P=17786
REPO=https://github.com/xocialize-code/gaea-plugin-team2-test; X=com.mountainviewstaging.gaea.team2-test; TEAM2=F84FKGN358
DEMO=https://github.com/xocialize-code/gaea-plugin-demo; D=com.xocialize.gaea.demo; OURS=CFZS6RXUCP
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
py() { python3 -c "$1" }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
job() { # json body → prints the settled job, or the refusal
  local r id j
  r=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1")
  id=$(print -r -- "$r" | py 'import json,sys; print(json.load(sys.stdin).get("id", ""))')
  [[ -z $id ]] && { print -r -- "$r"; return }
  for _ in {1..30}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | py 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' 2>/dev/null && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
start() {
  GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise >> "$H.out" 2>&1 &
  for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done
  say "Gaea didn't start:"; cat "$H.out" >> "$LOG"
}
held_id() { GAEA_HOME=$H $CLI trust --json | py 'import json,sys; h = json.load(sys.stdin)["held"]; print(h[-1]["id"] if h else "")' }
offered() { mes "http://127.0.0.1:$P/mes/v0/operations" | py "import json,sys; sys.exit(0 if any(m['id'] == '$1' for o in json.load(sys.stdin)['operations'] for m in o['models']) else 1)" }
GRADIENT='{"operation":"image.generate","model":"team2-gradient","inputs":{"prompt":"a second team"},"params":{"size":{"width":512,"height":384},"seed":11}}'
OURS_GRADIENT='{"operation":"image.generate","model":"demo-gradient","inputs":{"prompt":"our team"},"params":{"size":{"width":256,"height":256},"seed":12}}'
not_offered() { ! offered $1 }
refused() { job "$GRADIENT" | tee -a "$LOG" | grep -q '"error"' }
succeeded() { py "import json; j = json.load(open('$1')); assert j['outcome'] == 'succeeded', j" }
ran_on() { # file, plugin id → the job succeeded on that plugin's worker
  py "import json; j = json.load(open('$1')); assert j['outcome'] == 'succeeded', j; w = j['result']['effective']['model_params']['x-gaea.worker']; print(w); assert w['plugin'] == '$2', w"
}
worker_team() { # plugin id, team → the running worker's executable is signed by that team
  local pid=$(GAEA_HOME=$H $CLI ledger --json | py "import json,sys; print(next((w['pid'] for w in json.load(sys.stdin)['workers'] if w['pluginID'] == '$1'), ''))")
  [[ -n $pid ]] || { print "no worker for $1"; return 1 }
  local exe=$(ps -o comm= -p $pid)
  print "worker $pid: $exe"
  codesign -dvvv "$exe" 2>&1 | tee /dev/stderr | grep -q "^TeamIdentifier=$2"
}
cleanup() { pkill -TERM -f "^$GAEA --headless --port $P" 2>/dev/null; true }
trap cleanup EXIT

say "# Second team (AB-T-0429, G-25) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), $X from GitHub"
say "host: $(sysctl -n hw.model), macOS $(sw_vers -productVersion); GAEA_HOME $H"
unset GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API GAEA_UNTRUST_OWN_TEAM GAEA_DEMO_TRAP_SEED
export GAEA_GITHUB_TOKEN=${GAEA_GITHUB_TOKEN:-$(gh auth token)} # the repo is private
start
check "only Gaea's own team is trusted" zsh -c "GAEA_HOME=$H $CLI trust | tee -a $LOG | grep -q '^  $OURS  Gaea.s own team (built in)' && ! GAEA_HOME=$H $CLI trust | grep -q $TEAM2"

# 1. Held.
GAEA_HOME=$H $CLI plugins add $REPO > $WORK/held.txt 2>&1; cat $WORK/held.txt >> "$LOG"; cp $WORK/held.txt "$OUT/held.txt"
check "adding it holds the release instead of installing" grep -q "^Held h-.*Second-team test plugin 0.1.0 ($X) is signed by a team Gaea doesn't trust yet" $WORK/held.txt
check "the hold names the certificate, the team, notarization, the repo and the models" zsh -c "
  grep -q 'Signed by:  Developer ID Application: MOUNTAIN VIEW STAGING SERVICES INC ($TEAM2)' $WORK/held.txt &&
  grep -q 'Team:       $TEAM2' $WORK/held.txt && grep -q 'Notarized:  yes' $WORK/held.txt &&
  grep -q 'Repo:       $REPO (v0.1.0)' $WORK/held.txt && grep -q 'Models:     .*team2-gradient' $WORK/held.txt"
check "nothing is installed" zsh -c "GAEA_HOME=$H $CLI plugins | grep -q '^No plugins'"
check "nothing is offered" not_offered team2-gradient
check "a job for its model is refused" refused
HELD=$(held_id)

# 2. Approved, installed, run.
check "approving it trusts the team and installs the plugin" zsh -c "GAEA_HOME=$H $CLI trust approve $HELD | tee -a $LOG | grep -q 'Trusted its team. Installed Second-team test plugin 0.1.0 ($X), enabled.'"
GAEA_HOME=$H $CLI trust > "$OUT/trust-approved.txt" 2>&1
check "  the trust list has both teams" zsh -c "grep -q '^  $OURS  Gaea.s own team (built in)' $OUT/trust-approved.txt && grep -q '^  $TEAM2  MOUNTAIN VIEW STAGING SERVICES INC, approved .*plugins: $X' $OUT/trust-approved.txt"
check "  team2-gradient is offered" offered team2-gradient
job "$GRADIENT" > "$OUT/job-team2.json"
check "  a job runs on the second team's plugin" ran_on "$OUT/job-team2.json" $X
check "  its worker is signed by $TEAM2" worker_team $X $TEAM2

# 3. Our own team's plugin beside it.
check "our team's demo installs without asking" zsh -c "GAEA_HOME=$H $CLI plugins add $DEMO | tee -a $LOG | grep -q '^Installed Gaea demo worker'"
job "$OURS_GRADIENT" > "$OUT/job-ours.json"
check "  a job runs on it" ran_on "$OUT/job-ours.json" $D
check "  its worker is signed by $OURS" worker_team $D $OURS
check "  and the second team's worker is still signed by $TEAM2" worker_team $X $TEAM2
GAEA_HOME=$H $CLI plugins > "$OUT/plugins-both.txt" 2>&1

# 4. Removing the second team stops only its plugin.
check "removing $TEAM2 stops its plugin and keeps it" zsh -c "GAEA_HOME=$H $CLI trust remove $TEAM2 | tee -a $LOG | grep -q 'Stopped, and kept installed until it.s trusted again: $X'"
check "  it is marked stopped, still installed" zsh -c "GAEA_HOME=$H $CLI plugins | tee -a $LOG | grep -q \"stopped: its team $TEAM2 isn't trusted\" && [[ -d $H/Plugins/$X ]]"
check "  our demo still runs" zsh -c "GAEA_HOME=$H $CLI plugins | grep -q '^on  $D '"
check "approving $TEAM2 again runs it" zsh -c "GAEA_HOME=$H $CLI trust approve $TEAM2 | tee -a $LOG | grep -q 'Trusted $TEAM2. Its plugins run again: $X.'"
job "$GRADIENT" > "$OUT/job-team2-again.json"
check "  a job runs on it again" succeeded "$OUT/job-team2-again.json"

# 5. The sessions.
for s in $H/logs/sessions/*.gpp(N); do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
GAEA_HOME=$H $CLI plugins logs $X > "$OUT/events-team2.txt" 2>&1
say ""
say "$pass passed, $fail failed"
(( fail == 0 ))
