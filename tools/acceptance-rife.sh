#!/bin/zsh
# AB-T-0401's and AB-T-0402's acceptance: Gaea 0.10.0 serving MES Video 0.1 (media-engine-spec v0.9.0) with
# gaea-plugin-rife (RIFE 4.25) installed by repo URL, on video.interpolate.
#
#   1. the handshake lists video/0.1, and video.interpolate lists rife-4.25 with its limits;
#   2. factor 2 on a 128×96, 17-frame, 24 fps clip with sound and a comment: 33 frames at exactly 48 fps, the facts
#      reported and agreeing with the file, the source's AAC track and comment kept (Video §1.7, §1.9), and the frames
#      rife-inproc's (decoded, byte for byte);
#   3. factor 4: 65 frames at exactly 96 fps (Gaea retimes the package's 1/600 time base), rife-inproc's frames;
#   4. fps: 48 gives factor 2 with no warning; 60 gives the nearest factor, 3 (72 fps), with fps_adjusted;
#   5. output.codec h264 gives H.264; a ProRes QuickTime input is converted and accepted;
#   6. refusals: factor 9 and a 301 s or 4096-pixel-wide source are 422 out_of_limits; factor with fps is 400;
#   7. every recorded GPP session passes the validator.
#
#   tools/acceptance-rife.sh <short-work-dir> <evidence-dir>
#
# Needs: dist/Gaea.app; ffmpeg and ffprobe; PLUGIN_DIST (default ../gaea-plugin-rife/dist); RIFE_INPROC (default: the
# plugin repo's release rife-inproc, built with --build-system swiftbuild). REPO_FROM=github installs the published
# release instead of serving the dist folder through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=../gaea-plugin-rife
PLUGIN_DIST=${PLUGIN_DIST:-$PLUGIN/dist}
CLIP=$PLUGIN/Tests/Fixtures/clip.mp4
INPROC=${RIFE_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/rife-inproc}
rm -rf "$OUT" "$WORK"; mkdir -p "$OUT" "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
post() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
settle() {
  local j
  for _ in {1..90}; do
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
  print -r -- '{"operation":"video.interpolate","inputs":{"video":{"upload":"'$1'"}},"params":'$2'}'
}
# Each decoded frame's hash, in order (not its timestamps, which Gaea's retime changes).
frames() { ffmpeg -v error -i $1 -map 0:v -f framemd5 - | grep -v '^#' | awk -F', *' '{print $NF}' | shasum -a 256 | cut -c1-16 }
# The stream's own duration and frames (ffprobe's avg_frame_rate counts from the first decode time, which B-frames put
# before zero).
probe() { ffprobe -v error -count_frames -show_entries stream=codec_type,codec_name,nb_read_frames,r_frame_rate,duration,sample_rate,channels -show_entries format_tags=comment -of compact "$1" }

VERSION=$(py "import json; print(json.load(open('$PLUGIN_DIST/manifest.json'))['version'])")
say "# RIFE acceptance (AB-T-0401, AB-T-0402) $(date -u +%FT%TZ) — Gaea $(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null), rife $VERSION, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
# The extra clips: a ProRes QuickTime of the fixture, a 301 s clip, and a 4096-pixel-wide one.
ffmpeg -v error -y -i $CLIP -c:v prores_ks -profile:v 2 -c:a pcm_s16le $WORK/prores.mov
ffmpeg -v error -y -f lavfi -i "testsrc2=size=128x96:rate=24:duration=301" -c:v libx264 -preset ultrafast -pix_fmt yuv420p $WORK/long.mp4
ffmpeg -v error -y -f lavfi -i "testsrc2=size=4096x2304:rate=24:duration=0.25" -c:v libx264 -preset ultrafast -pix_fmt yuv420p $WORK/wide.mp4
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  REL=$WORK/standin/xocialize-code/gaea-plugin-rife/v$VERSION; mkdir -p "$REL"
  cp "$PLUGIN_DIST/rife-$VERSION.gaeaplugin.zip" "$PLUGIN_DIST/rife-$VERSION.gaeaplugin.zip.sha256" "$PLUGIN_DIST/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8777 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8777
