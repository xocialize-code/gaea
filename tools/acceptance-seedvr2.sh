#!/bin/zsh
# AB-T-0403's acceptance: Gaea 0.10.1 serving MES Video 0.1's video.upscale (media-engine-spec v0.9.0) with
# gaea-plugin-seedvr2 (SeedVR2-3B) installed by repo URL.
#
#   1. video.upscale lists seedvr2-int8 (draft, standard) and seedvr2-fp16 (best): scales 2 and 4, both contents, no
#      seed, deterministic, 1920×1080 and 60 s;
#   2. ×2 on a 128×96, 17-frame, 24 fps clip with sound and a comment, no quality named: seedvr2-int8, 256×192, the
#      same 17 frames at exactly 24 fps, effective scale, the source's AAC track and comment kept (Video §1.7, §1.9),
#      and seedvr2-inproc's frames (decoded, byte for byte);
#   3. ×4: 512×384, 17 frames, seedvr2-inproc's frames;
#   4. quality: best runs on seedvr2-fp16 (seedvr2-inproc's fp16 frames); draft on seedvr2-int8;
#   5. a 320×180, 48-frame clip ×2: 640×360, 48 frames; output.codec h264 gives H.264;
#   6. refusals: no content is 400; scale 3 is refused; an output past 1920×1080 (1280×720 ×2) and a 61 s source
#      are 422 out_of_limits on video;
#   7. every recorded GPP session passes the validator.
#
#   tools/acceptance-seedvr2.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; ffmpeg and ffprobe; PLUGIN_DIST (default ../gaea-plugin-seedvr2/dist); SEEDVR2_INPROC (default:
# the plugin repo's release seedvr2-inproc, built with --build-system swiftbuild). REPO_FROM=github installs the
# published release instead of serving the dist folder through tools/release-standin.py. Both SeedVR2 weights must be
# in the models root.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=../gaea-plugin-seedvr2
PLUGIN_DIST=${PLUGIN_DIST:-$PLUGIN/dist}
CLIP=$PLUGIN/Tests/Fixtures/clip.mp4
INPROC=${SEEDVR2_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/seedvr2-inproc}
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
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $P"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $P" > /dev/null || return; sleep 0.2; done }
py() { python3 -c "$1" }
refused() { py "import json; e=json.load(open('$1')).get('error', {}); assert (e.get('code'), e.get('param')) == ('$3', '$4'), e" && grep -q "^$2\$" "$1.status" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: ${2:-video/mp4}" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
body() { # upload id, params JSON
  print -r -- '{"operation":"video.upscale","inputs":{"video":{"upload":"'$1'"}},"params":'$2'}'
}
# Each decoded frame's hash, in order (not its timestamps, which Gaea's retime changes).
frames() { ffmpeg -v error -i $1 -map 0:v -f framemd5 - | grep -v '^#' | awk -F', *' '{print $NF}' | shasum -a 256 | cut -c1-16 }
# The stream's own duration and frames (ffprobe's avg_frame_rate counts from the first decode time, which B-frames put
# before zero).
probe() { ffprobe -v error -count_frames -show_entries stream=codec_type,codec_name,nb_read_frames,r_frame_rate,duration,sample_rate,channels -show_entries format_tags=comment -of compact "$1" }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# SeedVR2 acceptance (AB-T-0403) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), seedvr2 $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
# The extra clips: a 1280×720 one (×2 is past 1920×1080) and a 61 s one.
ffmpeg -v error -y -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=0.25" -c:v libx264 -preset ultrafast -pix_fmt yuv420p $WORK/hd.mp4
ffmpeg -v error -y -f lavfi -i "testsrc2=size=128x96:rate=24:duration=61" -c:v libx264 -preset ultrafast -pix_fmt yuv420p $WORK/long.mp4
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-seedvr2/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/seedvr2-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/seedvr2-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8777 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8777
fi
H=$WORK/main; P=17695
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs seedvr2 $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-seedvr2 | grep -q 'Installed .* $VERSION'"

# 1. The offers.
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "video.upscale lists seedvr2-int8 (draft, standard) and seedvr2-fp16 (best): scales, contents, no seed, limits" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['video.upscale']; m = {x['id']: x for x in d['models']}; assert list(m) == ['seedvr2-int8', 'seedvr2-fp16'], m
assert m['seedvr2-int8']['quality_tiers'] == ['draft', 'standard'] and m['seedvr2-fp16']['quality_tiers'] == ['best'], m
for x in m.values():
    s = x['supports']; assert s['scales'] == [2, 4] and s['content'] == ['live_action', 'drawn'] and s['seed'] is False and s['deterministic'] is True, s
    l = x['limits']; assert (l['max_width'], l['max_height'], l['max_source_s']) == (1920, 1080, 60), l
i = {x['name']: x for x in d['inputs']}; assert i['video']['required'] and i['video']['kind'] == 'video', i
p = d['params']['properties']; assert 'scale' in p and 'content' in p and p['output']['properties']['codec']['enum'] == ['h264', 'hevc'], p"

# 2. ×2, with sound and a comment, no quality named.
t0=$(py 'import time; print(time.time())')
job "$(body $(upload $CLIP) '{"scale":2,"content":"live_action"}')" > "$OUT/job-x2.json"
say "      x2, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare, upscale, finish)"
fetch "$OUT/job-x2.json" "$OUT/gaea-x2.mp4"
probe "$OUT/gaea-x2.mp4" > "$OUT/gaea-x2.probe"
check "x2: seedvr2-int8, 256×192, 17 frames at 24 fps, with its sound's facts; effective scale, fps, size and frames" py "
import json; r = json.load(open('$OUT/job-x2.json'))['result']; o = r['outputs'][0]
assert r['provenance']['model']['id'] == 'seedvr2-int8', r['provenance']
assert (o['width'], o['height'], o['frames'], o['fps']) == (256, 192, 17, 24), o
assert abs(o['duration_s'] - 17 / 24) < 0.001 and (o['sample_rate'], o['channels']) == (48000, 2), o
e = r['effective']; assert e['scale'] == 2 and e['fps'] == 24 and e['frames'] == 17 and e['size'] == {'width': 256, 'height': 192}, e"
check "x2's file agrees: hevc 256×192, 17 frames at exactly 24/1, an AAC track at 48 kHz stereo" zsh -c "grep -q 'codec_name=hevc|codec_type=video|r_frame_rate=24/1|duration=0.708333|nb_read_frames=17' $OUT/gaea-x2.probe && grep -q 'codec_name=aac|codec_type=audio|sample_rate=48000|channels=2' $OUT/gaea-x2.probe && ffprobe -v error -show_entries stream=width,height -of csv=p=0 $OUT/gaea-x2.mp4 | grep -q '^256,192'"
check "x2 kept the source's comment (Video §1.9)" grep -q 'comment=Test clip for gaea-plugin-rife' "$OUT/gaea-x2.probe"

# 3. ×4.
job "$(body $(upload $CLIP) '{"scale":4,"content":"drawn"}')" > "$OUT/job-x4.json"
fetch "$OUT/job-x4.json" "$OUT/gaea-x4.mp4"
check "x4 (drawn): 512×384, 17 frames, effective scale 4" py "
import json; r = json.load(open('$OUT/job-x4.json'))['result']; o = r['outputs'][0]
assert (o['width'], o['height'], o['frames']) == (512, 384, 17) and r['effective']['scale'] == 4, r"

# 4. Quality tiers.
job "$(body $(upload $CLIP) '{"scale":2,"content":"live_action","quality":"best"}')" > "$OUT/job-best.json"
fetch "$OUT/job-best.json" "$OUT/gaea-best.mp4"
check "quality best runs on seedvr2-fp16: 256×192, 17 frames" py "
import json; r = json.load(open('$OUT/job-best.json'))['result']; o = r['outputs'][0]
assert r['provenance']['model']['id'] == 'seedvr2-fp16' and (o['width'], o['height'], o['frames']) == (256, 192, 17), r"
job "$(body $(upload $CLIP) '{"scale":2,"content":"live_action","quality":"draft"}')" > "$OUT/job-draft.json"
check "quality draft runs on seedvr2-int8" py "
import json; r = json.load(open('$OUT/job-draft.json'))['result']; assert r['provenance']['model']['id'] == 'seedvr2-int8', r['provenance']"

# 5. A longer, larger clip, and the codec.
job "$(body $(upload $PLUGIN/Tests/Fixtures/clip180.mp4) '{"scale":2,"content":"live_action"}')" > "$OUT/job-180p.json"
check "320×180, 48 frames ×2: 640×360, 48 frames at 24 fps" py "
import json; j = json.load(open('$OUT/job-180p.json')); assert j['outcome'] == 'succeeded', j; o = j['result']['outputs'][0]
assert (o['width'], o['height'], o['frames'], o['fps']) == (640, 360, 48, 24), o"
job "$(body $(upload $CLIP) '{"scale":2,"content":"live_action","output":{"media_type":"video/mp4","codec":"h264"}}')" > "$OUT/job-h264.json"
fetch "$OUT/job-h264.json" "$OUT/gaea-h264.mp4"
check "output.codec h264 gives H.264, still 17 frames with sound" zsh -c "probe() { ffprobe -v error -count_frames -show_entries stream=codec_name,nb_read_frames -of compact \$1 }; probe $OUT/gaea-h264.mp4 | grep -q 'codec_name=h264|nb_read_frames=17' && probe $OUT/gaea-h264.mp4 | grep -q 'codec_name=aac'"

# 6. Refusals.
U=$(upload $CLIP)
refuse "$(body $U '{"scale":2}')" "$WORK/r-nocontent.json"
check "no content is 400" zsh -c "grep -q '^400' $WORK/r-nocontent.json.status"
refuse "$(body $U '{"scale":3,"content":"live_action"}')" "$WORK/r-scale.json"
check "scale 3 is refused (4xx)" zsh -c "grep -q '^4' $WORK/r-scale.json.status"
job "$(body $(upload $WORK/hd.mp4) '{"scale":2,"content":"live_action"}')" > "$WORK/r-hd.json"
check "1280×720 ×2 (2560×1440) is 422 out_of_limits on video" py "
import json; j = json.load(open('$WORK/r-hd.json')); e = j.get('error', {}); assert (e.get('code'), e.get('param')) == ('out_of_limits', 'video'), j"
job "$(body $(upload $WORK/long.mp4) '{"scale":2,"content":"live_action"}')" > "$WORK/r-long.json"
check "a 61 s source is 422 out_of_limits on video" py "
import json; j = json.load(open('$WORK/r-long.json')); e = j.get('error', {}); assert (e.get('code'), e.get('param')) == ('out_of_limits', 'video'), j"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status 2>/dev/null) $(py "import json; j=json.load(open('$f')); e=j.get('error') or {}; print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:120])")"; done

