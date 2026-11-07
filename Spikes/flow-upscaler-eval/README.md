# FlowUpscaler: is it worth a port and a Gaea plugin?

**Date:** 2026-11-07 · **Machine:** Mac Studio M5 Max (Mac17,14), 128 GB, macOS 27.3 · **Model:**
[TensorForger/FlowUpscaler](https://huggingface.co/TensorForger/FlowUpscaler) (Unlicense, `flow_upscaler.safetensors`
sha256 `91eb93b4…`) · **Reference:** its own `upscaler_unet.py`, the ComfyUI node's inference
(`TensorForger/comfyui-flow-upscaler`, `nodes.py`) and the training notebook (`tensorforger/CTGMWorkshop`, Unlicense).

## The answer

1. **Higher-resolution Klein: yes, port it.** Klein 4B draws at most 1024² of area in Gaea today. FlowUpscaler takes
   that picture to 2048² in 0.2 s and 4096² in 1 s of model time, keeping the composition the user saw.
   - Klein asked for 2048² itself takes 18 s and draws a different picture, which scores lower (IQA 0.877 vs 0.887).
   - The cost that matters is the FLUX.2 VAE decode: 3.9 s at 2048², 18.7 s at 4096².
   - It belongs inside the Klein plugins (FLUX.2 and FLUX 3 share the VAE: all 251 tensors are identical), so the
     latents never leave the worker.
2. **As a general photo upscaler: no.** On the G-5 photo set it lands between RealPLKSR and VOSR2 without beating
   either where it counts.
   - Its structure is RealPLKSR's at ×2, and worse at ×4.
   - Its perceived quality is a little above RealPLKSR's, well below VOSR2's.
   - It corrupts about twice as many words as Lanczos.
   - The VAE decode makes it no cheaper than VOSR2 at ×4.
3. **The 8K claim is true but costly on a Mac.** Three chained passes run in 3.9 s. Prompt to an 8192² image takes
   about 10 s with the tiny TAEF2 decoder, and the images are clean.
   - The full VAE at 8K costs 103 s and 52 GB at bf16, or 175 s and 104 GB at fp32.
   - The third pass mostly sharpens; it adds little new detail.
   - So 4K is the sensible ceiling for a product, with 8K behind TAEF2 as a preview or an opt-in.

## What it is

- **The network.** A 59M-parameter U-Net of SDXL-style ResNet blocks with no attention. The low-resolution latents
  enter through FiLM conditioning.
- **The latents.** It works on FLUX.2 latents: 32 channels at 1/8, batch-norm normalised the way the training data
  was stored (patchify to 128 channels, normalise, unpatchify).
- **Inference.** One rectified-flow step from noise at t = 1000: `x = noise − v(noise, 1000, low-res)`.
- **Training.** 20K FLUX.2 klein-4B generations at 1024², conditioned on their 512² downscale, re-encoded. So
  512→1024 is the only scale it has seen.
- **Licences.** The weights and code are Unlicense, Klein 4B is Apache-2.0, and TAEF2 is MIT.
- **Speed.** One ×2 pass to 1024² takes 48 ms warm here (PyTorch MPS, fp32), against 8 ms claimed on an RTX 5090.

## 1. Photos: the G-5 creative-upscale set

**The set.** The same 12 images and degradation as `mlxengine-todo/CREATIVE-UPSCALE-EVAL.md` §4.1, rebuilt from the
local Commons corpus (`prep_set.py`).
- Nine Commons crops at about 1 MP, Lanczos-downscaled and passed through JPEG q90, with exact ×2 and ×4 ground
  truth.
- Three Z-Image renders.

**The pipeline.** The FLUX.2 VAE encodes the input (edge-padded to /16), then ×2 is one pass and ×4 two. Decoding
is `flux2-vae-mlx-swift` 0.7.0's exact row-band decode, the decoder a product would use.

**The scores** are the G-5 kit's: `score.py` unchanged, the SigLIP2 IQA harness, Vision OCR (`vosrgate`), and
ArcFace rebuilt in `face_score.py`. RealPLKSR, VOSR2 and Nacre are the stored G-5 rows.

**Calibration:**
- The rebuilt inputs' IQA matches the stored values to 6e-8, so the set is identical.
- The rebuilt ArcFace reproduces the stored input-bicubic baseline to within 0.003.
- Vision OCR has drifted since G-5 (macOS 27.3): two inputs read differently, for example sign-forge's word-F1 is now
  0.85 against 0.67. So the text columns compare FlowUpscaler with Lanczos in this run only, not with the stored arms.

