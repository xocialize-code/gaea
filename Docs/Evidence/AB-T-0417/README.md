# AB-T-0417: crash and requeue reporting, and quarantine (G4 order 5, SRV-8, G-26)

**Done:** Gaea 0.14.0 ran the demo plugin's 0.3.2 release from GitHub with crashes injected. The run showed:
- **A SIGKILL mid-job:** the crash was recorded, and the job was requeued and succeeded.
- **A trap in the plugin:** both tries crashed. The job failed with both crashes named, and each record kept macOS's
  crash report and the worker's `Fatal error:` line.
- **The quarantine:** it tripped on the third crash in ten minutes and cleared when the operator switched the plugin
  on.

The run is `tools/acceptance-crashes.sh`, 31 of 31 ([acceptance.log](acceptance.log)).

## What Gaea does

- **A crash** is any worker exit Gaea didn't ask for. Exits from `shutdown`, the escalation ladder or a refused hello
  aren't crashes.
- **Each crash is a row in `gaea.sqlite`** (`crash`, migration v4). The row holds:
  - the plugin and version, and the pid;
  - the model, lane and job, or "idle";
  - the signal or exit code, and a fault if Gaea killed the worker for one (a line past GPP's limit);
  - what became of the job: `requeued`, `failed` or `idle`;
  - stderr's last 40 lines, read after stderr closes, so the `Fatal error:` printed just before a trap is kept.
- **macOS's crash report:** for a signal that writes one (a trap, a bad access, an abort), Gaea waits up to 20 s for
  the `.ips` in `~/Library/Logs/DiagnosticReports`. It matches the file by process name and pid, copies it to
  `<GAEA_HOME>/Crashes/<id>-…ips`, and keeps a summary: the exception and the faulting thread's first frames. A SIGKILL
  writes none, and the record says so. In the run, both reports were in within a second.
- **The job:**
  - A run whose worker dies is tried once more on a new worker, as before (AB-T-0363).
  - If that worker dies too, the job fails, naming both crashes. For example: "the worker crashed twice running this
    job, SIGTRAP (crash #2) then SIGTRAP (crash #3); it was requeued once" ([job-trap-failed.json](job-trap-failed.json)).
  - A streamed run is never requeued, and its failure names its one crash.
- **Quarantine (G-26):**
  - A plugin's third crash within ten minutes switches it off. Crashes during a requeue and while idle count too.
  - The plugin's models leave the offers, and its jobs are refused with the reason.
  - Switching it on (`gaea plugins enable`, or the console's On toggle) clears the quarantine, and its crash count
    starts again from then.
  - The quarantine survives a restart.
- **Where it shows:**
  - `gaea crashes [<plugin>]` lists the crashes, newest first ([crashes-end.txt](crashes-end.txt)).
  - `gaea crashes show <id>` gives one in full ([crash-3-trap.txt](crash-3-trap.txt),
    [crash-1-sigkill.txt](crash-1-sigkill.txt)).
  - `gaea plugins` shows a quarantined line, with how to clear it, and the last day's crashes
    ([plugins-quarantined.txt](plugins-quarantined.txt)).
  - `gaea status` has a `Crashes:` line.
  - Every crash, quarantine and clearing is an event (`gaea plugins logs`).
- **The console:** a quarantined plugin's row shows the reason, through MESEngineUI's failed state, and its On toggle
  clears it ([light](console-plugins-light-quarantined.png), [dark](console-plugins-dark-quarantined.png)).

## The run

| Step | What happened |
|---|---|
| SIGKILL | The demo's worker was killed while it rendered four 2048² images. Crash #1: SIGKILL, requeued, with the job, `demo-gradient`, lane fp32 and the pid, and "none: SIGKILL writes no crash report". The job succeeded on a new worker with `requeued: true` ([job-sigkill-requeued.json](job-sigkill-requeued.json)). |
| The trap | Seed 666, with `GAEA_DEMO_TRAP_SEED=666` in Gaea's environment, trapped twice: crash #2 requeued and crash #3 failed. Each has the worker's `Fatal error: demo-gradient: a trap on seed 666` line, and macOS's report copied into `Crashes/`, summarised as `EXC_BREAKPOINT (SIGTRAP)` in `GradientModel.run`, its pid the crashed worker's. |
| Quarantined | Crash #3 was the third in ten minutes. The demo was switched off and offered nothing, a job for it was refused, and `gaea plugins`, `gaea status` and the console said why. It was still quarantined after a restart. |
| Cleared | `gaea plugins enable` cleared it. `demo-gradient` was offered again, and a job ran ([job-after-clearing.json](job-after-clearing.json)). Crash #4, a SIGKILL while idle, was recorded and didn't quarantine it, because the count had started again. |
| Sessions | Every recorded GPP session passes `tools/validate.py`. The killed and trapped workers' transcripts end at their exits. |

`swift test`: 79 tests, including `CrashTests`:
- the tables;
- a report's summary, and finding it by process and pid;
- SIGKILLs against the demo's local release: requeued, failed with both named, then quarantined on an idle third crash;
  refused; cleared; the count restarted; stopping not counted;
- a real trap with its report.

`TrustTests` now reads the demo's version from its `dist`. It still named 0.3.0, so it had been skipped since the
template moved on.

## Also fixed

- **Transcripts of a relaunch:** a worker relaunched within the same second as the one before it overwrote that
  worker's GPP transcript, because the file name was the plugin, the version and the second. A requeue after a crash
  does exactly that. The name now ends with the launch's id.

## The demo's test hook

gaea-plugin-demo 0.3.2 ([d0cb299](https://github.com/xocialize-code/gaea-plugin-demo/commit/d0cb299), released
from CI, notarized) has `demo-gradient` call `fatalError` on the seed `GAEA_DEMO_TRAP_SEED` names. Only a server
started with that variable is affected. AUTHORING.md now says:
- what Gaea does when a worker crashes, and what three crashes cost;
- that a plugin made from the template deletes the hook.

## Released

[v0.14.0](https://github.com/xocialize-code/gaea/releases/tag/v0.14.0) was released from CI: run 41392542919, tag at
c683608, 10.5 minutes ([release-0.14.0.json](release-0.14.0.json)). It was downloaded and checked:
- the sha256 matched;
- `codesign --strict --deep` passed;
- `spctl` gave `source=Notarized Developer ID`, and the staple validated;
- the binary names no `.build` bundle path. The `.build` strings it does carry are source paths from the
  swift-nio-ssl and swift-crypto checkouts.
- `Gaea --version` said 0.14.0. Started headless off the runner, its `gaea status` had the `Crashes:` line, and
  `gaea crashes` answered.

## Left

- **The console's crash list:** MESEngineUI has no surface for one, nor a notice for a plugin that crashed but isn't
  quarantined. Both were asked of mlx-apps as **AB-A-0247**; until then the console shows only the quarantine.
- **macOS's own "quit unexpectedly" dialog:** it appears for a crashed worker of an app run by a person, beside
  Gaea's record. The operator's guide (order 6) should say so.
