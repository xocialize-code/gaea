"""Score the Klein run (after VAEDecode has written <out>/<name>-{base,native-2k,flow-2k,flow-4k,flow-8k}.png).
- consistency: each stage Lanczos'd back down to 1024² against the base decode (PSNR, and DISTS on a 2x2 grid of
  512² crops): "did it keep Klein's picture";
- chain drift: stage k+1 Lanczos'd down to stage k's size against stage k: what each later pass changes;
- lanczos-<k>: the base decode resized, written here, for IQA as the floor;
- sheets: one 64² region of the base followed through every stage, each shown at 512².
writes <out>/klein-scores.json
usage: python score_klein.py <out>
"""
import json, os, sys
import numpy as np, torch, piq
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
torch.set_grad_enabled(False)
OUT = sys.argv[1]
D = piq.DISTS(reduction="none")
NAMES = ["portrait", "forest", "sign", "cat", "city", "illustration"]
SIZES = {"2k": 2048, "4k": 4096, "8k": 8192}


def arr(img):
    return np.asarray(img.convert("RGB"), dtype=np.float32) / 255


def psnr(a, b):
    return float(10 * np.log10(1 / np.mean((a - b) ** 2)))


def dists(a, b, s=512):
    H, W = a.shape[:2]; v = []
    for y in range(0, H - s + 1, s):
        for x in range(0, W - s + 1, s):
            ta = torch.from_numpy(a[y:y+s, x:x+s]).permute(2, 0, 1)[None]; tb = torch.from_numpy(b[y:y+s, x:x+s]).permute(2, 0, 1)[None]
            v.append(D(ta, tb).item())
    return float(np.mean(v))


res = {}
os.makedirs(f"{OUT}/sheets", exist_ok=True)
for n in NAMES:
    base = Image.open(f"{OUT}/{n}-base.png").convert("RGB"); b = arr(base)
    r = {}
    prev = base
    for k, size in SIZES.items():
        base.resize((size, size), Image.LANCZOS).save(f"{OUT}/{n}-lanczos-{k}.png")
        for arm in ("flow", "taef"):
            p = f"{OUT}/{n}-{arm}-{k}.png"
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGB")
            d = arr(im.resize((1024, 1024), Image.LANCZOS))
            r[f"{arm}-{k}"] = {"psnr_vs_base": psnr(d, b), "dists_vs_base": dists(d, b)}
            if arm == "flow" and k != "2k":
                ps = prev.size[0]
                dd = arr(im.resize((ps, ps), Image.LANCZOS)); pa = arr(prev)
                r[f"{arm}-{k}"]["psnr_vs_previous"] = psnr(dd, pa)
                r[f"{arm}-{k}"]["dists_vs_previous"] = dists(dd, pa)
            if arm == "flow":
                prev = im
    res[n] = r
    print(n, json.dumps({k: {m: round(v, 3) for m, v in x.items()} for k, x in r.items()}), flush=True)
    # sheet: a 64x64 base region (picked at the centre-left third, where subjects usually have detail)
    bx, by = 448, 384
    tiles = [("base x8 (Lanczos)", base.crop((bx, by, bx + 64, by + 64)).resize((512, 512), Image.LANCZOS))]
    for k, f in (("2k", 2), ("4k", 4), ("8k", 8)):
        p = f"{OUT}/{n}-flow-{k}.png"
        if os.path.exists(p):
            im = Image.open(p)
            tiles.append((f"flow {k}", im.crop((bx * f, by * f, (bx + 64) * f, (by + 64) * f)).resize((512, 512), Image.LANCZOS)))
    p = f"{OUT}/{n}-taef-8k.png"
    if os.path.exists(p):
        tiles.append(("taef 8k", Image.open(p).crop((bx * 8, by * 8, (bx + 64) * 8, (by + 64) * 8))))
    sheet = Image.new("RGB", (512 * len(tiles), 512))
    for i, (_, t) in enumerate(tiles):
        sheet.paste(t.convert("RGB"), (512 * i, 0))
    sheet.save(f"{OUT}/sheets/{n}-zoom.png")
json.dump(res, open(f"{OUT}/klein-scores.json", "w"), indent=1)