fi
H=$WORK/main; P=17694
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs rife $VERSION" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-rife | grep -q 'Installed .* $VERSION'"

# 1. The handshake and the offer.
mes "http://127.0.0.1:$P/mes/v0/engine" > "$OUT/engine.json"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "the handshake lists video 0.1" py "
import json; e = json.load(open('$OUT/engine.json')); p = e['profiles']
assert {'id': 'video', 'versions': ['0.1']} in p, p"
check "video.interpolate lists rife-4.25: max_factor 8, 4K, 300 s, no seed, deterministic" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['video.interpolate']; m = d['models']; assert [x['id'] for x in m] == ['rife-4.25'], m
l = m[0]['limits']; assert (l['max_factor'], l['max_width'], l['max_height'], l['max_source_s']) == (8, 3840, 2160, 300), l
s = m[0]['supports']; assert s['seed'] is False and s['deterministic'] is True, s
i = {x['name']: x for x in d['inputs']}; assert i['video']['required'] and i['video']['kind'] == 'video', i
p = d['params']['properties']; assert 'factor' in p and 'fps' in p and p['output']['properties']['codec']['enum'] == ['h264', 'hevc'], p
assert [o['name'] for o in d['outputs']] == ['video'], d['outputs']"

# 2. Factor 2, with sound and a comment.
t0=$(py 'import time; print(time.time())')
job "$(body $(upload $CLIP) '{"factor":2}')" > "$OUT/job-x2.json"
say "      x2, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare, interpolate, finish)"
fetch "$OUT/job-x2.json" "$OUT/gaea-x2.mp4"
probe "$OUT/gaea-x2.mp4" > "$OUT/gaea-x2.probe"
check "x2: 33 frames at 48 fps, 128×96, with its sound's facts; effective factor, fps, size and frames" py "
import json; r = json.load(open('$OUT/job-x2.json'))['result']; o = r['outputs'][0]
assert r['provenance']['model']['id'] == 'rife-4.25', r['provenance']
assert (o['width'], o['height'], o['frames'], o['fps']) == (128, 96, 33, 48), o
assert abs(o['duration_s'] - 33 / 48) < 0.001 and (o['sample_rate'], o['channels']) == (48000, 2), o
e = r['effective']; assert e['factor'] == 2 and e['fps'] == 48 and e['frames'] == 33 and e['size'] == {'width': 128, 'height': 96}, e"
check "x2's file agrees: hevc 33 frames at exactly 48/1, an AAC track at 48 kHz stereo" zsh -c "grep -q 'codec_name=hevc|codec_type=video|r_frame_rate=48/1|duration=0.687500|nb_read_frames=33' $OUT/gaea-x2.probe && grep -q 'codec_name=aac|codec_type=audio|sample_rate=48000|channels=2' $OUT/gaea-x2.probe"
check "x2 kept the source's comment (Video §1.9)" grep -q 'comment=Test clip for gaea-plugin-rife' "$OUT/gaea-x2.probe"

# 3. Factor 4: retimed to exactly 96 fps.
job "$(body $(upload $CLIP) '{"factor":4}')" > "$OUT/job-x4.json"
fetch "$OUT/job-x4.json" "$OUT/gaea-x4.mp4"
probe "$OUT/gaea-x4.mp4" > "$OUT/gaea-x4.probe"
check "x4: 65 frames at exactly 96 fps (Gaea retimed the 1/600 time base)" zsh -c "grep -q 'r_frame_rate=96/1|duration=0.677083|nb_read_frames=65' $OUT/gaea-x4.probe"

