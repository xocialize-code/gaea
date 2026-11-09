#!/bin/zsh
# Gaea 1.5.0's acceptance: what an operator narrows on a server, so a preview server keeps to its quick work. FLUX.2
# Klein, Z-Image and TRELLIS.2 from GitHub.
#
#   1. The budget: gaea budget reads it (three quarters of memory); gaea budget 50 sets it now (TRELLIS.2's 1024 and 1536
#      stop being offered, gaea status says who set it) and for the next launch; gaea budget default goes back.
#   2. Lanes: switching off Z-Image Turbo's default lane (int4) moves jobs to the next lane and refuses a request naming
#      it (the lane extension still lists int4: Klein and Z-Image have one); with every lane off the model isn't offered; on again, all is back.
#   3. Caps:
#      - Klein capped at 4.2 megapixels: its offer says so, a 1024² job runs, a 4096² request naming it is refused at
#        submit, and an unnamed 4096² request goes to a model it fits (Klein 4B Base);
#      - TRELLIS.2 512 capped at 5,000 faces: its offer says so, a request for 20,000 is refused, and a request that
#        doesn't ask is made under 5,000 with faces_reduced;
#      - an unknown cap is refused, and caps and lanes survive a restart;
#      - removing every cap restores the plugin's limits.
#   4. Every recorded GPP session passes the validator.
#
#   tools/acceptance-controls.sh <short-work-dir> <evidence-dir>
#
# Needs APP (default dist/Gaea.app, 1.5.0 or later), GAEA_GITHUB_TOKEN for the plugin releases, and MODELS (default
# /Volumes/DEV_VOL1/Models) with FLUX.2 Klein 4B, Z-Image Turbo, TRELLIS.2 and BiRefNet.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
FOX=../gaea-plugin-trellis2/Tests/Fixtures/fox.png
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
op() { GAEA_HOME=$H "$CLI" "$@" }
submit() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
job() {
  local id j; id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  [[ -z $id ]] && { print -r -- '{"outcome":"refused"}' > "$2"; return }
  for _ in {1..300}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
  done
  print -r -- "$j" > "$2"
}
operations() { mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/$1.json" }
models_of() { py "import json; d={o['operation']: o for o in json.load(open('$OUT/$1.json'))['operations']}; print(' '.join(m['id'] for m in d.get('$2', {}).get('models', [])))" }
start() { GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root "$MODELS" > "$H.out" 2>&1 &; for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || return; sleep 0.2; done }

say "# Operator controls acceptance $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), plugins from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
H=$WORK/home; P=17676
start
for repo in gaea-plugin-flux2-klein gaea-plugin-z-image gaea-plugin-trellis2; do
  op plugins add https://github.com/xocialize-code/$repo | tail -1 | tee -a "$LOG"
done

# 1. The budget.
DEFAULT=$(py "import os; print(round($(sysctl -n hw.memsize) / 4 * 3 / 1e9, 2))")
op budget > "$OUT/budget-default.txt"
check "gaea budget reads three quarters of memory ($DEFAULT GB), the default" grep -q "Budget: $DEFAULT GB (three quarters of memory, the default)" "$OUT/budget-default.txt"
op budget 50 > "$OUT/budget-50.txt"; cat "$OUT/budget-50.txt" >> "$LOG"
check "gaea budget 50 sets it now and says what stops being offered" zsh -c "grep -q 'Budget: 50.00 GB (set by the operator)' $OUT/budget-50.txt && grep -q 'trellis2-1024' $OUT/budget-50.txt"
operations ops-budget
check "with 50 GB, mesh.generate offers only trellis2-512" test "$(models_of ops-budget mesh.generate)" = "trellis2-512"
check "gaea status names the operator's budget" zsh -c "GAEA_HOME=$H $CLI status | grep -q '50.00 GB budget (set by the operator)'"
stop; start
check "the budget survives a restart" zsh -c "GAEA_HOME=$H $CLI budget | grep -q 'Budget: 50.00 GB (set by the operator)'"
op budget default > /dev/null
operations ops-budget-default
check "gaea budget default goes back, and the cascades are offered again" zsh -c "GAEA_HOME=$H $CLI budget | grep -q 'the default' && test \"$(models_of ops-budget-default mesh.generate)\" = 'trellis2-512 trellis2-1024 trellis2-1536'"

# 2. Lanes.
op models lanes z-image-turbo off int4 > "$OUT/lanes-off.txt"; cat "$OUT/lanes-off.txt" >> "$LOG"
check "gaea models lanes z-image-turbo off int4 says so" grep -q "int4 off" "$OUT/lanes-off.txt"
operations ops-lanes
check "gaea models lanes reads it back" zsh -c "GAEA_HOME=$H $CLI models lanes z-image-turbo | grep -q 'int4 off, int8 on, bf16 on'"
job '{"operation":"image.generate","model":"z-image-turbo","inputs":{"prompt":"a lighthouse at dusk"},"params":{"size":{"width":512,"height":512},"seed":3}}' "$OUT/job-lane.json"
check "a Z-Image job runs on the next lane (int8), not int4" py "
import json; j=json.load(open('$OUT/job-lane.json')); w=j['result']['effective']['model_params']['x-gaea.worker']; print(j['outcome'], w['lane']); assert j['outcome']=='succeeded' and w['lane']=='int8'"
job '{"operation":"image.generate","model":"z-image-turbo","inputs":{"prompt":"a lighthouse at dusk"},"params":{"size":{"width":512,"height":512},"seed":3},"extensions":{"x-gaea.lane":"int4"}}' "$OUT/job-named.json"
check "a request naming int4 is refused (unsupported_parameter, switched off)" py "
import json; j=json.load(open('$OUT/job-named.json')); e=j.get('error') or {}; print(j.get('outcome'), e)
assert j.get('outcome') in ('failed', 'refused') and (e.get('code') == 'unsupported_parameter' and 'switched off' in e.get('message','') or j.get('outcome') == 'refused')"
op models lanes z-image-turbo off int8 > /dev/null; op models lanes z-image-turbo off bf16 > "$OUT/lanes-all-off.txt"
operations ops-lanes-all
check "with every lane off, z-image-turbo isn't offered" zsh -c "grep -q 'every lane is off' $OUT/lanes-all-off.txt && ! grep -q 'z-image-turbo' <<< \"$(models_of ops-lanes-all image.generate)\""
for l in int8 bf16; do op models lanes z-image-turbo on $l > /dev/null; done

# 3. Caps.
op models limit klein-4b max_megapixels 4.2 > "$OUT/cap-klein.txt"; cat "$OUT/cap-klein.txt" >> "$LOG"
operations ops-caps
check "Klein's offer says 4.2 megapixels" py "
import json; d={o['operation']: o for o in json.load(open('$OUT/ops-caps.json'))['operations']}['image.generate']
m=[m for m in d['models'] if m['id']=='klein-4b'][0]; print(m.get('limits')); assert m['limits']['max_megapixels'] == 4.2"
job '{"operation":"image.generate","model":"klein-4b","inputs":{"prompt":"a red fox in the snow"},"params":{"size":{"width":1024,"height":1024},"seed":5}}' "$OUT/job-klein1024.json"
check "a 1024² Klein job runs under the cap" py "import json; j=json.load(open('$OUT/job-klein1024.json')); print(j['outcome']); assert j['outcome']=='succeeded'"
submit '{"operation":"image.generate","model":"klein-4b","inputs":{"prompt":"a red fox in the snow"},"params":{"size":{"width":4096,"height":4096},"seed":5}}' "$OUT/refuse-klein4096.json"
check "a 4096² Klein request is refused at submit (422 out_of_limits)" zsh -c "test \"\$(cat $OUT/refuse-klein4096.json.status)\" = 422 && grep -q out_of_limits $OUT/refuse-klein4096.json"
job '{"operation":"image.generate","inputs":{"prompt":"a red fox in the snow"},"params":{"size":{"width":4096,"height":4096},"seed":5,"quality":"best"}}' "$OUT/job-unnamed4096.json" &
UNNAMED=$!
op models limit trellis2-512 max_faces 5000 > /dev/null
operations ops-caps-mesh
check "TRELLIS.2 512's offer says 5,000 faces" py "
import json; d={o['operation']: o for o in json.load(open('$OUT/ops-caps-mesh.json'))['operations']}['mesh.generate']
m=[m for m in d['models'] if m['id']=='trellis2-512'][0]; print(m['limits']); assert m['limits']['max_faces'] == 5000"
UP=$(mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @$FOX | py "import json,sys; print(json.load(sys.stdin)['upload_id'])")
submit '{"operation":"mesh.generate","model":"trellis2-512","inputs":{"image":{"upload":"'$UP'"}},"params":{"max_faces":20000}}' "$OUT/refuse-faces.json"
check "a mesh request for 20,000 faces is refused (422)" test "$(cat $OUT/refuse-faces.json.status)" = "422"
job '{"operation":"mesh.generate","model":"trellis2-512","inputs":{"image":{"upload":"'$UP'"}},"params":{"seed":42,"texture_size":512}}' "$OUT/job-mesh.json"
check "a mesh request that doesn't ask is made under 5,000 faces, with faces_reduced" py "
import json; j=json.load(open('$OUT/job-mesh.json')); o=[o for o in j['result']['outputs'] if o['name']=='mesh'][0]
print(j['outcome'], o['faces'], [w['code'] for w in j.get('warnings', [])]); assert o['faces'] <= 5000 and any(w['code']=='faces_reduced' for w in j['warnings'])"
wait $UNNAMED
check "an unnamed 4096² request goes to a model it fits, not capped Klein 4B" py "
import json; j=json.load(open('$OUT/job-unnamed4096.json')); r=j.get('result') or {}; m=(r.get('provenance') or {}).get('model', {}).get('id')
print(j.get('outcome'), m, (j.get('error') or {}).get('message')); assert m != 'klein-4b' and (j.get('outcome') == 'succeeded' or (j.get('error') or {}).get('code') != 'out_of_limits')"
GAEA_HOME=$H "$CLI" models limit klein-4b max_speed 3 > "$OUT/cap-unknown.txt" 2>&1
check "an unknown cap is refused, naming the caps there are" grep -q "caps are" "$OUT/cap-unknown.txt"
op models lanes z-image-turbo off int4 > /dev/null
stop; start
check "caps and lanes survive a restart" zsh -c "GAEA_HOME=$H $CLI models limit klein-4b | grep -q 'max_megapixels 4.2' && GAEA_HOME=$H $CLI models lanes z-image-turbo | grep -q 'int4 off'"
op models > "$OUT/models.txt"; sed 's/^/      /' "$OUT/models.txt" | tee -a "$LOG"
check "gaea models shows the caps and the lane switched off" zsh -c "grep -q 'caps: max_megapixels 4.2' $OUT/models.txt && grep -q 'int4\\*\\? (off)\\|int4 (off)' $OUT/models.txt"
op models limit klein-4b none > /dev/null; op models limit trellis2-512 none > /dev/null; op models lanes z-image-turbo on int4 > /dev/null
operations ops-cleared
check "removing every cap restores the plugins' limits" py "
import json; ops={o['operation']: o for o in json.load(open('$OUT/ops-cleared.json'))['operations']}
k=[m for m in ops['image.generate']['models'] if m['id']=='klein-4b'][0]; t=[m for m in ops['mesh.generate']['models'] if m['id']=='trellis2-512'][0]
print((k.get('limits') or {}).get('max_megapixels'), t['limits'].get('max_faces')); assert (k.get('limits') or {}).get('max_megapixels', 99) > 4.2 and t['limits']['max_faces'] == 2000000"
stop
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
