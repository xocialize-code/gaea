# AB-T-0355: the Gaea host skeleton, G0's exit tests

| | |
|---|---|
| **Date** | 2026-10-28 |
| **Build** | Gaea 0.1.1, Release, `dist/Gaea.app` from `scripts/build-app.sh`: Developer ID Application: Dustin Nielson (CFZS6RXUCP), hardened runtime, not notarized |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Plugin** | `xocialize/gaea-plugin-demo` v0.2.0 (pre-release, signed) and v0.2.1 (full release, signed and notarized), both real GitHub releases of a public repo, read with no token |
| **Script** | [`tools/acceptance-g0.sh`](../../../tools/acceptance-g0.sh): **35 passed, 0 failed** ([acceptance.log](acceptance.log)) |

## The four exit tests

| Test | Result | How |
|---|---|---|
| The MES Base conformance suite passes against Gaea serving the demo plugin | **Pass** | MESKit 0.5.0's `mes-conformance`. Open mode: 28 passed, 0 failed, 16 skipped ([report](conformance-open.md)). Paired mode, with `--pair`: 30 passed, 0 failed, 14 skipped ([report](conformance-paired.md)). Base 0.1 and Image 0.1 both conform. |
| A plugin added by repo URL installs, updates, rolls back, and enables and disables | **Pass** | Both demo releases on GitHub, with no stand-in. Add, naming v0.2.0, installed it in 1.6 s (download, sha256, signature, manifest). The update check found 0.2.1, the update installed it beside 0.2.0 and switched, keeping 0.2.0, and the rollback switched back to 0.2.0. A plain add, with no version, took v0.2.1 and skipped the pre-release. An update during an 8.6 s run was staged, then switched in when the run ended. Disabling removed the operation, and a job was then refused with 404; enabling brought it back. |
| An ad-hoc or tampered plugin is refused | **Pass** | At install, through the same path, from a stand-in releases API (`tools/release-standin.py`) built from the real 0.2.1 bundle: tampered (manifest edited after signing, OSStatus -67054), ad hoc (re-signed `-`), and a manifest naming another team (refused, citing G-22). Nothing reached the plugin folder or staging ([refusals](refusals.txt)). At launch: a bundle edited after install failed its job, and the plugin was marked failed until rolled back. |
| Configuration is reachable only from the server's own UI and the local CLI | **Pass** | MES answers 404 to `plugins`, `config`, `operator`, `admin` and `settings`, for both GET and POST. The only TCP listener is MES on loopback (open mode). The operator socket is mode 0600 in a 0700 folder. A Developer ID-signed Gaea refuses an unsigned client by its audit token and answers the signed `gaea` CLI. MCP lists only operations and the four helpers (BASE-080). |

## Also checked

- **Pre-releases are skipped by default.** "Newest compatible release", for an add or an update check, means the newest *full* release, as GitHub's own `latest` does. An operator installs a pre-release only by naming its version: `gaea plugins add <repo> 0.2.0`, or `gaea plugins update <id> 0.2.0`.
- **No token on the default path.** The plugin repos are public, so the run had no token in its environment. `GAEA_GITHUB_TOKEN` remains an optional override for a private repo; Gaea reads it per request and never stores it.
- **The host links no MLX.** `nm` finds 0 MLX symbols in `Gaea.app/Contents/MacOS/Gaea`; MLXToolKit is linked, for manifests.
- **GPP sessions.** Every session Gaea recorded passes `tools/validate.py --transcript` (4 of 4 in the run). [session-demo-0.2.0.gpp](session-demo-0.2.0.gpp) is one of them: hello, configure, prepare, two runs (310 progress lines), unload, memory, shutdown. It is checked against [its manifest](manifest-demo-0.2.0.json).
- **A refused launch fails at once.** The spike's harness fix: Apple's `/bin/sleep`, launched under our team's launch requirement, is a SIGKILL at exec. `WorkerProcess.start` fails through `terminationHandler` in 11 ms, not after the 10 s hello wait (`WorkerProcessTests.aRefusedLaunchFailsAtOnce`).
- **Hello latency** (Release, [hello-times](hello-times.txt)): 0.24–0.31 s on a worker's first launch of a newly installed bundle (two runs), and about 10 ms on a relaunch of the same bundle.
- **Unit tests:** 12 of 12 (`swift test`): lane choice (G-23), plugin stores, the enablement store, repo URLs, SemVer, a live demo session with a cancel, and refusals.
- **The console, live.** Driven through the real app window: **Add Plugin…** opened the add sheet, the repo URL was typed and Add pressed, the progress bar ran, and the plugin card appeared (0.2.1, Dustin Nielson (CFZS6RXUCP)). The plugin's toggle turned it off; the CLI and MES confirmed it, and it was turned back on.
- **Console pages** (rendered by `Gaea --snapshot` after one run, so the worker is live):
  - [Plugins, light](console-plugins-light.png) and [dark](console-plugins-dark.png): an update to 0.2.1 offered, with its notes.
  - [System → Memory](console-system-memory-light.png): Gaea at 273 MB, and the demo worker at 1.13 GB as a second process.
  - [Models](console-models-dark.png): the demo model as the autoswitch default.

  The black bar in the sidebar is the selected row in an offscreen render, as in MESKit's gallery.

## Not verified

- **The trust sheet.** v1 has no trust list (G-22): another team's plugin is refused with that reason, so the sheet never opens.
- **A caller of another user** on the operator socket. Only the same-user and signed-or-unsigned cases were run.
- **Lane fallback on a real worker.** The demo has one lane. The rules are unit-tested on the z-image example manifest's three lanes, and an unknown named lane is refused on the wire (422).
- **Eviction between two workers, and requeue after a worker dies mid-run.** Both are implemented. Neither was exercised, since only one plugin exists.
- **Notarization of Gaea itself.** It's signed but not notarized (CI's job).
- **Engine picking across a LAN** (G-19): that is G1.