| ×2 | DISTS vs GT ↓ | LPIPS vs GT ↓ | SigLIP2 IQA ↑ (GT 0.891) | ArcFace ↑ (min) | word-F1 | CORRUPTED / FIXED / INVENTED |
|---|---|---|---|---|---|---|
| RealPLKSR (stored) | 0.078 | **0.136** | 0.879 | **0.980** (0.800) | (0.747) | (9 / 27 / 21) |
| VOSR2 (stored) | 0.115 | 0.189 | **0.905** | 0.959 (0.770) | (0.674) | (11 / 21 / 26) |
| **FlowUpscaler, exact decode** | 0.075 | 0.162 | 0.883 | 0.967 (**0.839**) | 0.628 | 20 / 3 / 21 |
| FlowUpscaler, diffusers tiled decode | 0.089 | 0.176 | 0.880 | 0.962 (0.828) | 0.674 | 15 / 4 / 17 |
| Lanczos | **0.074** | 0.244 | 0.876 | 0.980 (0.814) | 0.715 | 10 / 7 / 26 |

| ×4 | DISTS vs GT ↓ | LPIPS vs GT ↓ | SigLIP2 IQA ↑ (GT 0.876) | ArcFace ↑ (min) | word-F1 | CORRUPTED / FIXED / INVENTED |
|---|---|---|---|---|---|---|
| RealPLKSR (stored) | **0.158** | **0.190** | 0.853 | **0.972** (**0.839**) | (0.829) | (5 / 9 / 16) |
| VOSR2 (stored) | 0.165 | 0.234 | **0.904** | 0.955 (0.640) | (0.798) | (8 / 12 / 31) |
| **FlowUpscaler, exact decode** | 0.170 | 0.230 | 0.872 | 0.952 (0.778) | 0.710 | 18 / 3 / 20 |
| FlowUpscaler, diffusers tiled decode | 0.200 | 0.268 | 0.870 | 0.933 (0.780) | 0.643 | 17 / 3 / 24 |
| Lanczos | 0.188 | 0.358 | 0.859 | 0.969 (0.758) | 0.813 | 11 / 4 / 12 |

**What the tables say:**
- At ×2 FlowUpscaler matches RealPLKSR's structure and edges it on perceived quality. It loses on LPIPS and on faces
  (mean), though its worst face is the best of any arm.
- At ×4 it is behind RealPLKSR on structure and faces, and far behind VOSR2 on perceived quality.
- On text it corrupts 18–20 words where Lanczos corrupts 10–11. The words it rewrites are the small ones.
- Hair and skin come out plausibly, with faithful colour (`results/sheets/face-woman-x4.jpg`).

**Cost per image (about 1 MP in):**
- Encode 0.4 s.
- Passes 0.2 s (×2) and 0.2 + 0.7 s (×4).
- Exact decode, fp32: 3–6 s at 6–7 GB (×2), and 18–42 s at 22–27 GB (×4).

For comparison, VOSR2 takes 7–10 s (×2) and 24–30 s (×4) at ≤ 7.2 GB (G-5), and RealPLKSR is a fraction of a second.
A photo tier would add nothing the shipped tiers lack.

**Decoder trap: diffusers' tiled FLUX.2 decode.** `AutoencoderKLFlux2.enable_tiling()` normalises each tile on its
own (GroupNorm), which leaves straight seams and a colour cast. Measured on the same latents:
- it costs FlowUpscaler 0.014 DISTS at ×2 and 0.030 at ×4;
- it shows plainly in `results/sheets/face-woman-x4.jpg` and `poster-x4.jpg`.

Anyone scoring a FLUX.2-latent model through diffusers at more than about 1 MP must decode exactly.
`flux2-vae-mlx-swift`'s row-band decode, with GroupNorm stats taken over all bands, is exact.

## 2. Klein, and the 8K claim

