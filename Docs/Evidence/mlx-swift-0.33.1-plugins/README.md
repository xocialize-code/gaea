# Gaea plugins on the fleet's mlx-swift 0.33.1 (AB-D-0264)

On 2026-11-19 the operator chose `xocialize/mlx-swift` 0.33.1 for the fleet (AB-D-0264): upstream 0.33.0 with the
vendored MLX's head-dim-split SDPA routes turned off. On M5 those routes abort, or with ml-explore/mlx#4903 give
wrong attention, for head-256 masked prefills of 1024+ tokens (AB-R-1009). The fork replaces the 0.32.4 leak-fix
fork (AB-D-0208); upstream 0.33.0 already carries that leak fix.

Seven plugins pinned the 0.32.4 fork as their root declaration. Each now names `xocialize/mlx-swift` 0.33.1 and
mlx-engine-swift 0.82.1, the first engine on that fork:

| Plugin | Release | Model package | Kit (resolved) | min_gaea |
|---|---|---|---|---|
| gaea-plugin-demo | 0.6.1 | (none) | 0.15.0 | 1.9.0 |
| gaea-plugin-sensenova | 0.2.1 | sensenova-u1-swift 0.7.0 | 0.16.0 (floor 0.14.1) | 1.8.0 |
| gaea-plugin-fibo2 | 0.2.2 | fibo2-swift 0.2.0 | 0.15.0 | 1.9.0 |
| gaea-plugin-z-image | 0.2.2 | z-image-swift 0.7.1 | 0.16.0 (floor 0.14.1) | 1.1.1 |
| gaea-plugin-trellis2 | 0.2.1 | mlx-trellis2-swift 0.17.0, mlx-birefnet-swift 0.4.x | 0.16.0 (floor 0.14.1) | 1.8.0 |
| gaea-plugin-locate | 0.1.1 | mlx-locate-swift **0.2.0** (was 0.1.0) | 0.15.0 | 1.9.0 |
| gaea-plugin-ltx | 0.2.0 | ltx-2-mlx-swift **0.23.0** (was 0.20.0) | 0.16.0 (floor 0.14.1) | 0.11.0 |

Every model package's newest tag admits mlx-swift 0.33 (sensenova, fibo2 and z-image take `from: 0.32.3` or lower;
trellis2 `from: 0.32.4`; locate and LTX `upToNextMinor(0.33.1)`), so none had to stay behind. mlx-swift-lm resolves
3.33.0 wherever it is in a graph.

All runs were on a Mac Studio (M5 Max, 128 GB, macOS 27.3), Release builds signed for team CFZS6RXUCP, through Gaea
1.9.2 (`dist/Gaea.app`). Full outputs are on `/Volumes/DEV_VOL1/Evidence/mlx-swift-0.33.1-plugins`.

## What the move turned up

- **GaeaPluginKit before 0.14.1 writes a stale engine into the manifest.** 0.14.0 and earlier hard-code
  `engineVersion` (0.14.0 says 0.79.0, 0.12.0 0.74.1, 0.9.1 0.72.0), so a plugin that resolved an older kit named
  the wrong engine in its manifest and `hello` even when it linked another. LTX 0.1.3's released manifest says
  engine 0.72.0 though it linked 0.74.1. sensenova, trellis2, z-image and LTX raise their kit floor to 0.14.1
  (resolved 0.16.0), whose kit reads `MLXEngineRelease`.
