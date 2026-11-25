# Gaea 1.10.0: notarized plugins from any developer, and the typed locate capability

2026-11-25, Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3). A local Release build of Gaea 1.10.0, run headless on
throwaway homes and ports. The GPU was shared with other sessions, so the times are upper bounds.

## What changed

- **G-32 (AB-D-0295):** a plugin runs when it is signed with a Developer ID and notarized by Apple, whoever its team
  is. Its own page: [../G-32/README.md](../G-32/README.md).
- **mlx-engine-swift 0.83.0** (contract 1.67.0; 1.66.0 brought `imageLocate`). GaeaPluginKit stays 0.16.0: a plugin
  builds the typed request itself, and the kit needed no change.
- **gaea-plugin-locate 0.2.0** on mlx-locate-swift 0.3.0: `ImageLocateRequest` in place of `imageAnalysis` and JSON
  text (AB-A-0295). It needs Gaea 1.10.0.
- **A model's licence comes from every licence among its weights** (AB-A-0318).
- **`tools/acceptance-rmbg.sh`**, new, for gaea-plugin-fibo2 0.3.0's RMBG 3.0 (AB-A-0328).

## Results

| Run | Result | Log |
|---|---|---|
| Gaea unit tests | 120 passed | |
| Trust acceptance (G-32), our team treated as unknown | 31 passed, 0 failed | [../G-32/acceptance.log](../G-32/acceptance.log) |
| Locate plugin 0.2.0: `scripts/golden.sh`, the signed bundle over GPP against `locate-inproc` | 8 passed, 0 failed | [golden-locate.log](golden-locate.log) |
| Locate acceptance, the plugin's local 0.2.0 build through a stand-in | 13 passed, 0 failed | [acceptance-locate-standin.log](acceptance-locate-standin.log) |
| RMBG 3.0 acceptance, gaea-plugin-fibo2 0.3.0 from GitHub (notarized) | 13 passed, 0 failed | [acceptance-rmbg.log](acceptance-rmbg.log) |
| HairDeck acceptance, gaea-plugin-hairdeck 0.1.2 from GitHub (notarized) | 32 passed, 0 failed | [acceptance-hairdeck-github.log](acceptance-hairdeck-github.log) |

The trust acceptance ran on the build before the engine moved; the unit tests ran after.

## Typed locate

`tools/acceptance-locate.sh` is unchanged and passes as it did on 0.1.0. On mlx-3d's 12 pictures, through Gaea on the
`int8` lane:

| Measure | 0.1.0 (Gaea 1.9.0) | 0.2.0 (Gaea 1.10.0) |
|---|---|---|
| Hair box IoU, median | 0.917 | 0.911 |
| Face box IoU, median | 0.750 | 0.739 |
| Head crop IoU, median | 0.939 | 0.929 |
| Head crop within tolerance | 12 of 12 | 12 of 12 |
| Time per query, warm, median | 0.64 s | 1.86 s |

- **The boxes moved a little.** mlx-locate-swift changed between 0.1.0 and 0.3.0 (its token budget, and the typed
  surface asks the model for every instance and keeps the best), and the plugin moved from mlx-swift 0.32 to 0.33.
  Nothing here separates those causes.
- **A query took about three times as long.** The GPU was shared, so some of that is load. mlx-image expected one-box
  answers to be as fast as before; this run doesn't show that, and I reported it on AB-A-0295.
- The lanes are charged 8.4 GB (`int8`) and 6.35 GB (`int4`), up from 8.0 and 5.95: the package's declared activation
  went from 2.6 to 3.0 GB.

## RMBG 3.0 on `image.matte`

What `tools/acceptance-rmbg.sh` shows, on the Fibo plugin 0.3.0 and the `bf16` lane:

- **Opt-in and named-only.** `rmbg-3` is off until the operator enables it. Enabled, `image.matte` lists it as
  CC-BY-NC-4.0, non-commercial, accepted-required, with Bria's attribution, and never as the default. A matte that
  names no model doesn't run on it.
- **The licence.** Named without the licence accepted, the job is refused with `policy_unmet`, and the message names
  the terms.
- **The matte.** Named and accepted, it returns a mask and an extract the picture's size, and the extract's alpha is
  the mask. A second run gives the same mask.
- **No seed (mlx-image's question 2).** MES `image.matte` has no `seed`, so Gaea refuses one. The worker ran at seed
  0. A model that wants a seed takes it as its own extension, `x-fibo2.seed`.
- **A subject (question 3).** The offer lists none and needs none. With the Forge pack beside it, Gaea's segmenter
  (SAM 2.1) picks the subject and RMBG 3.0 makes the matte; with no segmenter on the server a subject is refused.
- **Time.** 35 to 54 s a matte here, where mlx-image measured about 20 s on `int8` alone.

The pictures stay on `/Volumes/DEV_VOL1/Evidence/fibo2-0.3.0/`.

## HairDeck 0.1.2

`tools/acceptance-hairdeck.sh` with `REPO_FROM=github`: every case as on 0.1.1, byte for byte against
`hairdeck-inproc`. The three merge checks pass with the newer `vrmMerge.js` (the one with spring handling); the copy
in VRMXA_Specification, the script's default, drops an item's springs (AB-A-0333).

## Not covered

- **Through the released app.** Everything above ran on the local build. What ran on the published 1.10.0 is in the
  last section, added after the release.
- **Conformance** with every plugin was not rerun for this release. The last full run is 1.9.0's.
- **The other plugins on engine 0.83.0.** Gaea decodes their manifests in the unit tests' fixtures and in these four
  plugins' runs; the rest were not installed here.
- **The signer-change hold**, end to end, and `tools/acceptance-second-team.sh`: see G-32's page.
