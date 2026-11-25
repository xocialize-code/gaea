#!/bin/zsh
# AB-T-0482's acceptance: MES Mesh 0.1's mesh.generate_part through Gaea 1.7.0 with HairDeck (gaea-plugin-hairdeck).
#
#   1. The plugin by repo URL. The descriptor is Mesh 0.1's mesh.generate_part with one model, `hairdeck`: parts
#      [hair], subject_box required, physics, textures atlas and none, background removal, "Built with DINOv3".
#   2. A cut-out picture, a body and a box make a hair item:
#      - a GLB 2.0 and a 768² PNG preview with the disclosure and the attribution;
#      - marked ai_generated with the attribution in asset.copyright;
#      - effective: part, physics, texture, the box as sent, background alpha, and no placement or size;
#      - skinned to a joint named as the body's head bone, with VRMC_springBone;
#      - hairdeck-inproc's item: the BIN chunk byte for byte and every JSON member but `asset` (Gaea stamps the item
#        and never moves, scales or decimates it).
#   3. physics false has no springs, texture none no texture; each is hairdeck-inproc's.
#   4. An opaque JPEG runs as `remove` (BiRefNet) and is hairdeck-inproc's; a HEIC arrives upright as a PNG and runs
#      as `alpha`.
#   5. Refusals: no box, a box outside the picture, no body, a body that isn't a GLB, vertex colours, a part the
#      model doesn't make.
#   6. The item merges into the body with Item Studio's mergeVrm (MERGE, VRMMERGE, NODE_MODULES): one head bone, the
#      hair where the item put it; and, with a mergeVrm that carries an item's springs, its springs.
#   7. What the worker held, from Gaea's log; every recorded GPP session passes the validator.
#
#   tools/acceptance-hairdeck.sh <short-work-dir> <evidence-dir>
#
# Needs APP (default dist/Gaea.app, 1.7.0 or later), ../gaea-plugin-hairdeck with
# .build/out/Products/Release/hairdeck-inproc (or INPROC) and, for the stand-in, its dist/; BODY, a .vrm or rigged
# .glb; and MODELS (default /Volumes/DEV_VOL1/Models) holding xocialize/hairdeck-mlx, xocialize/trellis2-mlx's
# dino.safetensors and mlx-community/BiRefNet-fp16. REPO_FROM=github installs the published release instead of serving
# dist/ through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
HD=../gaea-plugin-hairdeck
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
INPROC=${INPROC:-$HD/.build/out/Products/Release/hairdeck-inproc}
PIC=${PIC:-$HD/Tests/Fixtures/girl.png}
BOX=${BOX:-'{"x":0.048,"y":0.03,"width":0.934,"height":0.941}'}
BODY=${BODY:?a .vrm or rigged .glb}
MERGE=${MERGE:-../mlxengine-3d/PROD/mlx-hairdeck-swift/tools/check_merged_vrm.mjs}
# Pass VRMMERGE=<vrmx-studio>/…/vrmMerge.js (9123c46 or later). This default, the copy in VRMXA_Specification, is older
# and drops an item's springs, so the two merge checks fail on it whatever the plugin did (AB-A-0333).
VRMMERGE=${VRMMERGE:-../VRMXA_Specification/reference/web/fitting/vrmMerge.js}
NODE_MODULES=${NODE_MODULES:-../vrmdeveloper/node_modules}
mkdir -p "$OUT"; OUT=${OUT:A}; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: $2" --data-binary @$1 | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
submit() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
job() { # json body, out file → the settled job
  local id j; id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  [[ -z $id ]] && { print -r -- '{"outcome":"refused"}' > "$2"; return }
  for _ in {1..120}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
  done
  print -r -- "$j" > "$2"
}
fetch() { # job file, output name, out path
  local href=$(py "import json; print([o for o in json.load(open('$1'))['result']['outputs'] if o['name']=='$2'][0]['href'])"); mes -o "$3" "http://127.0.0.1:$P$href"
}
part() { # name, picture, its media type, params JSON
  local up=$(upload $2 $3) body=$(upload $BODY model/gltf-binary)
  job '{"operation":"mesh.generate_part","inputs":{"image":{"upload":"'$up'"},"body":{"upload":"'$body'"}},"params":'$4'}' "$OUT/job-$1.json"
  if [[ $(py "import json; print(json.load(open('$OUT/job-$1.json')).get('outcome'))") == succeeded ]]; then
    fetch "$OUT/job-$1.json" mesh "$OUT/$1.glb"; fetch "$OUT/job-$1.json" preview "$OUT/$1-preview.png"
  fi
  say "      $1: $(py "import json; j=json.load(open('$OUT/job-$1.json')); r=j.get('result') or {}; w=(r.get('effective') or {}).get('model_params',{}).get('x-gaea.worker',{}); print(j.get('outcome'), (j.get('error') or {}).get('message',''), (r.get('provenance') or {}).get('model',{}).get('id'), w.get('seconds'), 's', [ (o['name'], o.get('vertices'), o.get('faces'), o.get('texture_size')) for o in r.get('outputs',[])])" 2>/dev/null)"
}
# pixels <picture>: the box in the picture's pixels as GaeaPluginKit makes it (left and top down, right and bottom up).
pixels() { python3 - "$(sips -g pixelWidth -g pixelHeight $1 | awk '/pixel/ {print $2}' | tr '\n' ' ')" "$BOX" <<'PYEOF'
import json, math, sys
w, h = map(int, sys.argv[1].split()); s = json.loads(sys.argv[2])
print(f"{math.floor(s['x']*w)},{math.floor(s['y']*h)},{min(w, math.ceil((s['x']+s['width'])*w))},{min(h, math.ceil((s['y']+s['height'])*h))}")
PYEOF
}
inproc() { # name, picture, extra flags…
  $INPROC --image $2 --box $(pixels $2) --body $BODY --seed 42 --models-root "$MODELS" --out $OUT/inproc-$1.glb "${@:3}" 2>> $LOG | tail -1 > $OUT/inproc-$1.json
}
# glbpy <glb> <python using g (the JSON), bin (the BIN chunk)>
glbpy() { python3 - "$1" "$2" <<'PYEOF'
import json, struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[:4] == b'glTF', 'not a GLB'
version, length = struct.unpack('<II', d[4:12])
chunks, i = [], 12
while i < length:
    n, t = struct.unpack('<I4s', d[i:i + 8]); chunks.append((t, d[i + 8:i + 8 + n])); i += 8 + n
g = json.loads(chunks[0][1]); bin = chunks[1][1] if len(chunks) > 1 else b''
exec(sys.argv[2])
PYEOF
}
same() { python3 - "$1" "$2" <<'PYEOF'
import json, struct, sys
def read(f):
    d = open(f, 'rb').read(); n = struct.unpack('<I', d[12:16])[0]
    return json.loads(d[20:20 + n]), d[20 + n + 8:]
(a, ab), (b, bb) = read(sys.argv[1]), read(sys.argv[2])
print(len(ab), len(bb)); assert ab.rstrip(b'\0') == bb.rstrip(b'\0'), 'BIN chunks differ'
for k in sorted(set(a) | set(b)):
    if k != 'asset': assert a.get(k) == b.get(k), k
print('asset:', a['asset'])
PYEOF
}
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise --models-root "$MODELS" "${@:3}" > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea at $1 didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $1" > /dev/null || return; sleep 0.2; done }

