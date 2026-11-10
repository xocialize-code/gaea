# gaea-plugin-z-image 0.2.0: NitroFusion2

z-image-swift moved from 0.5.4 to 0.7.1 on 2026-11-09 (mlx-image, AB-T-0469). The only change is a new tier,
NitroFusion2: Z-Image Turbo distilled to 1–4 steps (Chen & Song, Apache-2.0). Turbo and base are unchanged. The plugin's
0.2.0 offers it as a third model, `z-image-nitrofusion2`, and moves to GaeaPluginKit 0.12.0 with mlx-engine-swift 0.74.1
and the mlx-swift fork 0.32.4 pinned exactly.

All runs were on a Mac Studio (M5 Max, 128 GB, macOS 27.3) with Release builds, through Gaea 1.5.0. The full outputs are
on `/Volumes/DEV_VOL1/Evidence/zimage-0.2.0`.

## Results

- **The manifest against 0.1.2's:** Turbo's and base's models, lanes and four offers are the same but for the engine's
  contract version (1.58 to 1.59). One model and one `image.generate` offer are new.
- **The plugin against in-process** ([golden.log](golden.log), `scripts/golden.sh`): 10/10. NitroFusion2 at two steps
  (int4 and bf16, 1024²), one step and four steps, and Turbo as the control, each the same PNG byte for byte over GPP on
  the signed bundle as through `zimage-inproc`.
- **Through Gaea, from GitHub** ([acceptance.log](acceptance.log), `tools/acceptance-nitrofusion2.sh`): 14/14.
  - NitroFusion2 is offered by name only and has no `image.edit`; Turbo is still the default.
  - By name it runs two steps, pixel for pixel `zimage-inproc`'s.
  - Warm at 1024² on int4: 4.3 s against Turbo's 12 s.
  - One and four steps run as asked, five is refused, and a negative prompt is reported ignored.
  - A request naming no model still runs Turbo, pixel for pixel as before.
- **Conformance with the image plugins** ([conformance.md](conformance.md)): 43 passed, 0 failed, 64 skipped (no audio,
  video or mesh plugin was installed). Base and Image conform.
- **A two-step render** ([nf2-2step-512.png](nf2-2step-512.png), scaled down from 1024²).

## What the first acceptance run showed

The plugin's offer says `quality_tiers: ["draft"]`, but on the image path that field isn't what clients see.
pixel-agency-normalizer's operation table decides which model answers each tier: `klein-4b` for draft, `z-image-turbo`
for standard and best. A model it doesn't list shows as `standard`. So NitroFusion2 can't become a tier's default from
the plugin or from Gaea; that takes a change to the normalizer's table, which mlx-apps owns.

## Not covered

- Quality was judged by eye in mlx-image's receipts (AB-R-0818, AB-R-0819), with no metric. Small text is weaker than
  Turbo's.
- NitroFusion2's int8 lane wasn't run here; its footprint is Turbo's plus the LoRA, not measured.
- Sizes above 1024² weren't run.
