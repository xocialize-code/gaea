# The 24-hour soak (AB-T-0429, G4 order 7)

`tools/soak.py --app /tmp/gaea-soak/Gaea.app --hours 24 --update-at 12 --update-to 1.0.0-rc.2`, headless Gaea
1.0.0-rc.1 on an M5 Max (128 GB, macOS 27.3) with the default 103 GB budget, from 2026-11-04T16:39Z to
2026-11-05T16:40Z.

- **The mix.** One job at a time, round-robin over seven plugins installed from GitHub (Z-Image 0.1.2, FLUX.2 Klein
  0.2.3, Forge 0.2.1, Kokoro 0.1.1, MOSS-SoundEffect 0.1.2, RIFE 0.1.1, LTX 2.5 0.1.2).
- **Injected crashes.** Every hour, a demo job (0.3.3) with `GAEA_DEMO_TRAP_SEED=666` traps its worker.
- **The update.** At hour 12 Gaea updated itself to 1.0.0-rc.2 from GitHub, mid-mix.

## Result (`summary.json`, `jobs.jsonl`, `events.log`, `samples.jsonl`)

| | |
|---|---|
| Mixed jobs | **7,413 of 7,413 succeeded**: 1,059 on each plugin |
| Self-update | asked 04:39:27Z, waited for the running job, **rc.2 answering 63 s later**; 3,585 jobs on rc.1 and 3,828 on rc.2, none lost |
| Injected crashes | 24 of 24 jobs failed as designed: each worker crashed twice (48 demo crashes), the job was requeued once and then failed naming both crashes |
| Quarantine | none: no plugin crashed three times in ten minutes |
| Other crashes | **2, both LTX** (#19 at 01:45Z after 379 runs, #44 at 12:58Z): `[metal::malloc] Resource limit (499000) exceeded`. Both jobs were requeued and succeeded on a fresh worker |
| Wired memory (vm_stat, 1,073 samples) | first-quarter mean 10.64 GB, last-quarter mean 7.86 GB, peak 74.10 GB while a run held its weights wired |

The two LTX crashes were a leak: every run left 5,264 bytes (1,316 Metal buffers) in MLX. The cause was mlx-swift's
`_updateInternal`, fixed in mlx-engine-swift 0.74.1 and gaea-plugin-ltx 0.1.3. See `../ltx-leak/README.md`.
Everything else Gaea does held steady for 24 hours: the queue, requeueing a crashed job, crash reports, the governor
and the self-update.
