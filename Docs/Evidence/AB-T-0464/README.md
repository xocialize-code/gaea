# AB-T-0464: FLUX.2 Klein and FLUX 3 Klein at 2048² and 4096²

The two Klein plugins now reach 4096² by latent upscaling. Gaea charges each of those jobs for its size. The pieces:
- **FlowUpscaler** (TensorForger, Unlicense; evaluated in AB-R-0795) is ported to Swift/MLX and wired into
  flux2-klein-swift 0.11.0 and flux3-klein-swift 0.7.0 (AB-A-0257, AB-R-0797).
- **The plugins:** gaea-plugin-flux2-klein 0.3.0 and gaea-plugin-flux3-klein 0.2.0.
- **Gaea 1.2.0** charges each job on its lane's `ActivationScaling` line.

All runs were on an M5 Max (128 GB, macOS 27.3), with the weights in `/Volumes/DEV_VOL1/Models`.

## What changed

- **gaea-plugin-flux2-klein 0.3.0:**
  - Past 1024² of area, Klein draws a quarter (up to 2048²) or a sixteenth (up to 4096²) of the area, and
    FlowUpscaler doubles the latents once or twice before the row-band decode.
  - Sides are multiples of 16 × 2^passes. The draw is 256–2048 px a side.
  - Effective reports `x-klein.upscaled` {from, passes, model}.
  - Edits upscale only when they ask for a size.
- **gaea-plugin-flux3-klein 0.2.0:**
  - Up to 2048² it draws natively, as before. Past it, it draws a sixteenth of the area and upscales ×4 (multiples of
    64).
  - Effective reports `x-flux3.upscaled`.
- **Both plugins:** move to mlx-engine-swift 0.74.1 and GaeaPluginKit 0.11.1, and name the fleet's mlx-swift fork in
  their root (AB-D-0208).
- **Gaea 1.2.0:**
  - A lane that declares an `ActivationScaling` on `outputPixels` is admitted and charged per job at the line's value
    for the job's planned size, and only while the job runs (`LaneChoice.workload`, `transient`, `need(_:params:)`,
    and `Slot.runTransientBytes`).
  - Such a lane never learns a single measured peak from its largest job.
  - Lanes without a line are charged as before.
  - Three new unit tests; 86/86 pass.

## Results

**Goldens** (`golden/`, each plugin's `scripts/golden.sh`), over GPP against in-process, byte for byte:
- **FLUX.2 Klein: 19/19.**
  - Sizes: 1024², 2048², 4096², 1536×1024, Base at 1792×1024, and an edit at 2048².
  - The adapter edit and its control.
- **FLUX 3 Klein: 13/13**, a new script:
  - native: 1024² and 2048²;
  - upscaled: 4096², 3072×2048, and an edit at 4096².

**Acceptance** (`tools/acceptance-klein-upscale.sh`), in two runs, both **24 passed, 0 failed**:
- `standin/`: before release, against the local Gaea 1.2.0 build, with the plugins served by `tools/release-standin.py`.
- `github/`: after release, against Gaea 1.2.0 from its notarized release, with the plugins from GitHub. The images
  match the stand-in run exactly.

| Through Gaea 1.2.0 (github run) | Time | Made from | Drift vs the 1024² image (DISTS) |
|---|---|---|---|
| Klein 4B 1024² | 7.5 s | drawn | — |
| Klein 4B 2048² | 10.8 s | 1024² ×2 | 0.024 |
| Klein 4B 4096² | 28.8 s | 1024² ×4 | 0.044 |
| FLUX 3 Klein 1024² | 19.2 s | drawn | — |
| FLUX 3 Klein 2048² | 101.7 s | drawn natively | — |
| FLUX 3 Klein 4096² | 39.6 s | 1024² ×4 | 0.051 |

- **Pixel identity:** 2048² and 4096² match `klein-inproc` pixel for pixel, and FLUX 3's 4096² matches
  `flux3-inproc`. Gaea re-encodes the PNG as RGBA, so the bytes differ; the goldens check bytes at the worker.
- **More cases:**
  - Klein 4B Base 1792×1024 is drawn at 896×512 and upscaled once.
  - An edit asked at 2048² is drawn at 1024² and upscaled once.
  - 1536×1000 is made at 1536×992, with `size_snapped`.
  - 4096×200 fails cleanly with `invalid_request`. Gaea raises the short side to the offer's 256 (making 5472×256),
    and the plugin refuses that draw.
- **Memory:** Klein 4B bf16 is charged, while each job runs, exactly what its line declares:
  - **25.9 GB for a 1024² job and 41.7 GB for a 4096² job.** The flat charge would have been 25.9 GB for every job;
    the measured 4096² peak is 40.7 GB.
  - No lane learned a single peak or overran its declaration.
  - With the budget cut to 27.9 GB, a 1024² job runs, and a 4096² job is refused `no_capacity` (every lane's 4096²
    need, from 36.3 GB, is past the budget).

**Conformance** (`conformance/`): media-engine-spec v0.10.1 against Gaea 1.2.0 from its release, with all 25
public plugins and all seven opt-in models enabled (AuK-Flash, AuK, LTX's four tiers and FLUX 3 Klein):
**88 passed, 0 failed, 7 skipped**, the same as before. Base, Image, Audio and Video conform. The skips are the
structural seven: paired mode, expiries longer than the suite waits, and no video previews.

## Notes

- **FLUX 3 Klein at 2048²:** drawn natively it takes about 100 s, while 4096² upscaled from a 1024² draw takes
  about 40 s.
  - Upscaling ×2 from 1024² would make 2048² in about 21 s (AB-R-0797), but it draws a smaller picture than FLUX 3's
    native 2048².
  - 0.2.0 keeps the native draw, so existing 2048² results don't change. Whether to switch is the operator's call.
- **Plain FLUX.2 draws:** the package refuses one over 2048² and decodes one over 1024² in row bands. The plugin never
  sends one over 1024²: past that it always upscales.
