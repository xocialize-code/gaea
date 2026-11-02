#!/bin/zsh
# AB-T-0417's acceptance (G4 order 5, SRV-8, G-26): crash and requeue reporting, and quarantine, against the demo plugin's
# release on GitHub (0.3.2 or later, which traps on GAEA_DEMO_TRAP_SEED's seed).
#
#   tools/acceptance-crashes.sh            (APP=dist/Gaea.app by default)
#
#   1. a SIGKILL mid-job: the job is requeued and succeeds; the crash is recorded with the job, model, lane and signal,
#      and no crash report (SIGKILL writes none);
#   2. a trap in the plugin (seed 666): both tries crash with SIGTRAP and the job fails with both crashes named; each record
#      has the worker's `Fatal error:` line and macOS's crash report, copied into Crashes/ and summarised;
#   3. that third crash in ten minutes quarantines the demo: switched off, not offered, its jobs refused, marked in
#      `gaea plugins` and `gaea status`, and shown on the console's Plugins page;
#   4. the operator switches it on: the quarantine clears, a job runs, and a crash after that doesn't quarantine it again;
#   5. every recorded GPP session passes the validator.
set -uo pipefail
cd ${0:A:h:h}
APP=${APP:-dist/Gaea.app}
GAEA=$APP/Contents/MacOS/Gaea; CLI=$APP/Contents/Helpers/gaea
OUT=${OUT:-Docs/Evidence/AB-T-0417}; mkdir -p "$OUT"
LOG=$OUT/acceptance.log; : > "$LOG"
WORK=$(mktemp -d /tmp/gaea-crash.XXXX)
H=$WORK/h; P=17781
DEMO=https://github.com/xocialize-code/gaea-plugin-demo; D=com.xocialize.gaea.demo
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
py() { python3 -c "$1" }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
submit() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
state() { mes "http://127.0.0.1:$P/mes/v0/jobs/$1" | py 'import json,sys; print(json.load(sys.stdin)["state"])' }
settle() { # job id → prints the settled job
  local j
  for _ in {1..30}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$1?wait=10")
    print -r -- "$j" | py 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' 2>/dev/null && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
job() { # json body → prints the settled job, or the refusal
  local r id
  r=$(submit "$1")
  id=$(print -r -- "$r" | py 'import json,sys; print(json.load(sys.stdin).get("id", ""))')
  [[ -z $id ]] && { print -r -- "$r"; return }
  settle $id
}
start() {
  GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise >> "$H.out" 2>&1 &
  for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done
  say "Gaea didn't start:"; cat "$H.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..30}; do pgrep -f "$GAEA --headless --port $P" >/dev/null || return 0; sleep 0.2; done }
gaea() { print -r -- "\$ gaea $*" >> "$LOG"; GAEA_HOME=$H $CLI "$@" 2>&1 | tee -a "$LOG" }
wpid() { GAEA_HOME=$H $CLI ledger --json | py "import json,sys; print(next((w['pid'] for w in json.load(sys.stdin)['workers'] if w['pluginID'] == '$D'), ''))" }
not_offered() { ! offered $1 }
cleared_and_offered() { plugin "p['enabled'] and p.get('quarantined') is None" && offered demo-gradient }
offered() { mes "http://127.0.0.1:$P/mes/v0/operations" | py "import json,sys; sys.exit(0 if any(m['id'] == '$1' for o in json.load(sys.stdin)['operations'] for m in o['models']) else 1)" }
crash() { # id, python expression over c (the crash's JSON) → exit 0 if true
  GAEA_HOME=$H $CLI crashes show $1 --json | py "import json,sys; c = json.load(sys.stdin); ok = $2; print(c) if not ok else None; sys.exit(0 if ok else 1)"
}
plugin() { GAEA_HOME=$H $CLI plugins --json | py "import json,sys; p = next(p for p in json.load(sys.stdin) if p['id'] == '$D'); ok = $1; print(p) if not ok else None; sys.exit(0 if ok else 1)" }
gradient() { print -r -- '{"operation":"image.generate","model":"demo-gradient","inputs":{"prompt":"a lighthouse at dusk"},"params":{"size":{"width":'$2',"height":'$2'},"count":'$3',"seed":'$1'}}' }
succeeded() { py "import json; j = json.load(open('$1')); w = j['result']['effective']['model_params']['x-gaea.worker']; assert j['outcome'] == 'succeeded', j; ok = $2; assert ok, w; print(w)" }
cleanup() { pkill -TERM -f "^$GAEA" 2>/dev/null; true }
trap cleanup EXIT

say "# Crash acceptance (AB-T-0417) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), the demo from GitHub"
say "host: $(sysctl -n hw.model), macOS $(sw_vers -productVersion); GAEA_HOME $H; GAEA_DEMO_TRAP_SEED=666"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API GAEA_UNTRUST_OWN_TEAM
export GAEA_DEMO_TRAP_SEED=666
start
check "the demo installs from GitHub" zsh -c "GAEA_HOME=$H $CLI plugins add $DEMO | tee -a $LOG | grep -q '^Installed Gaea demo worker 0.3.[2-9]'"
job "$(gradient 1 512 1)" > "$WORK/warm.json"
check "a job runs, and nothing has crashed" zsh -c "python3 -c \"import json; assert json.load(open('$WORK/warm.json'))['outcome'] == 'succeeded'\" && GAEA_HOME=$H $CLI crashes | grep -q '^No crashes.'"

# ---- 1. SIGKILL mid-job ----
killed=""
for try in 1 2 3; do
  pid=$(wpid)
  r=$(submit "$(gradient 2 2048 4)"); ID=$(print -r -- "$r" | py 'import json,sys; print(json.load(sys.stdin)["id"])')
  for _ in {1..200}; do
    s=$(state $ID)
    if [[ $s == running && -n $pid ]]; then kill -KILL $pid && killed=$pid; break; fi
    [[ $s == holding || $s == purged ]] && break
    sleep 0.03
  done
  settle $ID > "$WORK/killed.json"
  [[ -n $killed ]] && break
  say "      try $try: the job ended before the kill; again"
done
say "      killed the demo's worker, pid ${killed:-none}, mid-job $ID"
cp "$WORK/killed.json" "$OUT/job-sigkill-requeued.json"
check "the job is requeued once and succeeds" succeeded "$WORK/killed.json" "w.get('requeued') is True"
check "crash #1: SIGKILL, requeued, with the job, model, lane and pid" crash 1 "c['how'] == 'SIGKILL' and c['outcome'] == 'requeued' and c['job'].startswith('$ID') and c['model'] == 'demo-gradient' and c['lane'] == 'fp32' and c['pid'] == ${killed:-0}"
check "…and no crash report, since SIGKILL writes none" crash 1 "c.get('reportPath') is None and c['reportNote'] == 'none: SIGKILL writes no crash report'"
gaea crashes show 1 > "$OUT/crash-1-sigkill.txt"

# ---- 2. a trap, twice: the job fails with both named ----
began=$(date +%s)
job "$(gradient 666 512 1)" > "$WORK/trap.json"
cp "$WORK/trap.json" "$OUT/job-trap-failed.json"
check "the trapped job fails with both crashes named" py "
import json; j = json.load(open('$WORK/trap.json')); m = j['error']['message']; print(m)
assert j['outcome'] == 'failed' and 'crashed twice running this job, SIGTRAP (crash #2) then SIGTRAP (crash #3); it was requeued once' in m"
check "…and the quarantine it caused" py "
import json; m = json.load(open('$WORK/trap.json'))['error']['message']
assert 'The plugin is quarantined after 3 crashes in 10 minutes, the last SIGTRAP running demo-gradient (crash #3)' in m"
for _ in {1..80}; do crash 3 "c.get('reportNote') is None" > /dev/null 2>&1 && crash 2 "c.get('reportNote') is None" > /dev/null 2>&1 && break; sleep 0.25; done
say "      reports collected $(( $(date +%s) - began )) s after the job"
check "crash #2: SIGTRAP, requeued; crash #3: SIGTRAP, failed, and it quarantined the demo" zsh -c "
  $(typeset -f crash py); H=$H CLI=$CLI
  crash 2 \"c['how'] == 'SIGTRAP' and c['outcome'] == 'requeued' and not c['quarantined']\" &&
  crash 3 \"c['how'] == 'SIGTRAP' and c['outcome'] == 'failed' and c['quarantined']\""
check "each has the worker's Fatal error line" zsh -c "
  $(typeset -f crash py); H=$H CLI=$CLI
  for i in 2 3; do crash \$i \"any('Fatal error: demo-gradient: a trap on seed 666' in l for l in c['stderrTail'])\" || exit 1; done"
check "each has macOS's crash report, copied into Crashes/ and summarised" zsh -c "
  $(typeset -f crash py); H=$H CLI=$CLI
  for i in 2 3; do crash \$i \"c['reportPath'].startswith('$H/Crashes/') and c['reportSummary'].startswith('EXC_BREAKPOINT (SIGTRAP)') and 'GradientModel.run' in c['reportSummary']\" || exit 1; done"
check "…whose pid is the crashed worker's" zsh -c "
  for i in 2 3; do
    f=\$(GAEA_HOME=$H $CLI crashes show \$i --json | python3 -c 'import json,sys; c = json.load(sys.stdin); print(c[\"reportPath\"], c[\"pid\"])')
    python3 -c \"import json,sys; p, pid = '\$f'.split(); b = json.loads(open(p).read().split(chr(10), 1)[1]); sys.exit(0 if b['pid'] == int(pid) else 1)\" || exit 1
  done"
gaea crashes show 3 > "$OUT/crash-3-trap.txt"

# ---- 3. quarantined ----
gaea crashes > "$OUT/crashes.txt"
check "gaea crashes lists all three, newest first, the third quarantining" zsh -c "grep -c '^#' $OUT/crashes.txt | grep -qx 3 && head -1 $OUT/crashes.txt | grep -q '^#3 .*SIGTRAP  failed' && grep -q 'quarantined $D' $OUT/crashes.txt"
check "the demo is switched off and marked quarantined" plugin "not p['enabled'] and p['quarantined'].startswith('3 crashes in 10 minutes, the last SIGTRAP running demo-gradient (crash #3)')"
gaea plugins > "$OUT/plugins-quarantined.txt"
check "gaea plugins says how to clear it" grep -q "quarantined .*(gaea plugins enable $D clears it)" "$OUT/plugins-quarantined.txt"
check "gaea status counts the crashes and names the quarantine" zsh -c "GAEA_HOME=$H $CLI status | tee -a $LOG | grep -q '^Crashes:   3 in the last 24 h; quarantined: $D'"
check "demo-gradient isn't offered" not_offered demo-gradient
job "$(gradient 1 512 1)" > "$WORK/refused.json"
check "a job for it is refused" grep -q '"error"' "$WORK/refused.json"
check "the events record each crash and the quarantine" zsh -c "GAEA_HOME=$H $CLI plugins logs $D | tee -a $LOG | grep -c ' crashed ' | grep -qx 3 && GAEA_HOME=$H $CLI plugins logs $D | grep -q ' quarantined: 3 crashes in 10 minutes'"
stop
unset GAEA_DEMO_TRAP_SEED
GAEA_HOME=$H "$GAEA" --snapshot "$WORK/snap" >> "$H.out" 2>&1
for f in console-plugins-light console-plugins-dark; do cp "$WORK/snap/$f.png" "$OUT/$f-quarantined.png" 2>/dev/null; done
check "the console rendered the quarantined plugin" test -s "$OUT/console-plugins-light-quarantined.png"
start
check "after a restart, still quarantined" plugin "not p['enabled'] and p.get('quarantined') is not None"

# ---- 4. cleared ----
check "the operator switches it on" zsh -c "GAEA_HOME=$H $CLI plugins enable $D | tee -a $LOG | grep -q 'enabled'"
check "the quarantine is cleared and demo-gradient is offered again" cleared_and_offered
job "$(gradient 1 512 1)" > "$WORK/cleared.json"
cp "$WORK/cleared.json" "$OUT/job-after-clearing.json"
check "a job runs" succeeded "$WORK/cleared.json" "True"
pid=$(wpid); [[ -n $pid ]] && kill -KILL $pid
sleep 2
check "a crash after clearing (#4, idle) is recorded" crash 4 "c['how'] == 'SIGKILL' and c['outcome'] == 'idle' and c.get('job') is None and c['pid'] == ${pid:-0}"
check "…and doesn't quarantine it: the count started again" plugin "p['enabled'] and p.get('quarantined') is None"
check "the events record the clearing" zsh -c "GAEA_HOME=$H $CLI plugins logs $D | grep -q ' quarantine_cleared: the operator switched it on'"
gaea crashes > "$OUT/crashes-end.txt"
sqlite3 -readonly "$H/gaea.sqlite" "SELECT at, plugin_id, version, kind, message FROM event ORDER BY id" > "$OUT/events.txt"
grep -F 'scheduler: crash' "$H.out" > "$OUT/scheduler-crashes.log"
stop

# ---- 5. transcripts ----
for s in $H/Logs/sessions/*.gpp; do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
check "the killed and trapped workers' transcripts end at their exits" zsh -c "grep -l -x '# exited: signal 9' $H/Logs/sessions/*.gpp | wc -l | grep -qw 2 && grep -l -x '# exited: signal 5' $H/Logs/sessions/*.gpp | wc -l | grep -qw 2"
cp "$H.out" "$OUT/gaea.log"
say "$pass passed, $fail failed"
exit $(( fail > 0 ))
