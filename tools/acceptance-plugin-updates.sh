#!/bin/zsh
# AB-T-0418's acceptance (G4 order 6, PLG-4 on real releases): every plugin from its previous GitHub release, updated
# through `gaea plugins update` to its release on mlx-engine-swift 0.73.1, then a job on each.
#
#   tools/acceptance-plugin-updates.sh            (APP=dist/Gaea.app by default)
#
#   1. all 22 plugins install at their previous release, and `gaea plugins check` finds each one's new release;
#   2. Z-Image is updated while it runs a job: the update waits, and the switch happens when the job ends;
#   3. the other 21 update at once; each keeps the version it replaced, and the new bundle links 0.73.1's volume probe
#      (its worker imports mincore and msync; the manifest's engine contract is 1.58.0);
#   4. `gaea plugins rollback` goes back to the previous release and, run again, forward to the new one;
#   5. one job on each plugin runs on the new version (the research five on the research store, LTX's tier opted in
#      and its licence accepted);
#   6. every recorded GPP session passes the validator.
set -uo pipefail
cd ${0:A:h:h}
APP=${APP:-dist/Gaea.app}
GAEA=$APP/Contents/MacOS/Gaea; CLI=$APP/Contents/Helpers/gaea
OUT=${OUT:-Docs/Evidence/AB-T-0418}; mkdir -p "$OUT/jobs"
LOG=$OUT/acceptance-updates.log; : > "$LOG"
WORK=$(mktemp -d /tmp/gaea-upd.XXXX)
H=$WORK/h; P=17783
DEV=${0:A:h:h:h}
RESEARCH_ROOT=${RESEARCH_ROOT:-/Volumes/DEV_VOL1/Models/gaea-research-store}
# plugin → previous release, new release
typeset -A OLD NEW
for spec in demo:0.3.2:0.3.3 z-image:0.1.0:0.1.2 flux2-klein:0.2.1:0.2.3 qwen-image:0.2.0:0.2.1 boogu:0.1.0:0.1.1 \
            ming-image:0.3.0:0.3.1 forge:0.2.0:0.2.1 prompt-enhance:0.1.0:0.1.1 mage-vl:0.1.0:0.1.1 kokoro:0.1.0:0.1.1 \
            qwen3-tts:0.2.0:0.2.1 step-audio-editx:0.1.0:0.1.1 moss-soundeffect:0.1.1:0.1.2 ace-step:0.1.0:0.1.1 \
            rife:0.1.0:0.1.1 seedvr2:0.1.0:0.1.1 ltx:0.1.1:0.1.2 mage-flow:0.1.0:0.1.1 sensenova:0.1.0:0.1.1 \
            moss-image:0.1.0:0.1.1 qwen-image-21:0.1.0:0.1.1 flux3-klein:0.1.0:0.1.1; do
  p=${spec%%:*}; OLD[$p]=${${spec#*:}%%:*}; NEW[$p]=${spec##*:}
done
PLUGINS=(${(k)OLD}); PLUGINS=(${(o)PLUGINS})
RESEARCH=(mage-flow sensenova moss-image qwen-image-21 flux3-klein)
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
py() { python3 -c "$1" }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
submit() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
settle() { # job id → prints the settled job
  local j
  for _ in {1..360}; do
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
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: $2" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
start() {
  GAEA_HOME=$H "$GAEA" --headless --port $P --no-advertise >> "$H.out" 2>&1 &
  for _ in {1..50}; do [[ -S $H/operator.sock ]] && return; sleep 0.2; done
  say "Gaea didn't start:"; cat "$H.out" >> "$LOG"
}
gaea() { print -r -- "\$ gaea $*" >> "$LOG"; GAEA_HOME=$H $CLI "$@" 2>&1 | tee -a "$LOG" }
row() { # plugin, python expression over p (its row in `gaea plugins --json`) → exit 0 if true
  GAEA_HOME=$H $CLI plugins --json | py "import json,sys; p = next(p for p in json.load(sys.stdin) if p['id'] == 'com.xocialize.gaea.$1'); ok = $2; print(p) if not ok else None; sys.exit(0 if ok else 1)"
}
linked() { # plugin, version → the worker imports 0.73.1's probe calls, and the manifest names contract 1.58.0
  local dir=$H/Plugins/com.xocialize.gaea.$1/$2 exe
  exe=$(print -r -- $dir/*.gaeaplugin/Contents/MacOS/*(.N[1]))
  [[ -n $exe ]] || { print "no bundle in $dir"; return 1 }
  local imports=$(nm -u "$exe") # held, not piped to grep -q: under pipefail nm's SIGPIPE fails the check
  grep -qx '_mincore' <<< $imports && grep -qx '_msync' <<< $imports \
    && py "import json,glob; m = json.load(open(glob.glob('$dir/*.gaeaplugin/Contents/Resources/manifest.json')[0])); print(m['engine']); assert m['engine']['contract'] == '1.58.0'"
}
ran() { # file, plugin → the job succeeded on the plugin's new version
  # A helper's result (the prompt enhancer) names no plugin version; its worker's session transcript, named by version, does.
  local sessions=($H/logs/sessions/com.xocialize.gaea.$2-${NEW[$2]}-*.gpp(N))
  py "
import json
j = json.load(open('$1')); r = j.get('result') or {}
assert j.get('outcome') == 'succeeded', j
w = (r.get('effective') or {}).get('model_params', {}).get('x-gaea.worker') or {}
v = w.get('version') or (r.get('provenance') or {}).get('model', {}).get('revision')
print(r.get('provenance', {}).get('model'), w.get('lane'), v)
assert v == '${NEW[$2]}' or (v is None and ${#sessions} > 0), v"
}
cleanup() { pkill -TERM -f "^$GAEA --headless --port $P" 2>/dev/null; true }
trap cleanup EXIT

say "# Plugin updates (AB-T-0418) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), 22 plugins from GitHub"
say "host: $(sysctl -n hw.model), macOS $(sw_vers -productVersion); GAEA_HOME $H"
unset GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API GAEA_UNTRUST_OWN_TEAM GAEA_DEMO_TRAP_SEED GAEA_UNWIRED
# GitHub allows 60 API calls an hour without a token, fewer than 22 plugins added, checked and updated need, and it can
# serve an anonymous caller a stale release list. Gaea reads the token from its environment and never stores it.
export GAEA_GITHUB_TOKEN=${GAEA_GITHUB_TOKEN:-$(gh auth token)}
start

# 1. The previous releases, and the check.
for p in $PLUGINS; do
  check "$p ${OLD[$p]} installs from GitHub" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-$p ${OLD[$p]} | tee -a $LOG | grep -q '^Installed .* ${OLD[$p]} '"
done
gaea plugins check > /dev/null
for p in $PLUGINS; do
  check "gaea plugins check finds $p ${NEW[$p]}" row $p "p['version'] == '${OLD[$p]}' and p.get('latest') == '${NEW[$p]}'"
done

# 2. Z-Image, updated while it runs four 1024² images: the switch waits for the job.
id=$(submit '{"operation":"image.generate","model":"z-image-turbo","inputs":{"prompt":"a lighthouse at dusk"},"params":{"size":{"width":1024,"height":1024},"count":4,"seed":3}}' \
  | py 'import json,sys; print(json.load(sys.stdin)["id"])')
busy() { GAEA_HOME=$H $CLI ledger --json | py "import json,sys; sys.exit(0 if any(w['pluginID'] == 'com.xocialize.gaea.z-image' and w['busy'] for w in json.load(sys.stdin)['workers']) else 1)" }
for _ in {1..300}; do busy 2>/dev/null && break; sleep 0.2; done # the worker has the job, not only the queue
check "updating the busy Z-Image waits for its job" zsh -c "GAEA_HOME=$H $CLI plugins update com.xocialize.gaea.z-image | tee -a $LOG | grep -q 'Gaea switches to it when the plugin is idle'"
check "  and its row says so" row z-image "p['version'] == '${OLD[z-image]}' and p.get('pending') == '${NEW[z-image]}'"
settle $id > $OUT/jobs/z-image-during-update.json
check "  the job finishes on ${OLD[z-image]}" py "import json; j = json.load(open('$OUT/jobs/z-image-during-update.json')); w = j['result']['effective']['model_params']['x-gaea.worker']; assert j['outcome'] == 'succeeded' and w['version'] == '${OLD[z-image]}', w"
for _ in {1..25}; do row z-image "p['version'] == '${NEW[z-image]}'" >/dev/null 2>&1 && break; sleep 0.2; done
check "  then Z-Image runs ${NEW[z-image]}, keeping ${OLD[z-image]}" row z-image "p['version'] == '${NEW[z-image]}' and p.get('previous') == '${OLD[z-image]}' and p.get('pending') is None"

# 3. The other 21, at once.
for p in ${PLUGINS:#z-image}; do
  check "$p updates to ${NEW[$p]}" zsh -c "GAEA_HOME=$H $CLI plugins update com.xocialize.gaea.$p | tee -a $LOG | grep -q 'now runs ${NEW[$p]}'"
done
updated() { row $1 "p['version'] == '${NEW[$1]}' and p.get('previous') == '${OLD[$1]}' and p.get('latest') is None" && linked $1 ${NEW[$1]} }
for p in $PLUGINS; do
  check "$p ${NEW[$p]} keeps ${OLD[$p]}, and links mlx-engine-swift 0.73.1's probe" updated $p
done

# 4. Rollback, and forward again.
for p in $PLUGINS; do
  GAEA_HOME=$H $CLI plugins rollback com.xocialize.gaea.$p >> "$LOG" 2>&1
  check "$p rolls back to ${OLD[$p]}" row $p "p['version'] == '${OLD[$p]}' and p.get('previous') == '${NEW[$p]}'"
  GAEA_HOME=$H $CLI plugins rollback com.xocialize.gaea.$p >> "$LOG" 2>&1
  check "  and forward to ${NEW[$p]}" row $p "p['version'] == '${NEW[$p]}' and p.get('previous') == '${OLD[$p]}'"
done

# 5. A job on each, on the new version. Bodies from each plugin's own acceptance.
FOX=$DEV/gaea-plugin-forge/scripts/fixtures/fox-256.png
TAKE=$DEV/gaea-plugin-step-audio-editx/Tests/Fixtures/take.wav
CLIP=$DEV/gaea-plugin-rife/Tests/Fixtures/clip.mp4
gaea models enable ltx-2.5-compact24 > /dev/null
typeset -A BODY
BODY[demo]='{"operation":"image.generate","model":"demo-gradient","inputs":{"prompt":"a gradient"},"params":{"size":{"width":512,"height":512},"seed":1}}'
BODY[z-image]='{"operation":"image.generate","model":"z-image-turbo","inputs":{"prompt":"a lighthouse at dusk"},"params":{"size":{"width":512,"height":512},"seed":1}}'
BODY[flux2-klein]='{"operation":"image.generate","model":"klein-4b","params":{"size":{"width":512,"height":512},"seed":42,"prompt_enhance":"off"},"inputs":{"prompt":"a fox in the snow"}}'
BODY[qwen-image]='{"operation":"image.generate","model":"qwen-image-flash","inputs":{"prompt":"a red fox sitting in a snowy forest at sunrise, photorealistic"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
BODY[boogu]='{"operation":"image.generate","model":"boogu","inputs":{"prompt":"a lighthouse on a rocky coast at dusk, warm light in the windows, photorealistic"},"params":{"size":{"width":400,"height":400},"seed":1},"extensions":{"x-gaea.lane":"int4","x-boogu.steps":4}}'
BODY[ming-image]='{"operation":"image.generate","model":"ming-image","inputs":{"prompt":"a minimalist poster for a jazz festival, deep blue background, a gold saxophone"},"params":{"size":{"width":1024,"height":1024},"seed":42}}'
BODY[prompt-enhance]='{"operation":"image.enhance_prompt","inputs":{"prompt":"a fox in the snow"},"params":{"target_operation":"image.generate","target_model":"klein-4b","seed":42}}'
BODY[kokoro]='{"operation":"audio.speak","model":"kokoro-82m","inputs":{"text":"Hello from af_heart."},"params":{"voice":"af_heart","seed":1}}'
BODY[qwen3-tts]='{"operation":"audio.speak","model":"qwen3-tts","inputs":{"text":"Gaea speaks, from a plugin it just updated."},"params":{"voice":"ryan","seed":42}}'
BODY[moss-soundeffect]='{"operation":"audio.generate","model":"moss-soundeffect","inputs":{"prompt":"Rain on a tin roof, steady, with distant thunder."},"params":{"duration_s":1.5,"quality":"draft","seed":11}}'
BODY[ace-step]='{"operation":"audio.compose","model":"ace-step-1.5","inputs":{"caption":"Upbeat synth-pop with a bright female vocal and a driving beat.","lyrics":"[verse]\nLights on the water\nWe follow the line\n[chorus]\nRun all night\n"},"params":{"duration_s":10,"language":"en","seed":5}}'
BODY[ltx]='{"operation":"video.generate","model":"ltx-2.5-compact24","inputs":{"prompt":"A red kite flies over a green hill on a sunny day."},"params":{"size":{"width":256,"height":256},"duration_s":0.375,"seed":7,"audio":false},"policy":{"accepted":["LicenseRef-LTX-2-Community"]}}'
for p in ${PLUGINS:|RESEARCH}; do
  case $p in
    forge)            body='{"operation":"image.restore","model":"nafnet-restore","inputs":{"image":{"upload":"'$(upload $FOX image/png)'"}}}' ;;
    mage-vl)          body='{"operation":"image.describe","model":"mage-vl","inputs":{"image":{"upload":"'$(upload $FOX image/png)'"}}}' ;;
    step-audio-editx) body='{"operation":"audio.edit_speech","model":"step-audio-editx","inputs":{"audio":{"upload":"'$(upload $TAKE audio/wav)'"},"transcript":"We don'"'"'t have much time, so listen carefully to what I say."},"params":{"seed":42,"edit":{"kind":"emotion","emotion":"angry"}}}' ;;
    rife)             body='{"operation":"video.interpolate","model":"rife-4.25","inputs":{"video":{"upload":"'$(upload $CLIP video/mp4)'"}},"params":{"factor":2}}' ;;
    seedvr2)          body='{"operation":"video.upscale","model":"seedvr2-int8","inputs":{"video":{"upload":"'$(upload $CLIP video/mp4)'"}},"params":{"scale":2,"content":"live_action"}}' ;;
    *)                body=${BODY[$p]} ;;
  esac
  job "$body" > $OUT/jobs/$p.json
  check "a job on $p runs on ${NEW[$p]}" ran $OUT/jobs/$p.json $p
done

# The research five, on their store.
gaea models root $RESEARCH_ROOT > /dev/null
gaea models enable flux-3-klein > /dev/null; gaea models enable qwen-image-2.1 > /dev/null
BODY[mage-flow]='{"operation":"image.generate","model":"mage-flow-turbo","inputs":{"prompt":"a lighthouse on a rocky coast at dusk, photorealistic"},"params":{"size":{"width":512,"height":512},"seed":42}}'
BODY[sensenova]='{"operation":"image.generate","model":"sensenova-u1-fast","inputs":{"prompt":"a red fox in snow, photorealistic"},"params":{"size":{"width":512,"height":512},"seed":42,"prompt_enhance":"off"}}'
BODY[moss-image]='{"operation":"image.generate","model":"moss-image-base","inputs":{"prompt":"a red fox sitting in a snowy forest, photorealistic"},"params":{"size":{"width":512,"height":512},"seed":42,"prompt_enhance":"off"}}'
BODY[qwen-image-21]='{"operation":"image.generate","model":"qwen-image-2.1","inputs":{"prompt":"a glass teapot on a wooden table, studio light"},"params":{"size":{"width":512,"height":512},"seed":42}}'
BODY[flux3-klein]='{"operation":"image.generate","model":"flux-3-klein","inputs":{"prompt":"a vintage travel poster that reads \"GAEA\" above a turquoise bay with a white sailboat"},"params":{"size":{"width":512,"height":512},"seed":42}}'
for p in $RESEARCH; do
  job "${BODY[$p]}" > $OUT/jobs/$p.json
  check "a job on $p runs on ${NEW[$p]} (research store)" ran $OUT/jobs/$p.json $p
done
gaea models root default > /dev/null

# 6. The sessions.
for s in $H/logs/sessions/*.gpp(N); do
  check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"
done
gaea plugins > $OUT/plugins-after.txt
gaea crashes > $OUT/crashes-after.txt
cp $H/logs/gaea.log $OUT/gaea-updates.log 2>/dev/null
say ""
say "$pass passed, $fail failed"
(( fail == 0 ))
