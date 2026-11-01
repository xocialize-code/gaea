"""Hi3D v1.0 on HF Jobs (AB-T-0385 goldens and the 1536³ comparison), run in the
townbox/hi3d10-zerogpu image (official sparc3d @ 23dcc68, weights @ 705fc09).

    python hi3d_job.py <inputs> <outdir> golden:dress:512 golden:shoes:512 run:dress:1536 ...

`run` refines <item>_trellis2.ply with <item>.png exactly as the Space's /refine does (25 Heun
steps per pass, seed 0, existing alpha kept) and writes hi3d_refined.glb and info.json.
`golden` does the same and also dumps every stage of every pass as .npz (see dump()).
Each item is written to <outdir>/<mode>_<item>_<res>/ as soon as it finishes.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import sys
import time
import traceback
import warnings
from pathlib import Path

import numpy as np
import torch
import trimesh
from huggingface_hub import snapshot_download
from PIL import Image

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("hi3d-job")

HI3D_REPO = "hi3d-official/Hi3Dv1.0"
HI3D_REVISION = "705fc0901c5d896cdcbf1dbf1feaa173e62bdd3a"
HI3D_FILES = [
    "model_index.json", "scheduler/scheduler_config.json", "vae/config.json", "vae/model.safetensors",
    "transformer_512/config.json", "transformer_512/model.safetensors",
    "transformer_1024/config.json", "transformer_1024/model.safetensors",
]
STEPS, SEED = 25, 0
SAVE_STEPS = {0, 12, 24}
BIG = 20_000_000  # float tensors with more elements are stored as float16


# ---------------------------------------------------------------- dumping
class Dumper:
    def __init__(self, root: Path | None):
        self.root = root
        self.manifest: dict[str, dict] = {}
        if root:
            root.mkdir(parents=True, exist_ok=True)

    @property
    def on(self) -> bool:
        return self.root is not None

    def dump(self, name: str, obj, **meta) -> None:
        if not self.on:
            return
        arrays: dict[str, np.ndarray] = {}
        flatten(obj, "", arrays)
        np.savez(self.root / f"{name}.npz", **arrays)
        self.manifest[name] = {
            "arrays": {k: [list(v.shape), str(v.dtype)] for k, v in arrays.items()},
            **meta,
        }
        (self.root / "manifest.json").write_text(json.dumps(self.manifest, indent=1))


def flatten(obj, prefix: str, out: dict) -> None:
    key = prefix or "value"
    if isinstance(obj, torch.Tensor):
        t = obj.detach()
        if t.is_floating_point():
            t = t.to(torch.float16 if t.numel() > BIG else torch.float32)
        out[key] = t.cpu().numpy()
    elif isinstance(obj, np.ndarray):
        out[key] = obj
    elif isinstance(obj, (int, float, bool)):
        out[key] = np.asarray(obj)
    elif isinstance(obj, trimesh.Trimesh):
        out[f"{prefix}.vertices" if prefix else "vertices"] = np.asarray(obj.vertices, dtype=np.float32)
        out[f"{prefix}.faces" if prefix else "faces"] = np.asarray(obj.faces, dtype=np.int32)
    elif isinstance(obj, dict):
        for k, v in obj.items():
            flatten(v, f"{prefix}.{k}" if prefix else str(k), out)
    elif isinstance(obj, (list, tuple)):
        for i, v in enumerate(obj):
            flatten(v, f"{prefix}.{i}" if prefix else str(i), out)
    elif hasattr(obj, "feats") and hasattr(obj, "coords"):  # SparseTensor
        flatten(obj.feats, f"{prefix}.feats" if prefix else "feats", out)
        flatten(obj.coords, f"{prefix}.coords" if prefix else "coords", out)
    elif hasattr(obj, "vertices") and hasattr(obj, "faces"):  # sparcubes Mesh
        flatten(obj.vertices, f"{prefix}.vertices" if prefix else "vertices", out)
        flatten(obj.faces, f"{prefix}.faces" if prefix else "faces", out)
    # anything else (spconv tensors, layouts, None) is skipped


class Hooks:
    """Forward hooks that record a module's input and output while armed."""

    def __init__(self, dumper: Dumper, prefix: str, modules: list[tuple[str, torch.nn.Module]],
                 inputs: bool = True):
        self.dumper, self.prefix, self.armed, self.inputs = dumper, prefix, False, inputs
        self.handles = [m.register_forward_hook(self._hook(n), with_kwargs=True) for n, m in modules]

    def _hook(self, name):
        def hook(module, args, kwargs, output):
            if self.armed:
                record = {"in": list(args), "kw": kwargs, "out": output} if self.inputs else {"out": output}
                self.dumper.dump(f"{self.prefix}.{name}", record, module=type(module).__name__)
        return hook


