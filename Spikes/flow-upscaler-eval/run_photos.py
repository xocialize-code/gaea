"""The photo set through FlowUpscaler: VAE encode -> 2x pass(es) -> VAE decode, at exactly the input's size x N.
Inputs are edge-padded to a multiple of 16 px (latent /8, patchified /2) and cropped back. Arms (runs/<arm>/x<s>/):
  flow     x2 = one pass (seed 0); x4 = two passes (seeds 0, 1)
  lanczos  the floor
Writes runs/timings.json: per image, encode / passes / decode seconds (warm: each image runs once untimed first)
and the MPS driver's peak allocation.
usage: python run_photos.py <cu>
"""
import json, os, sys, time
import numpy as np, torch
from PIL import Image
from flowup import Flow, sync

CU = sys.argv[1]
f = Flow()
names = sorted(p[:-4] for p in os.listdir(f"{CU}/set/in") if p.endswith(".png"))
timings = {}


def pad16(img):
    w, h = img.size
    W, H = -(-w // 16) * 16, -(-h // 16) * 16
    a = np.pad(np.asarray(img), ((0, H - h), (0, W - w), (0, 0)), mode="edge")
    return Image.fromarray(a), (w, h)


def run(img, passes):
    padded, (w, h) = pad16(img)
    sync(); t0 = time.time()
    z = f.encode(padded); sync(); t1 = time.time()
    steps = []
    for i in range(passes):
        s = time.time(); z = f.up2(z, seed=i); sync(); steps.append(time.time() - s)
    t2 = time.time()
    out = f.decode(z, tiled=z.shape[-1] * z.shape[-2] > 128 * 128); sync(); t3 = time.time()
    k = 2 ** passes
    return out.crop((0, 0, w * k, h * k)), dict(encode_s=t1 - t0, passes_s=steps, decode_s=t3 - t2, total_s=t3 - t0)


for scale, passes in ((2, 1), (4, 2)):
    for arm in ("flow", "lanczos"):
        os.makedirs(f"{CU}/runs/{arm}/x{scale}", exist_ok=True)
    for n in names:
        img = Image.open(f"{CU}/set/in/{n}.png").convert("RGB")
        img.resize((img.width * scale, img.height * scale), Image.LANCZOS).save(f"{CU}/runs/lanczos/x{scale}/{n}.png")
        run(img, passes)  # warm-up
        torch.mps.empty_cache()
        out, t = run(img, passes)
        t["peak_gb"] = torch.mps.driver_allocated_memory() / 1e9
        out.save(f"{CU}/runs/flow/x{scale}/{n}.png")
        timings[f"x{scale}|{n}"] = dict(t, input=list(img.size), output=list(out.size))
        print(f"x{scale} {n}: {img.size} -> {out.size}  encode {t['encode_s']:.2f} s, passes "
              f"{', '.join(f'{p*1000:.0f} ms' for p in t['passes_s'])}, decode {t['decode_s']:.2f} s", flush=True)
json.dump(timings, open(f"{CU}/runs/timings.json", "w"), indent=1)
