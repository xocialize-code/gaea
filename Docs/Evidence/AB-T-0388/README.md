# AB-T-0388: Ming-Image Design as a Gaea plugin

| | |
|---|---|
| **Date** | 2026-10-30 |
| **Plugin** | [gaea-plugin-ming-image 0.1.0](https://github.com/xocialize-code/gaea-plugin-ming-image/releases/tag/v0.1.0) (6f93528), on ming-image-swift 0.3.1 (AB-A-0224, footprints AB-R-0658), GaeaPluginKit 0.5.0, mlx-engine-swift 0.73.0, mlx-swift 0.32.3. Developer ID with the hardened runtime, notarized (submission 41ae7595-…) and stapled; Gatekeeper `accepted, source=Notarized Developer ID` |
| **Gaea** | 0.7.1 (`dist/Gaea.app`) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | the full-size images, job records and measurement sessions are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0388` |

## What it offers

One model, `ming-image`, on `image.generate`: 12 steps without CFG, the reference's Design profile. Lanes int8 (the
default, as in mlx-image-runtime's catalog), bf16 and int4. A request is drawn in the 1024² bucket, or the 2048² one
when its area needs it, at the bucket's nearest aspect; the worker reports the size drawn, and Gaea returns the size
asked. Up to 2048² in area. Not a default, so Gaea's routes don't change ([manifest.json](manifest.json)).

## Result

| Done = | Result |
|---|---|
| The notarized release passes gaea-plugin-check | **Pass.** `scripts/release.sh`: signature, launch under `Process.launchRequirement`, hello, int8 1024² in 6 steps (17.8 s, peak 28.0 GB against 7.9 + 24.4 declared), shutdown; the transcript validates; the bare worker outside the bundle finds no metallib ([sessions/check-session.gpp](sessions/check-session.gpp)) |
| Installed by repo URL, generate matches an in-process reference | **Pass, 17 of 17** ([acceptance.log](acceptance.log), `tools/acceptance-ming-image.sh`, `REPO_FROM=github`): int8 1024², int4 and bf16 each match `ming-inproc` pixel for pixel; a warm run repeats the bytes. 768×512 is drawn at 1248×832 (the worker's report, and `ming-inproc`'s draw) and returned at 768×512; count 2 gives two seeds; a negative prompt is reported ignored; a named lane runs that lane; an unnamed request still reaches Z-Image Turbo |
| Every lane runs, and its footprint is measured in the worker | **Pass** ([footprints.txt](footprints.txt)): the worker's phys_footprint, from gaea-plugin-check on the signed bundle with the build folder hidden. Every lane is under its declaration at 1024² and 2048²; the peak is the conditioning stage, the same at both sizes |
| The Image conformance suite still passes | **Pass: 40 passed, 0 failed, 4 skipped**, with every G1 plugin, Boogu and Ming-Image installed from GitHub ([conformance-open](conformance-open/report.md), [plugins](plugins-list.txt)) |
| Over GPP, byte for byte | **Pass, 4 of 4** (`scripts/golden.sh`, [golden.log](golden.log)): int8 at 1024², 1280×720 and 768×512 (drawn at 1248×832), and int4 at 1024², byte-identical on the signed bundle and through `ming-inproc` |

| Lane | Floor after prepare | Peak, 1024² | Peak, 2048² | Declared (resident + activation) | Time at 1024² / 2048² |
|---|---|---|---|---|---|
| int8 | 7.5 GB | 28.0 GB | 28.0 GB | 7.9 + 24.4 = 32.3 GB | 19.3 s / 90.6 s |
| bf16 | 13.2 GB | 49.8 GB | 49.8 GB | 13.5 + 44.1 = 57.6 GB | 17.0 s / 86.7 s |
| int4 | 7.5 GB | 19.4 GB | 20.0 GB | 7.9 + 14.6 = 22.5 GB | 18.6 s / 89.9 s |

![int8 through Gaea and in-process; 768×512 ×2; int4; bf16](contact-sheet.jpg)

## Found on the way

- **The worker trapped on its first job: a missing SwiftPM resource bundle.** Ming-Image's tokenizer config names no
  tokenizer class, so swift-transformers reads its bundled fallback configs through `Bundle.module`, and the template's
  build-plugin.sh copied only MLX's metallib bundle. The plugin now carries every resource bundle. The other plugins
  and the demo template don't yet (AB-L-0318).
- **Gaea returns the size asked, not the size drawn.** The worker draws in the model's bucket and reports it, with
  `size_snapped`; Gaea resizes the result to the request's size and drops the worker's warning. A pixel comparison of
  a snapped size therefore isn't possible through Gaea, and golden.sh covers it over GPP instead.
- **swift-transformers prints its tokenizer fallback warning on stdout**, ahead of `ming-inproc`'s JSON line.

## Not covered

- **Transparent backgrounds and layer decomposition** (the package's `background: transparent`, and the Design-Layer
  checkpoint): no MES parameter or operation yet. It needs an ask to media-engine-spec when wanted.
- **Paired-mode conformance.** Open mode only, as for AB-T-0387.
