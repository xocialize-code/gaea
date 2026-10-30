# AB-T-0387: Boogu Image as a Gaea plugin

| | |
|---|---|
| **Date** | 2026-10-30 |
| **Plugin** | [gaea-plugin-boogu 0.1.0](https://github.com/xocialize-code/gaea-plugin-boogu/releases/tag/v0.1.0) (8090e38), on boogu-image-swift 0.5.0 (AB-A-0224, footprints AB-R-0663), GaeaPluginKit 0.5.0, mlx-engine-swift 0.73.0, mlx-swift 0.32.3. Developer ID with the hardened runtime, notarized (submission 6514e4ff-…) and stapled; Gatekeeper `accepted, source=Notarized Developer ID` |
| **Gaea** | 0.7.1 (`dist/Gaea.app`, rebuilt from 994c26d) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | the full-size images and job records are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0387` |

## What it offers

| Model | MES operation | Lanes | Defaults |
|---|---|---|---|
| `boogu` | `image.generate` | bf16 (default), int8, int4 | 30 steps, CFG 3.5, negative prompts |
| `boogu-turbo` | `image.generate` | bf16 (default), int8 | 4 steps, no CFG |
| `boogu-edit` | `image.edit`, one image | bf16 (default), int8, int4 | 50 steps, true CFG 4, drawn at 768² unless a size is asked |

Footprints are the package's: resident 21.0 / 12.9 / 8.3 GB (bf16 / int8 / int4), activation 16.6 GB plus 3000 B a
pixel, 19.8 GB at 1024². Generation goes up to 1536² in area and editing up to 1024², 512–2048 a side. No offer is a
default: the normalizer's tier table doesn't name Boogu, so Gaea's routes don't change ([manifest.json](manifest.json)).

## Result

| Done = | Result |
|---|---|
| The notarized release passes gaea-plugin-check | **Pass.** `scripts/release.sh`: signature against the team's Developer ID requirement, launch under `Process.launchRequirement`, hello against the manifest, Boogu int4 512² in 8 steps (17.4 s, process peak 24.8 GB against 8.3 + 16.6 declared), shutdown; the transcript validates; the bare worker outside the bundle finds no metallib ([sessions/check-session.gpp](sessions/check-session.gpp)) |
| Installed by repo URL, generate and edit match an in-process reference | **Pass, 20 of 20** ([acceptance.log](acceptance.log), `tools/acceptance-boogu.sh`, `REPO_FROM=github`): Boogu bf16 1024² (30 steps, CFG, a negative prompt), Boogu Turbo int8, an edit at the package's 768², and the int4 lane each match `boogu-inproc` pixel for pixel. A warm run repeats the bytes |
| Every lane runs; sizes outside the envelope are handled | **Pass.** A named lane runs that lane (int4, int8). 1000² snaps to 992²; an edit asking 1536² is drawn at 1024² with `size_snapped`; 400² is drawn at 512² and returned at 400²; two images on an edit are refused `out_of_limits` |
| Routing doesn't change | **Pass.** With Z-Image beside it, a generate naming no model reaches Z-Image Turbo. Neither Boogu offer is a default |
| The Image conformance suite still passes | **Pass: 40 passed, 0 failed, 4 skipped**, as at the G1 exit, with every G1 plugin plus Boogu installed from GitHub ([conformance-open](conformance-open/report.md), [plugins](plugins-list.txt), `tools/conformance-with.sh`). The skips are the paired-mode tests and BASE-071 |
| Over GPP, byte for byte | **Pass, 3 of 3** (`scripts/golden.sh`, [golden.log](golden.log)): Boogu bf16 768², Turbo int8 1024² and an edit on bf16, on the signed bundle and through `boogu-inproc`, byte-identical |

![Boogu through Gaea, in-process, int4; Turbo ×2; the edit](contact-sheet.jpg)

Times through Gaea at 1024² bf16: 130.5 s cold and 128.7 s warm for 30 steps. Turbo int8: two 768² images in 22.8 s
with the launch. The edit: 362 s at 768² bf16 for 50 steps, the slowest path.

## Found on the way

- **Gaea re-encodes Boogu's PNGs.** The package writes RGBX PNGs; the normalizer re-encodes outputs, so the bytes
  differ from the worker's while every pixel is the same. Over GPP, without the normalizer, they are byte-identical.
  The acceptance compares pixels, as golden.sh does when bytes differ.
- **An unnamed edit picks the first edit offer when FLUX.2 Klein isn't installed.** With only Z-Image and Boogu,
  `image.edit`'s default is `boogu-edit`, because the normalizer's first choices (Klein 4B, Qwen-Image-Edit) are
  absent and the host takes the first route. On a server with the G1 plugins, Klein answers.
- **Model step options go in `extensions`,** not `params` (as `x-qwen.steps` already does); the first draft of the
  acceptance put them in params and those jobs were refused at submit.

## Not covered

- **Boogu Turbo bf16 and Edit int8 lanes through Gaea.** The golden check and acceptance ran bf16 Base and Edit,
  int8 Turbo and int4 Base; the other lanes load the same package with another published tier.
- **Paired mode conformance.** Open mode only; the paired run at the G1 exit used the same host code.
