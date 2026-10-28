# AB-T-0364: plugins' MES offers run as themselves, and the models root is a setting

| | |
|---|---|
| **Date** | 2026-10-28 |
| **Build** | Gaea 0.2.0, Release, `dist/Gaea.app` from `scripts/build-app.sh`: Developer ID Application: Dustin Nielson (CFZS6RXUCP), hardened runtime, not notarized |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Plugin** | `gaea-plugin-demo` 0.3.0, built and signed locally (`scripts/build-plugin.sh`), served by `tools/release-standin.py` through Gaea's real install path. It adds `demo-gradient`, whose `image.generate` offer writes real PNGs. |
| **Script** | [`tools/acceptance-offers.sh`](../../../tools/acceptance-offers.sh): **19 passed, 0 failed** ([acceptance.log](acceptance.log)) |

## What changed in the host

- **Offers run as themselves.** A manifest offer of an MES Image operation is served as that operation (`GaeaEngine.routes`). The offer's `x-` params become MES extensions, sent to the worker as `model_params`. Its `defaults` sit under the request's params. Its `lanes` limit the lanes the scheduler may choose. Its `limits` set the descriptor's limits. Inputs travel as spool paths; text and data inputs are written to `.txt` and `.json` files (GPP-1 §3.3, updated).
- **Outputs come from the spool.** The files the worker lists in `result`, plus any `chunk` the result doesn't repeat, become the job's outputs. Each is moved into the job's output folder and never re-encoded; its width and height are read from the header. A path outside `output_dir`, including through a symlink or `..`, fails the job and the file is left alone (`GaeaEngine.producedOutputs`).
- **The mock stays for models without an offer** (the demo's `demo-matmul` helper), until the image normalizer replaces it (AB-T-0366).
- **The models root is a setting.**
  - `gaea models root [<folder> | default]` reads it, sets it, or goes back to MLXEngine's store.
  - Gaea's **Settings…** window (⌘,) has a folder picker.
  - `--models-root` overrides it for one launch.
  - It is kept in gaea.sqlite as `models.root`.
  - When it changes, idle workers stop at once; a busy worker stops when its run ends. The next worker's `configure` carries the new folder.
  - `gaea status` and the host log name it.

## Acceptance

| Done = | Result | Evidence |
|---|---|---|
| The Base conformance suite still passes with the demo plugin | **Pass** | `mes-conformance`, open mode: 28 passed, 0 failed, 16 skipped. Base 0.1 and Image 0.1 conform ([report](conformance-open/report.md)). |
| A fixture plugin offer returns a PNG, and the MES result image is byte-identical to the spool file | **Pass** | `OfferRoutingTests.theDemoGradientsPNGsReachMESUnchanged` runs demo 0.3.0's signed bundle and hashes its files before and after collection. End to end, `image.generate` on `demo-gradient` (645×480, `count` 2, seed 7, angle 30) returned two 640×480 PNGs with `size_snapped`. Their sha256s equal those from the same request sent straight to the worker with `tools/gpp-run.py` ([direct.json](direct.json); [gradient-0.png](gradient-0.png), [gradient-1.png](gradient-1.png)). Provenance names `demo-gradient` revision 0.3.0, run in 386 ms. |
| The models root survives a restart and reaches `configure.models_root` | **Pass** | Set by `gaea models root`, then Gaea restarted, then a job: the new worker's recorded `configure` line carries the folder. A missing folder is refused. `default` goes back. `--models-root` reads "for this launch". |
| Evidence under Docs/Evidence/AB-T-0364/ | **Done** | This folder. |

## Also checked

- `operations` lists `demo-gradient` as `image.generate`'s default and still lists the mocked `demo-matmul`, with `x-gaea.gradient_angle` and `x-gaea.lane` as extensions ([operations.json](operations.json)).
- `effective` merges the worker's own (`size` 640×480, the angle) with `model_params["x-gaea.worker"]` (plugin, version, lane, operation) ([job-gradient.json](job-gradient.json)).
- The mock path still runs `demo-matmul` on the GPU ([job-mock.json](job-mock.json)).
- Every recorded GPP session passes `tools/validate.py --transcript` (3 of 3; [one of them](session-first.gpp)).
- **Unit tests:** 18 of 18 (`swift test`), 6 new:
  - output collection: values, chunks, no double counting;
  - refusal of paths outside `output_dir`;
  - text and data inputs written as files;
  - descriptor limits;
  - the real demo bundle.
- The first run of the script had one failing check: it looked for `size_snapped` on the result, but MES reports warnings on the job. The check was fixed, and the run recorded here is the second.

## Not covered here

- Demo 0.3.0 is not published yet. This run used a local stand-in for its GitHub release; publishing (notarize, release) follows.
- The Settings window was built and its actions go through `Scheduler.setModelsRoot`, which the CLI checks exercise. It was not driven by hand in this run.
