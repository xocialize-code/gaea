"""Prepare one mesh + reference image for TexturingPipeline: `prep_retex.py <mesh> <image> <outdir>`.

Writes npy inputs in the port's conventions:
  verts_model.npy  [V,3] f32  centered, scaled into [-0.5,0.5]^3, glTF Y-up -> model Z-up (y=-z, z=y)
  verts_gltf.npy   [V,3] f32  the same normalization, still Y-up (for GLB export)
  faces.npy        [F,3] i32
  uvs.npy          [V,2] f32  xatlas UVs (vertices split at seams)
  pixels_512.npy / pixels_1024.npy  [1,3,S,S] f32  DINOv3 input (ImagePreprocess.dinoPixels, alpha path)
"""
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import trimesh
import xatlas
from PIL import Image

MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)


def dino_pixels(img: Image.Image, size: int) -> np.ndarray:
    """Alpha bbox (>0.8) -> square crop -> RGB*alpha on black -> resize -> ImageNet NCHW."""
    rgba = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    alpha = rgba[..., 3]
    ys, xs = np.nonzero(alpha * 255 > int(0.8 * 255))
    cx, cy = (xs.min() + xs.max()) // 2, (ys.min() + ys.max()) // 2
    side = max(1, max(xs.max() - xs.min(), ys.max() - ys.min()))
    x0, y0 = cx - side // 2, cy - side // 2
    premult = rgba[..., :3] * alpha[..., None]
    crop = np.zeros((side, side, 3), np.float32)
    H, W = alpha.shape
    sx0, sy0, sx1, sy1 = max(0, x0), max(0, y0), min(W, x0 + side), min(H, y0 + side)
    crop[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = premult[sy0:sy1, sx0:sx1]
    out = Image.fromarray((crop * 255 + 0.5).clip(0, 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
    rgb = np.asarray(out).astype(np.float32) / 255.0
    return ((rgb - MEAN) / STD).transpose(2, 0, 1)[None].astype(np.float32)


def main() -> None:
    mesh_path, image_path, out = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    m = trimesh.load(mesh_path, force="mesh", process=False)
    v = np.asarray(m.vertices, np.float32)
    f = np.asarray(m.faces, np.int32)
    lo, hi = v.min(0), v.max(0)
    v = (v - (lo + hi) / 2) * (0.99999 / (hi - lo).max())

    t = time.time()
    if len(sys.argv) > 4:  # the port's parallel xatlas lane (retex-tool's `unwrap`)
        np.save(out / "verts.npy", v.astype(np.float32))
        np.save(out / "faces_in.npy", f)
        subprocess.run([sys.argv[4], str(out)], check=True)
        vmap, f_uv, uv = (np.load(out / f"{n}.npy") for n in ("vmap", "faces_uv", "uv"))
    else:
        vmap, f_uv, uv = xatlas.parametrize(v, f)
    print(f"xatlas: {len(f)} faces -> {len(vmap)} verts in {time.time() - t:.1f}s")
    v_uv = v[vmap]
    model = np.stack([v_uv[:, 0], -v_uv[:, 2], v_uv[:, 1]], 1)

    np.save(out / "verts_gltf.npy", v_uv.astype(np.float32))
    np.save(out / "verts_model.npy", model.astype(np.float32))
    np.save(out / "faces.npy", f_uv.astype(np.int32))
    np.save(out / "uvs.npy", uv.astype(np.float32))
    img = Image.open(image_path)
    for s in (512, 1024):
        np.save(out / f"pixels_{s}.npy", dino_pixels(img, s))
    print("prepared", out)


if __name__ == "__main__":
    main()
