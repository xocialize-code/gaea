#!/bin/zsh
# AB-T-0404's acceptance: Gaea 0.11.0 serving MES Video 0.1's video.generate, video.extend and video.retake
# (media-engine-spec v0.9.0) with gaea-plugin-ltx (LTX 2.5) installed by repo URL.
#
#   1. the four tiers are opt-in (accepted_required): nothing is offered until the operator enables them, and each
#      enabled tier is an offer of all three operations, with the licence, its quality tiers, supports and limits;
#   2. users' acceptance: a named tier without policy.accepted is 422 policy_unmet (terms_not_accepted);
#   3. generate on compact24 (quality draft, no model named), 256×256, 9 frames, seed 7: the facts, 48 kHz stereo
#      sound, the AI-generated comment item, the seed, and ltx-inproc's frames (decoded, byte for byte);
#   4. snapping: 250×260 for 1 s is 256×256 and 25 frames, with size_snapped and duration_snapped; audio: false is
#      silent; a first frame on compact24; past its 512×288 conditioned envelope is 422 out_of_limits;
#   5. two stages: quality standard with a last frame routes to standard64; a keyframe; a soundtrack sets the clip's
#      length and is the clip's sound, with soundtrack_fitted;
#   6. extend by 1/3 s and retake 0.4–0.7 s of a 128×96, 17-frame clip with sound and a comment: 25 and 17 frames at
#      the source's size, the span widened with span_snapped, the source's comment followed by the disclosure;
#   7. refusals: a retake past the clip, a source off the 8k + 1 grid, 10 s on compact24, keyframes on compact24;
#   8. every recorded GPP session passes the validator.
#
#   tools/acceptance-ltx.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; ffmpeg and ffprobe; LTX 2.5's weights in Gaea's models root (MODELS_ROOT, default DEV_VOL1's
# models folder, passed as --models-root); PLUGIN_DIST (default ../gaea-plugin-ltx/dist); LTX_INPROC (default: the
# plugin repo's release ltx-inproc). REPO_FROM=github installs the published release instead of serving the dist
# folder through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=../gaea-plugin-ltx
PLUGIN_DIST=${PLUGIN_DIST:-$PLUGIN/dist}
F=$PLUGIN/Tests/Fixtures
CLIP=$F/clip.mp4
MODELS=${MODELS_ROOT:-/Volumes/DEV_VOL1/Models/Models}
INPROC=${LTX_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/ltx-inproc}
PROMPT="A red kite flies over a green hill on a sunny day."
SPDX=LicenseRef-LTX-2-Community
rm -rf "$OUT" "$WORK"; mkdir -p "$OUT" "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
post() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
settle() {
  local j
  for _ in {1..360}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$1?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
job() { local r id; r=$(post "$1"); id=$(print -r -- "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))'); [[ -n $id ]] && settle $id || print -r -- "$r" }
fetch() { # job file, out file: the video output
  local href=$(python3 -c "import json,sys; print(next(o['href'] for o in json.load(open(sys.argv[1]))['result']['outputs'] if o['name'] == 'video'))" "$1")
  mes -o "$2" "http://127.0.0.1:$P$href"
}
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise --models-root "$MODELS" > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || return; sleep 0.2; done }
py() { python3 -c "$1" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: ${2:-video/mp4}" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
# body <operation> <inputs JSON, without the prompt> <params JSON> [model] [accepted: yes|no]
body() {
  python3 -c "import json,sys; i=json.loads(sys.argv[2]); i['prompt']=sys.argv[6]; b={'operation':sys.argv[1],'inputs':i,'params':json.loads(sys.argv[3])}
m=sys.argv[4]; b.update({'model':m} if m else {}); b.update({'policy':{'accepted':['$SPDX']}} if sys.argv[5]=='yes' else {})
print(json.dumps(b))" "$1" "$2" "$3" "${4:-}" "${5:-yes}" "$PROMPT"
}
# The job's error code and param, or "succeeded".
outcome() { py "import json; j=json.load(open('$1')); e=j.get('error') or {}; print('succeeded' if j.get('outcome')=='succeeded' else f\"{e.get('code')} {e.get('param')}\")" }
frames() { ffmpeg -v error -i $1 -map 0:v -f framemd5 - | grep -v '^#' | awk -F', *' '{print $NF}' | shasum -a 256 | cut -c1-16 }
probe() { ffprobe -v error -count_frames -show_entries stream=codec_type,codec_name,width,height,nb_read_frames,r_frame_rate,sample_rate,channels -show_entries format_tags=comment -of compact "$1" }
warnings() { py "import json; print(' '.join(w['code'] for w in json.load(open('$1')).get('warnings', [])))" }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# LTX acceptance (AB-T-0404) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), ltx $VERSION, source ${REPO_FROM:-stand-in}, models $MODELS"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
# The extra media: a 1 s soundtrack, a 24-frame clip (off the 8k + 1 grid).
ffmpeg -v error -y -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=1" -ac 2 $WORK/tone.wav
ffmpeg -v error -y -f lavfi -i "testsrc2=size=128x96:rate=24:duration=1" -c:v libx264 -pix_fmt yuv420p $WORK/off-grid.mp4
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-ltx/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/ltx-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/ltx-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8777 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8777
fi
H=$WORK/main; P=17696
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs ltx $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-ltx | grep -q 'Installed .* $VERSION'"

# 1. Opt-in, then the offers.
$CLI models list > "$OUT/models-before.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations-before.json"
check "the four tiers start off: the operator accepts the LTX-2 Community licence by enabling them" py "
import json; lines = [l for l in open('$OUT/models-before.txt') if 'ltx-2.5-' in l]; assert len(lines) == 4 and all(l.startswith('off') for l in lines), lines
ops = {o['operation'] for o in json.load(open('$OUT/operations-before.json'))['operations']}; assert not ops & {'video.generate', 'video.extend', 'video.retake'}, ops"
for t in compact24 balanced32 standard64 max128; do $CLI models enable ltx-2.5-$t >> "$LOG" 2>&1; done
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "enabled, each tier is an offer of generate, extend and retake, with the licence, tiers, supports and limits" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
ids = ['ltx-2.5-compact24', 'ltx-2.5-balanced32', 'ltx-2.5-standard64', 'ltx-2.5-max128']
for op in ['video.generate', 'video.extend', 'video.retake']:
    m = {x['id']: x for x in ops[op]['models']}; assert list(m) == ids, (op, list(m))
    for x in m.values():
        l = x['license']; assert l['spdx'] == '$SPDX' and l['user_accept_required'] is True and l['accepted_required'] is True and l['notice'], l
        s = x['supports']; assert s['audio'] and (s['sample_rate'], s['channels']) == (48000, 2) and s['frame_step'] == {'multiple': 8, 'offset': 1}, s
g = {x['id']: x for x in ops['video.generate']['models']}
assert [g[i]['quality_tiers'] for i in ids] == [['draft'], ['draft', 'standard'], ['standard', 'best'], ['best']]
assert [g[i]['limits']['max_width'] for i in ids] == [704, 576, 1280, 1920] and [g[i]['limits']['max_frames'] for i in ids] == [121, 161, 161, 481]
assert [g[i]['supports']['keyframes'] for i in ids] == [False, False, True, True] and [g[i]['supports']['deterministic'] for i in ids] == [False, False, False, True]
assert {x['id']: x['limits']['max_width'] for x in ops['video.retake']['models']}['ltx-2.5-compact24'] == 512"

# 2. Users' acceptance.
G='{"size":{"width":256,"height":256},"duration_s":0.375,"seed":7}'
refuse "$(body video.generate '{}' $G ltx-2.5-compact24 no)" "$WORK/r-terms.json"
check "a named tier without policy.accepted is 422 policy_unmet, terms_not_accepted" py "
import json; e = json.load(open('$WORK/r-terms.json'))['error']; assert (e['code'], e.get('reason')) == ('policy_unmet', 'terms_not_accepted'), e
assert open('$WORK/r-terms.json.status').read().strip() == '422'"

# 3. Generate, no model named, quality draft.
t0=$(py 'import time; print(time.time())')
job "$(body video.generate '{}' '{"size":{"width":256,"height":256},"duration_s":0.375,"seed":7,"quality":"draft"}')" > "$OUT/job-generate.json"
say "      generate, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare, generate, finish)"
fetch "$OUT/job-generate.json" "$OUT/gaea-generate.mp4"
probe "$OUT/gaea-generate.mp4" > "$OUT/gaea-generate.probe"
check "generate: compact24, 256×256, 9 frames at 24 fps with 48 kHz stereo sound; effective seed, size, frames" py "
import json; r = json.load(open('$OUT/job-generate.json'))['result']; o = r['outputs'][0]
assert r['provenance']['model']['id'] == 'ltx-2.5-compact24', r['provenance']
assert (o['width'], o['height'], o['frames'], o['fps'], o['sample_rate'], o['channels']) == (256, 256, 9, 24, 48000, 2), o
e = r['effective']; assert e['seed'] == 7 and e['frames'] == 9 and e['size'] == {'width': 256, 'height': 256}, e"
check "generate's file says it is AI-generated (Video §1.9), in H.264 at exactly 24/1" zsh -c "grep -q 'comment=AI-generated by LTX 2.5 (compact24)' $OUT/gaea-generate.probe && grep -q 'codec_name=h264|codec_type=video|width=256|height=256|r_frame_rate=24/1|nb_read_frames=9' $OUT/gaea-generate.probe"

# 4. Snapping, silence, a first frame.
job "$(body video.generate '{}' '{"size":{"width":250,"height":260},"duration_s":1,"seed":7}' ltx-2.5-compact24)" > "$OUT/job-snapped.json"
check "250×260 for 1 s is 256×256 and 25 frames, with size_snapped and duration_snapped" py "
import json; j = json.load(open('$OUT/job-snapped.json')); o = j['result']['outputs'][0]
assert (o['width'], o['height'], o['frames']) == (256, 256, 25), o
codes = [w['code'] for w in j.get('warnings', [])]; assert 'size_snapped' in codes and 'duration_snapped' in codes, codes"
job "$(body video.generate '{}' '{"size":{"width":256,"height":256},"duration_s":0.375,"seed":7,"audio":false}' ltx-2.5-compact24)" > "$OUT/job-silent.json"
fetch "$OUT/job-silent.json" "$OUT/gaea-silent.mp4"
check "audio: false gives a silent clip, still marked" zsh -c "! ffprobe -v error -show_entries stream=codec_type -of csv=p=0 $OUT/gaea-silent.mp4 | grep -q audio && ffprobe -v error -show_entries format_tags=comment -of csv=p=0 $OUT/gaea-silent.mp4 | grep -q AI-generated"
UF=$(upload $F/kite-first.png image/png)
job "$(body video.generate '{"first_frame":{"upload":"'$UF'"}}' '{"size":{"width":256,"height":256},"duration_s":0.375,"seed":7}' ltx-2.5-compact24)" > "$OUT/job-first.json"
check "a first frame on compact24: 256×256, 9 frames" py "
import json; j = json.load(open('$OUT/job-first.json')); o = j['result']['outputs'][0]; assert (o['width'], o['height'], o['frames']) == (256, 256, 9), j"
job "$(body video.generate '{"first_frame":{"upload":"'$(upload $F/kite-first.png image/png)'"}}' '{"size":{"width":704,"height":512}}' ltx-2.5-compact24)" > "$WORK/r-conditioned.json"
check "a first frame past compact24's 512×288 conditioned envelope is out_of_limits" zsh -c "[[ '$(outcome $WORK/r-conditioned.json)' == 'out_of_limits first_frame' ]]"

# 5. Two stages: a last frame routes to standard64; a keyframe; a soundtrack.
job "$(body video.generate '{"first_frame":{"upload":"'$(upload $F/kite-first.png image/png)'"},"last_frame":{"upload":"'$(upload $F/kite-last.png image/png)'"}}' '{"size":{"width":256,"height":256},"duration_s":0.7083,"seed":7,"quality":"standard"}')" > "$OUT/job-last.json"
check "quality standard with a last frame runs on standard64 (two stages): 256×256, 17 frames" py "
import json; r = json.load(open('$OUT/job-last.json'))['result']; o = r['outputs'][0]
assert r['provenance']['model']['id'] == 'ltx-2.5-standard64' and (o['width'], o['height'], o['frames']) == (256, 256, 17), r"
job "$(body video.generate '{"keyframes":[{"upload":"'$(upload $F/kite-last.png image/png)'"}]}' '{"size":{"width":256,"height":256},"duration_s":0.7083,"keyframe_times":[0.34],"seed":7}' ltx-2.5-standard64)" > "$OUT/job-keyframe.json"
check "a keyframe at 0.34 s on standard64: placed on frame 8 (0.333 s), 17 frames" py "
import json; r = json.load(open('$OUT/job-keyframe.json'))['result']; assert r['outputs'][0]['frames'] == 17, r
assert abs(r['effective']['keyframe_times'][0] - 8 / 24) < 1e-6, r['effective']"
job "$(body video.generate '{"soundtrack":{"upload":"'$(upload $WORK/tone.wav audio/wav)'"}}' '{"size":{"width":256,"height":256},"seed":7}' ltx-2.5-standard64)" > "$OUT/job-soundtrack.json"
fetch "$OUT/job-soundtrack.json" "$OUT/gaea-soundtrack.mp4"
check "a 1 s soundtrack sets the clip to 25 frames (1.042 s) with soundtrack_fitted, and is its sound" py "
import json; j = json.load(open('$OUT/job-soundtrack.json')); o = j['result']['outputs'][0]
assert o['frames'] == 25 and (o['sample_rate'], o['channels']) == (48000, 2), o
assert 'soundtrack_fitted' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"

# 6. Extend and retake a clip with sound and a comment.
job "$(body video.extend '{"video":{"upload":"'$(upload $CLIP)'"}}' '{"after_s":0.3333,"seed":7}' ltx-2.5-compact24)" > "$OUT/job-extend.json"
fetch "$OUT/job-extend.json" "$OUT/gaea-extend.mp4"
probe "$OUT/gaea-extend.mp4" > "$OUT/gaea-extend.probe"
check "extend by 1/3 s: 128×96, 25 frames at 24 fps with sound, effective after_s" py "
import json; r = json.load(open('$OUT/job-extend.json'))['result']; o = r['outputs'][0]
assert (o['width'], o['height'], o['frames'], o['fps'], o['sample_rate']) == (128, 96, 25, 24, 48000), o
assert abs(r['effective']['after_s'] - 8 / 24) < 1e-6, r['effective']"
check "extend kept the source's comment and added the disclosure" grep -q 'comment=Test clip for gaea-plugin-rife — AI-generated in part by LTX 2.5 (compact24)' "$OUT/gaea-extend.probe"
job "$(body video.retake '{"video":{"upload":"'$(upload $CLIP)'"}}' '{"start_s":0.4,"end_s":0.7,"seed":7}' ltx-2.5-compact24)" > "$OUT/job-retake.json"
fetch "$OUT/job-retake.json" "$OUT/gaea-retake.mp4"
check "retake 0.4–0.7 s: 17 frames at the source's size, the span widened to 0.375–0.708 s with span_snapped, both remade" py "
import json; j = json.load(open('$OUT/job-retake.json')); r = j['result']; o = r['outputs'][0]
assert (o['width'], o['height'], o['frames']) == (128, 96, 17), o
e = r['effective']; assert abs(e['start_s'] - 9 / 24) < 1e-6 and abs(e['end_s'] - 17 / 24) < 1e-6 and e['retake'] == 'both', e
assert 'span_snapped' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"

# 7. Refusals.
U=$(upload $CLIP)
job "$(body video.retake '{"video":{"upload":"'$U'"}}' '{"start_s":0.4,"end_s":0.9}' ltx-2.5-compact24)" > "$WORK/r-span.json"
check "a retake past the clip's end is out_of_limits on end_s" zsh -c "[[ '$(outcome $WORK/r-span.json)' == 'out_of_limits end_s' ]]"
job "$(body video.extend '{"video":{"upload":"'$(upload $WORK/off-grid.mp4)'"}}' '{"after_s":0.3333}' ltx-2.5-compact24)" > "$WORK/r-grid.json"
check "a 24-frame source (off the 8k + 1 grid) is input_invalid on video" zsh -c "[[ '$(outcome $WORK/r-grid.json)' == 'input_invalid video' ]]"
refuse "$(body video.generate '{}' '{"duration_s":10,"fps":24}' ltx-2.5-compact24)" "$WORK/r-long.json"
check "10 s on compact24 is 422" zsh -c "grep -q '^422' $WORK/r-long.json.status"
refuse "$(body video.generate '{"keyframes":[{"upload":"'$(upload $F/kite-last.png image/png)'"}]}' '{"duration_s":0.7083,"keyframe_times":[0.34]}' ltx-2.5-compact24)" "$WORK/r-keyframes.json"
check "keyframes to compact24, which doesn't take them, is 422 unsupported_parameter" zsh -c "grep -q '^422' $WORK/r-keyframes.json.status && grep -q unsupported_parameter $WORK/r-keyframes.json"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status 2>/dev/null) $(py "import json; j=json.load(open('$f')); e=j.get('error') or {}; print(e.get('code'), e.get('param'), e.get('reason') or '', '-', (e.get('message') or '')[:140])")"; done
say "      warnings: snapped [$(warnings $OUT/job-snapped.json)], soundtrack [$(warnings $OUT/job-soundtrack.json)], retake [$(warnings $OUT/job-retake.json)]"

$CLI ledger > "$OUT/ledger.txt"
stop

# The in-process side: the same frames.
"$INPROC" --tier compact24 --prompt "$PROMPT" --params '{"size":{"width":256,"height":256},"duration_s":0.375}' --seed 7 \
  --models-root "$MODELS" --out "$OUT/inproc-generate.mp4" 2>> "$LOG" | tail -1 > "$OUT/inproc-generate.json"
check "generate's frames through Gaea are ltx-inproc's (decoded, byte for byte)" test "$(frames $OUT/gaea-generate.mp4)" = "$(frames $OUT/inproc-generate.mp4)"
say "      in-process generate: $(cat "$OUT/inproc-generate.json")"
for n in generate snapped silent first last keyframe soundtrack extend retake; do say "      $n through Gaea: worker $(py "import json; print(json.load(open('$OUT/job-$n.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])") s"; done

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
