# AB-T-0365: gaea-plugin-z-image, the first real G1 plugin

| | |
|---|---|
| **Date** | 2026-10-28 |
| **Plugin** | [xocialize/gaea-plugin-z-image v0.1.0](https://github.com/xocialize/gaea-plugin-z-image/releases/tag/v0.1.0): Developer ID, notarized (Accepted), Gatekeeper "Notarized Developer ID". On z-image-swift 0.5.4, mlx-engine-swift 0.72.0 and GaeaPluginKit [0.2.0](https://github.com/xocialize/gaea-plugin-kit/releases/tag/v0.2.0), Apache-2.0 |
| **Host** | Gaea 0.2.0, Release, `dist/Gaea.app` |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Weights** | MLXEngine's store, `~/Library/Application Support/MLXEngine/Models` (`mlx-community/Z-Image-Turbo-bf16`, `mlx-community/Z-Image-bf16`), already on disk: no download |
| **Script** | [`tools/acceptance-z-image.sh`](../../../tools/acceptance-z-image.sh), twice. From the published GitHub release with no token: **12 passed, 0 failed** ([github/acceptance.log](github/acceptance.log)). Earlier, from the same build served by the release stand-in: 12 of 12 ([acceptance.log](acceptance.log)) |

## What the plugin is

| Model | Offers | Lanes |
|---|---|---|
| `z-image-turbo`: distilled 8 steps, no CFG | `image.generate` for draft and standard (Gaea's default); `image.edit`, named-only | int4 (default), int8, bf16 |
| `z-image`: base model, 28 steps, CFG 4, negative prompts | `image.generate` for best; `image.edit`, named-only | int4 (default), int8, bf16 |

- **Lanes.** Each lane is a DiT quant, carrying z-image-swift's measured footprint at the 1536² cap: 39.9, 43.0 and 48.5 GB (resident plus the 28 GB peak).
- **Sizes and count.** `size`, or `aspect` with `megapixels`, is fitted to 256–2048 px a side, at most 1536² in area, in multiples of 16 (`size_snapped`). `count` 1–8 makes one engine call per image, with `seed + i`.
- **Options.** `x-zimage.steps` and `x-zimage.guidance` (base only).
- **Warnings.** On Turbo, `negative_prompt` is reported `negative_prompt_ignored`.
- **Edit.** `image.edit` is image-to-image at `strength` (default 0.75), at the input's size.

## Acceptance

| Done = | Result | Evidence |
|---|---|---|
| gaea-plugin-check reports ALL PASS on the notarized release, and Gatekeeper accepts it | **Pass** | `scripts/release.sh`: check ALL PASS, with every `.build` hidden. The int4 lane prepared in 0.93 s (warm page cache) and a 512² image generated in 2.71 s. The control (the bare worker outside the bundle) fails on the metallib. Notarization Accepted; `spctl` "Notarized Developer ID". |
| Gaea installs and enables it by its repo URL | **Pass** | `gaea plugins add https://github.com/xocialize/gaea-plugin-z-image` against the real GitHub release, anonymously: both models are on, Turbo is `image.generate`'s default, and Z-Image is listed for `best` ([operations.json](github/operations.json), [models.txt](models.txt)). |
| Turbo int4 1024², fixed seed and prompt, through Gaea is the same image as z-image-swift in-process | **Pass, byte for byte** | Seed 42, 8 steps: both give sha256 `ac59f107c37c9601…` ([gaea-turbo-0.png](gaea-turbo-0.png)). The in-process side is AB-T-0356's `bench-inproc` ([inproc.json](github/inproc.json)). A warm rerun gives the same bytes. |
| A receipt: cold start and steady-state seconds per image, against AB-T-0356's 12.52 s | **Filed** | See the timings below. |

## Timings (Release, from the GitHub run)

| | Through Gaea | In-process (`bench-inproc`) |
|---|---|---|
| Cold, Turbo int4 1024²: launch, prepare and the first image | 12.76 s submit to settled (run 12.72 s) | 12.40 s (prepare and run1) |
| Warm, Turbo int4 1024² | 11.46 s | 11.47 s |
| Turbo int8, 992² | 11.91 s | |
| Base model int4, 1024², 28 steps CFG 4 | 72.73 s | |
| Turbo int4, 768×512, two images | 7.94 s | |
| Turbo int4 edit, 1024², strength 0.8 | 11.72 s | |

- **The worker costs nothing measurable at steady state.** The warm run took 11.46 s through Gaea against 11.47 s in-process. Cold is 0.36 s slower than in-process, which is the launch and hello; AB-T-0356 measured 12.52 s and 12.59 s.
- **The ledger** after the run ([ledger.txt](ledger.txt)): one worker with both models' int4 lanes prepared, declared 51.8 GB and measured at 26.2 GB `phys_footprint`.

## Also checked

- `quality: best` with no model reaches the base model: 28 steps, guidance 4, the negative prompt honoured ([job-best.json](job-best.json), [preview](gaea-base-0-preview.jpg)).
- `count` 2 at 768×512 gives two different images, seeds 7 and 8. Turbo reports the negative prompt as ignored ([job-count.json](job-count.json)).
- `x-gaea.lane: int8` runs lane int8; 1000² snaps to 992² with `size_snapped` ([job-int8.json](job-int8.json)).
- `image.edit` on Turbo re-generates the uploaded 1024² image toward "the same lighthouse in a snowstorm at night" at strength 0.8 ([job-edit.json](job-edit.json), [preview](gaea-edit-0-preview.jpg)).
- The recorded GPP session passes `tools/validate.py --transcript`.

## Fixed along the way

- **GaeaPluginKit 0.2.0.**
  - `EngineOperation(op, calls:)` makes one engine call per result, so an MES `count` works on a capability that returns one image per call.
  - `Job.text(_:)` reads a text input file.
  - `gaea-plugin-check` gains `--models-root`, `--model`, `--lane`, `--model-params`, `--seed`, `--text`, `--input` and `--timeout`, so a plugin with real weights can be checked without a download.
- **The acceptance scripts' `job()` helper** declared `local j` inside its polling loop. In zsh, re-declaring a set local prints it, so any job that needed a second poll wrote `j='…'` into its JSON. The first run here failed 6 checks that way. It's fixed in `acceptance-g0.sh`, `acceptance-offers.sh` and `acceptance-z-image.sh`. AB-T-0355's and AB-T-0364's runs had no job long enough to hit it.

## Not covered here

- **bf16, and int4 on a smaller Mac.** The bf16 lane, and the int4 lane on a Mac smaller than this one, weren't run. On 128 GB every lane fits, so lane fallback with this plugin is exercised under a small `--budget-bytes` in AB-T-0363.
- **The release CI.** The workflow fails on the tag push because its signing and notary secrets aren't set (the same as the demo's runs). That is by design: a CI release that skipped notarization must never look green. This release was built, checked, notarized and published locally.
