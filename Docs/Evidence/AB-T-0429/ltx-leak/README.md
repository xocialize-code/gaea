# LTX's worker crashes after ~379 runs: a leak in mlx-swift's `_updateInternal` (AB-T-0429)

The 24-hour soak (`../soak/`) ran 1,059 LTX jobs, all of which succeeded. Twice, though, the LTX worker crashed mid-run
with `[metal::malloc] Resource limit (499000) exceeded`, after 379 runs at 01:45Z and after 8 h 18 min at 12:58Z.
Gaea requeued each job once and it succeeded on a fresh worker (crashes #19 and #44 in `../soak/summary.json`; the
`.ips` reports are here).

## What leaks

MLX caps the Metal buffers one process holds at `iogpu.rsrc_limit`, which defaults to 499,000. MLX's allocator frees
its whole cache before it gives up, so the buffers it counted were live.

- **About 5,264 bytes per run.** The worker's own `memory` report (`gpuActiveBytes`, MLX's live memory) grew by
  exactly 5,264 bytes per run: 1,984,576 bytes after run 378 of the soak's first worker
  (`soak-worker1-memory-samples.gpp`), and 5,312 → 10,576 → 15,840 → 21,104 → 26,368 with LTX alone in a fresh Gaea
  (`gaea-ltx-alone-memory.gpp`).
- **The arithmetic:** 5,264 bytes is 1,316 four-byte scalar buffers, and 499,000 ÷ 1,316 = 379 runs, which is the
  soak's first worker exactly.
- **What it isn't.** The idle footprint grew about 0.3 GB/h, but that is Metal heap overhead around the scalars, not
  the cause.

## Bisect (`gaea-plugin-ltx/Sources/ltx-inproc`, diagnostic `GAEA_PROBE_*` modes, in-process, M5 Max 128 GB, macOS 27.3, Release)

| Run | MLX live bytes after each round (cache cleared) |
|---|---|
| LTX compact24, 256², 0.375 s, three runs | 10,576 · 15,880 · 21,104 (+5,264 a run) |
| … `LTX_EVICT_DIT=0` (DiT stays resident) | +5,264 a run: not the DiT rebuild |
| … `LTX_ONE_STAGE=1` | +5,264 a run: not the upsampler or the refine stage |
| … `MLX_DISABLE_COMPILE=1` | +5,264 a run: not the compile cache |
| Gemma 4 encoder (LTX 2.5's) load + encode, dropped | 5,276 · 10,524 · 15,772 · 21,020 |
| … load only | +5,248 a load: the leak is the load, which LTX does every run |
| Gemma 3 12B 4-bit, LTX 2.3's loader | +5,416 a load: not Gemma 4 specific |
| `MLX.loadArrays` of the same files, serial, threaded, CPU stream | 0: MLX's loading is clean |
| mlx-swift-lm: create the model only | 8 (the RNG key), flat |
| … + sanitize, + quantize | 8, flat |
| … + `model.update(parameters:)` (with or without verify) | +5,416 a round: **the leak** |
| Minimal: 100 × `quantized(uniform(...))`, the three outputs replaced via `_updateInternal` | +1,600 a round (16 B a layer) |
| … the same three outputs simply dropped | 8, flat |

## Cause

`MLXArray._updateInternal` (mlx-swift 0.32.3, `Source/MLX/MLXArray.swift:566`), which `Module.update(parameters:)`
uses for every parameter, assigns over the old `mlx::core::array` through `mlx_array_set`. In MLX core that is
`array::operator=`, which just replaces `array_desc_`. It skips the sibling-cycle check that only `~array()` does. A
parameter that is one output of a multi-output op (`quantize(model:)` makes each `QuantizedLinear`'s weight, scales and
biases as siblings of one lazy `quantized(...)` of the random init) is therefore never freed once replaced. The three
siblings hold each other, and their graph's materialized scalars (the init's bounds) stay allocated: 4 per quantized
layer per load.

Any quantized model loaded through mlx-swift-lm leaks this way once per load. Most plugins load once per worker and
never notice. LTX 2.5 reloads its Gemma 4 encoder on every run (sequential stages, AB-D-0011), so it reaches the
limit in about 379 runs.

## Fix (tested)

`mlx-swift-updateInternal.patch`: `_updateInternal` sets a fresh `mlx_array` and frees the old one, so `~array()`
runs and breaks the cycle once the last sibling is replaced. Built through `swift package edit mlx-swift` against a
patched copy:

| Run | Before | Patched |
|---|---|---|
| Minimal sibling case, 3 rounds | 1,608 · 3,208 · 4,808 | 8 · 8 · 8 |
| mlx-swift-lm `loadWeights`, Gemma 3 4-bit | 5,424 · 10,840 · 16,256 | 8 · 8 · 8 |
| Gemma 4 load + encode | 5,276 · 10,524 · 15,772 | 28 · 28 · 28 |
| Full LTX compact24 runs | 10,576 · 15,880 · 21,104 | 56 · 56 · 96 |

## Shipped

Upstream had already made the same fix (ml-explore/mlx-swift#501, released in 0.33.0), but mlx-swift-lm 3.32.3 and
ltx-2-mlx-swift 0.20.0 cap mlx-swift below 0.33. mlx-engine answered AB-A-0249 with a fork (decision AB-D-0208,
receipt AB-R-0751).

- **The fork:** xocialize/mlx-swift 0.32.4 (`4650bd13`) is upstream 0.32.3 plus #501.
- **The engine:** mlx-engine-swift 0.74.1 (`1cc9efa`) takes it with `from: "0.32.4"`.
- **LTX:** gaea-plugin-ltx 0.1.3 pins that engine, and names the fork in its own root line for `ltx-inproc`. A root
  line naming ml-explore's URL would win over the fork and drop the fix.

On 0.1.3 the minimal case and Gemma 4 loads stay at 8 bytes. Through Gaea (1.0.0-rc.2, LTX 0.1.3 from GitHub, 12 jobs
back to back, `gaea-ltx-0.1.3*.{jsonl,gpp}`), all jobs succeeded. The worker's MLX live bytes after each run were
76 · 56 · 96 · 96 · 96 · 96 · 56 · 56 · 56 · 56 · 56 · 56 · 56, against 0.1.2's 5,312 · 10,576 · 15,840 · 21,104 · 26,368
(`gaea-ltx-alone*`). Its idle footprint held at about 1,097 MB.
