#!/bin/zsh
# magevl-probe.sh <local|github> <out-dir>: a probe, not a scripted acceptance (Gaea's tools have none for Mage-VL
# alone). gaea-plugin-mage-vl installed by repo URL in a throwaway Gaea 1.10.0, one image.describe through MES, and the
# worker's text compared with mage-vl-inproc on the same photo and the normalizer's describe question.
set -uo pipefail
src=$1; OUT=$2
S=${0:A:h}; DEV=/Volumes/Satechi/Development; G=$DEV/gaea-mes-media-server; R=$DEV/gaea-plugin-mage-vl
APP=/Volumes/DEV_VOL1/Evidence/gaea-1.10.0/released/app/Gaea.app
GAEA=$APP/Contents/MacOS/Gaea; CLI=$APP/Contents/Helpers/gaea
H=/tmp/gv$$; P=17695; V=${V:-0.1.2}
mkdir -p $OUT $H; LOG=$OUT/probe.log; : > $LOG
pass=0; fail=0
say() { print -r -- "$*" | tee -a $LOG }
check() { local name=$1; shift; if "$@" >> $LOG 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
say "# Mage-VL probe through Gaea $(defaults read $APP/Contents/Info CFBundleShortVersionString) $(date -u +%FT%TZ), source $src"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
sp=
if [[ $src == local ]]; then
  ROOT=$H.standin; rel=$ROOT/xocialize-code/gaea-plugin-mage-vl/v$V; mkdir -p $rel
  cp $R/dist/mage-vl-$V.gaeaplugin.zip $R/dist/mage-vl-$V.gaeaplugin.zip.sha256 $R/dist/manifest.json $rel/
  python3 $G/tools/release-standin.py $ROOT --port 8773 > $OUT/standin.out 2>&1 & sp=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8773
fi
GAEA_HOME=$H $GAEA --headless --port $P --no-advertise > $OUT/server.log 2>&1 & gp=$!
for _ in {1..50}; do [[ -S $H/operator.sock ]] && break; sleep 0.2; done
export GAEA_HOME=$H
check "add by repo URL installs mage-vl $V" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-mage-vl | tee -a $LOG | grep -q 'Installed .* $V '"
$CLI plugins list > $OUT/plugins.txt 2>&1; $CLI models > $OUT/models.txt 2>&1
mes http://127.0.0.1:$P/mes/v0/operations > $OUT/operations.json
check "image.describe is offered with mage-vl as its default" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
m = {x['id']: x for x in ops['image.describe']['models']}; print(m); assert m['mage-vl'].get('default') is True"
for photo in fox:$R/scripts/fixtures/fox-256.png face:$R/scripts/fixtures/face-512.png; do
  name=${photo%%:*}; file=${photo#*:}
  up=$(mes -X POST http://127.0.0.1:$P/mes/v0/uploads -H 'Content-Type: image/png' --data-binary @$file | py 'import json,sys; print(json.load(sys.stdin)["upload_id"])')
  id=$(mes -X POST http://127.0.0.1:$P/mes/v0/jobs -H 'Content-Type: application/json' -d '{"operation":"image.describe","inputs":{"image":{"upload":"'$up'"}}}' | tee $OUT/submit-$name.json | py 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  for _ in {1..60}; do
    mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10" > $OUT/job-$name.json
    py "import json,sys; sys.exit(0 if json.load(open('$OUT/job-$name.json')).get('state') in ('holding','purged') else 1)" && break
  done
  check "$name: image.describe succeeds on mage-vl $V with a caption, alt text and tags" py "
import json; j = json.load(open('$OUT/job-$name.json')); assert j.get('outcome') == 'succeeded', json.dumps(j)[:600]
r = j['result']; v = next(o['value'] for o in r['outputs'] if o['name'] == 'description'); print(json.dumps(v))
assert v['caption'] and v['alt_text'] and v['tags'], v
w = r['effective']['model_params']['x-gaea.worker']; print(w.get('plugin'), w.get('version'), w.get('lane'), w.get('seconds'))
assert r['provenance']['model']['id'] == 'mage-vl' and w['plugin'] == 'com.xocialize.gaea.mage-vl' and w['version'] == '$V'
open('$OUT/$name-worker-text.txt', 'w').write(next(o['value'] for o in w['outputs'] if o['name'] == 'text'))"
done
check "the worker's hello names mlx-engine-swift 0.83.0" zsh -c "grep -h '\"type\":\"hello\"' $H/Logs/sessions/*.gpp | tee -a $LOG | grep -q '\"version\":\"0.83.0\"'"
mkdir -p $OUT/sessions; cp $H/Logs/sessions/*.gpp $OUT/sessions/
kill -TERM $gp 2>/dev/null; sleep 2
# In-process, after Gaea has stopped: the same photo and the normalizer's describe question (the plugin's fixture of it).
# Gaea re-encodes the upload and removes the worker's inputs after the run, so the photo here is the fixture itself.
for name in fox face; do
  [[ -f $OUT/$name-worker-text.txt ]] || { fail=$((fail+1)); say "FAIL  $name: no worker text kept"; continue }
  $R/.build/release/mage-vl-inproc --image $R/scripts/fixtures/$([[ $name == fox ]] && print fox-256.png || print face-512.png) \
    --question-file $R/scripts/fixtures/describe-question.txt > $OUT/$name-inproc.json 2>> $LOG < /dev/null
  check "$name: the worker's text through Gaea is mage-vl-inproc's for the same photo and the describe question" py "
import json; a = open('$OUT/$name-worker-text.txt').read(); b = json.load(open('$OUT/$name-inproc.json'))['text']; print(a[:200]); assert a.strip() and a == b, b[:200]"
done
for s in $OUT/sessions/*.gpp; do check "transcript ${s:t} passes validate.py" python3 $G/tools/validate.py --transcript $s; done
say "== $pass passed, $fail failed"
[[ -n $sp ]] && kill $sp 2>/dev/null
rm -rf $H $H.standin
exit $(( fail > 0 ))
