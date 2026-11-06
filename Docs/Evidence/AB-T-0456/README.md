# AB-T-0456: G5's exit (order 6)

G5 added three audio plugins to Gaea:
- IndexTTS 2.5 (AB-T-0452);
- VoxCPM2 (AB-T-0453);
- AuK and AuK-Flash (AB-T-0455).

It also added MES 0.10's `audio.separate` (AB-T-0454). The exit has three parts:
- Gaea Lab on the new audio;
- conformance with every plugin and every opt-in model;
- a 1-hour soak of AuK's staged edits with memory flat.

All runs were against Gaea 1.1.1 from its notarized GitHub release, with plugins from their GitHub releases, on an M5
Max (128 GB, macOS 27.3).

## Gaea Lab on the new audio (`lab/`)

**`tools/lab-audio-g5.sh`: 28 passed, 0 failed** (`lab/lab-audio-g5.log`). Gaea Lab now builds on
media-engine-spec 0.10.1 with pixel-agency-run 0.3.0 unchanged. It runs IndexTTS, VoxCPM2, AuK and the demo, all
installed from GitHub, with AuK's two models enabled.

- **`lab-run`, as the Lab runs jobs:**
  - **IndexTTS:** a clone fitted to 4.0 s at 22.05 kHz.
  - **VoxCPM2:** its own voice at 48 kHz, and `design_voice` with two samples.
  - **AuK without acceptance:** the job fails, and `lab-run` names the licence and the flag to add
    (`--accept LicenseRef-Qwen-Research`).
  - **AuK with `--accept`:** a clone, a dereverb, and a hum at the start with the edited transcript output.
  - **AuK separate:** the second speaker on AuK-Flash, and every voice on Base. Each stem is one WAV of exactly the
    mixture's 133,281 frames.
  - **An unnamed separate:** it runs on `demo-separator` (two stems), never on AuK, which is named-only.
- **The Lab app (`--snapshot`, `lab/app/`):**
  - New presets: an AuK-Flash edit (a hum at the start) and an AuK-Flash separation (the second speaker), each on
    `--input`.
  - Both show AuK's notice and terms, accept them for the run only, run on Every server, and render before and after,
    in light and dark.
  - The separate form shows its stem checkboxes and the speaker pick by order. The result is the `speaker` stem.
- **Transcripts:** all five recorded GPP sessions pass `validate.py`.

**One Lab fix:** snapshot mode kept its own licence acceptances, but its servers went into the user's saved server
list (`PixelAgency.addedEngines` in GaeaLabApp's defaults). Four test servers from recorded runs had built up there.
Snapshot mode now uses a throwaway store (`Gaea.Lab.snapshot`), and the app's server list shows only the run's server.

## Conformance (`conformance/`)

media-engine-spec v0.10.1's `mes-conformance` against Gaea 1.1.1, with all 25 public plugins from GitHub and all
six opt-in models enabled (AuK-Flash, AuK, and LTX's four tiers). Command: `ALL=1 ENABLE="auk-flash auk
ltx-2.5-compact24 ltx-2.5-balanced32 ltx-2.5-standard64 ltx-2.5-max128" tools/conformance-with.sh`.

**88 passed, 0 failed, 7 skipped. Base, Image, Audio and Video 0.1 all conform.**
- The skips are structural:
  - four tests only apply in paired mode (BASE-005, 006, 035, 090);
  - two expiries run longer than the suite waits (BASE-034, 071);
  - no video offer declares previews (VIDEO-014).
- With AuK's offers in play, the Base and Audio tests that name a model now pass. v0.10.1 sends users' acceptance on
  every job (AB-A-0252).
- AUDIO-004 passes this time. It failed once on Step-Audio-EditX in AB-T-0455's runs, and passed 5 of 5 reruns there.

## The soak (`soak/`)

**`tools/soak-auk.py --hours 1`: 4,607 of 4,607 jobs succeeded, 0 crashes, one AuK worker (pid 6468) the whole hour,
and its footprint flat** (`soak/summary.json`).

Each cycle does the following, one job at a time through MES, every request accepting the Qwen Research terms:
- AuK-Flash clones the reference, kept as an asset;
- that take goes through four staged edits, each output kept as an asset and edited in turn: emotion happy, speed 1.25
  (snapped), a hum at the start, then dereverb. Each intermediate asset is deleted once the next edit has used it;
- every third cycle adds a separation of the second speaker on AuK-Flash, and every voice on Base.

| Job | Jobs | Succeeded | Median seconds, submit to settled |
|---|---|---|---|
| speak (clone) | 813 | 813 | 0.58 |
| edit: emotion | 813 | 813 | 0.52 |
| edit: speed | 813 | 813 | 0.50 |
| edit: hum | 813 | 813 | 0.48 |
| edit: dereverb | 813 | 813 | 0.48 |
| separate: speaker (Flash) | 271 | 271 | 0.69 |
| separate: voices (Base) | 271 | 271 | 4.23 |

**Memory:**
- The AuK worker's `phys_footprint` was sampled 57 times, once a minute and always between jobs.
- After warm-up (median over minutes 10–15) it was **17.79 GB**. Over the last 5 minutes it was **17.80 GB**, a change
  of **+0.06 %** against the 5 % bound.
- Over the whole hour it stayed between 17.75 and 17.98 GB.
- The Mac's wired memory, which counts every process, stayed between 24.3 and 25.7 GB until a last sample of 27.9 GB.

This is the workload the G4 soak's leak would have killed: AuK reloads its quantized encoder per request. Before
mlx-engine-swift 0.74.1's mlx-swift fork, every quantized load leaked MLX buffers (AB-L-0330). An hour of these jobs
ran on one worker, with no crash and no growth.

**Interrupted run (`soak-interrupted/`):** the first soak lost power at 38 minutes. By then 2,413 of 2,413 jobs had
succeeded, on one worker, at 17.78–17.91 GB. The run above started from scratch after the reboot.

## Files

- `lab/`: the Lab run's log, every saved output and report, the app's PNGs, and the GPP sessions.
- `conformance/`: the suite's report.
- `soak/`: `jobs.jsonl`, `samples.jsonl` (the ledger every minute), `events.log` and `summary.json`.
- `soak-interrupted/`: the same files, from the run cut short at 38 minutes.
