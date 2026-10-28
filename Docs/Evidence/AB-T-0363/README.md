# AB-T-0363: eviction, requeue once and lane fallback, with real workers

| | |
|---|---|
| **Date** | 2026-10-28 |
| **Host** | Gaea 0.2.1, Release, `dist/Gaea.app`, `--budget-bytes 44000000000` |
| **Plugins** | [gaea-plugin-z-image 0.1.0](https://github.com/xocialize/gaea-plugin-z-image/releases/tag/v0.1.0) (lanes int4 39.9, int8 43.0, bf16 48.5 GB) and [gaea-plugin-demo 0.3.0](https://github.com/xocialize/gaea-plugin-demo/releases/tag/v0.3.0) (`demo-matmul`, 2.37 GB), both notarized, installed by repo URL from the release stand-in |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Script** | [`tools/acceptance-scheduler.sh`](../../../tools/acceptance-scheduler.sh): **20 passed, 0 failed** ([acceptance.log](acceptance.log)) |

A 44 GB budget is what makes each path happen: Z-Image's int8 lane (43.0 GB) fits alone but not beside the demo's
2.37 GB, and bf16 (48.5 GB) never fits. Every Turbo job is 1024², seed 42.

## Acceptance

| Done = | Result | Evidence |
|---|---|---|
| (1) The idle worker is stopped to admit the other | **Pass, both ways** | With Turbo's default set to int8 and the demo's worker idle and resident, the Turbo job stops the demo and runs int8, with no `lane_fallback`. Then demo-matmul stops the idle Z-Image worker. [scheduler.log](scheduler.log), [ledger-1-demo.txt](ledger-1-demo.txt), [ledger-2-turbo.txt](ledger-2-turbo.txt) |
| (2) A job whose worker is SIGKILLed mid-run completes on a relaunched worker with `requeued: true` | **Pass** | The worker (pid 35665) was killed at denoise step 2 of 8. Gaea logged `worker_died`, launched pid 35752 (hello after 0.015 s) and ran the job again. The job succeeded with `requeued: true`, lane int8, and the same bytes as the clean int8 run (sha256 `3b69831138a24cc0…`). [job-requeued.json](job-requeued.json), [z-image-logs.txt](z-image-logs.txt) |
| (3) No `x-gaea.lane`: the smaller lane and a `lane_fallback` warning. A request naming the big lane is refused `no_capacity` | **Pass** | With Turbo's default set to bf16, the job ran int8 with *"Loaded z-image-turbo lane int8 (43.00 GB) instead of the default bf16 (48.50 GB), which doesn't fit in the memory free now."* `x-gaea.lane: bf16` failed `no_capacity`: *"Lane bf16 needs 48.50 GB and 44.00 GB is free; a request that names a lane never falls back."* [job-fallback.json](job-fallback.json), [job-named-bf16.json](job-named-bf16.json) |
| Transcripts pass `tools/validate.py --transcript` | **Pass, 5 of 5** | [sessions/](sessions). The killed worker's session ends `# exited: signal 9` (see below). |

| Job | Submit to settled | Worker run |
|---|---|---|
| Turbo int8, demo evicted, cold launch and int8 prepare | 15 s | 13.80 s |
| Turbo int8, killed at step 2 and requeued | 18 s | 13.41 s (the second attempt) |
| Turbo, bf16 default falls back to int8 (warm) | 13 s | 13.41 s |
| demo-matmul, Z-Image evicted | 1 s | 0.012 s |

The requeue cost the four seconds already spent before the kill, with no relaunch delay to speak of.

## What changed in Gaea (0.2.1)

- **`gaea models lane <id> [<lane> | default]`** (operator command `models.lane`). It sets the lane a model loads when
  it fits, MEM-7's "operator's default". The scheduler had always read this setting, but nothing could write it. Z-Image's
  manifest default is int4, its smallest lane, so without it a fallback could never happen. `gaea models` marks the
  default in effect with `*`.
- **Transcripts record how the worker ended.** The host appends `# exited: status N` or `# exited: signal N` when the
  process ends. A run left open by a worker that died without a shutdown is not a protocol error, because the host
  requeues it. `validate.py` accepts such a run, and rejects any line after the exit
  (`examples/v1/invalid/line-after-exit.gpp`). GPP-1 says so. Before this, the killed session failed with
  `run h3 never ended`.

## Found: idle workers are charged their peak

The ledger charges every worker its declared bytes, which are persistent bytes plus the largest peak transient. After
its run, Z-Image's idle worker measured **17.3 GB** `phys_footprint` but was charged **43.0 GB**: 15 GB resident plus
the 28 GB peak. That is why demo-matmul (2.37 GB) evicted it, though 26 GB of the budget was physically free. Gaea
runs one GPU job at a time (`GPULane`, G-13), so only the job about to run needs its peak reserved. An idle worker
should be charged its resident bytes. This test depends on the conservative rule as it stands, so it isn't changed
here. It goes to the cross-process governor (AB-T-0371), which replaces this accounting with mlx-engine's shared
policy.

## Not covered here

- An eviction while the other plugin is **busy**, which must wait, not evict: the scheduler skips busy workers, but no
  run here had two plugins' jobs in flight at once.
- A second death on the requeued attempt, which fails the job, wasn't staged.
