# Hi3D v1.0 as a detail pass after TRELLIS.2 (2026-10-29)

[Hi3D v1.0](https://huggingface.co/hi3d-official/Hi3Dv1.0) (released 2026-10-23) is **not** an image-to-3D
generator. It refines an existing coarse mesh into high-resolution geometry, conditioned on a reference image
of the same object, and returns geometry only (no texture). So it competes with nothing in TRELLIS.2: it can
follow it. This folder records the first test of that pipeline on our garment corpus:

1. TRELLIS.2 mesh (our port, the `Trellis2Metrics` corpus) →
2. Hi3D refinement at 1024³ on a Hugging Face ZeroGPU Space →
3. re-texture of the refined mesh on this Mac with our port's `TexturingPipeline`.

Big meshes and GLBs (296 MB) are on `/Volumes/DEV_VOL1/Evidence/hi3d-eval-2026-10-29/`
(`coarse/` the rotated TRELLIS.2 inputs, `hi3d/` the refined meshes, `retex/` the re-textured GLBs).

## The model

- **What it is:** Sparc3D refinement. Two sparse flow transformers of about 1.8B parameters each
  (`transformer_512`, `transformer_1024`; 3.7 GB fp16 each), conditioned on DINOv2-L and CLIP-L. A sparse VAE
  with a PTv3 decoder, then FlexiCubes. 512³ runs one pass, 1024³ two, 1536³ three.
- **Runtime:** CUDA only (flash-attn, spconv, Triton). No CPU or MPS path.
- **Output:** geometry only, recentred and normalized to unit radius. It keeps the input's axes.
- **License:** Hi3D Open License 1.0. Commercial use is allowed worldwide (no regional exclusion). Above
  200k MAU or $1M a month in revenue, you must apply for a separate license. Commercial integrations must
  show "Powered by Hi3D 1.0". A port or quantization is very likely a "Model Derivative". Governing law is
  Hong Kong. Generated meshes carry no obligations. DINOv2 is Apache-2.0 and CLIP is MIT.

## Step 2: geometry (Hi3D at 1024³, 25 Heun steps per pass, seed 0)

The runs used the unofficial Space `townbox/hi3d10-zerogpu` and its `/refine` endpoint, with our own coarse
mesh. It runs the official code at commit `23dcc68` and the official weights at `705fc09`, on a ½ RTX PRO 6000
(MIG 48 GB). It cost $0 in money and about 17 minutes of PRO ZeroGPU quota. Each run's info is in `runs/`.

Our port writes Z-up GLBs. Hi3D expects Hunyuan3D's Y-up glTF frame, so each mesh was rotated
`(x, y, z) → (x, z, −y)`. A chamfer search over all 24 axis rotations, against a Hunyuan coarse mesh of the
dress, picked the same rotation (`tools/align.py`).

| Item | Verdict | GPU time | Peak VRAM | Voxel grid, pass 2 |
|---|---|---|---|---|
| dress | **Big gain.** Eyelets, boning seams, ruffled neckline, lace appliqué. TRELLIS.2's skirt pitting is gone. | 238 s | 31.4 GB | 109 (capped from 128) |
| shoes | **Big gain.** Stitch lines, eyelets, toe-cap seam, sole edge profile | 139 s | 24.3 GB | 128 |
| top | **Moderate gain.** Double collar trim, crisper tie knot, hem stitching. The plain back shows faint ripple banding. | 138 s | 23.3 GB | 128 |
| skirt | **Small gain.** Sharper pleats and waistband seam. One shredded streak on the back. | 226 s | 31.0 GB | 115 (capped) |
| hair | **Mixed.** Cleaner strand grooves, but the strand tips fray into shards and the hidden inner surface goes noisy. | 224 s | 30.3 GB | 109 (capped) |

Mesh checks (`runs/mesh-stats.txt`, `tools/mesh_stats.py`):
- **Faces:** every Hi3D output is about 1.0M faces, against about 285k for TRELLIS.2 after our simplify step.
  TRELLIS.2's raw decoder output is about 17M faces, so part of the gap is our simplify.
- **Holes:** every Hi3D mesh has 150–570 open boundary edges. TRELLIS.2's have none, because our DC remesh
  closes them. Neither is watertight.
- **Stray fragments:** Hi3D has fewer on skirt, top and hair, and more on dress (2,839 vs 551) and shoes
  (415 vs 224).

## Step 3: texture (our port, on this Mac)

`mlx-trellis2-swift`'s `TexturingPipeline` does upstream's `Trellis2TexturingPipeline`, and its parity was
gated in SW8 (`swift run texturize`). For this test it ran at resolution 1024 (`tex_flow_1024`, DINOv3 cond at
1024, bf16 SDPA) with a 2048 texture map, seed 42.

The tools are in `tools/retex-tool`, a scratch package that depends on the port by path:
- **`unwrap`:** the port's parallel xatlas lane. 1M faces in 15–35 s; Python xatlas took over 20 minutes.
- **`retex`:** encode, sample, decode, bake onto the mesh's own UVs, then write the GLB.

`tools/prep_retex.py` normalizes into model space and prepares the DINOv3 pixels.

| Mesh | Time | Peak RSS | Texture-map coverage |
|---|---|---|---|
| shoes, TRELLIS.2 (266k) | 78 s | 5.4 GB | 66% |
| dress, TRELLIS.2 (299k) | 190 s | — | 55% |
| shoes, Hi3D (1M) | 71 s | 5.9 GB | 64% |
| dress, Hi3D (1M) | 176 s | 9.2 GB | 57% |

Verdicts (`screenshots/`):
- **Dress:** Hi3D plus TRELLIS.2 texture is clearly closer to the input than the original TRELLIS.2 output:
  lace pattern, lacing eyelets, ruffled neckline, lace hem. The texture pass alone, on the original mesh,
  already fixes the original's wrong beige hem. Hi3D adds the fine detail on top. Remaining flaws: light streaks
  where the skirt panels part, and a hem that comes out light grey although the input's lace is black.
- **Shoes:** stitching, toe-cap and heel seams show. The sole's side wall comes out blotchy, a texture flaw the
  original doesn't have.
- **Hair, top, skirt:** not re-textured.

### UV convention

`MeshBake.bakeWithUVs` writes texel row `(1 − v)·S`. A glTF sampler reading the same UVs reads row `v·S`.
Exporting the bake's UVs unchanged with `GLTFExport` therefore scrambles the texture across charts. The fix is
to export `v' = 1 − v` (`tools/retex-tool/Sources/retex/main.swift`). Today nothing outside the `texturize` gate
calls `TexturingPipeline`, but whoever wires it to a GLB will hit this.

## What it would take

- **Pipeline:** TRELLIS.2 generate (about 13 minutes at res1024 on the M-series Mac), then Hi3D (CUDA, 2–4
  minutes), then re-texture (1–3 minutes on the Mac). Hi3D is the only step that can't run on the Mac.
- **Memory for a Mac port:** 23–31 GB peak at 1024³ on garments. 1536³ is unmeasured on our inputs, probably
  about 40 GB.
- **Port work:** much of TRELLIS.2's infrastructure carries over: sparse convolution, sparse and cross
  attention, flow samplers. The new parts are the PTv3 decoder (windowed attention over a space-filling-curve
  order), FlexiCubes, the Heun scheduler, and the DINOv2 and CLIP conditioners.
- **Open items:**
  - re-texture hair, top and skirt;
  - run 1536³ (HF Jobs on an A100 80 GB is about $3 for all five);
  - fix the sole blotching;
  - close Hi3D's holes, or remesh, before texturing.