- **ltx-2-mlx-swift 0.21+ declares typed adapters the plugin doesn't carry.** Its t2v surface now has `adapters` (a
  LoRA or an IC adapter, contract 1.55.0), and the kit turns that into `adapter_support` on every `video.generate`
  offer. But the plugin's `call` builds the `T2VRequest` without the run's adapters, so Gaea would have admitted a
  registered LTX LoRA and the worker would have dropped it without a word. LTX 0.2.0 takes the declaration (and the
  surface's `adapters` parameter) off its models' manifests (`withoutAdapters` in LTX.swift): no offer has
  `adapter_support`, and the kit refuses a run that sends one. Only the package's surface summary still mentions
  adapters. Carrying them through is a follow-up.
- **mlx-swift-lm 3.33 made `sanitize(weights:metadata:)` throwing**, which broke `ltx-inproc`'s leak probe
  (LoadProbe.swift) and with it LTX's golden and acceptance, whose scripts build `ltx-inproc` with its output hidden.
- **The new stack changes pixels slightly.** Against the same plugins' previous releases (on the 0.32.4 fork), seeded
  outputs differ at the float level: z-image 37.2 to 40.2 dB PSNR (fine edges, [z-image-old-new-diff.jpg](z-image-old-new-diff.jpg):
  0.2.0 left, 0.2.2 centre, |difference| × 4 right), sensenova 42.8 dB (sensenova-u1-fast at 512²) to 54.7 dB (the
  first TailSteer edit). Gaea against in-process on the new stack is still byte for byte or pixel for pixel
  everywhere it was before, so any pixel-exact reference made on the old stack is stale.

## Manifests

[manifest-diffs/](manifest-diffs/) compares each new `dist/manifest.json` with the previous release's. In every one
the engine moves (version and contract, now 1.66.0, which adds only the `imageLocate` capability, which none of
these models declares). Beyond that:
- z-image and LTX add an empty `requirements.processEnvironment` per model (contract 1.60.0), which the older
  engines' synthesized decoders skip, so their `min_gaea` stays;
- LTX adds `emitsFramePreviews: false` to its t2v controls and the package's longer surface summary;
- demo and trellis2 list a set's members in another order (characterPart and imageTo3D features).

## Results

| Plugin | `check-plugin.sh` | `golden.sh` | Through Gaea 1.9.2 |
|---|---|---|---|
| demo 0.6.1 | pass ([demo-check.log](demo-check.log)) | — | conformance below |
| sensenova 0.2.1 | pass | 11/11 ([sensenova-golden.log](sensenova-golden.log)) | 15/3 ([sensenova-acceptance.log](sensenova-acceptance.log), `acceptance-tailsteer.sh`, from GitHub) |
| fibo2 0.2.2 | pass (fibo-2-dev, int8, 512², 8 steps) | — | 13/13 ([fibo2-acceptance.log](fibo2-acceptance.log), `acceptance-fibo-enhance.sh`, from GitHub) |
| z-image 0.2.2 | pass | 10/10 ([z-image-golden.log](z-image-golden.log)) | 13/13 ([z-image-acceptance.log](z-image-acceptance.log), `acceptance-nitrofusion2.sh`, from GitHub) |
| trellis2 0.2.1 | pass | 19/20, the miss 1/1 alone ([trellis2-golden.log](trellis2-golden.log), [rerun](trellis2-golden-remove-rerun.txt)) | 40/40 ([trellis2-acceptance.log](trellis2-acceptance.log), `acceptance-trellis2.sh`, from GitHub, without FULL) |
| locate 0.1.1 | pass | 8/8 ([locate-golden.log](locate-golden.log)) | 13/13 ([locate-acceptance.log](locate-acceptance.log), `acceptance-locate.sh`, from GitHub; head crop 12/12) |
| ltx 0.2.0 | pass | 8/8 with max128 re-run ([plain](ltx-golden-plain.log), [inputs](ltx-golden-inputs.log), [max128 re-run](ltx-golden-max128-rerun.log)): standard64, compact24-first, compact24-extend and max128 the same frames; compact24 and balanced32 within 42 dB, standard64-last 51 dB, compact24-retake 29 dB (int8) | 22/22 ([ltx-acceptance.log](ltx-acceptance.log), `acceptance-ltx.sh`, stand-in, before the tag) |

`*-check-summary.txt` hold each check's PASS lines and its metallib control.

- **sensenova's three failures** are the chain checks against mlx-image's own driver's pictures (AB-R-0842), made on
  the 0.32 stack: turns 1 to 3 are 54.7, 53.3 and 51.6 dB from them. Through Gaea the chain still matches
  sensenova-inproc's on the new stack pixel for pixel, and every other check passes.
- **The first runs of the sensenova and z-image acceptances** ([sensenova-acceptance-run1.log](sensenova-acceptance-run1.log),
  [z-image-acceptance-run1.log](z-image-acceptance-run1.log)) also failed "add … 0.2.0 by repo URL": the scripts
  expected that version by name. They take `V` now, as acceptance-trellis2.sh does, and the logs above are re-runs
  with `V` set.
- **trellis2's miss** was the in-process side of the first case: a Metal GPU timeout
  (`kIOGPUCommandBufferCallbackErrorTimeout`) while the sensenova acceptance held the GPU. Alone it gives the bundle's
  GLB byte for byte (sha256 395856e4…, 32 s against 113 s under contention). The checks after it were run one at a
  time.
- **LTX's max128 flaked once.** The first max128 run after a reboot gave frames 3cc91cde…, 50 dB from
  in-process's ad8c9c74…, though bf16 says `deterministic: true`. The bundle before the reboot, the re-run right
  after, and 4 more runs one at a time with nothing else on the GPU ([ltx-max128-repeat.txt](ltx-max128-repeat.txt))
  all gave ad8c9c74…, as ltx-inproc did twice: 1 in 9, on a cold page cache (AB-L-0369). That reboot was for
  DEV_VOL1, where from about 10:00 macOS reported 0 bytes of `volumeAvailableCapacityForImportantUsage` (1.3 TB
  free) and the engine's prepare-time `VolumeProbe` refused every LTX lane with `materialize_failed`. After the
  reboot, Swift Build's cached build description pointed at the Metal toolchain's old mount, so the first build
  failed until `.build/{plugin/,}out/Intermediates.noindex/XCBuildData` was removed.
- **Timings here aren't receipts.** Most runs shared the GPU with another job (NitroFusion2's 8.7 s warm against
  Turbo's 25.4 s, for instance, is twice 0.2.0's).

## Not covered

- FULL=1 cases (TRELLIS.2 at 1024 and 1536, Pixal3D at 1536) weren't run.
- Gaea versions older than 1.9.2 weren't driven; `min_gaea` is unchanged on the reading above.
