# AB-T-0371: the cross-process governor on MLXMemoryPolicy

| | |
|---|---|
| **Date** | 2026-10-28 |
| **Host** | Gaea 0.3.0, Release, `dist/Gaea.app`, on mlx-engine-swift 0.73.0's `MLXMemoryPolicy` (contract 1.58.0, AB-T-0357) |
| **Plugins** | From their GitHub releases: [qwen-image 0.1.1](https://github.com/xocialize/gaea-plugin-qwen-image/releases/tag/v0.1.1), [z-image 0.1.0](https://github.com/xocialize/gaea-plugin-z-image/releases/tag/v0.1.0), [flux2-klein 0.1.0](https://github.com/xocialize/gaea-plugin-flux2-klein/releases/tag/v0.1.0) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Scripts** | [`tools/acceptance-governor.sh`](../../../tools/acceptance-governor.sh) under a 70 GB budget: **14 passed, 0 failed** ([run/acceptance.log](run/acceptance.log)). [`tools/acceptance-scheduler.sh`](../../../tools/acceptance-scheduler.sh) (AB-T-0363's), restaged: **19 of 19** ([scheduler-0.3.0](scheduler-0.3.0/acceptance.log)) |

## What changed

- **Admission and eviction come from the shared policy.** Gaea builds a `MemoryState` from its workers: each worker is
  a tenant, with its prepared lanes' resident bytes, their largest peak, its measured `phys_footprint` and when it was
  last used, and a busy worker carries a run. `MemoryPolicy.plan` decides, and the scheduler carries out the plan: it
  stops the idle workers the plan evicts, in order, including any that real pressure (R-MEM-1) evicts. A refusal is
  `no_capacity`. MLXServeEngine runs the same rules in-process (AB-D-0170).
- **Two settings make it Gaea's.** `transientAccounting: .admittedRunsOnly` means only the job being admitted reserves
  a peak, since Gaea runs one GPU job at a time. `idleCharge: .largerOfDeclaredAndMeasured` charges an idle worker its
  resident bytes or what it measures, whichever is larger. This fixes AB-T-0363's finding: the idle Z-Image worker that
  was charged 43.0 GB is now charged 17.26 GB ([ledger](scheduler-0.3.0/ledger-2b-both.txt)), and it stays beside
  demo-matmul.
- **Lane choice (G-23) asks the policy** what stopping every idle worker would free
  (`availableBytes(_:afterEvictingIdleExcept:)`), without committing to it, then picks the lane.
- **A worker's own other models.** The policy sees workers, not the models inside one. When a lane fits only without
  the worker's other models, Gaea unloads them from the worker first and logs it.
- **Every worker gets the whole budget** in `configure`. Before, a worker's ceiling was the budget less what the other
  workers held when it launched. That went stale once the plan stopped them: the first run here had the Qwen worker
  refuse Qwen-Image-Edit at 55.7 GB after Gaea had made room for it. GPP-1 now says so.
- **Every eviction is logged with its reason:** the plan (what the admission needs against the budget, and who goes),
  then each eviction with the worker's charge ([run/scheduler.log](run/scheduler.log)).

## The recorded run: three plugins, 70 GB

Declared, the lanes add up to 160.4 GB: Qwen-Image-Edit 63, Qwen-Image Flash 31.6, Z-Image Turbo int4 39.9 and FLUX.2
Klein bf16 25.9.

| Job | Ran | Workers after | What the governor did |
|---|---|---|---|
| 1 Klein 4B bf16 | 7.3 s | Klein | Fits alone |
| 2 Z-Image Turbo int4 | 13.5 s | Klein, Z-Image | Fits: the idle Klein worker is charged 15.97 GB, what it measures, not its 25.9 GB declaration |
| 3 Qwen-Image-Edit bf16, 4 steps | 71.5 s | Qwen | Needs 93.07 GB: evicts Klein (15.97 GB), then Z-Image (14.10), least recently used first |
| 4 Z-Image again | 13.2 s | Z-Image | Needs 84.03 GB: evicts the idle Qwen worker (44.13 GB) |
| 5 Qwen-Image Flash int8 | 14.8 s | Qwen, Z-Image | Fits beside Z-Image, charged 14.10 GB. The old rule charged Z-Image its 39.9 GB declaration, and 39.9 + 31.6 = 71.5 would have evicted it |
| 6 Qwen-Image-Edit, in Flash's worker | 75.6 s | Qwen | Fits only without Flash: Flash is unloaded from the worker, then the plan needs 77.10 GB and evicts Z-Image |
| 7 Qwen-Image Flash again | 15.6 s | Qwen | Fits only without Edit: Edit is unloaded from the worker |

- **No OOM.** Every job succeeded, no worker died and nothing was requeued. Sampled every second, the workers'
  `phys_footprint` summed to at most **60.31 GB**, during Qwen-Image-Edit, under the 70 GB budget
  ([footprint-samples.txt](run/footprint-samples.txt)).
- **The ledger against host-read footprints.** After each job, what each worker reports matches what the host reads
  with `proc_pid_rusage`, to within 1 %. All but two readings are identical: the idle workers in ledger 2 and 5, whose
  report predates their last read.

| After job | Worker | Host reads | Worker reports | Charged | Declared |
|---|---|---|---|---|---|
| 1 | Klein (bf16) | 16.12 GB | 16.12 | 16.12 | 25.9 |
| 2 | Klein, idle | 15.97 | 16.12 | 15.97 | 25.9 |
| 2 | Z-Image (int4) | 14.25 | 14.25 | 14.25 | 39.9 |
| 3 | Qwen (Edit bf16) | 44.13 | 44.13 | 44.13 | 63.0 |
| 5 | Qwen (Flash int8) | 27.45 | 27.45 | 27.45 | 31.6 |
| 5 | Z-Image, idle | 14.10 | 14.25 | 14.10 | 39.9 |
| 6 | Qwen (Edit) | 44.09 | 44.09 | 44.09 | 63.0 |
| 7 | Qwen (Flash) | 25.05 | 25.05 | 25.05 | 31.6 |

Every recorded GPP session passes `tools/validate.py --transcript` ([run/sessions](run/sessions)).

## The System page

The System page lists Gaea and each worker with its measured footprint, and sums them (AB-T-0355). Each line now
carries the ledger too:
- **Gaea's line:** the budget, what the workers are charged, and what is free.
- **Each worker's line:** its lanes, its charge against its declaration, and whether it is running a job or past its
  declaration.

![System, memory](console-system-memory-light.png)

[Dark](console-system-memory-dark.png). MESKit's Engine Processes card has no budget field, so the budget is text on
Gaea's line. A bar for it would be a MESKit change, through mlx-apps.

## Fixed along the way

- **`Gaea --snapshot` never quit.** It called `NSApp.terminate` from inside a main-actor task, whose `terminateLater`
  reply waited on another main-actor task that couldn't start. The snapshot now stops the workers and exits, in 9.7 s.
  The bug had been there since 0.1.0.
- **AB-T-0363's script was staged on the old over-charge.** At 44 GB nothing is evicted any more, so it now runs at
  43.1 GB, where int8 still can't fit beside the demo's measured bytes. It now expects the idle Z-Image worker to be
  kept for demo-matmul.
- **The first runs of the governor script failed on the script itself.** A check called `exit` in the script's own
  shell and skipped the shutdown, so the next run met that Gaea still serving its port. A second check counted an
  eviction once that happens twice. Neither was a governor fault.

## Deviation from the task

The task's run names Qwen-Image-Edit, Z-Image and **the forge pack**. The forge pack (AB-T-0369) isn't built yet, so
FLUX.2 Klein took its place. Three plugins, with lanes adding up to 160 GB declared against a 70 GB budget, still
exercise every rung Gaea uses.

## Not covered here

- **Preemption.** Gaea runs one GPU job at a time, so a plan never reclaims a run, and nothing staged one. If a plan
  ever did, Gaea logs it and goes on.
- **External tenants** (AB-A-0210) aren't modelled: Gaea declares none.
- **Real pressure.** The R-MEM-1 path is wired, with the reading being what the other workers measure plus what the
  admitted worker will hold. No run went past `0.85 × budget`, so it never evicted anything.
