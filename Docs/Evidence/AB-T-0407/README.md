# AB-T-0407: G3's exit

| | |
|---|---|
| **Date** | 2026-11-01 |
| **Gaea** | 0.11.3 (fad9b28), signed Release `dist/Gaea.app`, on media-engine-spec v0.9.0 (Video 0.1) |
| **Suite** | `mes-conformance` built from a clean clone of media-engine-spec v0.9.0, as shipped |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0407` |

G3's exit (Plan §5 G3, order 7) has three parts: Video conformance with every G3 plugin, the tier budgets, and the
Lab. FlashVSR, the fourth plugin the plan named, is still a work in progress in mlx-video. **The operator decided on
2026-11-01 to exit without it**; its plugin is AB-T-0408, parked until mlx-video releases the port.

## Result

| Done = | Result |
|---|---|
| Video conformance with every G3 plugin | **80 passed, 0 failed, 11 skipped: Base 0.1, Image 0.1, Audio 0.1 and Video 0.1 conform** ([report](conformance/report.md)). A fresh Gaea 0.11.3 with all 14 plugins from GitHub ([plugins](conformance/plugins-list.txt), [models](conformance/models.txt)): the six G1 plugins, the five audio plugins, RIFE 0.1.0, SeedVR2 0.1.0 and LTX 2.5 0.1.1 with all four tiers enabled. 14 of the 15 Video tests run and pass; VIDEO-014 skips because no Video offer sends previews |
| Every LTX tier within its budget at 32, 64 and 128 GB | **Pass, 31 of 31** ([AB-T-0405](../AB-T-0405/README.md)): budgets staged with `--budget-bytes` (the operator's call, 2026-10-31). Offers follow the budget, every envelope job stays within it (max128's 1920×1088×481 corner at 90.9 of 103.08 GB), and Gaea charges the measured peak of the three lanes that held more than they declare. DEV_VOL1 reads 4.2 GB/s against max128's 1 GB/s floor |
| Gaea Lab on video | **Pass, 28 of 28** ([AB-T-0406](../AB-T-0406/README.md)): on pixel-agency-run 0.3.0, `lab-run` runs all five Video operations against Gaea (generate refused without the users' acceptance and run with it, a keyframe, extend, retake, upscale, interpolate, each clip the next one's input), and the app shows LTX's terms and the clip |
| The Lab still conforms as a client | **11 passed, 0 failed: Base 0.1 (client) conforms** ([client report](client/client-report.md)), `lab-run` on pixel-agency-run 0.3.0 under v0.9.0's client suite, which has no video tests yet |

The 11 skips:
- four for open mode (BASE-005, 006, 035, 090);
- two for waits the suite doesn't take by default (BASE-034, 071);
- BASE-017: no offer the suite can drive declares `seed: false`;
- IMAGE-014 to 016: no `image.decompose` offer, because Ming-Image isn't in the G1 set;
- VIDEO-014: previews.

They are the same skips as AB-T-0404's run on Gaea 0.11.0.

## What G3 built

| Order | Record | What |
|---|---|---|
| 1 | AB-A-0235 | Video 0.1 in MES: media-engine-spec v0.9.0 (mlx-apps) |
| 2 | AB-T-0400 | GPP and GaeaPluginKit for video: canonical MP4 inputs, previews, storage floors |
| 3 | AB-T-0401 | Gaea 0.10.0 serves Video 0.1: retiming, the source's sound and comment kept, codecs |
| 4 | AB-T-0402, 0403, 0404 | RIFE (`video.interpolate`), SeedVR2 (`video.upscale`), LTX 2.5 (`video.generate`, `extend`, `retake`, four tiers) |
| 5 | AB-T-0405 | The governor on LTX's tiers: offers by budget, learned peaks (Gaea 0.11.1, 0.11.2), the disk floor |
| 6 | AB-T-0406 | Gaea Lab on video (pixel-agency-run 0.3.0, AB-A-0243); Gaea 0.11.3's disclosure fix |
| 7 | AB-T-0407 | This exit |

## Left after G3

- **FlashVSR** (AB-T-0408, parked): when mlx-video releases mlx-flashvsr-swift.
- **Previews:** no video plugin sends `job.preview`. The packages have no frame hook (VIDEO-EVALUATION §8).
- **LTX's LoRAs and IC-LoRAs** wait on mlx-ltx's typed adapters (AB-A-0197).
- **Asks of mlx-ltx:**
  - AB-A-0240: the granules probe;
  - AB-A-0241: the low tiers loading the bf16 tree, and declared needs below measured peaks.

  Gaea and the plugin work around both.
- **The probe fix** (AB-A-0242) is in mlx-engine-swift v0.73.1. Plugins pick it up when they are rebuilt.
- **Real 32 and 64 GB Macs** weren't used; the budgets were staged, as decided.
