"""Rebuild the G-5 creative-upscale photo set (mlxengine-todo/CREATIVE-UPSCALE-EVAL.md §4.1) exactly as its
kit/prep_set.py made it, finding each Commons original in the local corpus by title instead of the old pick lists.
usage: python prep_set.py <cu>   ->  <cu>/set/{in,gt2,gt4}/<name>.png
"""
import io, json, math, os, sys
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
CU = sys.argv[1]
CORPUS = "/Volumes/Satechi/Development/mlxengine-image/corpus/commons-sr"
MAN = "/Volumes/Satechi/Development/mlxengine-todo/probes/creative-upscale/results/set-manifest.json"
B = "/Volumes/Satechi/Development/pixel-agency-image-engine/bench"
ZT = [("zt-jazz", B + "/r1b-hard/generate/z-image-turbo/job_fqk3gvmtvs6xp2eqxpfe-0.png"),
      ("zt-reader", B + "/r1b/generate/z-image-turbo/job_twf5jgtr6y7zh5835gpj-0.png"),
      ("zt-cats", B + "/r1b-hard/generate/z-image-turbo/job_b7ann2dc4h067hgjpsbw-0.png")]
for d in ("in", "gt2", "gt4"):
    os.makedirs(f"{CU}/set/{d}", exist_ok=True)
paths = {}
for l in open(f"{CORPUS}/fetched.jsonl"):
    r = json.loads(l)
    paths.setdefault(r["title"], r["path"])
for m in json.load(open(MAN)):
    if m["source"] != "commons":
        continue
    im = Image.open(os.path.join(CORPUS, paths[m["title"]])).convert("RGB")
    oW, oH = im.size
    s = min(math.sqrt(1024 * 1024 / (oW * oH)), 0.25)
    inW, inH = int(oW * s) // 8 * 8, int(oH * s) // 8 * 8
    cw, ch = min(oW, round(oH * inW / inH)), min(oH, round(oW * inH / inW))
    x0, y0 = (oW - cw) // 2, (oH - ch) // 2
    crop = im.crop((x0, y0, x0 + cw, y0 + ch))
    crop.resize((inW * 4, inH * 4), Image.LANCZOS).save(f"{CU}/set/gt4/{m['name']}.png")
    crop.resize((inW * 2, inH * 2), Image.LANCZOS).save(f"{CU}/set/gt2/{m['name']}.png")
    small = crop.resize((inW, inH), Image.LANCZOS)
    buf = io.BytesIO(); small.save(buf, "JPEG", quality=90); buf.seek(0)
    Image.open(buf).convert("RGB").save(f"{CU}/set/in/{m['name']}.png")
    ok = [oW, oH] == m["orig"] and [inW, inH] == m["input"]
    print(m["name"], (oW, oH), (inW, inH), "matches the manifest" if ok else f"DIFFERS from {m['orig']} {m['input']}")
for name, p in ZT:
    Image.open(p).convert("RGB").save(f"{CU}/set/in/{name}.png")
    print(name, "copied")
