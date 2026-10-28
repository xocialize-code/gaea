#!/bin/zsh
# G0's exit tests for the Gaea host (AB-T-0355), against a built Gaea.app:
#
#   1. the MES Base conformance suite passes against Gaea serving the demo plugin (open mode, then paired mode);
#   2. a plugin added by repo URL installs, updates, rolls back, and enables and disables (the demo's GitHub releases);
#   3. an ad-hoc or tampered plugin is refused (at install, and a bundle tampered after install at launch);
#   4. configuration is reachable only from the server's own UI and the local CLI.
#
#   tools/acceptance-g0.sh <short-work-dir> <evidence-dir>
#
# <short-work-dir> holds the test Gaea folders; keep it short (a Unix socket path is at most 103 bytes).
# Needs: dist/Gaea.app (scripts/build-app.sh), MES_CONFORMANCE (media-engine-spec's mes-conformance), and STANDIN_ROOT: a tools/release-standin.py tree with tamper/, adhoc/ and
# otherteam/ repos (see the receipt doc for how they were made).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
CONFORMANCE=${MES_CONFORMANCE:?path to mes-conformance}
REPO=https://github.com/xocialize/gaea-plugin-demo; ID=com.xocialize.gaea.demo
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { # name, then a command whose exit status decides
  local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
job() { # port, json body → prints the settled job
  local id; id=$(mes -X POST "http://127.0.0.1:$1/mes/v0/jobs" -H 'Content-Type: application/json' -d "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  for _ in 1 2 3 4 5 6; do
    local j; j=$(mes "http://127.0.0.1:$1/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
field() { python3 -c "import json,sys; j=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1" }
start() { # home, port, extra args… → waits for the operator socket
  local home=$1 port=$2; shift 2
  GAEA_HOME=$home "$GAEA" --headless --port $port --no-advertise "$@" > "$home.out" 2>&1 &
  for _ in {1..50}; do [[ -S $home/operator.sock ]] && return; sleep 0.2; done
  say "Gaea at $home didn't start:"; cat "$home.out" >> "$LOG"
}
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }

say "# Gaea G0 acceptance $(date -u +%FT%TZ) — $($CLI --help >/dev/null 2>&1; codesign -dv $APP 2>&1 | grep -E '^(Identifier|TeamIdentifier)' | tr '\n' ' ')"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN   # the plugin repos are public: Gaea reads them anonymously
say "GitHub: anonymous (no token in Gaea's environment)"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"

# ---- 2. Lifecycle on the real releases, plus 1. conformance (open mode; Base's shortest outputs TTL, 60 s, so the
# suite can watch outputs expire, BASE-071)
H=$WORK/main; P=17630
start $H $P --outputs-ttl 60
export GAEA_HOME=$H
t0=$(python3 -c 'import time; print(time.time())')
check "add by repo URL, naming the pre-release v0.2.0, installs it" zsh -c "$CLI plugins add $REPO 0.2.0 | grep -q 'Installed .* 0.2.0'"
say "      add took $(python3 -c "import time; print(round(time.time()-$t0,2))") s (download, sha256, signature, manifest)"
job $P '{"operation":"image.generate","inputs":{"prompt":"a lighthouse at dusk"}}' > "$OUT/job-first.json"
check "a MES job runs on the plugin's worker on the GPU (0.2.0)" zsh -c "grep -q '\"version\":\"0.2.0\"' $OUT/job-first.json && grep -q 'Device(gpu, 0)' $OUT/job-first.json"
"$CONFORMANCE" engine "http://127.0.0.1:$P/mes/v0" --max-ttl-wait 75 -o "$OUT/conformance-open" > "$OUT/conformance-open.txt" 2>&1
check "MES Base conformance, open mode: Base 0.1 conforms" grep -q 'Base 0.1: conforms' "$OUT/conformance-open.txt"
say "      $(tail -2 "$OUT/conformance-open.txt" | head -1)"
check "check for updates finds 0.2.1" zsh -c "$CLI plugins check | grep -q 'update available: 0.2.1'"
check "update installs the newest and keeps 0.2.0 for rollback" zsh -c "$CLI plugins update $ID | grep -q 'now runs 0.2.1' && $CLI plugins | grep -q 'rollback: 0.2.0'"
check "versions sit side by side on disk" zsh -c "ls $H/Plugins/$ID | tr '\n' ' ' | grep -q '0.2.0 0.2.1'"
check "roll back switches to 0.2.0" zsh -c "$CLI plugins rollback $ID | grep -q 'now runs 0.2.0'"
job $P '{"operation":"image.generate","inputs":{"prompt":"after rollback"}}' > "$OUT/job-after-rollback.json"
check "the next job runs the rolled-back version" grep -q '"version":"0.2.0"' "$OUT/job-after-rollback.json"
# Switch when idle: an update during a long run waits for it (0.2.1 is installed already, so this is a switch).
mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' \
  -d '{"operation":"image.generate","inputs":{"prompt":"long"},"extensions":{"x-gaea.demo_matmul":{"n":8192,"iterations":300}}}' > "$OUT/long-job.json"
sleep 2
check "an update during a run is staged, not switched" zsh -c "$CLI plugins update $ID | grep -q 'switches to it when the plugin is idle' && $CLI plugins | grep -q 'switching to 0.2.1 when idle'"
for _ in {1..60}; do $CLI plugins | grep -q 'when idle' || break; sleep 1; done
check "…and switches once the run ends" zsh -c "$CLI plugins | grep -q '$ID 0.2.1'"
LONG=$(field 'j["id"]' < "$OUT/long-job.json"); mes "http://127.0.0.1:$P/mes/v0/jobs/$LONG" > "$OUT/long-job-settled.json"
check "…and the run it waited for succeeded on 0.2.0" zsh -c "grep -q '\"outcome\":\"succeeded\"' $OUT/long-job-settled.json && grep -q '\"version\":\"0.2.0\"' $OUT/long-job-settled.json"
check "disable removes the plugin's operations" zsh -c "$CLI plugins disable $ID && curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/operations | grep -q '\"operations\":\\[\\]'"
check "a job for a disabled plugin is refused (404 unknown_operation)" zsh -c "curl -s -H 'MES-Version: 0.1' -H 'Content-Type: application/json' -X POST http://127.0.0.1:$P/mes/v0/jobs -d '{\"operation\":\"image.generate\",\"inputs\":{\"prompt\":\"x\"}}' | grep -q unknown_operation"
check "enable brings it back" zsh -c "$CLI plugins enable $ID && curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/operations | grep -q demo-matmul"
check "a model can be switched off and on" zsh -c "$CLI models disable demo-matmul && ! curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/operations | grep -q demo-matmul && $CLI models enable demo-matmul"
# Lane rules on the wire: an unknown named lane is refused.
check "a request naming an unknown lane is refused (422)" zsh -c "curl -s -H 'MES-Version: 0.1' -H 'Content-Type: application/json' -X POST http://127.0.0.1:$P/mes/v0/jobs -d '{\"operation\":\"image.generate\",\"inputs\":{\"prompt\":\"x\"},\"extensions\":{\"x-gaea.lane\":\"int4\"}}' | grep -qE 'out_of_limits|unsupported_parameter'"
$CLI ledger > "$OUT/ledger.txt"; $CLI status > "$OUT/status.txt"; $CLI plugins logs $ID -n 40 > "$OUT/plugin-logs.txt"

# ---- 4. The configuration surface
check "MES has no configuration routes (plugins, config, operator, admin → 404)" zsh -c "for p in plugins config operator admin settings; do for m in GET POST; do c=\$(curl -s -o /dev/null -w '%{http_code}' -X \$m -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/\$p); [[ \$c == 404 ]] || exit 1; done; done"
PID=$(pgrep -f "$GAEA --headless --port $P")
lsof -nP -a -p $PID -i > "$OUT/listeners.txt" 2>&1; lsof -nP -a -p $PID -U >> "$OUT/listeners.txt" 2>&1
check "the only TCP listener is MES on loopback" zsh -c "[[ \$(grep LISTEN $OUT/listeners.txt | grep -c TCP) == 1 ]] && grep LISTEN $OUT/listeners.txt | grep -q '127.0.0.1:$P'"
check "the operator socket is mode 0600 in a 0700 folder" zsh -c "[[ \$(stat -f %Lp $H/operator.sock) == 600 && \$(stat -f %Lp $H) == 700 ]]"
check "the operator API checks the caller's code: an unsigned client gets no answer" zsh -c "! GAEA_HOME=$H .build/debug/gaea status"
check "the signed gaea CLI is answered" zsh -c "$CLI status | grep -q 'same user, Developer ID team'"
check "MCP lists only operations and the four helpers (BASE-080 above)" grep -q '✅ BASE-080' "$OUT/conformance-open.txt"

# ---- 3. Refusals at launch: a bundle tampered after install
ACTIVE=$H/Plugins/$ID/0.2.1/demo.gaeaplugin/Contents/Resources/manifest.json
$CLI plugins disable $ID > /dev/null; $CLI plugins enable $ID > /dev/null   # stops the worker
cp "$ACTIVE" "$WORK/manifest-0.2.1.json"
print ' ' >> "$ACTIVE"
job $P '{"operation":"image.generate","inputs":{"prompt":"after tampering"}}' > "$OUT/job-tampered.json"
$CLI plugins > "$OUT/plugins-after-tamper.txt"
check "a bundle tampered after install is refused at launch, and the job fails" zsh -c "grep -q '\"outcome\":\"failed\"' $OUT/job-tampered.json && grep -q 'failed: Refused' $OUT/plugins-after-tamper.txt"
check "rolling back to the intact version recovers" zsh -c "$CLI plugins rollback $ID | grep -q 'now runs 0.2.0'"
job $P '{"operation":"image.generate","inputs":{"prompt":"recovered"}}' > "$OUT/job-recovered.json"
check "…and jobs run again" grep -q '"outcome":"succeeded"' "$OUT/job-recovered.json"
cp "$WORK/manifest-0.2.1.json" "$ACTIVE"   # the recorded sessions name this manifest
stop $P

# ---- 3. Refusals at install, through the same path, from a stand-in releases API
if [[ -n "${STANDIN_ROOT:-}" ]]; then
  python3 tools/release-standin.py "$STANDIN_ROOT" --port 8766 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  R=$WORK/refuse; GAEA_GITHUB_API=http://127.0.0.1:8766 start $R 17634
  export GAEA_HOME=$R
  check "a tampered plugin is refused at install (seal broken)" zsh -c "$CLI plugins add https://github.com/tamper/gaea-plugin-demo 2>&1 | grep -q 'signature is invalid'"
  check "an ad-hoc-signed plugin is refused at install" zsh -c "$CLI plugins add https://github.com/adhoc/gaea-plugin-demo 2>&1 | grep -q \"isn't signed with a Developer ID\""
  check "another team's plugin is refused, naming G-22" zsh -c "$CLI plugins add https://github.com/otherteam/gaea-plugin-demo 2>&1 | grep -q 'G-22'"
  check "nothing refused reached the plugin folder or staging" zsh -c "[[ -z \$(ls $R/Plugins) && -z \$(ls $R/Caches/staging) ]]"
  $CLI logs -n 20 > "$OUT/refusals.txt"
  stop 17634; kill $STANDIN 2>/dev/null
fi

# ---- 1. Paired mode: TLS, pairing, bearer tokens (BASE-005, 006, 090)
export GAEA_HOME=$WORK/paired
start $GAEA_HOME 17633 --paired --host 127.0.0.1 --approve-pairings
check "a plain add takes the newest full release and skips pre-releases (v0.2.1)" zsh -c "$CLI plugins add $REPO | grep -q 'Installed .* 0.2.1'"
"$CONFORMANCE" engine "https://127.0.0.1:17633/mes/v0" --pair --max-ttl-wait 0 -o "$OUT/conformance-paired" > "$OUT/conformance-paired.txt" 2>&1
check "MES Base conformance, paired mode: Base 0.1 conforms" grep -q 'Base 0.1: conforms' "$OUT/conformance-paired.txt"
say "      $(tail -2 "$OUT/conformance-paired.txt" | head -1)"
stop 17633

# ---- Every recorded GPP session passes the validator
for f in $WORK/*/Logs/sessions/*.gpp(N); do
  check "transcript ${f:t} validates" python3 tools/validate.py --transcript "$f"
  cp "$f" "$OUT/"
done
grep -h 'hello after' $WORK/*/Logs/gaea.log > "$OUT/hello-times.txt"
say ""; say "$pass passed, $fail failed"
exit $(( fail > 0 ))
