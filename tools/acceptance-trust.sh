#!/bin/zsh
# AB-T-0411's acceptance (G4 order 3, PLG-3, UI-3, G-7, G-25): the trust list, with Gaea's own team treated as unknown
# (GAEA_UNTRUST_OWN_TEAM=1, an injected trust set), against the demo and Z-Image plugins' releases on GitHub.
#
#   tools/acceptance-trust.sh            (APP=dist/Gaea.app by default)
#
#   1. nothing trusted: adding the demo holds it, with the certificate's name, team, notarization, repo and models,
#      and installs and offers nothing; declining drops the download;
#   2. held again (0.3.0 by version) and approved: the team joins the list, the demo installs, and a job runs; Z-Image
#      from the same team then installs without asking;
#   3. the team removed: both plugins stop and leave the offers, a job is refused, and they stay installed, through a
#      restart; an update while the team is untrusted (demo 0.3.1) is held too;
#   4. that update approved: the team is trusted again, the demo switches to 0.3.1 and runs, and Z-Image is offered
#      again; the console's Plugins page and its trusted teams are rendered;
#   5. without the injected set, Gaea's own team is built in: the demo installs at once, and the team can't be removed.
set -uo pipefail
cd ${0:A:h:h}
APP=${APP:-dist/Gaea.app}
GAEA=$APP/Contents/MacOS/Gaea; CLI=$APP/Contents/Helpers/gaea
OUT=${OUT:-Docs/Evidence/AB-T-0411}; mkdir -p "$OUT"
LOG=$OUT/acceptance.log; : > "$LOG"
WORK=$(mktemp -d /tmp/gaea-trust.XXXX)
H=$WORK/h; P=17771
DEMO=https://github.com/xocialize-code/gaea-plugin-demo; ZREPO=https://github.com/xocialize-code/gaea-plugin-z-image
D=com.xocialize.gaea.demo; Z=com.xocialize.gaea.z-image; TEAM=CFZS6RXUCP
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
removed_and_back() {
  GAEA_HOME=$H $CLI trust remove $TEAM >> "$LOG" && not_offered demo-gradient &&
    GAEA_HOME=$H $CLI trust approve $TEAM | tee -a "$LOG" | grep -q "Trusted $TEAM. Its plugins run again: $D, $Z." && offered demo-gradient
}
cleanup() { pkill -TERM -f "^$GAEA" 2>/dev/null; true }
trap cleanup EXIT

say "# Trust-list acceptance (AB-T-0411) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), plugins from GitHub"
say "host: $(sysctl -n hw.model), macOS $(sw_vers -productVersion); GAEA_HOME $H"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API

# ---- 1. nothing trusted ----
export GAEA_UNTRUST_OWN_TEAM=1
start $H $P
check "status says no team is trusted" zsh -c "GAEA_HOME=$H $CLI status | tee -a $LOG | grep -q '^Trust:     no team'"
gaea trust > /dev/null
gaea plugins add $DEMO > "$WORK/held1.txt"
check "adding the demo holds it instead of installing" grep -q "^Held h-.*Gaea demo worker 0.3.1 ($D) is signed by a team Gaea doesn't trust yet" "$WORK/held1.txt"
check "the hold names the certificate, team, notarization, repo and models" zsh -c "
  grep -q 'Signed by:  Developer ID Application: Dustin Nielson ($TEAM)' $WORK/held1.txt && grep -q 'Team:       $TEAM' $WORK/held1.txt &&
  grep -q 'Notarized:  yes' $WORK/held1.txt && grep -q 'Repo:       $DEMO (v0.3.1)' $WORK/held1.txt && grep -q 'Models:     .*demo-gradient' $WORK/held1.txt"
H1=$(held_id)
check "nothing is installed" zsh -c "GAEA_HOME=$H $CLI plugins | grep -q '^No plugins'"
check "nothing is offered" not_offered demo-gradient demo-matmul
check "a job for its model is refused" refused
check "the held bundle is kept aside in Held/$H1" test -d "$H/Held/$H1"
gaea trust decline $H1
check "declining drops the download" zsh -c "[[ -z \$(ls $H/Held) ]] && GAEA_HOME=$H $CLI trust | grep -q '^Held: none'"
check "the events record the hold and the decline" zsh -c "GAEA_HOME=$H $CLI plugins logs $D | tee -a $LOG | grep -q ' held 0.3.1: v0.3.1' && GAEA_HOME=$H $CLI plugins logs $D | grep -q ' declined 0.3.1: '"
check "an unknown hold can't be approved" zsh -c "! GAEA_HOME=$H $CLI trust approve h-00000000"

# ---- 2. approved ----
gaea plugins add $DEMO 0.3.0 > "$WORK/held2.txt"
H2=$(held_id)
check "0.3.0, named, is held as $H2" grep -q "^Held $H2: Gaea demo worker 0.3.0" "$WORK/held2.txt"
check "trust lists it" zsh -c "GAEA_HOME=$H $CLI trust | tee -a $LOG | grep -q 'Held $H2: Gaea demo worker 0.3.0'"
check "approving it trusts the team and installs the demo" zsh -c "GAEA_HOME=$H $CLI trust approve $H2 | tee -a $LOG | grep -q 'Trusted its team. Installed Gaea demo worker 0.3.0 ($D), enabled.'"
check "the team is on the list, approved by the operator" zsh -c "GAEA_HOME=$H $CLI trust | tee -a $LOG | grep -q '^  $TEAM  Dustin Nielson, approved .*plugins: $D'"
check "demo-gradient is offered" offered demo-gradient
job $P "$GRADIENT" > "$WORK/job1.json"
check "a job runs on demo 0.3.0" succeeded "$WORK/job1.json"
cp "$WORK/job1.json" "$OUT/job-approved.json"
check "Z-Image from the same team installs without asking" zsh -c "GAEA_HOME=$H $CLI plugins add $ZREPO | tee -a $LOG | grep -q '^Installed Z-Image .* ($Z), enabled.'"
check "z-image-turbo is offered" offered z-image-turbo

