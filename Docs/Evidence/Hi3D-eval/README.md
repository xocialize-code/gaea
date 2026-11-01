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

`MeshBake.bakeWithUVs` wrote texel row `(1 − v)·S`, while a glTF sampler reading the same UVs reads row `v·S`.
Exporting the bake's UVs unchanged with `GLTFExport` therefore scrambled the texture across charts, and the
first runs here exported `v' = 1 − v` to compensate.

mlx-trellis2-swift 6037d1c (AB-A-0223) fixed the bake: it now takes glTF UVs (row `v·S`, like
`MeshBake.run`). `tools/retex-tool` exports UVs unchanged and needs that commit.

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
  - ~~run 1536³~~: done 2026-10-31, see below.

## Follow-up: AB-A-0223 (mlx-3d, same day)

- **Decision (AB-D-0189):** spike Hi3D's 512³ pass as a Swift/MLX port (task AB-T-0385), gated against goldens
  dumped on HF Jobs. Admit the license with attribution: mlx-engine is asked to allowlist it in AB-A-0226.
- **Shoe sole blotches:** these are Hi3D geometry. The untextured mesh shows the same relief
  (`screenshots/shoes-sole-textured-vs-geometry.jpg`).
- **Dress streaks:** the skirt slits are already in TRELLIS.2's mesh, and Hi3D keeps them
  (`screenshots/dress-slits-inherited-from-trellis2.jpg`).
- **Holes:** 51–190 single missing triangles per mesh. `trimesh.fill_holes` closes them all
  (`tools/holes.py`).
- **MLXMesh cleanup:** `MLXMesh.fillHoles` *adds* boundary loops on these non-manifold meshes (190 → 1,782 on
  the dress; task AB-T-0386). `removeSmallConnectedComponents` works: on the dress, 2,839 components → 1.
  `tools/retex-tool`'s `unwrap` can run that chain via `CLEAN=<minArea>,<maxPerimeter>[,<repairNonManifold>]`.
- **Receipt:** AB-R-0659.

## 1536³, and goldens for AB-T-0385 (HF Jobs, 2026-10-31)

One HF Job ([`tools/hi3d_job.py`](tools/hi3d_job.py)) ran in the Space's own image
(`hf.co/spaces/townbox/hi3d10-zerogpu`, so the same stack as the 1024³ runs: torch 2.8.0+cu128, flash-attn
2.8.3, spconv 2.3.6, sparc3d @ `23dcc68`, weights @ `705fc09`) on one full RTX PRO 6000 (96 GB):
- **Cost:** 24.4 minutes of GPU time (`rtx-pro-6000`, $2.75 an hour), about **$1.12**.
- **What ran:** the same five inputs as before, 25 Heun steps per pass, seed 0. Two goldens, dress and shoes
  at 512³. A 1024³ dress as a same-GPU control. All five garments at 1536³.
- **Where the outputs are:** the private bucket `xocialize/hi3d-eval` (`run-2026-10-31/`), copied to
  `/Volumes/DEV_VOL1/Evidence/hi3d-eval-2026-10-31/` (7.2 GB). Each run's info is in `runs/jobs-2026-10-31/`,
  and the job's log is `job.log` beside the outputs.

### 1536³ is not worth it at the release's budgets

| Item | 1024³ (Space) | 1536³ (Jobs) | Grid of pass 2 / pass 3 | Verdict |
|---|---|---|---|---|
| dress | 238 s, 31.4 GB | 272 s, 35.1 GB | 109 / 121 | **Moderate.** Eyelets get real grommet holes; waistband and bow crisper; gathers tighter |
| shoes | 139 s, 24.3 GB | 198 s, 29.2 GB | 128 / 156 | **Moderate, and a step back.** Laces, eyelet rims and the tongue's stitch seam cleaner, but the sole's blotchy relief gets stronger |
| top | 138 s, 23.3 GB | 184 s, 26.6 GB | 128 / 156 | **Small.** Crisper tie knot and stripes; fine noise spreads over the plain cloth |
| skirt | 226 s, 31.0 GB | 250 s, 32.9 GB | 115 / 121 | **None** |
| hair | 224 s, 30.3 GB | 229 s, 31.5 GB | 109 / 114 | **Small.** Cleaner edges inside; the strand tips still fray |