say "# HairDeck acceptance (AB-T-0482) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
say "picture ${PIC:t} $(pixels $PIC | tr ',' ' ' | awk '{print "box [" $1 ", " $2 ", " $3 ", " $4 "] px"}'), body ${BODY:t}"
unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
if [[ ${REPO_FROM:-} != github ]]; then
  V=$(py "import json; print(json.load(open('$HD/dist/manifest.json'))['version'])")
  REL=$WORK/standin/xocialize-code/gaea-plugin-hairdeck/v$V; mkdir -p "$REL"
  cp "$HD/dist/hairdeck-$V.gaeaplugin.zip" "$HD/dist/hairdeck-$V.gaeaplugin.zip.sha256" "$HD/dist/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8774 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8774
fi

# 1. The plugin and the descriptor.
H=$WORK/main; P=17684
start $H $P
check "add hairdeck by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-hairdeck | tee $OUT/plugins.txt | grep -q 'Installed '"
sed 's/^/      /' "$OUT/plugins.txt" | tee -a "$LOG"
GAEA_HOME=$H "$CLI" models > "$OUT/models.txt"; sed 's/^/      /' "$OUT/models.txt" | tee -a "$LOG"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "mesh.generate_part is Mesh 0.1 with hairdeck: hair, a required box, physics, atlas and none, background removal" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['mesh.generate_part']; assert d['profile'] == 'mesh' and d['profile_version'] == '0.1', d['profile']
assert [m['id'] for m in d['models']] == ['hairdeck']; m = d['models'][0]; s = m['supports']; print(s)
assert s['parts'] == ['hair'] and s['subject_box'] == 'required' and s['physics'] is True
assert s['textures'] == ['atlas', 'none'] and s['background_removal'] is True and s['seed'] is True
assert m['license']['attribution'] == 'Built with DINOv3'
assert [o['name'] for o in d['outputs']] == ['mesh', 'preview'] and d['outputs'][0]['kind'] == 'mesh'
assert 'mesh.generate' not in ops and 'mesh.rig' not in ops"