def interesting(module: torch.nn.Module, depth: int) -> list[tuple[str, torch.nn.Module]]:
    """Children up to `depth`; of a ModuleList only the first, middle and last entries."""
    picked = []

    def walk(m, path, d):
        children = list(m.named_children())
        if isinstance(m, torch.nn.ModuleList) and len(children) > 3:
            keep = {0, len(children) // 2, len(children) - 1}
            children = [c for i, c in enumerate(children) if i in keep]
        for n, c in children:
            p = f"{path}.{n}" if path else n
            picked.append((p, c))
            if d > 1:
                walk(c, p, d - 1)

    walk(module, "", depth)
    return picked


# ---------------------------------------------------------------- one item
def refine(pipeline, inputs: Path, item: str, res: int, out: Path, golden: bool) -> dict:
    import sparc3d.sparcubes.extract as extract_mod
    import sparc3d.sparcubes.fill_hole as fill_mod
    import sparc3d.utils.image as image_mod
    from sparc3d.pipelines import sparc3d_pipeline as sp
    from sparc3d.schedulers.schedule import apply_effective_guidance
    from sparc3d.nn.sparse.basic import SparseTensor

    d = Dumper(out / "golden" if golden else None)
    passes: list[dict] = []

    image = Image.open(inputs / f"{item}.png")
    alpha = image.mode in ("RGBA", "LA", "PA") or "transparency" in image.info
    image = image.convert("RGBA") if alpha else image.convert("RGB")
    coarse = trimesh.load(inputs / f"{item}_trellis2.ply", force="mesh", process=False)
    d.dump("input.coarse", coarse)

    # prepare_image is imported inside __call__, so patching the module attribute reaches it.
    orig_prepare = image_mod.prepare_image

    def prepare(img):
        p = orig_prepare(img)
        if d.on:
            p.save(d.root / "input.prepared.png")
        return p

    image_mod.prepare_image = prepare

    # Conditioner: encoder inputs and the final tokens.
    cond_hooks = Hooks(d, "cond", [("dino", pipeline.conditioner.dino), ("clip", pipeline.conditioner.clip)])
    cond_hooks.armed = golden

    def cond_out(module, args, output):
        d.dump("cond.tokens", output)

    h_cond = pipeline.conditioner.register_forward_hook(cond_out)

    t_hooks = {
        id(t): Hooks(d, name, interesting(t, 2))
        for name, t in (("t512", pipeline.transformer_512),)
        + ((("t1024", pipeline.transformer_1024),) if res > 512 else ())
    }
    # Decoder modules update the Point in place, so only outputs are meaningful.
    dec_hooks = Hooks(d, "dec", interesting(pipeline.vae.decoder, 2), inputs=False)

    orig_vox = pipeline._adaptive_voxelize

    def voxelize(mesh, structure, budget):
        coords = orig_vox(mesh, structure, budget)
        k = len(passes)
        passes.append({"structure": structure, "budget": budget, "voxels": int(coords.shape[0])})
        d.dump(f"p{k}.voxelize", {"mesh": mesh, "coords": coords}, structure=structure, budget=budget)
        return coords

    def sample(transformer, condition, voxel_coords, structure, steps, generator, *, pass_index, num_passes):
        # sp.Sparc3DPipeline._sample_latents @ 23dcc68, with dumps.
        k = pass_index
        dev = pipeline._device
        coords = voxel_coords.to(device=dev, dtype=torch.int32)
        batch = torch.zeros((coords.shape[0], 1), dtype=torch.int32, device=dev)
        batched = torch.cat((batch, coords), dim=1)
        noise = torch.randn((coords.shape[0], 32), generator=generator, device="cpu", dtype=torch.float32).to(dev)
        sample = SparseTensor(feats=noise, coords=batched)
        negative = torch.zeros_like(condition)
        timesteps = pipeline.scheduler.set_timesteps(steps, num_tokens=coords.shape[0], device=dev)
        if getattr(pipeline.scheduler, "order", 1) != 2:
            raise RuntimeError("expected the second-order (Heun) scheduler of the release")
        d.dump(f"p{k}.noise", {"noise": noise, "coords": batched, "timesteps": timesteps})
        hooks = t_hooks[id(transformer)]

        def guided(x, sigma, tag):
            mt = (1000.0 * sigma).reshape(1)
            hooks.armed = golden and tag == "s0.v1"
            pos = transformer(x, mt, condition)
            hooks.armed = False
            if float(sigma) < 0.7:
                v, neg = pos.feats, None
            else:
                neg = transformer(x, mt, negative).feats
                v = apply_effective_guidance(pos.feats, neg, sigma)
            return v, pos.feats, neg

        t0 = time.perf_counter()
        for i, sigma in enumerate(timesteps):
            v1, pos1, neg1 = guided(sample, sigma, f"s{i}.v1")
            predicted, next_sigma = pipeline.scheduler.predict(v1, sigma, sample.feats)
            v2, pos2, neg2 = guided(sample.replace(predicted), next_sigma, f"s{i}.v2")
            updated = pipeline.scheduler.step(v1, sigma, sample.feats, second_output=v2)
            if i in SAVE_STEPS:
                d.dump(f"p{k}.step{i:02d}", {
                    "x": sample.feats, "sigma": sigma, "next_sigma": next_sigma,
                    "v1": v1, "pos1": pos1, "neg1": neg1, "predicted": predicted,
                    "v2": v2, "pos2": pos2, "neg2": neg2, "updated": updated,
                })
            sample = sample.replace(updated)
        torch.cuda.synchronize()
        passes[k]["sample_s"] = round(time.perf_counter() - t0, 1)
        mean, std = pipeline._latent_stats(transformer, sample)
        latents = sample.replace(sample.feats * std + mean)
        d.dump(f"p{k}.latents", {"normalized": sample, "denormalized": latents, "mean": mean, "std": std})
        log.info("%s %d pass %d (%d^3): %d voxels, sampled in %.1fs", item, res, k + 1, structure,
                 coords.shape[0], passes[k]["sample_s"])
        return latents

    orig_decode = pipeline._decode_latents

    def decode(latents, structure):
        k = len(passes) - 1
        dec_hooks.armed = golden
        t0 = time.perf_counter()
        decoded = orig_decode(latents, structure)
        torch.cuda.synchronize()
        dec_hooks.armed = False
        passes[k]["decode_s"] = round(time.perf_counter() - t0, 1)
        passes[k]["decoded_rows"] = int(decoded["feat"].shape[0])
        d.dump(f"p{k}.decoded", decoded)
        return decoded

    def extract(decoded):
        # sp.Sparc3DPipeline._extract_mesh @ 23dcc68, with dumps.
        k = len(passes) - 1
        raw = extract_mod.point_to_mesh(decoded)
        d.dump(f"p{k}.mesh_raw", raw)
        filled = fill_mod.fill_mesh_holes(raw)
        if not filled.success:
            raise RuntimeError("mesh extraction produced an empty isosurface")
        mesh = trimesh.Trimesh(vertices=filled.vertices.detach().cpu().numpy(),
                               faces=filled.faces.detach().cpu().numpy(), process=False)
        passes[k]["extracted_faces"] = int(len(mesh.faces))
        d.dump(f"p{k}.mesh_filled", mesh)
        return mesh

    orig_post = pipeline._postprocess_mesh

    def post(mesh, *, target_face_count):
        result = orig_post(mesh, target_face_count=target_face_count)
        d.dump("final.mesh", result, target_face_count=target_face_count)
        return result

    pipeline._adaptive_voxelize = voxelize
    pipeline._sample_latents = sample
    pipeline._decode_latents = decode
    pipeline._extract_mesh = extract
    pipeline._postprocess_mesh = post
    try:
        torch.cuda.reset_peak_memory_stats()
        t0 = time.perf_counter()
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            result = pipeline(image, coarse, resolution=res, num_inference_steps=STEPS, seed=SEED)
        refine_s = time.perf_counter() - t0
    finally:
        image_mod.prepare_image = orig_prepare
        for attr in ("_adaptive_voxelize", "_sample_latents", "_decode_latents", "_extract_mesh",
                     "_postprocess_mesh"):
            delattr(pipeline, attr)
        h_cond.remove()
        for h in [cond_hooks, dec_hooks, *t_hooks.values()]:
            for handle in h.handles:
                handle.remove()

    mesh = result.mesh
    _ = mesh.vertex_normals
    material = trimesh.visual.material.PBRMaterial(baseColorFactor=[205, 205, 210, 255],
                                                   metallicFactor=0.05, roughnessFactor=0.65)
    mesh.visual = trimesh.visual.TextureVisuals(material=material)
    mesh.export(out / "hi3d_refined.glb")
    info = {
        "item": item, "resolution": res, "passes": passes, "steps_per_pass": STEPS, "seed": SEED,
        "refine_s": round(refine_s, 1), "gpu": torch.cuda.get_device_name(),
        "peak_gpu_memory_gb": round(torch.cuda.max_memory_allocated() / 2**30, 2),
        "warnings": sorted({str(w.message) for w in caught if "sparc3d" in (w.filename or "")}),
        "refined_faces": int(len(mesh.faces)), "refined_vertices": int(len(mesh.vertices)),
        "coarse_faces": int(len(coarse.faces)), "background": "kept existing alpha" if alpha else "none",
        "golden": golden, "stack": {"torch": torch.__version__, "hi3d_weights": HI3D_REVISION,
                                     "sparc3d": "23dcc684bc6e1fab86ecafb99ec5270edad122f9"},
    }
    (out / "info.json").write_text(json.dumps(info, indent=2))
    log.info("DONE %s", json.dumps(info))
    return info


def main() -> None:
    inputs, outdir, jobs = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3:]
    from sparc3d import Sparc3DPipeline

    t0 = time.perf_counter()
    root = snapshot_download(HI3D_REPO, revision=HI3D_REVISION, allow_patterns=HI3D_FILES)
    pipeline = Sparc3DPipeline.from_pretrained(root)
    if any(int(j.split(":")[2]) > 512 for j in jobs):
        _ = pipeline.transformer_1024
    pipeline.to("cuda")
    log.info("loaded in %.1fs on %s", time.perf_counter() - t0, torch.cuda.get_device_name())

    summary = []
    for job in jobs:
        mode, item, res = job.split(":")
        scratch = Path("/tmp/hi3d") / f"{mode}_{item}_{res}"
        shutil.rmtree(scratch, ignore_errors=True)
        scratch.mkdir(parents=True)
        try:
            info = refine(pipeline, inputs, item, int(res), scratch, golden=(mode == "golden"))
            summary.append(info)
        except Exception as exc:  # keep going: one failed item shouldn't cost the rest
            log.error("FAILED %s: %s", job, exc)
            (scratch / "error.txt").write_text(traceback.format_exc())
            summary.append({"job": job, "error": str(exc)})
        torch.cuda.empty_cache()
        t = time.perf_counter()
        shutil.copytree(scratch, outdir / scratch.name, dirs_exist_ok=True)
        log.info("copied %s to the bucket in %.1fs", scratch.name, time.perf_counter() - t)
        shutil.rmtree(scratch, ignore_errors=True)
        (outdir / "summary.json").write_text(json.dumps(summary, indent=2))
    log.info("ALL DONE")


if __name__ == "__main__":
    os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
    main()
