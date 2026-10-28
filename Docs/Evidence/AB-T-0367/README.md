# AB-T-0367: gaea-plugin-flux2-klein, FLUX.2 Klein 4B and 4B Base

| | |
|---|---|
| **Date** | 2026-10-28 |
| **Plugin** | [xocialize/gaea-plugin-flux2-klein v0.1.0](https://github.com/xocialize/gaea-plugin-flux2-klein/releases/tag/v0.1.0): Developer ID, notarized (Accepted), Gatekeeper "Notarized Developer ID". On flux2-klein-swift 0.10.1, mlx-engine-swift 0.72 and GaeaPluginKit 0.2.0, Apache-2.0 |
| **Host** | Gaea 0.2.1, Release, `dist/Gaea.app` |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Weights** | MLXEngine's store, `~/Library/Application Support/MLXEngine/Models` (`mlx-community/FLUX.2-klein-4B-bf16`, `mlx-community/FLUX.2-klein-base-4B-bf16`), already on disk: no download |
| **Script** | [`tools/acceptance-klein.sh`](../../../tools/acceptance-klein.sh), twice. From the published GitHub release with no token: **16 passed, 0 failed** ([github/acceptance.log](github/acceptance.log)). Before publishing, from the release stand-in: 16 of 16 ([acceptance.log](acceptance.log)) |

## What the plugin is

| Model | Offers | Lanes |
|---|---|---|
| `klein-4b`: distilled 4 steps, no CFG | `image.generate` for draft and standard; `image.edit` for draft and standard, **Gaea's default editor** | bf16 (default), int8, int4 |
| `klein-4b-base`: undistilled, 28 steps, CFG 4, negative prompts | `image.generate` and `image.edit` for best | bf16 (default), int8, int4 |

- **Lanes.** Each lane is a DiT quant with the package's measured 1024² footprint: 25.9, 22.7 and 20.5 GB distilled,
  and 27.1, 23.9 and 21.7 GB base. bf16 is the default, as in mlx-image-runtime's catalog.
- **Edit.** Klein's multi-reference editing takes 1–4 images; the output is drawn from noise at the first image's
  size. MES `image.edit` has one output and no `count`.
- **Sizes and count.** 256–2048 px a side, at most 1024² in area, in multiples of 16 (`size_snapped`). `count` 1–8
  on generate, with `seed + i`.
- **Settings.** None: mlx-image-runtime's catalog has no environment variants for Klein.

## Acceptance

| Done = | Result | Evidence |
|---|---|---|
| gaea-plugin-check reports ALL PASS on the notarized release | **Pass** | `scripts/release.sh`: check ALL PASS with every `.build` hidden (Klein 4B int4, 512²); the bare worker fails on the metallib. Notarization Accepted; `spctl` "Notarized Developer ID". |
| Gaea installs the plugin by its repo URL | **Pass** | `gaea plugins add https://github.com/xocialize/gaea-plugin-flux2-klein` against the real release, anonymously ([github/operations.json](github/operations.json), [models.txt](models.txt)). |
| Generate and edit through Gaea match the in-process output for fixed seeds | **Pass, byte for byte, four ways** | Against `klein-inproc`, the plugin repo's in-process reference on the same dependency resolution: Klein 4B bf16 1024² seed 42 (sha256 `91e5e7d05445b52a…`, [png](gaea-klein-0.png)); Klein 4B Base bf16, 28 steps CFG 4 with a negative prompt (`025284a674d08bf6…`, [preview](gaea-base-0-preview.jpg)); a two-reference edit, seed 7 (`2a8189190f5d4702…`, [preview](gaea-edit-0-preview.jpg)); and Klein 4B int4 at 992² (`6eafe83a2b32f527…`). Both runs and both builds give the same bytes. |
| A receipt: cold start and seconds per image, Release | **Filed** | See the timings below. |

## Timings (Release, from the GitHub run)

| 1024² unless noted | Through Gaea, worker run | In-process (`klein-inproc`) |
|---|---|---|
| Klein 4B bf16, warm | 6.32 s | 6.27–6.30 s |
| Klein 4B bf16, cold: launch, prepare, first image | 11.68 s submit to settled (run 10.37 s) | 7.03 s (prepare 0.72 s, run 6.30 s) |
| Klein 4B int4, 992² | 6.42 s | 6.23–6.26 s |
| Klein 4B Base bf16, 28 steps CFG 4 | 75.79 s | 75.42–75.45 s |
| Edit, Klein 4B bf16, two 1024² references | 21.11 s | 20.78–20.83 s |
| Klein 4B bf16, 768×512, two images | 4.99 s | |

- **At steady state the worker costs nothing measurable,** within 1–2 % of in-process in every row.
- **The first run of a newly installed build is about 4 s slower.** The cold job's run took 10.37 s from the GitHub
  install, and 11.48 s on the stand-in's first install earlier in the day, but 6.09 s on the stand-in's second run of
  the same build. The extra time is in the first `run`, not in the launch (hello after 0.30 s) or `prepare`. It is
  probably Metal compiling the build's kernels the first time; `klein-inproc` ran after Gaea, so it wasn't charged it.
- **The ledger** after the run ([github/ledger.txt](github/ledger.txt)): one worker holding klein-4b int4 and
  klein-4b-base bf16, declared 36.4 GB and measured at 25.6 GB.

## Also checked

- `quality: best` with no model reaches Klein 4B Base: 28 steps, guidance 4, the negative prompt honoured.
- `image.edit` with no model reaches Klein 4B, and keeps the first image's 1024².
- `count` 2 at 768×512 gives two different images, seeds 7 and 8, and the distilled model reports a negative prompt
  as ignored.
- `x-gaea.lane: int4` runs lane int4; 1000² snaps to 992² with `size_snapped`.
- Five references are refused `out_of_limits` (`images`) when the job is submitted. In Gaea 0.2.1 that limit was
  MESKit's default for `image.edit`, which happens to be 4; the offer's `max_images` wasn't applied. Gaea 0.2.2 sets
  each image input's count from the offers (AB-T-0368).
- The recorded GPP sessions pass `tools/validate.py --transcript`.

## Fixed along the way

- The first edit returned `engine_error`, "undeclared output 'images'": MES `image.edit` declares a single output,
  `image`. The plugin now names it `image` and makes one engine call per edit.

## Not covered here

- **Adapters.** Klein takes up to four LoRAs per request; Gaea doesn't route adapters to plugins yet.
- **The encoder-evict light tier** (about 10 GB at 768²) for 16 GB Macs. Its footprint was measured at 768² only, so
  it isn't declared as a lane at 1024².
- **References are drawn square.** flux2-klein-swift's `decodeReference` scales each reference to width × width, so a
  non-square reference is stretched. Both references here were square. Asked of mlx-image as AB-A-0213.
- **The release CI** fails on the tag push because the signing and notary secrets aren't set, as for the demo and
  Z-Image. The release was built, checked, notarized and published locally.
