#!/bin/zsh
# AB-A-0328's acceptance: Bria's RMBG 3.0 (CC BY-NC 4.0) as `rmbg-3` on MES image.matte, from gaea-plugin-fibo2 0.3.0 on
# GitHub, through Gaea. The model is named-only and opt-in, and needs the users' acceptance of its licence.
#
#   tools/acceptance-rmbg.sh <short-work-dir> <evidence-dir>
#
#   1. Gaea adds the Fibo plugin; `rmbg-3` is off until the operator enables it, and then listed on image.matte:
#      named-only, non-commercial, accepted-required, with its attribution, and never the default.
#   2. A matte naming no model doesn't run on it.
#   3. Named without the licence accepted, the job is refused (policy_unmet).
#   4. Named and accepted: a mask and an extract the picture's size, the mask not blank, the extract's alpha the mask.
#   5. A second run gives the same mask, and `seed` is refused: MES image.matte has no seed, so a model that wants one
#      takes it as its own extension (AB-A-0328's question 2).
#   6. A subject with this model (question 3): refused while the server has no segmenter; with the Forge pack beside
#      it, Gaea's segmenter picks the subject and RMBG 3.0 mattes it, the offer listing no `supports.subject` itself.
#
# Needs: APP (default dist/Gaea.app), MODELS (default /Volumes/DEV_VOL1/Models) with briaai/RMBG-3.0 and a Fibo Edit
# Turbo or Dev snapshot (the weights are gated: the operator downloads them), IMAGE (default the locate plugin's fox),
# and PY, a python with PIL, for the picture checks (default python3; the checks are skipped without PIL).
set -uo pipefail
cd ${0:A:h:h}
WORK=${1:?short work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA=$APP/Contents/MacOS/Gaea; CLI=$APP/Contents/Helpers/gaea
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
IMAGE=${IMAGE:-../gaea-plugin-locate/Tests/Fixtures/fox.png}
PY=${PY:-/Volumes/DEV_VOL1/flow-upscaler-eval/.venv/bin/python}
REPO=https://github.com/xocialize-code/gaea-plugin-fibo2
V=${V:-0.3.0}; MODEL=rmbg-3; SPDX=CC-BY-NC-4.0
H=$WORK/h; P=17781
mkdir -p $WORK $OUT
LOG=$OUT/acceptance.log; : > $LOG
pass=0; fail=0
say() { print -r -- "$*" | tee -a $LOG }
check() { local name=$1; shift
  if "$@" >> $LOG 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
py() { python3 -c "$1" }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
gaea() { GAEA_HOME=$H $CLI "$@" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @$1 | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
matte() { # name, json extras merged into the body → $OUT/<name>.json (the settled job or the refusal), <name>-mask.png, <name>-extract.png
  local name=$1 up; up=$(upload $IMAGE)
  py "
import json
b = {'operation': 'image.matte', 'inputs': {'image': {'upload': '$up'}}, 'params': {}}  # outputs: mask and extract by default
b.update(json.loads('''$2'''))
json.dump(b, open('$OUT/body-$name.json', 'w'))"
  local r id j
  r=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d @$OUT/body-$name.json)
  id=$(print -r -- "$r" | py 'import json,sys; print(json.load(sys.stdin).get("id", ""))')
  if [[ -z $id ]]; then print -r -- "$r" > $OUT/$name.json; else
    for _ in {1..60}; do
      j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
      print -r -- "$j" | py 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' 2>/dev/null && break
    done
    print -r -- "$j" > $OUT/$name.json
    for o in mask extract; do
      local href; href=$(py "import json; o=[x for x in (json.load(open('$OUT/$name.json')).get('result') or {}).get('outputs', []) if x['name']=='$o']; print(o[0]['href'] if o else '')")
      [[ -n $href ]] && mes -o $OUT/$name-$o.png "http://127.0.0.1:$P$href"
    done
  fi
  say "      $name: $(py "import json; j=json.load(open('$OUT/$name.json')); r=j.get('result') or {}; e=j.get('error') or {}; p=r.get('provenance') or {}; print(j.get('outcome',''), (p.get('model') or {}).get('id',''), [(h.get('role'), h.get('id') or (h.get('model') or {}).get('id')) for h in p.get('helpers', [])], [o['name'] for o in r.get('outputs', [])], r.get('effective'), [x['code'] for x in j.get('warnings', [])], e.get('code',''), e.get('message','')[:200])")"
}
cleanup() { pkill -TERM -f "^$GAEA --headless --port $P" 2>/dev/null; true }
trap cleanup EXIT

say "# RMBG 3.0 acceptance (AB-A-0328) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), gaea-plugin-fibo2 $V from GitHub"
say "host: $(sysctl -n hw.model), $(sysctl -n hw.memsize | awk '{print $1/1073741824}') GB, macOS $(sw_vers -productVersion)"
unset GAEA_GITHUB_API
GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise --models-root $MODELS >> $H.out 2>&1 &
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done

# 1. The offer.
check "add the Fibo plugin $V by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add $REPO $V | tee -a $LOG | grep -q '^Installed .* $V '"
check "$MODEL is off until the operator enables it" zsh -c "! curl -s -H 'MES-Version: 0.1' http://127.0.0.1:$P/mes/v0/operations | grep -q '\"$MODEL\"'"
gaea models enable $MODEL >> $LOG 2>&1
mes "http://127.0.0.1:$P/mes/v0/operations" > $OUT/operations.json
check "enabled, image.matte lists it: named-only, $SPDX, non-commercial, accepted-required, attributed, not the default" py "
import json; ops={o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m={x['id']: x for x in ops['image.matte']['models']}['$MODEL']; l=m['license']; print(m)
assert m.get('named_only') is True and not m.get('default'), m
assert l['spdx']=='$SPDX' and l['commercial_use'] in (False, 'no') and l['accepted_required'] is True and 'RMBG 3.0' in l.get('attribution',''), l"

# 2. and 3. Not by default, and not without the licence.
matte unnamed '{}'
check "a matte naming no model doesn't run on $MODEL" py "
import json; j=json.load(open('$OUT/unnamed.json')); p=((j.get('result') or {}).get('provenance') or {}).get('model') or {}
assert p.get('id') != '$MODEL', p"
matte unaccepted '{"model":"'$MODEL'"}'
check "named without the licence accepted, it is refused (policy_unmet)" py "
import json; j=json.load(open('$OUT/unaccepted.json')); e=j.get('error') or {}; assert e.get('code')=='policy_unmet' and '$SPDX' in e.get('message',''), j"

# 4. Named and accepted.
matte accepted '{"model":"'$MODEL'","policy":{"accepted":["'$SPDX'"]}}'
check "named and accepted: it succeeds on $MODEL with a mask and an extract" py "
import json; j=json.load(open('$OUT/accepted.json')); r=j['result']
assert j['outcome']=='succeeded' and r['provenance']['model']['id']=='$MODEL' and sorted(o['name'] for o in r['outputs'])==['extract','mask'], j"
if $PY -c "import PIL" 2>/dev/null; then
  check "the mask and the extract are the picture's size, the mask isn't blank, the extract's alpha is the mask" $PY -c "
from PIL import Image, ImageChops
src=Image.open('$IMAGE'); m=Image.open('$OUT/accepted-mask.png'); e=Image.open('$OUT/accepted-extract.png')
assert m.size==src.size==e.size, (src.size, m.size, e.size)
lo, hi = m.convert('L').getextrema(); assert lo < 32 and hi > 223, (lo, hi)
diff = ImageChops.difference(e.convert('RGBA').getchannel('A'), m.convert('L')).getextrema(); print('alpha vs mask', diff); assert diff[1] <= 1, diff"
else
  say "SKIP  the picture checks: $PY has no PIL"
fi

# 5. Repeatable, and no seed on image.matte (question 2).
matte again '{"model":"'$MODEL'","policy":{"accepted":["'$SPDX'"]}}'
check "a second run gives the same mask" cmp $OUT/accepted-mask.png $OUT/again-mask.png
matte seeded '{"model":"'$MODEL'","policy":{"accepted":["'$SPDX'"]},"params":{"seed":8}}'
check "seed is refused: image.matte has no such parameter" py "
import json; e=json.load(open('$OUT/seeded.json')).get('error') or {}; assert e.get('code')=='unsupported_parameter' and 'seed' in e.get('message',''), e"

# 6. A subject (question 3).
SUBJECT='{"model":"'$MODEL'","policy":{"accepted":["'$SPDX'"]},"params":{"subject":{"box":{"x":0.2,"y":0.2,"width":0.6,"height":0.6}}}}'
matte subject-alone $SUBJECT
check "with no segmenter on the server a subject is refused" py "
import json; e=json.load(open('$OUT/subject-alone.json')).get('error') or {}; assert e.get('code')=='unsupported_parameter', e"
gaea plugins add https://github.com/xocialize-code/gaea-plugin-forge >> $LOG 2>&1
matte subject $SUBJECT
check "with the Forge pack beside it, a subject runs: the segmenter is a helper and $MODEL makes the matte" py "
import json; j=json.load(open('$OUT/subject.json')); r=j['result']; h=[x for x in r['provenance'].get('helpers', []) if x.get('role')=='subject']
assert j['outcome']=='succeeded' and r['provenance']['model']['id']=='$MODEL' and h and r['effective'].get('subject'), j"

for f in $H/Logs/sessions/*.gpp(N); do check "transcript ${f:t} passes validate.py" python3 tools/validate.py --transcript "$f"; cp $f $OUT/; done
gaea ledger >> $LOG 2>&1
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
