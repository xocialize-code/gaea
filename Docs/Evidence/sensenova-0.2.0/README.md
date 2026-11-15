# gaea-plugin-sensenova 0.2.0: the TailSteer model for chains of edits

2026-11-15, Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3). The plugin's 0.2.0 release from GitHub (`000b2a6`,
notarized) through the released Gaea 1.8.0 app, headless on a throwaway home.

mlx-image's sensenova-u1-swift 0.7.0 added `SenseNovaVariant.fast8V2TailSteer`: the V2 8-step recipe over SenseNova's
TailSteer finetune, which drifts less when each edit's result is edited again (AB-R-0841, AB-R-0842, AB-R-0843). The
plugin was on sensenova-u1-swift 0.5.3, GaeaPluginKit 0.3.0 and mlx-engine-swift 0.73.1.

## What changed

- **`sensenova-u1-tailsteer`** on `image.generate` and `image.edit`, named-only like every SenseNova model. One lane,
  int8 (24.7 GB charged): a 4-bit build loses the benefit, so the package has none. Its licence entry points at
  TailSteer's own page (Apache-2.0).
- **Pins:** sensenova-u1-swift 0.7.0, GaeaPluginKit 0.14.0, mlx-engine-swift 0.79.0 exactly, the mlx-swift fork 0.32.4
  exactly. The plugin now needs Gaea 1.8.0.
- **The three earlier models** are the same in the manifest but for the contract version (1.58.0 to 1.64.0).
- **New in the repo:** unit tests (4) and `scripts/golden.sh`.

## Results

| Run | Result | Log |
|---|---|---|
| Plugin unit tests | 4 passed | |
| `scripts/golden.sh`: the signed bundle over GPP against `sensenova-inproc`, byte for byte | 11 passed, 0 failed | [golden.log](golden.log) |
| `tools/acceptance-tailsteer.sh`, the plugin's local build through a stand-in | every check passed | |
| `tools/acceptance-tailsteer.sh`, the release from GitHub through the released Gaea 1.8.0 | 18 passed, 0 failed | [acceptance-github.log](acceptance-github.log) |
| Conformance with the image plugins and SenseNova 0.2.0, through the released Gaea 1.8.0 | 43 passed, 0 failed, 73 skipped (no audio, video or mesh plugin installed): Base and Image 0.1 conform | [conformance.md](conformance.md) |

What the acceptance shows:

- **The offer.** `image.generate` and `image.edit` list `sensenova-u1-tailsteer` by name only, beside the three earlier
  models, with one int8 lane.
- **Generate.** By name at 768², eight steps without CFG; the picture is `sensenova-inproc`'s, pixel for pixel.
- **A chain of edits.** The first three turns of the vendor's `cafe-20turn` demo (a 1024×672 photo; seeds 42, 43, 44),
  each turn's result downloaded and uploaded as the next turn's input:
  - every turn ran TailSteer at the photo's size;
  - turn 1 is `sensenova-inproc`'s edit of the same photo, pixel for pixel;
  - turns 1, 2 and 3 are the pictures mlx-image's own driver made (`mlxengine-image/WIP/tailsteer-gate/runs/cafe/ts8q8`),
    pixel for pixel. A chain through Gaea's uploads and PNG re-encoding loses nothing.
- **Ignored and refused.** A negative prompt is reported `negative_prompt_ignored`. Think mode isn't in the model's
  offer and isn't run. Naming an `int4` lane fails the job: "sensenova-u1-tailsteer has no lane int4."
- **The earlier model.** `sensenova-u1-fast` by name is still `sensenova-inproc`'s picture.

Warm times through Gaea: 768² generate 2.1 s; a 1024×672 edit 2.8 s on TailSteer and on `sensenova-u1-fast` alike.

## The chain against sensenova-u1-fast

Reported, not judged. Whole-picture PSNR against the source photo, edit included:

| Turn | TailSteer | `sensenova-u1-fast` |
|---|---|---|
| 1 | 24.46 dB | 23.90 dB |
| 2 | 23.84 dB | 23.10 dB |
| 3 | 22.41 dB | 21.68 dB |

TailSteer stays about 0.6 to 0.7 dB closer over three turns. That agrees in direction with mlx-image's measurement over
ten turns (18.0 against 15.9 dB outside the edited area), and three turns are too few to show more.

A strip of the chain is at `/Volumes/DEV_VOL1/Evidence/sensenova-0.2.0/chain-strip.png`. It isn't in this repo because
the photo is the vendor's.

## Found on the way: an edit of SenseNova's own soft picture restyles all of it

The golden script's edits start from a picture TailSteer generated (a fox in a snowy forest, shallow focus). One edit
("add a red knitted scarf … keep everything else the same") redrew the whole picture in a hard, high-contrast style:
about 13 dB against its source, at 768² and at 1024², and the same on `sensenova-u1-fast` and on the 50-step base. The
cafe photo's first edit holds 24.5 dB.

It isn't the plugin: the plugin's path gives mlx-image's result on the photo to the pixel. It reads as the model's own
behaviour on a soft generated source. Pictures: `/Volumes/DEV_VOL1/Evidence/sensenova-0.2.0/fox-restyle/`. Told to
mlx-image as AB-A-0290.

## Not covered

- **Long chains.** Three turns ran here. The ten- and twenty-turn results are mlx-image's.
- **TailSteer's memory.** The lane's 24.7 GB is the package's declared footprint; the worker's peak wasn't measured.
- **`sensenova-u1` (the base) and `sensenova-u1-fast-v1`** weren't run through Gaea in this pass; `-fast-v1`'s weights
  aren't under this models root. Their manifest entries are unchanged.
- **Fill, extend and erase with a SenseNova model.** Not tried.
