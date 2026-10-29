#!/bin/zsh
# AB-T-0377's acceptance through Gaea: G1's coverage of what pixel-agency-image-engine v0.9.1 serves, from the GitHub
# releases, installed by repo URL into a Gaea home that has every other G1 plugin:
#
#   1. gaea-plugin-forge updates to 0.2.0 and gaea-plugin-mage-vl installs, both verified and notarized;
#   2. image.relight, image.colorize, image.describe and image.score are offered, and restore and upscale list DRUNet,
#      Anime4K VL, VOSR2 and Nacre;
#   3. tools/coverage-routing.py: every job succeeds, describe answers with a caption, alt text and tags, score with a
#      value in 0…1, restore's scratches run the defect helper, then LaMa;
#   4. the licence links: qwen3.5-4b's terms_url names its own checkpoint, not the 0.8B.
#
#   tools/acceptance-coverage.sh <gaea-home> <evidence-dir>
#
# Needs: dist/Gaea.app; a Gaea home with the G1 plugins (AB-T-0373's, copied); the weights in MLXEngine's store;
# FIXTURES (default ../gaea-plugin-forge/scripts/fixtures).
set -uo pipefail
cd "${0:A:h}/.."
H=${1:?gaea home}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
FIXTURES=${FIXTURES:-../gaea-plugin-forge/scripts/fixtures}
P=${PORT:-17762}
mkdir -p "$OUT"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { # name, then a command whose exit status decides
  local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }

say "# AB-T-0377 acceptance $(date -u +%FT%TZ): $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString) on $H"
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise > "$OUT/server.log" 2>&1 &
SERVER=$!
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
for _ in {1..100}; do mes "http://127.0.0.1:$P/mes/v0/operations" > /dev/null && break; sleep 0.3; done

# ---- 1. The releases, by repo URL
GAEA_HOME=$H "$CLI" plugins update com.xocialize.gaea.forge 0.2.0 >> "$LOG" 2>&1
GAEA_HOME=$H "$CLI" plugins add https://github.com/xocialize-code/gaea-plugin-mage-vl >> "$LOG" 2>&1
GAEA_HOME=$H "$CLI" plugins list > "$OUT/plugins.txt" 2>&1
check "forge 0.2.0 is the active version" grep -Eq 'com.xocialize.gaea.forge.*0\.2\.0' "$OUT/plugins.txt"
check "mage-vl 0.1.0 is installed" grep -Eq 'com.xocialize.gaea.mage-vl.*0\.1\.0' "$OUT/plugins.txt"
check "both verified and notarized" py "
import sqlite3; db = sqlite3.connect('$H/gaea.sqlite')
rows = dict(((p, v), (s, n)) for p, v, s, n in db.execute('select plugin_id, version, signature, notarized from plugin_version'))
for key in [('com.xocialize.gaea.forge', '0.2.0'), ('com.xocialize.gaea.mage-vl', '0.1.0')]:
    s, n = rows[key]; print(key, s[:60], n); assert 'Developer ID' in s and n == 1, key"

# ---- 2. What's offered
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "relight, colorize, describe and score are offered, by the models v0.9.1 defaults to" py "
import json; ops = {d['operation']: d for d in json.load(open('$OUT/operations.json'))['operations']}
want = {'image.relight': 'cidnet-relight', 'image.colorize': 'ddcolor-colorize', 'image.describe': 'mage-vl', 'image.score': 'siglip2-quality'}
for op, model in want.items():
    ids = [m['id'] for m in ops[op]['models']]; print(op, ids); assert model in ids, (op, ids)"
check "restore lists DRUNet; upscale lists Anime4K VL, VOSR2 and Nacre" py "
import json; ops = {d['operation']: d for d in json.load(open('$OUT/operations.json'))['operations']}
r = [m['id'] for m in ops['image.restore']['models']]; u = [m['id'] for m in ops['image.upscale']['models']]; print(r, u)
assert 'drunet-denoise' in r and {'anime4k-upscale', 'vosr2-upscale', 'nacre-upscale'} <= set(u)"

# ---- 3. The coverage jobs
python3 tools/coverage-routing.py $P "$FIXTURES" "$OUT/coverage" > "$OUT/coverage.log" 2>&1
check "every coverage job succeeded" py "
import json; rs = json.load(open('$OUT/coverage/coverage.json'))
bad = [(r['name'], r['outcome'], r['error']) for r in rs if r['outcome'] != 'succeeded']; print(len(rs), 'jobs', bad); assert rs and not bad"
check "describe: a caption, alt text and tags (Mage-VL)" py "
import json; r = {x['name']: x for x in json.load(open('$OUT/coverage/coverage.json'))}['describe']
v = r['values']['description']; print(r['model'], v); assert r['model'] == 'mage-vl' and v['caption'] and v['alt_text'] and v['tags']"
check "score: a value in 0…1 (SigLIP2)" py "
import json; r = {x['name']: x for x in json.load(open('$OUT/coverage/coverage.json'))}['score']
v = r['values']['score']; print(r['model'], v); assert r['model'] == 'siglip2-quality' and 0 <= v['score'] <= 1"
check "scratches: BOPBTL's defects, then LaMa" py "
import json; r = {x['name']: x for x in json.load(open('$OUT/coverage/coverage.json'))}['restore-scratches-standard']
print(r['model_params']); assert r['model_params'].get('detector') == 'bopbtl-defects' and r['model_params'].get('model') == 'lama-inpaint'"
check "guarded upscales name what ran (Nacre on the sign: protected words)" py "
import json; r = {x['name']: x for x in json.load(open('$OUT/coverage/coverage.json'))}
print({k: r[k]['model_params'] for k in ('named-vosr2-x4', 'named-nacre-x4', 'named-nacre-sign-x2')})
assert 'protected words' in json.dumps(r['named-nacre-sign-x2']['model_params'])"

# ---- 4. The licence link
mes "http://127.0.0.1:$P/mes/v0/operations/image.enhance_prompt" > "$OUT/enhance-prompt.json"
check "qwen3.5-4b's terms_url is the 4B's own checkpoint" py "
import json; d = json.load(open('$OUT/enhance-prompt.json')); m = {x['id']: x for x in d['models']}['qwen3.5-4b']
url = m['license'].get('terms_url'); print(url); assert url and 'Qwen3.5-4B' in url and '0.8B' not in url"

kill -TERM $SERVER 2>/dev/null; wait $SERVER 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