**The run.** Six prompts were drawn by FLUX.2 klein-4B (diffusers, bf16, MPS, 4 steps, guidance 1) at 1024²:
portrait, forest, enamel sign, cat, aerial city and watercolour illustration.
- Klein's own latents were chained through three passes (seeds 0, 1, 2) to 2048², 4096² and 8192².
- Each stage was decoded by the exact Swift VAE and by TAEF2 (banded in latent rows at ≥ 4K, because PyTorch MPS
  can't convolve an 8K image in one go).
- Comparators: the 1024² decode Lanczos'd up, and Klein drawing 2048² itself with the same prompt and seed.

| Time and memory | → 2048² | → 4096² | → 8192² |
|---|---|---|---|
| FlowUpscaler pass (PyTorch MPS, fp32) | 0.22 s | 0.76 s | 2.87 s |
| Full VAE decode, exact (Swift, fp32) | 3.85 s, 7.4 GB | 18.7 s, 26.8 GB | 175 s, 104 GB |
| Full VAE decode, exact (Swift, bf16; 53 dB vs fp32) | — | — | 103 s, 52 GB |
| TAEF2 decode (PyTorch MPS) | 0.16 s | 0.74 s | 2.94 s |

Klein at 1024² takes 3.4 s, and at 2048² 18.0 s. So:
- **prompt to 8192²** takes about 10 s with TAEF2, or about 110 s with the full VAE at bf16;
- **prompt to 2048²** takes about 7.5 s through FlowUpscaler, against about 22 s by drawing it natively.

**Does it keep Klein's picture?** Each stage was Lanczos'd back to 1024² and compared with the 1024² decode (DISTS on
512² crops). Low means faithful.

| Drift vs the 1024² decode | 2048² | 4096² | 8192² |
|---|---|---|---|
| FlowUpscaler, full VAE | 0.015–0.034 | 0.031–0.061 | 0.045–0.088 |
| FlowUpscaler, TAEF2 | 0.029–0.048 | 0.051–0.081 | 0.062–0.099 |

Each later pass moves 0.020–0.043 from the stage before it. The composition never changes
(`results/sheets/whole-base-flow-native.jpg`). Klein asked for 2048² instead draws a different picture: other
boats, another skyline, a different lighthouse.

| Mean SigLIP2 IQA, 6 prompts (comparable within a column only) | 2048² | 4096² | 8192² |
|---|---|---|---|
| Klein native | 0.877 | — | — |
| FlowUpscaler, full VAE | **0.887** | 0.860 | 0.856 |
| FlowUpscaler, TAEF2 | 0.888 | 0.870 | 0.870 |
| Lanczos of the 1024² | 0.887 | 0.849 | 0.843 |

**What the eye says** (`results/sheets/*-zoom.jpg`: one 64² region of the 1024² followed through every stage at
512²):
- The first pass adds real detail: skin texture, plaster, sharp letter edges.
- The second and third mostly sharpen. They are trained only at 512→1024, so past that scale they don't invent
  structure.
- No pass makes tiling, ringing, repetition or invented text.
- TAEF2 is softer and slightly redder at 8K.

## 3. Recommendation

- **Port it for Klein**, an ask to `mlx-image`:
  - a Swift/MLX `FlowUpscaler` module in a FLUX.2-latent package, with parity against `upscaler_unet.py` (59M
    params, convs, GroupNorm, FiLM, about 300 lines);
  - weights converted to bf16 (about 120 MB);
  - route its 3×3 convs around MLX's Metal Winograd window (AB-R-0340).
- **Then in Gaea**, a feature in `gaea-plugin-flux2-klein` and `gaea-plugin-flux3-klein`, not a plugin of its own:
  - lift the size envelope to 2048² and 4096²;
  - a request for a size over 1024² draws at 1024² of the same aspect, then runs one or two passes in the worker;
  - decode with the row-band VAE;
  - charge the decode's measured peak to the lane's footprint;
  - report `effective.upscaled: true`.
- **Untested:** FLUX 3 Klein's own outputs. The latent space is the same, but the training data was FLUX.2 klein's.
  Check this before turning it on for the FLUX 3 plugin.
- **8K:** behind TAEF2 as a fast preview, or opt-in with the full VAE (52 GB at bf16), never by default.
- **Photos:** don't register it as an `image.upscale` tier.

## Files

| Path | What |
|---|---|
| `flowup.py` | The reference pipeline: VAE encode and decode, bn normalisation, one ×2 pass |
| `prep_set.py` | Rebuilds the G-5 photo set from the local Commons corpus |
| `run_photos.py`, `photos_latents.py` | The photo arms and timings (PyTorch), and the latents for the exact decode |
| `run_klein.py`, `score_klein.py` | The Klein generations, the 8K chain, TAEF2, drift and zoom sheets |
| `score.py` | The G-5 kit's scorer, unchanged |
| `face_score.py`, `report.py` | ArcFace rebuilt, and the photo tables against the stored G-5 rows |
| `results/` | Tables, raw scores, IQA, faces, timings (PyTorch and Swift), drift, and the sheets |

**Outside the repo:**
- The work folder, venv and every image are in `/Volumes/DEV_VOL1/flow-upscaler-eval/`. The tools there are the IQA
  harness, `vosrgate` and `VAEDecode`, a Swift tool on `flux2-vae-mlx-swift`'s `decodePackedLatents(_:tile:)`.
- The weights are in `/Volumes/DEV_VOL1/Models/Models/models--TensorForger--FlowUpscaler` and `models--madebyollin--taef2`.
