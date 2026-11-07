"""The photo set's FlowUpscaler latents (the same encode, seeds and passes as run_photos.py), saved packed and
bn-normalised for VAEDecode (flux2-vae-mlx-swift's exact row-band decode): <cu>/lat/x<s>/<name>.safetensors, plus
the size to crop back to in lat/crops.json.
usage: python photos_latents.py <cu>
"""
import json, os, sys
import numpy as np
from PIL import Image
from safetensors.torch import save_file
from flowup import Flow, patchify

CU = sys.argv[1]
f = Flow()
crops = {}
for scale, passes in ((2, 1), (4, 2)):
    os.makedirs(f"{CU}/lat/x{scale}", exist_ok=True)
    for p in sorted(os.listdir(f"{CU}/set/in")):
        if not p.endswith(".png"):
            continue
        n = p[:-4]
        img = Image.open(f"{CU}/set/in/{p}").convert("RGB")
        w, h = img.size
        W, H = -(-w // 16) * 16, -(-h // 16) * 16
        z = f.encode(Image.fromarray(np.pad(np.asarray(img), ((0, H - h), (0, W - w), (0, 0)), mode="edge")))
        for i in range(passes):
            z = f.up2(z, seed=i)
        save_file({"latents": patchify(z).contiguous().cpu()}, f"{CU}/lat/x{scale}/{n}.safetensors")
        crops[f"x{scale}/{n}"] = [w * scale, h * scale]
        print(scale, n, tuple(z.shape), flush=True)
json.dump(crops, open(f"{CU}/lat/crops.json", "w"))
