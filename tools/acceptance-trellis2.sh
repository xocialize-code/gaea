#!/bin/zsh
# AB-T-0467's acceptance: MES Mesh 0.1's mesh.generate through Gaea 1.4.0 with TRELLIS.2 (gaea-plugin-trellis2), and the
# operator's tier controls.
#
#   1. The plugin by repo URL. The descriptor is Mesh 0.1's mesh.generate with three models (512 draft and standard,
#      1024 best, 1536 by resolution), the licence's "Built with DINOv3", and GET /health's idle policy.
#   2. A default request (no quality) runs trellis2-512 on the fox photo, background removed. The result:
#      - a GLB 2.0 and a 768² PNG preview, transparent at its corners, its Comment saying AI-generated with the model and
#        its Copyright the attribution;
#      - the GLB marked ai_generated with the attribution in asset.copyright, centred and 1 m long;
#      - its facts (vertices, faces ≤ max_faces, bounds, texture_size) agreeing with the file, its effective values,
#        prepare_ms on the first job;
#      - the same geometry and texture as trellis2-inproc's, byte for byte (Gaea adds a placement node and the
#        disclosure, and keeps the model's buffers).
#   3. The fox already cut out runs as `alpha`; `background: keep` as `keep`; grounded at 1.8 m stands on Y = 0.
#   4. Refusals: vertex colours, an unlisted texture size, a resolution no offer lists, fewer faces than min_faces.
#   5. A preview server: with trellis2-1024 and -1536 disabled the descriptor offers draft and standard only, and best is
#      refused; with the budget at 51.54 GB (--budget-bytes) only trellis2-512 is offered.
#   6. FULL=1: best runs trellis2-1024, and resolution 1536 runs trellis2-1536.
#   7. Every recorded GPP session passes the validator.
#
#   tools/acceptance-trellis2.sh <short-work-dir> <evidence-dir>
#
# Needs APP (default dist/Gaea.app, 1.4.0 or later), ../gaea-plugin-trellis2 with its dist/ and
# .build/out/Products/Release/trellis2-inproc (or INPROC), and MODELS (default /Volumes/DEV_VOL1/Models) holding
# xocialize/trellis2-mlx and mlx-community/BiRefNet-fp16. REPO_FROM=github installs the published release instead of
# serving dist/ through tools/release-standin.py.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
T2=../gaea-plugin-trellis2
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models}
INPROC=${INPROC:-$T2/.build/out/Products/Release/trellis2-inproc}
FOX=$T2/Tests/Fixtures/fox.png; CUT=$T2/Tests/Fixtures/fox-cutout.png
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
py() { python3 -c "$1" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H 'Content-Type: image/png' --data-binary @$1 | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
submit() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
job() { # json body, out file → the settled job
  local id j; id=$(mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  [[ -z $id ]] && { print -r -- '{"outcome":"refused"}' > "$2"; return }
  for _ in {1..400}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$id?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && break
  done
  print -r -- "$j" > "$2"
}
fetch() { # job file, output name, out path
  local href=$(py "import json; print([o for o in json.load(open('$1'))['result']['outputs'] if o['name']=='$2'][0]['href'])"); mes -o "$3" "http://127.0.0.1:$P$href"
}
mesh() { # name, image file, params JSON, [model]
  local up=$(upload $2) model=""; [[ -n ${4:-} ]] && model='"model":"'$4'",'
  job '{"operation":"mesh.generate",'$model'"inputs":{"image":{"upload":"'$up'"}},"params":'$3'}' "$OUT/job-$1.json"
  if [[ $(py "import json; print(json.load(open('$OUT/job-$1.json')).get('outcome'))") == succeeded ]]; then
    fetch "$OUT/job-$1.json" mesh "$OUT/$1.glb"; fetch "$OUT/job-$1.json" preview "$OUT/$1-preview.png"
  fi
  say "      $1: $(py "import json; j=json.load(open('$OUT/job-$1.json')); r=j.get('result') or {}; w=(r.get('effective') or {}).get('model_params',{}).get('x-gaea.worker',{}); print(j.get('outcome'), (r.get('provenance') or {}).get('model',{}).get('id'), w.get('seconds'), 's', [ (o['name'], o.get('faces'), o.get('texture_size')) for o in r.get('outputs',[])])" 2>/dev/null)"
}
# glbpy <glb> <python using g (the JSON), bin (the BIN chunk), facts…>
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
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise --models-root "$MODELS" "${@:3}" > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea at $1 didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1"; for _ in {1..100}; do pgrep -f "$GAEA --headless --port $1" > /dev/null || return; sleep 0.2; done }

V=$(py "import json; print(json.load(open('$T2/dist/manifest.json'))['version'])")
say "# TRELLIS.2 acceptance (AB-T-0467) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString 2>/dev/null), trellis2 $V, source ${REPO_FROM:-stand-in}"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
if [[ ${REPO_FROM:-} != github ]]; then
  unset GAEA_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
  REL=$WORK/standin/xocialize-code/gaea-plugin-trellis2/v$V; mkdir -p "$REL"
  cp "$T2/dist/trellis2-$V.gaeaplugin.zip" "$T2/dist/trellis2-$V.gaeaplugin.zip.sha256" "$T2/dist/manifest.json" "$REL/"
  python3 tools/release-standin.py "$WORK/standin" --port 8773 > "$WORK/standin.out" 2>&1 &
  STANDIN=$!; sleep 1
  export GAEA_GITHUB_API=http://127.0.0.1:8773
fi

# 1. The plugin, the descriptor, /health.
H=$WORK/main; P=17674
start $H $P
check "add trellis2 $V by repo URL" zsh -c "GAEA_HOME=$H $CLI plugins add https://github.com/xocialize-code/gaea-plugin-trellis2 | tee $OUT/plugins.txt | grep -q 'Installed .* $V'"
GAEA_HOME=$H "$CLI" models > "$OUT/models.txt"; sed 's/^/      /' "$OUT/models.txt" | tee -a "$LOG"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "mesh.generate is Mesh 0.1 with the three TRELLIS.2 models and their tiers" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
d = ops['mesh.generate']; assert d['profile'] == 'mesh' and d['profile_version'] == '0.1', d['profile']
models = {m['id']: m for m in d['models']}; print(sorted(models)); assert sorted(models) == ['trellis2-1024', 'trellis2-1536', 'trellis2-512']
assert models['trellis2-512']['quality_tiers'] == ['draft', 'standard'] and models['trellis2-1024']['quality_tiers'] == ['best']
assert models['trellis2-1536']['supports']['resolutions'] == [1536]
assert all(m['license']['attribution'] == 'Built with DINOv3' for m in models.values())
assert sorted(d['quality_tiers']) == ['best', 'draft', 'standard']
assert [o['name'] for o in d['outputs']] == ['mesh', 'preview'] and d['outputs'][0]['kind'] == 'mesh'"
mes "http://127.0.0.1:$P/mes/v0/health" > "$OUT/health-before.json"
check "GET /health states the idle policy (900 s)" py "import json; h=json.load(open('$OUT/health-before.json')); print(h); assert h['memory']['idle_unload_s'] == 900"

# 2. The default request.
mesh fox $FOX '{"seed":42,"max_faces":20000,"texture_size":512}'
check "a request with no quality runs trellis2-512 and succeeds" py "
import json; j=json.load(open('$OUT/job-fox.json')); assert j['outcome'] == 'succeeded' and j['result']['provenance']['model']['id'] == 'trellis2-512', j.get('error')"
check "the mesh is a GLB 2.0 by Mesh §1.1–1.2 (one JSON and one BIN chunk, triangles with normals, Y up)" glbpy $OUT/fox.glb "
assert version == 2 and [t for t, _ in chunks] == [b'JSON', b'BIN\x00'], [t for t, _ in chunks]
assert not g.get('extensionsRequired') and all('uri' not in b for b in g['buffers'])
for m in g['meshes']:
    for p in m['primitives']: assert p.get('mode', 4) == 4 and 'NORMAL' in p['attributes'] and 'TEXCOORD_0' in p['attributes']"
check "it says AI-generated by TRELLIS.2 512, with Built with DINOv3 in asset.copyright" glbpy $OUT/fox.glb "
mes = g['asset']['extras']['mes']; print(mes, g['asset'].get('copyright'))
assert mes['ai_generated'] is True and mes['model'] == 'TRELLIS.2 512' and mes['attribution'] == 'Built with DINOv3'
assert g['asset']['copyright'].startswith('Built with DINOv3')"
check "its facts agree with the file: faces ≤ 20,000, a 512 texture, centred, 1 m long" py "
import json; j=json.load(open('$OUT/job-fox.json')); o=[o for o in j['result']['outputs'] if o['name']=='mesh'][0]; print(o)
assert o['media_type'] == 'model/gltf-binary' and 0 < o['faces'] <= 20000 and o['texture_size'] == 512 and o['vertices'] > 0
b = o['bounds']; ext = [hi - lo for lo, hi in zip(b['min'], b['max'])]; c = [(lo + hi) / 2 for lo, hi in zip(b['min'], b['max'])]
assert abs(max(ext) - 1) < 1e-4 and all(abs(x) < 1e-4 for x in c), (ext, c)"
check "effective: seed 42, 20,000 faces, atlas at 512, background removed, resolution 512, centred, 1 m; prepare_ms" py "
import json; j=json.load(open('$OUT/job-fox.json')); r=j['result']; e=r['effective']; print(e, r['provenance']['timings'])
for k, v in {'max_faces': 20000, 'texture': 'atlas', 'texture_size': 512, 'background': 'remove', 'resolution': 512, 'placement': 'centered', 'size_m': 1}.items():
    assert e.get(k) == v, (k, e.get(k))
assert r['provenance']['seed'] == 42 and r['provenance']['timings'].get('prepare_ms', 0) > 0"
check "the preview is a 768² PNG of the object on transparent, with the disclosure and the attribution" python3 tools/png-facts.py $OUT/fox-preview.png --size 768 --comment 'AI-generated with TRELLIS.2 512' --copyright 'Built with DINOv3'
check "the preview's corners are transparent and its middle isn't" python3 tools/png-facts.py $OUT/fox-preview.png --transparent-corners --opaque-centre
mes "http://127.0.0.1:$P/mes/v0/health" > "$OUT/health-after.json"
check "after the job, /health says when trellis2-512 will be unloaded" py "import json; h=json.load(open('$OUT/health-after.json')); print(h.get('resident_until')); assert 'trellis2-512' in (h.get('resident_until') or {})"

# The same picture in-process: the model's buffers must be the same bytes.
if [[ -x $INPROC ]]; then
  $INPROC --image $FOX --tier 512 --seed 42 --faces 20000 --texture-size 512 --background remove --models-root "$MODELS" --out $OUT/inproc-fox.glb > $OUT/inproc-fox.json 2>> $LOG
  check "the geometry and texture are trellis2-inproc's, byte for byte" python3 - $OUT/fox.glb $OUT/inproc-fox.glb <<'PYEOF'
import json, struct, sys
def read(f):
    d = open(f, 'rb').read(); n = struct.unpack('<I', d[12:16])[0]
    g = json.loads(d[20:20 + n]); b = d[20 + n + 8:]
    return g, b
(a, ab), (b, bb) = read(sys.argv[1]), read(sys.argv[2])
print(len(ab), len(bb)); assert ab[:len(bb)].rstrip(b'\0') == bb.rstrip(b'\0') or ab == bb, 'BIN chunks differ'
for k in ('meshes', 'accessors', 'bufferViews', 'materials', 'textures', 'images'):
    assert a.get(k) == b.get(k), k
PYEOF
else
  say "SKIP  in-process comparison: no $INPROC"
fi

# 3. Alpha, keep, grounded.
mesh cut $CUT '{"seed":42,"max_faces":20000,"texture_size":512}'
check "a picture with transparency runs as alpha (already cut out)" py "import json; e=json.load(open('$OUT/job-cut.json'))['result']['effective']; assert e['background'] == 'alpha', e"
mesh keep $FOX '{"seed":42,"max_faces":20000,"texture_size":512,"background":"keep"}'
check "background: keep runs as keep" py "import json; e=json.load(open('$OUT/job-keep.json'))['result']['effective']; assert e['background'] == 'keep', e"
mesh ground $FOX '{"seed":42,"max_faces":20000,"texture_size":512,"placement":"grounded","size_m":1.8}'
check "grounded at 1.8 m stands on Y = 0 and is 1.8 m long" py "
import json; o=[o for o in json.load(open('$OUT/job-ground.json'))['result']['outputs'] if o['name']=='mesh'][0]; b=o['bounds']
ext = [hi - lo for lo, hi in zip(b['min'], b['max'])]; print(b); assert abs(b['min'][1]) < 1e-4 and abs(max(ext) - 1.8) < 1e-4"
check "the same seed gives the same model buffers (deterministic)" python3 - $OUT/fox.glb $OUT/ground.glb <<'PYEOF'
import json, struct, sys
def bin(f):
    d = open(f, 'rb').read(); n = struct.unpack('<I', d[12:16])[0]; return d[20 + n + 8:]
assert bin(sys.argv[1]).rstrip(b'\0') == bin(sys.argv[2]).rstrip(b'\0')
PYEOF

# 4. Refusals.
UP=$(upload $FOX)
for spec in "colours|{\"texture\":\"vertex_colors\"}|422" "size300|{\"texture_size\":300}|422" "res2048|{\"resolution\":2048}|422" "fewfaces|{\"max_faces\":500}|422"; do
  IFS='|' read name params want <<< "$spec"
  submit '{"operation":"mesh.generate","inputs":{"image":{"upload":"'$UP'"}},"params":'$params'}' "$OUT/refuse-$name.json"
  check "refused: $name ($params) is $want" test "$(cat $OUT/refuse-$name.json.status)" = "$want"
done

# 5. A preview server.
GAEA_HOME=$H "$CLI" models disable trellis2-1024 >> "$LOG" 2>&1; GAEA_HOME=$H "$CLI" models disable trellis2-1536 >> "$LOG" 2>&1
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations-preview.json"
check "with 1024 and 1536 disabled, mesh.generate offers draft and standard only" py "
import json; d = {o['operation']: o for o in json.load(open('$OUT/operations-preview.json'))['operations']}['mesh.generate']
print([m['id'] for m in d['models']], d['quality_tiers']); assert [m['id'] for m in d['models']] == ['trellis2-512'] and sorted(d['quality_tiers']) == ['draft', 'standard']"
submit '{"operation":"mesh.generate","inputs":{"image":{"upload":"'$UP'"}},"params":{"quality":"best"}}' "$OUT/refuse-best.json"
check "and quality best is refused (422)" test "$(cat $OUT/refuse-best.json.status)" = "422"
GAEA_HOME=$H "$CLI" models enable trellis2-1024 >> "$LOG" 2>&1; GAEA_HOME=$H "$CLI" models enable trellis2-1536 >> "$LOG" 2>&1
H2=$WORK/small; P2=17675
start $H2 $P2 --budget-bytes 51540000000
GAEA_HOME=$H2 "$CLI" plugins add https://github.com/xocialize-code/gaea-plugin-trellis2 > /dev/null 2>&1
check "with a 51.54 GB budget only trellis2-512 is offered" py "
import json, urllib.request
req = urllib.request.Request('http://127.0.0.1:$P2/mes/v0/operations', headers={'MES-Version': '0.1'})
d = {o['operation']: o for o in json.load(urllib.request.urlopen(req))['operations']}['mesh.generate']; print([m['id'] for m in d['models']])
assert [m['id'] for m in d['models']] == ['trellis2-512']"
stop $P2

# 6. The cascades.
if [[ ${FULL:-0} == 1 ]]; then
  mesh best $FOX '{"seed":42,"quality":"best","max_faces":100000,"texture_size":1024}'
  check "quality best runs trellis2-1024" py "import json; r=json.load(open('$OUT/job-best.json'))['result']; assert r['provenance']['model']['id'] == 'trellis2-1024' and r['effective']['resolution'] == 1024, r['provenance']['model']"
  mesh r1536 $FOX '{"seed":42,"resolution":1536,"max_faces":100000,"texture_size":2048}'
  check "resolution 1536 runs trellis2-1536 with a 2048 texture" py "
import json; r=json.load(open('$OUT/job-r1536.json'))['result']; o=[o for o in r['outputs'] if o['name']=='mesh'][0]
assert r['provenance']['model']['id'] == 'trellis2-1536' and o['texture_size'] == 2048, (r['provenance']['model'], o)"
fi

stop $P
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/" 2>/dev/null
for s in $OUT/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
[[ -n ${STANDIN:-} ]] && kill $STANDIN 2>/dev/null
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
