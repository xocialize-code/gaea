# AB-T-0368: gaea-plugin-qwen-image, Qwen-Image-Edit 2511 and Qwen-Image Flash

| | |
|---|---|
| **Date** | 2026-10-28 |
| **Plugin** | [xocialize/gaea-plugin-qwen-image v0.1.1](https://github.com/xocialize/gaea-plugin-qwen-image/releases/tag/v0.1.1): Developer ID, notarized (Accepted), Gatekeeper "Notarized Developer ID". On qwen-image-edit-swift 0.11.0, mlx-engine-swift 0.72 and GaeaPluginKit 0.2.0, Apache-2.0 |
| **Host** | Gaea 0.2.2, Release, `dist/Gaea.app` |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Weights** | MLXEngine's store, `~/Library/Application Support/MLXEngine/Models` (`Qwen/Qwen-Image-Edit-2511`, 54 GB; `mlx-community/Qwen-Image-Flash-8bit`, 28 GB), already on disk: no download |
| **Script** | [`tools/acceptance-qwen.sh`](../../../tools/acceptance-qwen.sh), from the published GitHub release with no token: **13 passed, 0 failed** ([acceptance.log](acceptance.log)) |

## What the plugin is

| Model | Offers | Lane |
|---|---|---|
| `qwen-image-edit`: Qwen-Image-Edit 2511, 20B DiT with Qwen2.5-VL-7B conditioning, Apache-2.0 | `image.edit` for standard and best: 1–3 references, 20 steps of true CFG at 4 | `bf16`: 42 GB resident, 21 GB peak, 63 GB scheduled |
| `qwen-image-flash`: NVIDIA's DMD2 4-step distill of Qwen-Image, NVIDIA Open Model License | `image.generate` for draft and standard | `int8` (pre-quantized): 22.3 GB resident, 9.3 GB peak, 31.6 GB scheduled |

- **Flash and Edit are in one package**, `qwen-image-edit-swift`, so they ship as one plugin.
- **Edit sizes.** Qwen-Image-Edit draws about 1024² at the first image's aspect, in multiples of 32. It ignores a
  requested size. Gaea reports the change as `size_snapped`: a 1280×768 input is edited at 1312×800.
- **Flash's licence** is sent to clients as `LicenseRef-NVIDIA-Open-Model`, commercial use allowed, with the notice
  the licence requires: "Licensed by NVIDIA Corporation under the NVIDIA Open Model License".
- **Settings.** None: mlx-image-runtime's catalog has no environment variants for either model.

## Acceptance

| Done = | Result | Evidence |
|---|---|---|
| gaea-plugin-check reports ALL PASS on the notarized release | **Pass** | `scripts/release.sh` for 0.1.0 and 0.1.1: check ALL PASS with every `.build` hidden (Flash int8, 512², 6.47 s, peak 30.6 GB of the 31.6 declared); the bare worker fails on the metallib. Notarization Accepted; `spctl` "Notarized Developer ID". |
| Gaea installs the plugin by its repo URL | **Pass** | `gaea plugins add https://github.com/xocialize/gaea-plugin-qwen-image` against the real release, anonymously ([operations.json](operations.json), [models.txt](models.txt)). |
| Edit through Gaea matches the in-process output for fixed seeds | **Pass, byte for byte** | Against `qwen-inproc`, the plugin repo's in-process reference on the same dependency resolution: a two-reference edit, seed 7 ("Put the fox from Picture 1 on the rug in the cabin from Picture 2", sha256 `a12e59d2db441ba7…`, [preview](gaea-edit-0-preview.jpg)), and Flash int8 1024², seed 42 (`bf76d3cfde6aa105…`, [png](gaea-flash-0.png)). Earlier 0.1.0 runs gave the same bytes. |
| A receipt: cold start, seconds per image and each lane's resident footprint, Release | **Filed** | See below. |

## Timings and memory (Release)

| | Through Gaea, worker run | In-process (`qwen-inproc`) |
|---|---|---|
| Flash int8 1024², warm | 11.80 s | 11.77 s |
| Flash int8 1024², cold: launch, prepare, first image | 13.98 s submit to settled (run 12.48 s) | 14.59 s (prepare 2.08 s, run 12.46 s) |
| Flash int8 1280×768 | 10.84 s | |
| Flash int8 768×512, two images | 9.00 s | |
| Edit bf16, two 1024² references, 20 steps CFG 4: prepare beside Flash, then the edit | 554.2 s submit to settled (run 548.4 s) | 544.6 s (prepare 3.50 s, run 541.0 s) |
| Edit bf16, one 1280×768 reference, warm | 292.0 s | |

| Lane | Resident, measured (`phys_footprint`) | Declared |
|---|---|---|
| Flash int8 | 24.06 GB after prepare in-process; 26.44 GB in the worker after its runs ([ledger-1-flash.txt](ledger-1-flash.txt)) | 22.3 + 9.3 GB |
| Edit bf16 | 43.51 GB after prepare in-process, 45.80 GB after the edit; with Flash in the same worker, 66.46 GB together ([ledger-2-both.txt](ledger-2-both.txt)) | 42 + 21 GB |

- **The worker costs nothing measurable,** within 1.5 % of in-process in every row.
- **The edit is slow:** about 27 s a step with two references and 15 s with one. In-process is the same, so the cost
  is the package's. Qwen-Image 2.1's port measured 3.6–3.9 s a step at 1024² (AB-R-0259), with its reference tokens'
  K/V cached. Asked of mlx-image as AB-A-0214.
- **One worker holds both models,** declared 85.3 GB against Gaea's 103 GB budget here.

## Also checked

- An `image.edit` naming no model or quality reaches Qwen-Image-Edit at standard, and a 1280×768 input comes back
  1312×800 with `size_snapped` ([job-edit-wide.json](job-edit-wide.json), [preview](gaea-edit-wide-0-preview.jpg)).
- `count` 2 at 768×512 gives two different images, seeds 7 and 8; Flash reports a negative prompt as ignored.
- Four references are refused `out_of_limits` (`images`) when the job is submitted.
- The recorded GPP session passes `tools/validate.py --transcript`.

## Fixed along the way

- **Gaea 0.2.2 applies an offer's `max_images`.** Gaea had left every image input at MESKit's default count, 4 for
  `image.edit`, so a four-reference request reached Qwen-Image-Edit. The descriptor now takes the most any offer
  allows, when every offer says (`GaeaEngine.maxImages`, tested). Klein's five-reference refusal in AB-T-0367 came
  from MESKit's default, which is 4 too; its evidence now says so.
- **Plugin 0.1.1 widens the quality tiers.** With only this plugin installed, an `image.edit` naming no model or
  quality asked for `standard`, which 0.1.0's Qwen-Image-Edit didn't offer, and was refused. Edit now offers standard
  and best, and Flash draft and standard. When Klein is installed too, it stays `image.edit`'s default.
- **The acceptance script** first reused an MES upload, which is single-use. Each job now uploads its own.

## Not covered here

- **Edit Turbo** (the Lightning 4-step LoRA, with an int4 tier of about 29 GB) would bring Qwen editing to smaller
  Macs. It needs the LoRA and the pre-quantized DiT from `xocialize/qwen-image-edit-2511-mlx-int4`, neither of them
  on this Mac.
- **Flash's bf16 lane** (60.7 GB) needs `mlx-community/Qwen-Image-Flash-bf16`, a 41 GB download not on this Mac.
- **Adapters**, which Flash and Edit Turbo take per request: Gaea doesn't route adapters to plugins yet.
- **Text rendering.** The catalog calls Flash strong at text, but its one sign here reads "GEEA" for "GAEA"
  ([preview](gaea-cabin-0-preview.jpg)). One sample is not a measurement.
- **The release CI** fails on each tag push because the signing and notary secrets aren't set, as for the other
  plugins. Both releases were built, checked, notarized and published locally.
