# AB-T-0356: what running a model out of process costs

| | |
|---|---|
| **Date** | 2026-10-28 |
| **Machine** | Mac Studio, Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2. Internal SSD (Apple Fabric) and the external Satechi volume (PCI-Express SSD, APFS, **100% full: 32 GB free**) |
| **Build** | Release only (`swift build -c release`, Swift 6.4). The worker ran as a signed `bench.gaeaplugin` (Developer ID Application: Dustin Nielson (CFZS6RXUCP), hardened runtime), launched with `Process.launchRequirement` pinned to that team, and found its metallib through its own bundle. |
| **Versions** | gaea-plugin-kit **0.1.1** (89ff3f2), z-image-swift **0.5.4** (eadca87), mlx-engine-swift **0.72.0** (0ca55ed), mlx-swift 0.32.3, mlx-swift-lm 3.32.3; the host side models Gaea **0.1.1** (97f18da). Pinned in [`Package.resolved`](../../../Benchmarks/AB-T-0356/Package.resolved). |
| **Harness** | [`Benchmarks/AB-T-0356/`](../../../Benchmarks/AB-T-0356): `bench-worker` (a GaeaPluginKit worker: Z-Image Turbo int4, and a probe model with a trivial GPU op and a spool echo), `bench-host` (a minimal MLX-free GPP host that reads the worker's `phys_footprint` with `proc_pid_rusage`), `bench-inproc` (the same lane in-process through `MLXServeEngine`). `scripts/build.sh`, `scripts/run.sh`, `scripts/summarize.py`. Not a plugin; never published. |
| **Data** | One JSON line per run in [`raw/`](raw). Every metric's median, min, max and standard deviation: [summary.md](summary.md). |

Figures are **median (min–max)**. Each row is at least 5 runs.

## Verdict

- **No IOSurface or shared memory.** Spool files cost **0.06–0.36%** of a typical image job and **1.0–2.2%** of the cheapest real per-frame video job, on both volumes. That's below the 5% bar, so the shared-memory comparison was not built. The plan keeps files in the spool (GPP v1 as written).
- **The codec costs, not the transport.** Moving raw 1080p RGBA through files costs 3.2 ms per frame on the internal SSD. Encoding and decoding PNG at each of the four hops costs 20 ms per frame on every core, and 160 ms on one. IOSurface would remove the file but not the codec. Frame batches should cross the spool raw, or in the plugin's native format, not as PNG.
- **A worker's fixed cost is about 146 MB and about 80 ms.** That is the `phys_footprint` once MLX and the Metal device are up, with no model loaded, and the time from launch to a finished first GPU op. Unloading a model doesn't return the 146 MB; only exiting does.
- **Out of process costs nothing measurable on a real model.** Z-Image Turbo int4's cold start, from launch to the first 1024² image, is 12.52 s through a worker and 12.59 s in-process. The warm second job takes 11.50 s and 11.47 s. The spreads overlap. Both produce byte-identical PNGs.

## 1. Worker baseline

`bench-host baseline`, 7 runs. Each run is a fresh worker process: hello, `configure` (a 64 GB `WorkerBudget`, `wiresWeights` off, as Gaea's scheduler sends), then `prepare` on the probe model. Then one 256×256 matmul on the GPU, a second one, unload, and shutdown. `phys_footprint` is read by the host from outside.

| After | phys_footprint |
|---|---:|
| hello | **3.2 MB** (3.1–3.3) |
| `configure`: `MLXServeEngine(workerBudget:)` built, Metal not yet touched | **5.3 MB** (5.2–5.5) |
| the first GPU op: MLX and the Metal device up, no model loaded | **146.1 MB** (145.4–146.6) |
| `unload` | 145.6 MB (144.8–146.1) |
| `shutdown` | process gone (`proc_pid_rusage` fails on the pid in 7 of 7 runs) |

The worker's own `memory` report agreed with the host's reading after the GPU op (146.1 MB; `gpuActiveBytes` 0.3 MB). So the 146 MB is the Metal device, the command queue and MLX's loaded kernels, not buffers. After a real model is unloaded, the floor is **209 MB** (208–209), 5 of 5 runs for Z-Image: the 146 MB plus what the model's code paths left.

| Phase | Time |
|---|---:|
| launch → main (exec, dyld, the launch requirement) | 19.2 ms (11.0–30.1) |
| main → hello | 18.3 ms (2.9–27.4) |
| **launch → hello** | **38.9 ms** (13.9–57.5) |
| `configure` round trip | 20.4 ms (9.2–47.1) |
| first GPU op, round trip | 16.3 ms (11.9–21.9) |
| second GPU op, round trip | 6.4 ms (1.5–8.3) |
| **launch → first GPU op done** | **83.3 ms** (35.6–101.4) |
| `shutdown` → exit | 6.5 ms (5.6–12.4) |

**First launch of a newly signed bundle** (`raw/baseline-first-launch.jsonl`, 5 runs, each after a fresh `codesign`): launch → hello is **235 ms** (225–259), almost all of it before main (232 ms). That is the system's first assessment of a new code signature. It matches AB-T-0355's 0.24–0.31 s for a newly installed plugin. The footprints are unchanged.

**Not repeatable, one observation:** the first GPU op of the first launch after a fresh build took 1.34 s, against 16 ms afterwards. The Metal shader cache was cold. Re-signing the same binary didn't repeat it, so it is paid once per build on a machine, not once per install.

**Memory returned at exit:** the machine's anonymous memory (internal, wired and compressed pages), taken before launch and after exit, moved by −410 to +83 MB across the 7 runs, a median of −0.1 MB. Other processes add that much noise, so this says only that nothing near a model's size stays behind. The direct evidence is the pid being gone.

## 2. Real-model cold start: Z-Image Turbo int4

**Choice.** Z-Image Turbo's weights were already local (`mlx-community/Z-Image-Turbo-bf16`, 19 GB; z-image-swift quantizes the DiT to int4 at load), so nothing was downloaded. Both modes ran z-image-swift 0.5.4 lane int4 (`ZImageConfiguration.turbo(quant: .int4)`) with the same request: 1024², 8 steps, seed 42, guidance at the Turbo default 0, and the same prompt. Both used the same `WorkerBudget` (64 GB, `wiresWeights` off). Runs alternated worker and in-process, 5 each, after one unrecorded pass of each mode, so both found the snapshot in the file cache. **The worker PNG and the in-process PNG are byte-identical** ([the image](zimage-turbo-int4-seed42.png)).

| Phase | Worker (GPP) | In-process (`MLXServeEngine`) |
|---|---:|---:|
| launch → hello | 13.5 ms (11.3–15.8) | n/a |
| `configure` / engine init | 8.6 ms (7.6–10.7) | 9.4 ms (8.0–43.3) |
| `prepare` (register and load int4 to resident) | 1.065 s (1.025–1.181) | 1.083 s (1.034–1.105) |
| first generate, 1024² | 11.47 s (11.41–11.53) | 11.50 s (11.38–11.52) |
|   of which: encode → first denoise step | 0.04 s | 0.04 s |
|   denoise, 8 steps | 9.90 s | 9.90 s |
|   decode (VAE) | 1.48 s | 1.51 s |
|   postprocess (PNG) and, for the worker, the spool write and the result line | 0.04 s | 0.04 s |
| **cold total (launch → first image)** | **12.52 s** (12.50–12.74) | **12.59 s** (12.43–12.65) |
| host reads the output PNG (file / full decode) | 0.21 ms / 18.3 ms | n/a |
| **warm second generate** | **11.50 s** (11.43–11.52) | **11.47 s** (11.40–11.54) |
| phys after prepare | 14.19 GB (14.19–14.19) | 14.18 GB (14.18–14.20) |
| peak phys, first generate | 22.44 GB (21.98–22.58) | 22.57 GB (22.50–22.58) |
| phys after unload / evict | 0.209 GB | 0.209 GB |

The phases are the time each `RunProgress` phase first appeared, from the worker's `progress` lines and from the in-process sink. The cold and warm generates are equal because `prepare` already made the weights resident: the first generate pays no load. What out-of-process adds to a cold job is launch → hello plus `configure`, about 22 ms, against 9 ms of engine init in-process. That is 0.2% of the job, inside the run-to-run spread (σ ≈ 0.1 s). A warm job's GPP overhead, round trip minus the worker's own run time, is 0.23 ms.

**Memory, both modes:** 14.19 GB after prepare is the declared int4 resident (11.9 GB, AB-R-0612; the worker reports `gpuActiveBytes` 11.84 GB) plus MLX's buffer pool (`gpuCacheBytes` 2.12 GB, the engine's automatic `min(2 GB, 5% of ceiling)`). The 22.6 GB peak is inside the declared 11.9 + 28 GB.

**Not measured: a load from a cold file cache.** Flushing the file cache needs `sudo purge`, which this session couldn't run, so every prepare read the 19 GB snapshot from memory. A first load after a reboot reads it from the SSD as well; that cost is the same in both modes.

## 3. Spool throughput

`bench-host spool`: a warm worker. Per run, the host encodes and writes the inputs into `<root>/job-*/in`. It sends a `run` that touches nothing (`gpp_noop`: the message round trip with the same path list), then an echo `run`: the worker reads every input (file, then a full decode), then writes as many outputs (encode, then file). The host then reads every output (file, then a full decode) and deletes the job folder. Files are written with plain `write(2)`, with no fsync or atomic rename, as a spool needs. Inputs are the Z-Image output scaled to cover the frame, panned per frame (60 distinct frames, cycled). Each case ran 5 times after a warm-up run.

**The file path** is host write I/O, worker read I/O, worker write I/O, host read I/O, and the GPP round trip beyond the worker's own work. **The codec** is the four encodes and decodes. **The job** is the Z-Image warm generate (11.50 s) for single images, and RIFE ×2 at 1080p, the cheapest real video model on record, at 0.32 s per output frame (model registry, frameInterpolate row; mlx-rife-swift, M5 Max, Release), for frame batches.

| Case | Bytes in | Internal: file path | External: file path | Codec, all four hops (internal) | File path, % of the job (internal / external) |
|---|---:|---:|---:|---:|---:|
| 4K PNG, 1 image | 7 MB | 8.0 ms (3.1–8.3) | 6.3 ms (6.3–6.4) | 505 ms | 0.07% / 0.06% |
| 4K 16-bit TIFF, 1 image | 66 MB | 17.0 ms (16.2–23.7) | 41.1 ms (40.7–42.9) | 118 ms | 0.15% / 0.36% |
| 1080p raw RGBA × 120 | 995 MB | 377 ms (373–468): **3.14 ms/frame** | 799 ms (792–832): **6.66 ms/frame** | none | 0.98% / 2.08% |
| 1080p raw RGBA × 600 | 4.98 GB | 1.95 s (1.94–1.98): **3.25 ms/frame** | 4.27 s (4.16–4.63): **7.11 ms/frame** | none | 1.01% / 2.22% |
| 1080p PNG × 120, one core | 314 MB | 148 ms: 1.23 ms/frame | 297 ms: 2.48 ms/frame | 19.2 s: **160 ms/frame** | 0.38% / 0.77% |
| 1080p PNG × 120, every core | 314 MB | 51 ms: 0.43 ms/frame | 185 ms: 1.54 ms/frame | 2.27 s: **18.9 ms/frame** | 0.13% / 0.48% |
| 1080p PNG × 600, every core | 1.57 GB | 316 ms: 0.53 ms/frame | 1.26 s: 2.10 ms/frame | 12.0 s: **20.0 ms/frame** | 0.16% / 0.66% |

Each hop, separately (medians; every hop of every case is in [summary.md](summary.md)):

| 1080p raw × 600 | Internal | External |
|---|---:|---:|
| host write (4.98 GB) | 651 ms (7.65 GB/s) | 1,763 ms (2.82 GB/s) |
| GPP: a run that touches nothing, 600 paths | 3.4 ms | 3.5 ms |
| GPP beyond the worker's work, echo with 600 outputs | 28 ms | 34 ms |
| worker read | 320 ms (15.5 GB/s) | 333 ms (15.0 GB/s) |
| worker write | 644 ms | 1,798 ms |
| host read | 305 ms | 311 ms |
| delete the job folder | 158 ms | 439 ms |

- **Writes are where the volumes differ:** 7.6 GB/s on the internal SSD against 2.8 GB/s on the external one. Reads come back from the file cache at about 15 GB/s on both. The external volume was 100% full during the run, which may slow APFS writes; a spool there should have headroom.
- **Writes land in the file cache.** They aren't flushed before the worker reads them, and a spool doesn't need them to be. A machine short of memory would push those pages to the SSD sooner, and then a write runs at the SSD's own speed. That wasn't measured.
- **The GPP message is never the cost:** 0.27–0.33 ms for one path, and 3–5 ms for 600 paths both ways.
- **One limit for long batches.** A `result` with 600 file outputs is a 74–147 KB line, about 245 bytes per output. GPP's 1 MiB line cap therefore stops one `result` at roughly 4,000 file outputs. A longer batch needs `chunk` messages (which GPP v1 already has) or an output folder. This is noted for the video profile (G3); nothing changes now.

## Not measured

- **A load from a cold file cache** (needs `sudo purge`, see §2).
- **The IOSurface or shared-memory handoff itself.** The file path stayed under 5% of the job, so by the task's rule it wasn't built.
- **Writes that reach the SSD**, under memory pressure (see §3).
- **A per-frame video job measured here.** The 0.32 s per frame for RIFE is the model registry's figure, cited rather than measured in this run. A faster model would raise the percentages in §3 in proportion: raw frames on the external volume would reach 5% at about 140 ms per frame.
- **Gaea itself as the host.** `bench-host` does what Gaea's `WorkerProcess` does (signature-pinned launch, GPP lines, `proc_pid_rusage`) with timestamps at each step. Gaea 0.1.1's own hello times (AB-T-0355: 0.24–0.31 s on a first launch, about 10 ms on a relaunch) are in the same range as §1.