# 2. A cut-out picture.
P1='{"seed":42,"subject_box":'$BOX'}'
part hair $PIC image/png "$P1"
check "a cut-out picture, a body and a box make a hair item" py "
import json; j=json.load(open('$OUT/job-hair.json')); assert j['outcome'] == 'succeeded' and j['result']['provenance']['model']['id'] == 'hairdeck', j.get('error')"
check "the item is a GLB 2.0 by Mesh §1.1–1.2 (one JSON and one BIN chunk, triangles with normals)" glbpy $OUT/hair.glb "
assert version == 2 and [t for t, _ in chunks] == [b'JSON', b'BIN\x00'], [t for t, _ in chunks]
assert not g.get('extensionsRequired') and all('uri' not in b for b in g['buffers'])
for m in g['meshes']:
    for p in m['primitives']: assert p.get('mode', 4) == 4 and 'NORMAL' in p['attributes']"
check "it says AI-generated by HairDeck, with Built with DINOv3 in asset.copyright" glbpy $OUT/hair.glb "
mes = g['asset']['extras']['mes']; print(mes, g['asset'].get('copyright'))
assert mes['ai_generated'] is True and mes['model'] == 'HairDeck' and mes['attribution'] == 'Built with DINOv3'
assert g['asset']['copyright'].startswith('Built with DINOv3')"
check "effective: hair, physics, atlas, the box as sent, background alpha, seed 42; no placement or size" py "
import json; j=json.load(open('$OUT/job-hair.json')); r=j['result']; e=r['effective']; print(e)
for k, v in {'part': 'hair', 'physics': True, 'texture': 'atlas', 'background': 'alpha', 'subject_box': json.loads('$BOX')}.items():
    assert e.get(k) == v, (k, e.get(k))
assert r['provenance']['seed'] == 42 and 'placement' not in e and 'size_m' not in e and 'max_faces' not in e"
check "its facts agree with the file: vertices, faces, a texture" py "
import json; o=[o for o in json.load(open('$OUT/job-hair.json'))['result']['outputs'] if o['name']=='mesh'][0]; print(o)
assert o['media_type'] == 'model/gltf-binary' and o['vertices'] > 0 and o['faces'] > 0 and o.get('texture_size', 0) > 0"
python3 - $BODY > $OUT/body-head.txt <<'PYEOF'
import json, struct, sys
d = open(sys.argv[1], 'rb').read(); n = struct.unpack('<I', d[12:16])[0]; g = json.loads(d[20:20 + n])
e = g.get('extensions', {})
if 'VRMC_vrm' in e: i = e['VRMC_vrm']['humanoid']['humanBones']['head']['node']
else: i = [b['node'] for b in e['VRM']['humanoid']['humanBones'] if b['bone'] == 'head'][0]
print(g['nodes'][i]['name'])
PYEOF
check "it is skinned under a joint named as the body's head bone ($(cat $OUT/body-head.txt)), with spring bones" glbpy $OUT/hair.glb "
head = open('$OUT/body-head.txt').read().strip(); joints = [g['nodes'][j].get('name') for s in g['skins'] for j in s['joints']]
springs = g['extensions']['VRMC_springBone']['springs']; print(len(joints), 'joints,', len(springs), 'springs')
assert head in joints and len(springs) > 0
assert all('JOINTS_0' in p['attributes'] and 'WEIGHTS_0' in p['attributes'] for m in g['meshes'] for p in m['primitives'])"
check "the preview is a 768² PNG with the disclosure and the attribution" python3 tools/png-facts.py $OUT/hair-preview.png --size 768 --comment 'AI-generated with HairDeck' --copyright 'Built with DINOv3'
check "the preview's corners are transparent" python3 tools/png-facts.py $OUT/hair-preview.png --transparent-corners
part again $PIC image/png "$P1"
check "the same seed gives the same item" same $OUT/hair.glb $OUT/again.glb
for i in 1 2 3; do part warm$i $PIC image/png "$P1"; done
say "      warm run_ms: $(for n in again warm1 warm2 warm3; do py "import json; print(json.load(open('$OUT/job-$n.json'))['result']['provenance']['timings']['run_ms'])"; done | tr '\n' ' ')"