The 1024³ column is the Space: half a GPU (MIG 48 GB), default allocator. The 1536³ column is a full GPU. On
the full GPU, the dress control at 1024³ took 157 s and 27.6 GB.

- **Why the gain is small.** The third pass is meant to sample a 192³ structure, but the adaptive voxelizer
  must fit `PASS_BUDGETS[2]` = 110k occupied voxels. It settles at 114–121 on the dress, skirt and hair and at 156 on the
  shoes and top (the runs' `warnings`). Pass 2 already settles at 109–128. On large garments "1536³" is
  5–11% finer than 1024³, and on the shoes and top 22%. Raising the budgets would leave the training
  distribution and is untested.
- **Cost of a third pass.** Twice the faces (the 2M target). On the same GPU the dress went from 157 s and
  27.6 GB to 272 s and 35.1 GB (+73% time, +7.5 GB). The job ran with `expandable_segments`, which the Space
  doesn't use, so the Space's 1024³ peaks aren't directly comparable. Peak memory at 1536³ is 26.6–35.1 GB:
  it fits 48 GB, and the earlier 40 GB guess was high.
- **Meshes** (`runs/mesh-stats-1536.txt`, `tools/mesh_stats_1536.py`): 2M faces. The open edges are about the
  same (165–618; at 1024³, 153–600). Shards go up on the dress, shoes and top and down on the skirt and hair.
- **Run to run.** The same input decodes to 2,713,802 rows in the golden run and 2,709,940 in the control (pass
  1). GPU sparse conv and attention aren't deterministic, as AB-T-0385 assumed.

**For the Mac port:** two passes (1024³) stay the target. 1536³ is worth another look only if the budgets
are raised. Screenshots are `screenshots/1536-*.png`, with 1024³ on the left in each.

### Goldens for the 512³ spike

These are in `golden_dress_512/golden/` (4.7 GB) and `golden_shoes_512/golden/` (2.2 GB). Each holds 42
`.npz` stages and a `manifest.json` with every array's shape and dtype. Float tensors over 20M elements are
float16; everything else is float32 or int.

| Stage | Files |
|---|---|
| Inputs | `input.coarse` (the PLY as loaded) and `input.prepared.png` (after `prepare_image`) |
| Conditioner | `cond.dino` and `cond.clip` (their `pixel_values` and outputs), `cond.tokens` [1, 2917, 2048] |
| Voxelize | `p0.voxelize` (input mesh and coords; dress 21,816 voxels, shoes 10,492) |
| Sampling | `p0.noise` (noise, coords, the 25 timesteps); `p0.step00`, `step12`, `step24` (x, sigma, next sigma, both Heun slopes with their positive and negative outputs, prediction, update); `p0.latents` (normalized, denormalized, mean, std) |
| Transformer at step 0, positive call | `t512.input_layer`, `t512.input_blocks.0` and `.1`, `t512.blocks.0`, `.12` and `.23` (inputs and outputs, 4,275 tokens × 2112 for the dress), `t512.out_blocks.*`, `t512.out_layer`, `t512.t_embedder`, `t512.adaLN_modulation` |
| VAE decoder (outputs; it updates the Point in place) | `dec.z_to_f`, `dec.mid.*`, `dec.dec.dec3` to `dec0`, `dec.conv_out`, and `p0.decoded` (dress: 2.71M rows) |
| Extraction | `p0.mesh_raw` (FlexiCubes, 5.39M faces), `p0.mesh_filled` (after the ear-clip fill), `final.mesh` (postprocessed, 1M faces) |

Run on 512³ alone, the goldens took 74 s and 14.5 GB for the dress and 20 s and 11.6 GB for the shoes.
**Deviation from AB-T-0385's plan:** the task named torch 2.5 / cu124 and flash-attn 2.7.4 on an A100. These
goldens use the Space's torch 2.8 stack on Blackwell, the same stack as every eval run here. The math is the
same; only kernel-level rounding differs.
