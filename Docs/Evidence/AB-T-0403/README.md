# AB-T-0403: SeedVR2 on video.upscale

| | |
|---|---|
| **Date** | 2026-11-01 |
| **Gaea** | 0.10.1 (dcc5755), on media-engine-spec v0.9.0 (Video 0.1) and GaeaPluginKit 0.9.0 |
| **Plugin** | [gaea-plugin-seedvr2 0.1.0](https://github.com/xocialize-code/gaea-plugin-seedvr2/releases/tag/v0.1.0) (886901e), on mlx-seedvr2-swift 0.10.1. Built, signed, notarized and stapled by its release workflow |
| **Spec** | MES Video 0.1 §1.7, §1.9, §3.4, §4 (media-engine-spec v0.9.0) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every clip, job record and session are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0403` |

## What it took

**gaea-plugin-seedvr2 0.1.0** has two models on one package, `SeedVR2UpscalePackage`, one per quality tier
(VIDEO-EVALUATION §6.2):

| Model | `quality` | Lane |
|---|---|---|
| `seedvr2-int8` | `draft`, `standard` | `int8` (4.7 GB of weights) |
| `seedvr2-fp16` | `best` | `fp16` (8.4 GB) |

Each model has one lane, so a tier refused for memory is never swapped for the other (Video §3.4).
- **Scale** 2 or 4, default 2 (the offer's `defaults`).
- **Content:** both `live_action` and `drawn`.
- **Limits:** up to 1920×1080 out and 60 s.
- **Seed:** none, and deterministic. The package's seed is in its configuration, fixed per lane.
- **Pipeline:** the package's defaults, with 9-frame temporal windows, 256-pixel tiles and colour correction.

Its in-process reference is `seedvr2-inproc`.

**Gaea 0.10.1** bounds an upscale's output by the offer's `max_width` and `max_height` (Video §3.4). The output is the
source's size × `scale`, the request's or else the offer's default. A larger one is 422 `out_of_limits` on `video`,
once Gaea has read the source. In 0.10.0 only `interpolate`'s sizes were checked.

## Result

| Done = | Result |
|---|---|
| Over GPP, against in-process | **Pass, 8 of 8** ([golden.log](golden.log)): int8 ×2 and ×4 on a 128×96, 17-frame clip, int8 ×2 on a 320×180, 48-frame clip (six windows), and fp16 ×2. Each pair decodes to the same frames, byte for byte (`framemd5`), at size × scale with the source's frame count. The four sessions validate |
| Through Gaea, installed from GitHub | **Pass, 18 of 18** ([acceptance.log](acceptance.log), `tools/acceptance-seedvr2.sh`, `REPO_FROM=github`): see the list below |
| Conformance | **With every G1 plugin, the five audio plugins, RIFE and SeedVR2: 73 passed, 0 failed, 18 skipped; Base 0.1, Image 0.1, Audio 0.1 and Video 0.1 conform** ([report](conformance/report.md)), under v0.9.0's suite as shipped. VIDEO-011 now runs and passes, and VIDEO-013 checks both upscale and interpolate. The other skips are generate, extend, retake and previews, which have no offers yet |

What the 18 acceptance checks cover:
- **The offers:** `video.upscale` lists both models, with their tiers, scales, contents, no seed, `deterministic` and
  their limits.
- **×2, no quality named:** runs on `seedvr2-int8`.
  - The output is 256×192, the same 17 frames at exactly 24 fps (0.708333 s), in HEVC.
  - It reports effective scale, fps, size and frames.
  - The source's AAC track (48 kHz stereo) and its comment are kept.
  - The frames are `seedvr2-inproc`'s, decoded byte for byte.
- **×4 with `drawn`:** 512×384, 17 frames, with `seedvr2-inproc`'s frames.
- **Quality:** `best` runs on `seedvr2-fp16`, with `seedvr2-inproc --quant fp16`'s frames. `draft` runs on
  `seedvr2-int8`.
- **A larger clip:** 320×180 with 48 frames gives 640×360 with 48 frames at 24 fps.
- **Codec:** `output.codec` `h264` gives H.264 with sound.
- **Refusals:**
  - no `content` is 400 `invalid_request`;
  - scale 3 is 422 (`out_of_limits` on `scale`, the descriptor's enum);
  - 1280×720 ×2, which would be 2560×1440, is 422 `out_of_limits` on `video`;
  - a 61 s source is 422 `out_of_limits` on `video`.

| Job (warm) | In-process | Through Gaea (worker) |
|---|---|---|
| 128×96, 17 frames, ×2, int8 | 3.70 s | 3.5–4.1 s |
| ×4, int8 | 19.1 s | 19.5 s |
| ×2, fp16 | 4.72 s | 3.63 s |
| 320×180, 48 frames, ×2, int8 | 53.7 s | 54.6 s |
| The first job through Gaea (worker launch, prepare, upscale, finish) | | 4.85 s from submit to settled |

The worker held both models at 17.07 GB `phys_footprint` against 16.80 GB declared ([ledger.txt](ledger.txt)).
In-process, int8 peaks at 4.9 GB RSS and fp16 at 8.6 GB.

## Found on the way

- **The seed lives in the package's configuration.** `VideoUpscaleRequest` has no seed, so a per-job MES `seed` would
  mean re-registering the package. The offers say `seed: false` with `deterministic: true`, which is true at the fixed
  seed. A request-level seed is added to mlx-video's AB-A-0238.
- **Memory grows with the output's size, not the declared footprint.** At 9-frame windows each extra 256-pixel tile
  position holds about 0.8 GiB, so a 1920×1080 output is about 48 GiB (AB-A-0238 item 6). The package narrows its
  window to fit the budget Gaea sends the worker, and Gaea's governor charges the measured footprint. At the sizes run
  here the measured footprint stayed within the declared one.
- **The 1/600 time base** (AB-A-0239) didn't show at 24 fps, which is exact on it. Gaea retimes every transformation
  anyway.

## Not covered

- **Large outputs:** nothing above 640×360 was upscaled. 1080p out, where the temporal window has to narrow on smaller
  budgets, wasn't run.
- **Progress and previews:** the package reports neither (AB-A-0238 item 2).
- **A tier refused for memory:** that `best` is refused rather than swapped follows from one lane per model, but no
  staged budget was run to show it. That comes with the governor order.