if [[ -x $INPROC ]]; then
  inproc hair $PIC
  check "the item is hairdeck-inproc's: the BIN chunk byte for byte, every JSON member but asset" same $OUT/hair.glb $OUT/inproc-hair.glb
else
  say "SKIP  in-process comparisons: no $INPROC"
fi

# 3. Without springs, without a texture.
part still $PIC image/png '{"seed":42,"subject_box":'$BOX',"physics":false}'
check "physics false: no spring bones, effective says so" glbpy $OUT/still.glb "
import json as J; e = J.load(open('$OUT/job-still.json'))['result']['effective']
assert 'VRMC_springBone' not in g.get('extensions', {}) and e['physics'] is False, e"
part plain $PIC image/png '{"seed":42,"subject_box":'$BOX',"texture":"none"}'
check "texture none: no texture, effective says so" glbpy $OUT/plain.glb "
import json as J; j = J.load(open('$OUT/job-plain.json'))['result']; o = [o for o in j['outputs'] if o['name'] == 'mesh'][0]
assert not g.get('textures') and not g.get('images') and j['effective']['texture'] == 'none' and not o.get('texture_size'), o"
if [[ -x $INPROC ]]; then
  inproc still $PIC --no-physics; check "physics false is hairdeck-inproc's --no-physics" same $OUT/still.glb $OUT/inproc-still.glb
  inproc plain $PIC --no-texture; check "texture none is hairdeck-inproc's --no-texture" same $OUT/plain.glb $OUT/inproc-plain.glb
fi

# 4. An opaque picture, and one Gaea converts.
python3 - $PIC $OUT/opaque.ppm <<'PYEOF'
import struct, sys, zlib
d = open(sys.argv[1], 'rb').read(); i, idat = 8, b''
while i < len(d):
    n, t = struct.unpack('>I4s', d[i:i + 8]); body = d[i + 8:i + 8 + n]; i += 12 + n
    if t == b'IHDR': w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
    elif t == b'IDAT': idat += body