$CLI ledger > "$OUT/ledger.txt"
stop

# The in-process side: the same frames.
"$INPROC" --video $CLIP --scale 2 --out "$OUT/inproc-x2.mp4" 2>> "$LOG" | tail -1 > "$OUT/inproc-x2.json"
"$INPROC" --video $CLIP --scale 4 --out "$OUT/inproc-x4.mp4" 2>> "$LOG" | tail -1 > /dev/null
"$INPROC" --video $CLIP --scale 2 --quant fp16 --out "$OUT/inproc-best.mp4" 2>> "$LOG" | tail -1 > /dev/null
check "x2's frames through Gaea are seedvr2-inproc's (decoded, byte for byte)" test "$(frames $OUT/gaea-x2.mp4)" = "$(frames $OUT/inproc-x2.mp4)"
check "x4's frames through Gaea are seedvr2-inproc's" test "$(frames $OUT/gaea-x4.mp4)" = "$(frames $OUT/inproc-x4.mp4)"
check "best's frames through Gaea are seedvr2-inproc's fp16 frames" test "$(frames $OUT/gaea-best.mp4)" = "$(frames $OUT/inproc-best.mp4)"
say "      in-process x2: $(cat "$OUT/inproc-x2.json")"
for n in x2 x4 best draft 180p h264; do say "      $n through Gaea: worker $(py "import json; print(json.load(open('$OUT/job-$n.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])") s"; done

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
