# AB-T-0369: gaea-plugin-forge, the processing pack

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Plugin** | [xocialize/gaea-plugin-forge v0.1.1](https://github.com/xocialize/gaea-plugin-forge/releases/tag/v0.1.1): Developer ID, notarized (Accepted), Gatekeeper "Notarized Developer ID". On GaeaPluginKit 0.2.2, mlx-engine-swift 0.73.0, and ForgeCore 0.43.0's model packages; Apache-2.0 |
| **Host** | Gaea 0.4.1, Release, `dist/Gaea.app` |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Scripts** | Over GPP: `scripts/golden.sh` in the plugin repo, **15 of 15 byte-identical** ([golden/golden.log](golden/golden.log)). Through Gaea, from the GitHub release: [`tools/acceptance-forge.sh`](../../../tools/acceptance-forge.sh), **22 passed, 0 failed** ([acceptance.log](acceptance.log)) |

## What the pack is

Fourteen models in one worker process, each registered in the configuration ForgeCore's `ForgeEngineService`
registers it with, under mlx-image-runtime's catalog id, so the image normalizer's table applies to it.

| MES operation | Models | Default, from the normalizer's table |
|---|---|---|
| `image.fill`, `image.erase`, `image.extend` | `lama-inpaint` (LaMa; MI-GAN as its `fast` mode, at draft) | LaMa |
| `image.upscale` | `nerve-upscale`, `realplksr-upscale`, `heart-upscale` | RealPLKSR; HEART at best |
| `image.matte` | `birefnet-matte` | BiRefNet |
| `image.segment` | `edgetam-segment`, `sam21-segment` | SAM 2.1; EdgeTAM at draft |
| `image.restore` | `nafnet-restore`, `restormer-motion`, `restormer-defocus`, `restormer-denoise`, `scunet-denoise`, `gfpgan-face`, `restoreformer-face` | by `kind`: NAFNet for general, SCUNet for denoise, Restormer for deblur, GFPGAN for faces |

- **Dependencies.** The worker links only the model packages. `forge-inproc`, the golden reference, links ForgeCore
  itself, and both resolve one version of each package.
- **Bundled weights.** NERVE's, RealPLKSR's and NAFNet's weights ship inside the plugin, in their SwiftPM resource
  bundles under `Contents/Resources`. The build copies every bundle the worker links, and the release notarized with
  them. The other models come from the store.

## Acceptance

| Done = | Result | Evidence |
|---|---|---|
| gaea-plugin-check reports ALL PASS on the notarized release | **Pass** | `scripts/release.sh` for 0.1.0 and 0.1.1: ALL PASS with every `.build` hidden (NAFNet restore on a 256² fixture, from its bundled weights). The bare-worker control fails on the metallib. Notarization Accepted; `spctl` "Notarized Developer ID". |
| Every helper can be called over GPP, and its output matches ForgeCore's in-process golden output | **Pass, byte for byte, 15 of 15** | `golden.sh` runs each call with `gaea-plugin-check` against the signed bundle (launch requirement, configure, prepare, run, shutdown). It runs the same call in `forge-inproc` through ForgeCore's `ForgeEngineService`, then compares the PNGs: LaMa, MI-GAN, NERVE ×2, RealPLKSR ×4, HEART ×4, BiRefNet's matte, EdgeTAM's and SAM 2.1's masks at a point, NAFNet, the three Restormers and SCUNet on the fox fixture, and GFPGAN and RestoreFormer++ on a portrait. |
| A receipt: the worker's footprint with every helper loaded, and with only one | **Filed** | Through Gaea: NAFNet alone, **0.53 GB** `phys_footprint` ([ledger-one.txt](ledger-one.txt)); all fourteen models prepared in the one worker, **2.51 GB**, against 19.61 GB declared ([ledger-all.txt](ledger-all.txt)). |

### Through Gaea

`tools/acceptance-forge.sh` installs the pack from GitHub into a fresh Gaea and runs every model by name, as an MES
job through the image normalizer:
- each output comes back at the right size: exactly input × scale for the upscalers, and the input's size otherwise;
- `quality: draft` on fill runs MI-GAN;
- `restore` with `kind: faces` and no model picks GFPGAN;
- no worker died, and the session passes the validator.

With every G1 plugin installed (Qwen-Image, Z-Image, Klein and this pack), Gaea's conformance:

| Mode | Passed | Failed | Skipped | Report |
|---|---|---|---|---|
| Open | **35** | 0 | 9 | [conformance-open.md](conformance-open.md) |
| Paired | **38** | 0 | 6 | [conformance-paired.md](conformance-paired.md) |

Upscale (IMAGE-002) and matte (IMAGE-004) now run and pass; under AB-T-0366 they were skipped. What's skipped:
- `enhance_prompt` (IMAGE-011, IMAGE-012), which waits for the LLM plugin, AB-T-0370;
- adapters (BASE-013, BASE-029, IMAGE-013);
- output expiry (BASE-071);
- in the open run only, the three paired-mode tests.

### Per model, over GPP

Each call is the first after a cold launch, on the 256² fixture (the face models on the 512² portrait). The footprint
is `phys_footprint` read right after the call, with only that model loaded.

| Call | Prepare | Run | Footprint |
|---|---|---|---|
| LaMa / MI-GAN fill | 0.00 s | 0.06 / 0.07 s | 0.94 / 1.83 GB |
| NERVE ×2 | 0.00 s | 0.14 s | 0.61 GB |
| RealPLKSR ×4 | 0.04 s | 0.21 s | 1.67 GB |
| HEART ×4 | 0.07 s | 0.59 s | 2.41 GB |
| BiRefNet matte | 0.03 s | 0.39 s | 7.11 GB |
| EdgeTAM / SAM 2.1 segment | 0.00 s | 0.06 / 0.07 s | 1.36 / 2.02 GB |
| NAFNet restore | 0.01 s | 0.11 s | 0.53 GB |
| Restormer motion / defocus / denoise | 0.03 s | 0.28–0.29 s | 2.44 GB |
| SCUNet denoise | 0.03 s | 0.17 s | 2.42 GB |
| GFPGAN / RestoreFormer++ | 0.03 s | 0.38 / 0.34 s | 0.82 / 0.81 GB |

BiRefNet's 7.11 GB is MLX's cache right after the call, inside its declared 0.9 + 14 GB. With all fourteen models
loaded and idle, the worker measured 2.51 GB.

## Fixed along the way

- **GaeaPluginKit 0.2.1: bundled weights.** NAFNet's configuration conforms to both `WeightSourcing` and
  `BundledWeightSourcing`. MLXToolKit 1.58 resolves its signage lane as `engine` with nothing to download, which the
  manifest schema refuses. The kit records it as `bundled`.
- **GaeaPluginKit 0.2.2: GPP gets a private stdout.** MLXServeCore's `WeightPrewarmer` `print`s "[Prewarm] …" to
  stdout. In 0.1.0 those lines reached Gaea at shutdown as protocol errors, and the session failed the validator. The
  worker now keeps a private descriptor for GPP and points stdout at stderr, so stray prints land in the worker's log.

  Both bugs are upstream, and are asked of mlx-engine as AB-A-0216.
- **The pack's build script** builds the worker in its own scratch folder and copies every resource bundle into the
  plugin. The check's control copies the packages' own bundles beside the bare worker: its startup reads NAFNet's
  bundled-weights URL, and the control is about MLX's metallib alone.
- **Gaea 0.4.1.**
  - The model host passes a call's own params (`scale`, `kind`, `strength`, `points`, `pointLabels`) and its `mode`
    to the worker.
  - Matting and segmentation come back as mattes, with the model's score.
  - `tools/validate.py` maps operations to MLXToolKit's capability names (`imageInpaint`, `imageUpscale`,
    `promptSegment`, …). It had old names, and refused the pack's offers.

