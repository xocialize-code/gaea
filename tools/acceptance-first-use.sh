#!/bin/zsh
# AB-A-0259's acceptance (Gaea 1.3.0): the first use of a model, as Gaea's first real client met it. Kokoro (339 MB of
# weights) from GitHub, against models roots that don't have its weights yet.
#
#   1. plugins add names the weights that aren't under the models root and points to gaea plugins warm; gaea models
#      marks the model the same way.
#   2. The first job downloads and loads before it runs.
#      - The client sees progress stage preparing: "downloading the weights (first use): x of y GB", then the load,
#        then running.
#      - The worker block reports prepare_seconds.
#      - A second job has neither, and the model is no longer marked.
#   3. With a new empty root:
#      - gaea plugins warm downloads and loads the model;
#      - the next job finds it loaded (no preparing, no prepare_seconds);
#      - warming again says it's already loaded.
#   4. The idle unload is an operator setting:
#      - gaea workers idle 30 shows in gaea status and survives a restart;
#      - a worker idle past it is stopped;
#      - gaea workers idle default returns to 900 s.
#   5. Every recorded GPP session passes the validator.
#
#   tools/acceptance-first-use.sh <short-work-dir> <evidence-dir>
#
# Needs: APP (default dist/Gaea.app, 1.3.0 or later), network for Kokoro's weights (downloaded only under ROOTS, default
# /Volumes/DEV_VOL1/Evidence/AB-A-0259/roots, which the script empties first).
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
ROOTS=${ROOTS:-/Volumes/DEV_VOL1/Evidence/AB-A-0259/roots}
KOKORO=com.xocialize.gaea.kokoro
[[ $ROOTS == /Volumes/DEV_VOL1/Evidence/* ]] || { print "ROOTS must be under /Volumes/DEV_VOL1/Evidence"; exit 2 }
rm -rf "$ROOTS"; mkdir -p "$ROOTS/a" "$ROOTS/b"
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
py() { python3 -c "$1" }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
op() { GAEA_HOME=$H "$CLI" "$@" }
start() { GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise "$@" >> "$H.out" 2>&1 &; for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || return; sleep 0.2; done }
speak() { # name: a Kokoro job, with every distinct progress the client could see (polled every 0.2 s) in <name>.progress
  local id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' \
    -d '{"operation":"audio.speak","model":"kokoro-82m","inputs":{"text":"Gaea speaks after loading its model."},"params":{"voice":"af_heart","seed":1}}' \
    | py "import json,sys; print(json.load(sys.stdin)['id'])")
  : > "$OUT/$1.progress"
  local j state
  for _ in {1..3000}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id")
    print -r -- "$j" | py "import json,sys; p=json.load(sys.stdin).get('progress') or {}; print(json.dumps({k: p.get(k) for k in ('stage','message')}))" >> "$OUT/$1.progress"
    state=$(print -r -- "$j" | py "import json,sys; print(json.load(sys.stdin)['state'])")
    [[ $state == holding || $state == purged ]] && break
    sleep 0.2
  done
  print -r -- "$j" > "$OUT/job-$1.json"
  sort -u "$OUT/$1.progress" -o "$OUT/$1.progress"
}
worker() { py "import json; w=json.load(open('$OUT/job-$1.json'))['result']['effective']['model_params']['x-gaea.worker']; print(w.get('$2'))" }

say "# First use (AB-A-0259) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), Kokoro from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
H=$WORK/home; P=17690
start
op models root "$ROOTS/a" > /dev/null
op plugins add https://github.com/xocialize-code/gaea-plugin-kokoro > "$OUT/plugins-add.txt" 2>&1
sed 's/^/      /' "$OUT/plugins-add.txt" | tee -a "$LOG"
check "plugins add names Kokoro's missing weights and points to gaea plugins warm" zsh -c "grep -q \"aren't under the models root\" $OUT/plugins-add.txt && grep -q 'kokoro-82m bf16: mlx-community/Kokoro-82M-bf16' $OUT/plugins-add.txt && grep -q 'gaea plugins warm $KOKORO' $OUT/plugins-add.txt"
op models > "$OUT/models-before.txt"
check "gaea models marks the model: the first job downloads its weights" grep -q 'weights not under the models root: mlx-community/Kokoro-82M-bf16' "$OUT/models-before.txt"

speak first
sed 's/^/      /' "$OUT/first.progress" | tee -a "$LOG"
check "the first job succeeds" py "import json; assert json.load(open('$OUT/job-first.json'))['outcome'] == 'succeeded'"
check "its client saw stage preparing: the download in GB" py "
import json; ps=[json.loads(l) for l in open('$OUT/first.progress')]
assert any(p['stage'] == 'preparing' and (p['message'] or '').startswith('downloading the weights (first use):') and ' GB' in p['message'] for p in ps), ps"
check "then the load, then running" py "
import json; ps=[json.loads(l) for l in open('$OUT/first.progress')]
assert any(p['stage'] == 'preparing' and 'loading' in (p['message'] or '') for p in ps) and any(p['stage'] == 'running' for p in ps), ps"
P1=$(worker first prepare_seconds); say "      first job: prepare_seconds $P1, worker seconds $(worker first seconds)"
check "the worker block reports prepare_seconds" py "assert float('$P1') > 0"
speak second
check "a second job sees no preparing and reports no prepare_seconds" py "
import json; ps=[json.loads(l) for l in open('$OUT/second.progress')]
assert not any(p['stage'] == 'preparing' for p in ps), ps; assert '$(worker second prepare_seconds)' == 'None'"
check "gaea models no longer marks it" zsh -c "! GAEA_HOME=$H $CLI models | grep -q 'weights not under'"

op models root "$ROOTS/b" > /dev/null
op plugins warm $KOKORO > "$OUT/warm.txt" 2>&1
sed 's/^/      /' "$OUT/warm.txt" | tee -a "$LOG"
check "plugins warm downloads and loads Kokoro under the new root" zsh -c "grep -qE 'kokoro-82m bf16: downloaded [0-9.]+ GB and loaded in [0-9.]+ s' $OUT/warm.txt && ls -d $ROOTS/b/models--mlx-community--Kokoro-82M-bf16"
speak warmed
check "the next job finds it loaded: no preparing, no prepare_seconds" py "
import json; ps=[json.loads(l) for l in open('$OUT/warmed.progress')]
assert json.load(open('$OUT/job-warmed.json'))['outcome'] == 'succeeded' and not any(p['stage'] == 'preparing' for p in ps), ps
assert '$(worker warmed prepare_seconds)' == 'None'"
op plugins warm $KOKORO > "$OUT/warm-again.txt" 2>&1
check "warming again says it's already loaded" grep -q 'kokoro-82m bf16: already loaded' "$OUT/warm-again.txt"

op workers idle 30 > "$OUT/idle.txt"
check "gaea workers idle 30 is kept and shown in gaea status" zsh -c "grep -q 'idle 30 s' $OUT/idle.txt && GAEA_HOME=$H $CLI status | grep -q 'a worker idle 30 s'"
stop; start
check "it survives a restart" zsh -c "GAEA_HOME=$H $CLI status | grep -q 'a worker idle 30 s'"
speak idle
GONE=no
for _ in {1..30}; do op status | grep -q 'Workers:   none' && { GONE=yes; break }; sleep 5; done
check "a worker idle past 30 s is stopped (the sweep runs every 30 s)" test $GONE = yes
op workers idle default > /dev/null
check "gaea workers idle default returns to 900 s" zsh -c "GAEA_HOME=$H $CLI status | grep -q 'a worker idle 900 s'"
stop
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
rm -rf "$ROOTS"
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