assert depth == 8 and ctype == 6, 'an 8-bit RGBA PNG'
raw = zlib.decompress(idat); stride = w * 4; prev = bytearray(stride); out = bytearray()
for y in range(h):
    f = raw[y * (stride + 1)]; line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
    for x in range(stride):
        a = line[x - 4] if x >= 4 else 0; b = prev[x]; c = prev[x - 4] if x >= 4 else 0
        if f == 1: line[x] = (line[x] + a) & 255
        elif f == 2: line[x] = (line[x] + b) & 255
        elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
        elif f == 4:
            p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    prev = line
    for x in range(w):
        r, g, b, a = line[x * 4:x * 4 + 4]
        out += bytes(((v * a + 255 * (255 - a)) // 255) for v in (r, g, b))     # on white
open(sys.argv[2], 'wb').write(b'P6\n%d %d\n255\n' % (w, h) + bytes(out))
PYEOF
sips -s format jpeg -s formatOptions 95 $OUT/opaque.ppm --out $OUT/opaque.jpg >> $LOG 2>&1; rm -f $OUT/opaque.ppm
part opaque $OUT/opaque.jpg image/jpeg "$P1"
check "an opaque JPEG is cut out (background remove) and makes an item" py "
import json; j=json.load(open('$OUT/job-opaque.json')); assert j['outcome'] == 'succeeded' and j['result']['effective']['background'] == 'remove', (j.get('error'), j.get('result', {}).get('effective'))"
if [[ -x $INPROC ]]; then
  inproc opaque $OUT/opaque.jpg; check "the opaque picture's item is hairdeck-inproc's (BiRefNet as the matte)" same $OUT/opaque.glb $OUT/inproc-opaque.glb
fi
sips -s format heic $PIC --out $OUT/cutout.heic >> $LOG 2>&1
part heic $OUT/cutout.heic image/heic "$P1"
check "a HEIC with transparency arrives upright as a PNG and runs as alpha" py "
import json; j=json.load(open('$OUT/job-heic.json')); assert j['outcome'] == 'succeeded' and j['result']['effective']['background'] == 'alpha', (j.get('error'), j.get('result', {}).get('effective'))"

# 5. Refusals.
UP=$(upload $PIC image/png); UB=$(upload $BODY model/gltf-binary); UX=$(upload $PIC image/png)
IN='"inputs":{"image":{"upload":"'$UP'"},"body":{"upload":"'$UB'"}}'
refuse() { # name, body, statuses wanted
  submit "$2" "$OUT/refuse-$1.json"; local got=$(cat $OUT/refuse-$1.json.status)
  say "      $1: $got $(py "import json; e=json.load(open('$OUT/refuse-$1.json')).get('error', {}); print(e.get('code'), '|', e.get('message'))" 2>/dev/null)"
  check "refused: $1 ($3)" zsh -c "[[ ' $3 ' == *' $got '* ]]"
}
refuse no-box '{"operation":"mesh.generate_part",'$IN',"params":{"seed":1}}' "400 422"
refuse box-outside '{"operation":"mesh.generate_part",'$IN',"params":{"subject_box":{"x":0.5,"y":0.5,"width":0.8,"height":0.2}}}' "400"
refuse box-empty '{"operation":"mesh.generate_part",'$IN',"params":{"subject_box":{"x":0.2,"y":0.2,"width":0,"height":0.2}}}' "400"
refuse no-body '{"operation":"mesh.generate_part","inputs":{"image":{"upload":"'$UP'"}},"params":{"subject_box":'$BOX'}}' "400 422"
refuse vertex-colours '{"operation":"mesh.generate_part",'$IN',"params":{"subject_box":'$BOX',"texture":"vertex_colors"}}' "422"
refuse part-clothing '{"operation":"mesh.generate_part",'$IN',"params":{"subject_box":'$BOX',"part":"clothing"}}' "400 422"
refuse a-generate '{"operation":"mesh.generate","inputs":{"image":{"upload":"'$UP'"}},"params":{}}' "404 422"
job '{"operation":"mesh.generate_part","inputs":{"image":{"upload":"'$UP'"},"body":{"upload":"'$UX'"}},"params":{"subject_box":'$BOX'}}' "$OUT/job-body-png.json"
say "      body-png: $(py "import json; j=json.load(open('$OUT/job-body-png.json')); print(j.get('outcome'), j.get('error'))")"
check "a body that isn't a GLB is refused or fails as input_invalid, and nothing is made" py "
import json; j=json.load(open('$OUT/job-body-png.json')); assert j.get('outcome') in ('refused', 'failed'), j.get('outcome')
assert j['outcome'] == 'refused' or j['error']['code'] == 'input_invalid', j['error']"

# 6. The client's step: the item merged into the body.
if [[ -f $MERGE && -f $VRMMERGE && -d $NODE_MODULES ]]; then
  NODE_MODULES=${NODE_MODULES:A} node $MERGE $VRMMERGE $BODY $OUT/hair.glb $OUT/merged.vrm > $OUT/merge.txt 2>> $LOG
  sed 's/^/      /' $OUT/merge.txt | tr -s ' \n' ' ' | tee -a "$LOG"; print | tee -a "$LOG"
  check "mergeVrm takes the item into the body: one head bone, the chains intact, the hair where the item put it" py "
import json; t = open('$OUT/merge.txt').read(); m = json.loads(t[:t.rindex('}') + 1])
assert m['report']['parts'] == 1 and m['headBonesNamedLikeItem'] == 1 and m['hairChainsIntact'] and m['restPositionError_m'] < 1e-4 and not m['nan'], m"
  check "and carries its springs: the merged file has the body's and the item's, and the hair swings" py "
import json; t = open('$OUT/merge.txt').read(); m = json.loads(t[:t.rindex('}') + 1]); print(m)
assert m['springsMerged'] == m['springsBody'] + m['springsItem'] and m['hairSprings'] == m['springsItem'] and m['peakEndLag_m'] > 0.005, 'springs not carried'"
  check "and the hair settles: the tool's own verdict (within 1 cm of rest 5 s after the head turns, from 12f24cd)" py "
t = open('$OUT/merge.txt').read(); assert 'CHECK PASSED' in t, t[t.rindex('}') - 80:]"
  [[ ${KEEP_MERGED:-0} == 1 ]] || rm -f $OUT/merged.vrm
else
  say "SKIP  the merge: no $MERGE, $VRMMERGE or $NODE_MODULES"
fi

# 7. Memory and the sessions.
GAEA_HOME=$H "$CLI" models > "$OUT/models-after.txt"
grep -h -E "starting|held|budget" $H/Logs/*.log $H.out 2>/dev/null | sort -u > "$OUT/memory.txt"; sed 's/^/      /' "$OUT/memory.txt" | tee -a "$LOG"
check "the worker held no more than its lane declares, BiRefNet included (no 'held … past' in Gaea's log)" zsh -c "! grep -q 'held .* past' '$OUT/memory.txt'"
stop $P
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