# ---- 3. the team removed ----
check "a worker is running before" zsh -c "GAEA_HOME=$H $CLI ledger | tee -a $LOG | grep -q '$D 0.3.0 pid'"
check "removing the team stops both plugins and keeps them" zsh -c "GAEA_HOME=$H $CLI trust remove $TEAM | tee -a $LOG | grep -q 'Stopped, and kept installed until it.s trusted again: $D, $Z'"
check "no worker runs" zsh -c "! GAEA_HOME=$H $CLI ledger | tee -a $LOG | grep -q ' pid '"
check "neither is offered" not_offered demo-gradient z-image-turbo
check "a job for demo-gradient is refused" refused
check "both stay installed, marked stopped" zsh -c "GAEA_HOME=$H $CLI plugins | tee -a $LOG | grep -c \"stopped: its team $TEAM isn't trusted\" | grep -q 2 && [[ -d $H/Plugins/$D/0.3.0 && -d $H/Plugins/$Z ]]"
check "trust lists them as not trusted" zsh -c "GAEA_HOME=$H $CLI trust | tee -a $LOG | grep -q '^  $TEAM  plugins: $D, $Z  (gaea trust approve $TEAM)'"
check "the events record the removal" zsh -c "GAEA_HOME=$H $CLI plugins logs $D | grep -q ' untrusted: its team $TEAM was removed'"
stop $P
GAEA_HOME=$H "$GAEA" --snapshot "$WORK/snap-removed" >> "$H.out" 2>&1
cp "$WORK/snap-removed/console-plugins-light.png" "$OUT/console-plugins-untrusted-light.png" 2>/dev/null
cp "$WORK/snap-removed/console-plugins-dark.png" "$OUT/console-plugins-untrusted-dark.png" 2>/dev/null
start $H $P
check "after a restart, still not offered" not_offered demo-gradient z-image-turbo
check "after a restart, still marked stopped" zsh -c "GAEA_HOME=$H $CLI plugins | grep -q \"stopped: its team $TEAM\""
gaea plugins update $D > "$WORK/held3.txt"
H3=$(held_id)
check "an update (0.3.1) while the team is untrusted is held too" grep -q "^Held $H3: Gaea demo worker 0.3.1" "$WORK/held3.txt"

# ---- 4. trusted again ----
check "approving the update trusts the team again and switches the demo" zsh -c "GAEA_HOME=$H $CLI trust approve $H3 | tee -a $LOG | grep -q 'Trusted its team. $D now runs 0.3.1.'"
check "the demo is offered again" offered demo-gradient
check "Z-Image is offered again" offered z-image-turbo
job $P "$GRADIENT" > "$WORK/job2.json"
check "a job runs on demo 0.3.1" zsh -c "python3 -c \"import json; j = json.load(open('$WORK/job2.json')); assert j['outcome'] == 'succeeded' and j['result']['effective']['model_params']['x-gaea.worker']['version'] == '0.3.1', j\""
cp "$WORK/job2.json" "$OUT/job-trusted-again.json"
check "0.3.0 is kept for rollback" zsh -c "GAEA_HOME=$H $CLI plugins | grep -q 'rollback: 0.3.0'"
check "removing a team that isn't trusted is refused" zsh -c "! GAEA_HOME=$H $CLI trust remove ABCDE12345"
check "approving a team with nothing installed or held is refused" zsh -c "! GAEA_HOME=$H $CLI trust approve ABCDE12345"
gaea trust > /dev/null
check "trust remove, then approve by team id, runs them again" removed_and_back
stop $P
GAEA_HOME=$H "$GAEA" --snapshot "$WORK/snap-trusted" >> "$H.out" 2>&1
for f in console-plugins-light console-plugins-dark; do cp "$WORK/snap-trusted/$f.png" "$OUT/$f.png" 2>/dev/null; done
check "the console rendered the Plugins page, untrusted and trusted" test -s "$OUT/console-plugins-light.png" -a -s "$OUT/console-plugins-untrusted-light.png"
sqlite3 -readonly "$H/gaea.sqlite" "SELECT at, plugin_id, version, kind, message FROM event ORDER BY id" > "$OUT/events.txt"
check "nothing is left held" zsh -c "[[ -z \$(ls $H/Held) ]]"

# ---- 5. without the injected trust set ----
unset GAEA_UNTRUST_OWN_TEAM
H=$WORK/plain; P=17772
start $H $P
check "Gaea's own team is built in" zsh -c "GAEA_HOME=$H $CLI trust | tee -a $LOG | grep -q '^  $TEAM  Gaea.s own team (built in)'"
check "the demo installs at once" zsh -c "GAEA_HOME=$H $CLI plugins add $DEMO | tee -a $LOG | grep -q '^Installed Gaea demo worker 0.3.1'"
check "the built-in team can't be removed" zsh -c "GAEA_HOME=$H $CLI trust remove $TEAM 2>&1 | tee -a $LOG | grep -q 'is Gaea.s own team, trusted always'"
stop $P

cp "$WORK/h/gaea.log" "$OUT/gaea.log" 2>/dev/null || cp "$WORK/h/Logs/gaea.log" "$OUT/gaea.log" 2>/dev/null
say ""
say "$pass passed, $fail failed"
exit $(( fail > 0 ))
