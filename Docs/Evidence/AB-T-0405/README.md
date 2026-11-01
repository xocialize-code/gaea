# AB-T-0405: the governor on LTX 2.5's tiers

| | |
|---|---|
| **Date** | 2026-11-01 |
| **Gaea** | 0.11.2 (9e58122, 79e4f28), on media-engine-spec v0.9.0 (Video 0.1) and GaeaPluginKit 0.9.1 |
| **Plugin** | [gaea-plugin-ltx 0.1.1](https://github.com/xocialize-code/gaea-plugin-ltx/releases/tag/v0.1.1), on ltx-2-mlx-swift 0.20.0 (`MLXLTX25Package`), installed from GitHub. Built, signed, notarized and stapled by its release workflow |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2; weights on DEV_VOL1 (external PCI-Express SSD) |
| **Budgets** | Gaea's budget is 3/4 of memory. 32 GB and 64 GB Macs are staged on this one with `--budget-bytes` (the operator's call, 2026-10-31): **25.77**, **51.54** and **103.08 GB** |
| **Large files** | every clip, job record, ledger and session are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0405` |

## What it took

**Gaea 0.11.1:**
- **Offers follow the budget.** A model none of whose lanes fits the budget isn't offered (`PluginOffers.fits`), and
  `gaea models` says why: "not offered: no lane fits the 25.77 GB budget". A request only such a model could serve is
  refused at submit, not queued.
- **The ledger reads each worker's lifetime peak** (`ri_lifetime_max_phys_footprint`), shown beside its charge.

**Gaea 0.11.2: learned peaks.** After each run, Gaea stores the worker's peak per plugin version, model and lane
(`measured-peak/<plugin>@<version>/<model>/<lane>`), and logs `memory_learned` when it passes the declared need. Next
time, the governor admits the lane at the larger of the two: `LaneChoice.learned` rebuilds the lane with peakTransient =
peak − persistent. A new plugin version starts again from its declared needs.

**gaea-plugin-ltx 0.1.1:**
- **compact24's pixel-frame ceiling.** The package refuses work past its `activationScalingHint`
  (`workloadExceedsDeclaredCeiling`): 17.8 M pixel-frames for compact24, so 704×512 is 49 frames, not the 121 the
  envelope gave. The plugin now refuses past each tier's ceiling itself, as `out_of_limits` on `duration_s`, with the
  most frames the size allows.
- **The low tiers load the int8 encoder.** compact24 and balanced32 asked for the int8 Gemma, but the package loaded
  the bf16 component tree (24.8 GB peak). The plugin now points them at `mlx-community/ltx-2.5-mlx-q8` (AB-A-0241),
  and their peak is 14.65 GB.

**The tool:** `tools/acceptance-tiers.sh` runs one Gaea per budget with the plugin from GitHub and all four tiers
enabled. Each envelope job runs on a fresh worker (the plugin is disabled and enabled again), so each peak is that
job's alone. `CORNER=1` adds max128's own corner.

## Result

**Pass, 31 of 31** ([acceptance.log](acceptance.log), [peaks.txt](peaks.txt), [models.txt](models.txt)).

| Budget | Offered (generate, extend, retake) | Not offered |
|---|---|---|
| 25.77 GB (32 GB) | compact24, balanced32 | standard64 (34.8 GB), max128 (75.3 GB) |
| 51.54 GB (64 GB) | compact24, balanced32, standard64 | max128 |
| 103.08 GB (128 GB) | all four | — |

Every job ran within its budget:

| Budget | Tier | Job | Out (w, h, frames) | Time | Peak | Declared | Charged after |
|---|---|---|---|---|---|---|---|
| 25.77 | compact24 | text, at the ceiling | 704, 512, 49 | 46.5 s | 14.65 GB | 16.2 | 16.2 |
| 25.77 | compact24 | text, long | 512, 288, 121 | 50.1 s | 14.65 GB | 16.2 | 16.2 |
| 25.77 | compact24 | first frame | 512, 288, 121 | 49.6 s | 14.65 GB | 16.2 | 16.2 |
| 25.77 | compact24 | extend to 121 | 512, 288, 121 | 51.7 s | **18.55 GB** | 16.2 | **18.55** |
| 25.77 | compact24 | retake | 512, 288, 105 | 51.0 s | **18.56 GB** | 16.2 | **18.56** |
| 25.77 | balanced32 | text | 576, 320, 161 | 52.3 s | 14.64 GB | 18.0 | 18.0 |
| 51.54 | standard64 | text | 1280, 704, 161 | 316.3 s | **44.04 GB** | 34.8 | **44.04** |
| 51.54 | standard64 | 5 s soundtrack | 704, 512, 121 | 71.5 s | 29.04 GB | 34.8 | 44.04 |
| 103.08 | max128 | text | 1920, 1088, 121 | 392.0 s | 63.83 GB | 75.3 | 75.3 |
| 103.08 | max128 | text, the corner | 1920, 1088, 481 | 4051.6 s | **90.91 GB** | 75.3 | **90.91** |

- **Three lanes hold more than they declare:** compact24 when it edits (18.6 against 16.2 GB), standard64 at its
  envelope (44.0 against 34.8 GB), and max128 at its corner (90.9 against 75.3 GB). In each case Gaea learned the peak
  and now charges it ([ledger-after-corner.json](ledger-after-corner.json): `declaredBytes` 90.91 GB against the
  worker's `reportedDeclaredBytes` 75.3 GB). Every one still fits its budget, with 7.2, 7.5 and 12.2 GB to spare.
- **max128's corner** is exactly its 1,004,789,760 pixel-frame ceiling: 20 s at 1920×1088, made in 67.5 minutes.
  Afterwards the idle worker kept 12.5 GB (1.6 GB after small jobs), which the ledger charges until it is evicted.
- **Refusals at submit** (each one a 4xx before any worker started):
  - 32 GB, `quality: best`: 422 `unsupported_parameter` on `quality`, "video.generate offers draft, standard";
  - 32 GB, a last frame: 422 `unsupported_parameter` on `last_frame`;
  - 32 GB, 704×512×121 on compact24: `out_of_limits` on `duration_s`, at most 49 frames;
  - 64 GB, max128 by name: 422 `model_unavailable`.
- The eleven sessions validate against GPP-1.

## The disk floor

LTX's tiers declare `minSustainedReadBytesPerSecond`; max128's (bf16, streamed) is the highest, at 1 GB/s. Reads of
256 MB in 16 MB chunks with `F_NOCACHE`, from files not recently read ([volprobe.py](volprobe.py), the engine's
VolumeProbe in Python):

| Volume | Read |
|---|---|
| DEV_VOL1 (external, PCI-Express), where the weights are | **4.15–4.17 GB/s** |
| The internal SSD | 10.23 GB/s |
| Satechi (external, PCI-Express) | 5.07 GB/s |

DEV_VOL1 is four times max128's floor; standard64's 4.4-minute and max128's 6.5-minute runs are compute-bound, not
read-bound. A volume under the floor wasn't tried, since none of these is one.

**Caveat:** `F_NOCACHE` stops new pages being cached but still serves cached ones. A re-read of the same file gave
12.52 GB/s, and the engine's own probe reported 13.5–16.3 GB/s from the worker, which is the cache, not the disk. A
volume under the floor could pass the probe after a recent read. Asked of mlx-engine as AB-A-0242.

## Found on the way

- **Declared needs understate three lanes** (above). The package's `QuantFootprint` for standard64 and for edits on
  compact24 is low; max128's is right at its envelope (63.8 against 75.3 GB) but not at its corner. Gaea now protects
  itself by learning, and the figures go to mlx-ltx on AB-A-0241.
- **compact24's ceiling against its envelope** (704×512×121 refused by the package): the plugin enforces the ceiling
  since 0.1.1. AB-A-0241.
- **The low tiers loaded the bf16 component tree** for an int8 encoder: worked around with the `-q8` repo in 0.1.1.
  AB-A-0241.

## Not covered

- **Real 32 GB and 64 GB Macs.** The budgets are staged on 128 GB, as decided; the OS and other apps on a smaller Mac
  leave less than a quarter of memory free, and Gaea's budget doesn't see that.
- **Two tiers at once.** One GPU job runs at a time (G-13); eviction between tiers was covered with Z-Image in
  AB-T-0363 and AB-T-0371, not with LTX.
- **A learned peak past the budget.** Every learned peak here fits. If one didn't, the governor would refuse the job at
  admission (`exceedsBudget`), but the offers still follow declared needs.
