# Gaea 1.10.0: notarized plugins from any developer, and the typed locate capability

2026-11-25, Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3). A local Release build of Gaea 1.10.0 first, then the
published app (`Gaea-1.10.0.zip`, sha256 `549b1ad1…8f8088da`, Gatekeeper: Notarized Developer ID), each run headless on
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

Those ran on the local build; the first trust run was on the build before the engine moved. Through the published
app:

| Run | Result | Log |
|---|---|---|
| Trust acceptance (G-32) | 31 passed, 0 failed | [acceptance-trust-released.log](acceptance-trust-released.log) |
| Locate acceptance, the plugin's 0.2.0 release from GitHub | 13 passed, 0 failed | [acceptance-locate-released.log](acceptance-locate-released.log) |
| Kokoro 0.1.3 from GitHub (`tools/acceptance-kokoro.sh`) | 34 passed, 0 failed | [acceptance-kokoro-github.log](acceptance-kokoro-github.log) |
| SeedVR2 0.1.2 from GitHub (`tools/acceptance-seedvr2.sh`) | 18 passed, 0 failed | [acceptance-seedvr2-github.log](acceptance-seedvr2-github.log) |
| LTX 0.2.1, its local build through a stand-in (`tools/acceptance-ltx.sh`) | 22 passed, 0 failed | [acceptance-ltx-standin.log](acceptance-ltx-standin.log) |
| LTX 0.2.1 from GitHub | 22 passed, 0 failed | [acceptance-ltx-github.log](acceptance-ltx-github.log) |

## Typed locate

`tools/acceptance-locate.sh` is unchanged and passes as it did on 0.1.0. On mlx-3d's 12 pictures, through Gaea on the
`int8` lane:

| Measure | 0.1.0 (Gaea 1.9.0) | 0.2.0 (Gaea 1.10.0) |
|---|---|---|
| Hair box IoU, median | 0.917 | 0.911 |
| Face box IoU, median | 0.750 | 0.739 |
| Head crop IoU, median | 0.939 | 0.929 |
| Head crop within tolerance | 12 of 12 | 12 of 12 |
| Time per query, warm, median | 0.64 s | 1.86 s (1.38 s on the published app's run) |

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

## Plugins moved to newer packages

Released the same day, each checked with its own `scripts/golden.sh` (the signed bundle over GPP against in-process)
and through the published Gaea 1.10.0:

| Plugin | What moved | Golden | Through Gaea |
|---|---|---|---|
| gaea-plugin-kokoro 0.1.3 | mlx-kokoro-tts-swift 0.5.0 → 0.6.0 (word and phoneme timings on the engine's side) | 8 of 8, byte-identical ([log](golden-kokoro.log)) | 34 of 34 from GitHub |
| gaea-plugin-ltx 0.2.1 | ltx-2-mlx-swift 0.23.0 → 0.24.0 (the decode streams into the MP4 writer on every run path) | 16 of 16 ([log](golden-ltx.log)) | 22 of 22 from its local build, and from GitHub |
| gaea-plugin-seedvr2 0.1.2 | mlx-seedvr2-swift 0.10.1 → 0.10.3, and onto the fleet's mlx-swift fork: it resolves mlx-swift 0.33.2 and mlx-engine-swift 0.83.0, the first plugin on either | 8 of 8 ([log](golden-seedvr2.log)) | 18 of 18 from GitHub |

- Kokoro's word timings don't reach a client: nothing in Gaea asks the engine for them yet.
- LTX's declared lane charges are unchanged in 0.24.0 (max128 still 0.8 + 74.5 GB). Nothing here measured its peak.
- **Not moved here:** gaea-plugin-flux2-klein, which another session released as 0.5.0 the same day (below);
  gaea-plugin-fastframes, which is mlx-video's; and the ten plugins last released on 2026-11-02, still on
  mlx-engine-swift 0.73.1 and the mlx-swift it resolved then.

## Klein 0.5.0

gaea-plugin-flux2-klein 0.5.0 (flux2-klein-swift 0.12.0, AB-R-1139) adds `klein-4b-bonsai`, Prism ML's Bonsai Image
Ternary 4B. `tools/acceptance-klein.sh` with `REPO_FROM=github`, through the published Gaea 1.10.0, with the models
root on `/Volumes/DEV_VOL1/Models` (`MODELS`, new, since Bonsai's weights are there):
22 passed, 0 failed ([log](acceptance-klein-0.5.0-github.log)).

- **The models it had.** Klein 4B at 1024², the base at standard (28 steps, CFG 4, a negative prompt), a two-reference
  edit and the `int4` lane at 992² are each byte for byte the image `klein-inproc` makes on the 0.5.0 resolution.
  Count, the ignored negative prompt, size snapping and the five-reference refusal are as before.
- **Bonsai (section 5, new).** `image.generate` lists `klein-4b-bonsai` as named-only, Apache-2.0 and never the
  default; `image.edit` doesn't list it. It has the one lane, `ternary`, charged 8.0 GB. By name at 1024² (4 steps)
  and at 2048² (drawn at 1024², one FlowUpscaler pass) it is byte for byte the in-process image.
- **Tier.** The plugin's offer says draft; the normalizer's table doesn't list the model, so clients see standard.
  It is named-only, so no tier routes to it either way.
- **Memory.** One worker held Klein 4B `int4`, the base `bf16` and Bonsai together at 29.5 GB, peaking at 36.4 GB.
- **Time.** A warm 1024² job took 10.9 s on Klein 4B `bf16` and 10.8 s on Bonsai here; Klein 4B's own figure is
  6.5 s, so read these as a busy machine's times and not as a comparison.

Not covered: the RDM model, fill and extend, 4096², adapters (the plugin's `scripts/golden.sh`, which AB-R-1139 says
was not rerun on the new pin), and how Bonsai's pictures compare with Klein 4B's.

The pictures stay on `/Volumes/DEV_VOL1/Evidence/gaea-1.10.0/klein-0.5.0/`.

## Not covered

- **Conformance** with every plugin was not rerun for this release. The last full run is 1.9.0's.
- **The other plugins on engine 0.83.0.** Gaea decodes their manifests in the unit tests' fixtures and in these four
  plugins' runs; the rest were not installed here.
- **The signer-change hold**, end to end, and `tools/acceptance-second-team.sh`: see G-32's page.