# 4. fps.
job "$(body $(upload $CLIP) '{"fps":48}')" > "$OUT/job-fps48.json"
check "fps 48 is factor 2, with no warning" py "
import json; j = json.load(open('$OUT/job-fps48.json')); assert j['outcome'] == 'succeeded', j
assert j['result']['effective']['factor'] == 2 and not [w for w in j.get('warnings', []) if w['code'] == 'fps_adjusted'], j"
job "$(body $(upload $CLIP) '{"fps":60}')" > "$OUT/job-fps60.json"
check "fps 60 is the nearest factor, 3 (72 fps), with fps_adjusted" py "
import json; j = json.load(open('$OUT/job-fps60.json')); assert j['outcome'] == 'succeeded', j
o = j['result']['outputs'][0]; assert j['result']['effective']['factor'] == 3 and o['fps'] == 72 and o['frames'] == 49, o
assert 'fps_adjusted' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"

# 5. Codec and container.
job "$(body $(upload $CLIP) '{"factor":2,"output":{"media_type":"video/mp4","codec":"h264"}}')" > "$OUT/job-h264.json"
fetch "$OUT/job-h264.json" "$OUT/gaea-h264.mp4"
check "output.codec h264 gives H.264, still 33 frames with sound" zsh -c "probe() { ffprobe -v error -count_frames -show_entries stream=codec_name,nb_read_frames -of compact \$1 }; probe $OUT/gaea-h264.mp4 | grep -q 'codec_name=h264|nb_read_frames=33' && probe $OUT/gaea-h264.mp4 | grep -q 'codec_name=aac'"
job "$(body $(upload $WORK/prores.mov video/quicktime) '{"factor":2}')" > "$OUT/job-prores.json"
check "a ProRes QuickTime input is converted and accepted: 33 frames" py "
import json; j = json.load(open('$OUT/job-prores.json')); assert j['outcome'] == 'succeeded', j; assert j['result']['outputs'][0]['frames'] == 33, j"

# 6. Refusals.
U=$(upload $CLIP)
refuse "$(body $U '{"factor":9}')" "$WORK/r-factor.json"
check "factor 9 is 422" zsh -c "grep -q '^422' $WORK/r-factor.json.status"
refuse "$(body $U '{"factor":2,"fps":48}')" "$WORK/r-both.json"
check "factor with fps is 400" zsh -c "grep -q '^400' $WORK/r-both.json.status"
job "$(body $(upload $WORK/long.mp4) '{"factor":2}')" > "$WORK/r-long.json"
check "a 301 s source is 422 out_of_limits on video" py "
import json; j = json.load(open('$WORK/r-long.json')); e = j.get('error', {}); assert (e.get('code'), e.get('param')) == ('out_of_limits', 'video'), j"
job "$(body $(upload $WORK/wide.mp4) '{"factor":2}')" > "$WORK/r-wide.json"
check "a 4096-pixel-wide source is 422 out_of_limits on video" py "
import json; j = json.load(open('$WORK/r-wide.json')); e = j.get('error', {}); assert (e.get('code'), e.get('param')) == ('out_of_limits', 'video'), j"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status 2>/dev/null) $(py "import json; j=json.load(open('$f')); e=j.get('error') or {}; print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:100])")"; done

$CLI ledger > "$OUT/ledger.txt"
stop

# The in-process side: the same frames.
"$INPROC" --video $CLIP --factor 2 --out "$OUT/inproc-x2.mp4" 2>> "$LOG" | tail -1 > "$OUT/inproc-x2.json"
"$INPROC" --video $CLIP --factor 4 --out "$OUT/inproc-x4.mp4" 2>> "$LOG" | tail -1 > /dev/null
check "x2's frames through Gaea are rife-inproc's (decoded, byte for byte)" test "$(frames $OUT/gaea-x2.mp4)" = "$(frames $OUT/inproc-x2.mp4)"
check "x4's frames through Gaea, retimed, are rife-inproc's" test "$(frames $OUT/gaea-x4.mp4)" = "$(frames $OUT/inproc-x4.mp4)"
say "      in-process x2: $(cat "$OUT/inproc-x2.json")"
for n in x2 x4 h264 prores; do say "      $n through Gaea: worker $(py "import json; print(json.load(open('$OUT/job-$n.json'))['result']['effective']['model_params']['x-gaea.worker']['seconds'])") s"; done

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
