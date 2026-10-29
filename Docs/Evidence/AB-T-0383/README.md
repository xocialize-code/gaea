# AB-T-0383: an edit on a large input, the same as v0.9.1

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Gaea** | 0.7.0, Release, `dist/Gaea.app` (this change), every G1 plugin from its GitHub release, with flux2-klein 0.2.1 (installed from a local stand-in of its notarized build before publishing; the published zip is the same, sha256 `07a4183d…`) |
| **Old engine** | pixel-agency-image-engine v0.9.1 (fd93d86), Release, `--allow-research` |
| **Input** | DIV2K 0831 at its full 2040×1356 (`mlxengine-image/corpus/sr-bench/DIV2K_valid_HR/0831.png`), seed 7, instruction "make it a snowy winter scene" |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2, one engine at a time |
| **Script** | [`tools/parity-adapters.py`](../../../tools/parity-adapters.py) with `KLEIN_ONLY=1 CONTROL=1`, and `NO_ADAPTERS=1 CONTROL=1 CONTROL_MODEL=qwen-image-edit` |
| **Images** | Off the repo at `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0383/`; their sha256s are in the `adapters.json` files |

## The cause

For an edit that names no size, pixel-agency-image-engine v0.9.1 sends the package none (mlx-image-runtime
`RequestMapping`: "Edits default to the model's choice"), and flux2-klein-swift then draws 1024×1024
(`Klein4BT2IPackage`, `edit.width ?? 1024`); the normalizer brings the result back to the first image's size. Gaea's
Klein plugin sent the first image's size, fitted to 1024² of area: 1248×832 for this photo. At a 1024² input, both
come to 1024×1024, which is why AB-T-0373 and AB-T-0378's 1024² runs matched.

## The fix

- **gaea-plugin-flux2-klein 0.2.1:** an edit without a `size` or `aspect` sends the package none. A size the request
  names is still drawn as asked.
- **Gaea:** an edit that asks no size is sent without one (`GaeaModelHost.run`), so the model chooses here too; the
  host's raise-to-the-smallest-side rule stays for the other operations. This replaces AB-T-0378's interim rule for an
  ic edit made only of slot images, which now runs at the package's 1024² as on v0.9.1.

## Result

| Done = | Result |
|---|---|
| The full-size control and the 7 adapters are byte-identical with v0.9.1 | **Pass, 8 of 8** ([klein-full/compare.md](klein-full/compare.md)). Same prompts, revisions and licences. The control runs in 12.9 s on Gaea and 12.7 s on v0.9.1 (it was 19.3 s against 12.8 s before) |
| The same holds for Qwen-Image-Edit 2511 on a large input | **Pass** ([qwen-edit-full/compare.md](qwen-edit-full/compare.md)): byte-identical, 307 s against 304 s. Its plugin already sent no size |
| Evidence under Docs/Evidence/AB-T-0383 | This folder |

Before the fix, the same Klein run matched 0 of 8 ([../AB-T-0378/klein-full/compare.md](../AB-T-0378/klein-full/compare.md)).
Host tests 32/32. Open-mode conformance with this build and every G1 plugin: 40 passed, 0 failed, 4 skipped, with
BASE-013, BASE-029 and IMAGE-013 passing ([conformance-open/report.md](conformance-open/report.md)).