## Deviations from the task

- **Offers, not helpers.** The task says `helpers[]`. Since AB-T-0366 the image normalizer composes Gaea's models
  through their offers of MES operations (`GaeaModelHost`), and these operations are client-facing too, so the pack
  offers them. A helper is still the right shape for a capability with no MES operation: BOPBTL's defect detection, or
  a quality score.
- **No ForgeCore in the worker.** The plugin depends on ForgeCore, but only for the in-process reference. Linking it
  into the worker would bring ForgeCore's generative tiers (SeedVR2, VOSR, FlashVSR, Generative Fill) into the plugin.

## Not covered here

- **A GPU timeout.** On 2026-10-29 at 01:22Z, during a conformance run with the stand-in 0.1.0 build, the pack's first
  BiRefNet matte failed with Metal's `kIOGPUCommandBufferCallbackErrorTimeout`. MLX made it fatal, and the worker
  trapped. Gaea requeued the job on a new worker, and the job succeeded. It hasn't happened since: not in four golden
  runs, two acceptance runs, or two further conformance runs. It's recorded here as seen once.
- **Models ForgeCore registers that the task didn't list:** DRUNet, CIDNet relight, DDColor colorize, BOPBTL defects
  (restore's `scratches`), the SigLIP2 quality score, and the generative upscalers.
- **16-bit** upscale and restore: Gaea's host doesn't pass raw pixels to plugins yet.
