# AB-T-0389: Ming-Image transparent backgrounds through current MES

| | |
|---|---|
| **Date** | 2026-10-30 |
| **Plugin** | [gaea-plugin-ming-image 0.2.0](https://github.com/xocialize-code/gaea-plugin-ming-image/releases/tag/v0.2.0) (fd1dda7), on ming-image-swift 0.3.1, GaeaPluginKit 0.5.0, mlx-engine-swift 0.73.0. Developer ID with the hardened runtime, notarized (submission 39d19a8b-…) and stapled; Gatekeeper `accepted` |
| **Gaea** | 0.7.1 (`dist/Gaea.app`), unchanged |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | the images, job records and golden sessions are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0389` |

## What changed

Ming-Image's native alpha reaches MES clients with no spec change. An offer extension (Base §6.2) on `image.generate`:

```json
"extensions": {"x-ming.background": "transparent"}
```

sends `T2IRequest.background = .transparent` to ming-image-swift, which already ran the measured recipe (AB-R-0341): its
English phrase, a retry at the same seed with a Chinese phrase when the first image is opaque, and an alpha floor. The
result is a straight-alpha PNG, as the Image profile's §1.5 asks.

The worker now runs `image.generate`'s calls itself (GaeaPluginKit's `perform:`) so it can look at each image. One that is
still opaque by the package's gate metric (more than 10% of pixels with α ≤ 12) carries the warning `background_opaque`.
Base §10.1 lets an engine use a code no registry defines, and Gaea passes worker warnings through to the job. The option
appears in `effective`, and an unknown value is refused.

Gaea needed nothing. Its normalizer re-encodes from premultiplied RGBA8, so alpha survives exactly and RGB under partial
alpha is requantized, invisibly. The comparisons below are made in premultiplied space for that reason.

## Result

| Done = | Result |
|---|---|
| Notarized and released | **Pass.** `scripts/release.sh`: check-plugin ALL PASS, notarized, stapled, [v0.2.0](https://github.com/xocialize-code/gaea-plugin-ming-image/releases/tag/v0.2.0) |
| Over GPP, byte for byte, and the warning matches the in-process alpha | **Pass, 8 of 8** ([golden.log](golden.log)): the four opaque cases unchanged from 0.1.0 (same sha256s), and transparent at 1024², 1280×720, a glass bottle and a full-bleed scene, each byte-identical to `ming-inproc --background transparent`. The scene is opaque in-process too, and only it warns |
| Through Gaea, installed from GitHub | **Pass, 24 of 24** ([acceptance.log](acceptance.log), `tools/acceptance-ming-image.sh`, `REPO_FROM=github`). AB-T-0388's 17 checks still pass, plus seven for this task: the transparent 1024² job has `x-ming.background` in `effective`, and its PNG has alpha and matches the in-process image pixel for pixel. A 768×512 drawn at 1248×832 and resized by Gaea keeps its alpha. The full-bleed scene warns `background_opaque` exactly as its in-process image lacks alpha, and matches it pixel for pixel. `checkerboard` is refused |
| The Image conformance suite still passes | **Pass: 40 passed, 0 failed, 4 skipped**, Base 0.1 and Image 0.1 conform, with every G1 plugin, Boogu and Ming-Image 0.2.0 installed from GitHub ([conformance-open](conformance-open/report.md), [plugins](plugins-list.txt)) |

![Over a checkerboard: the sticker at 1024² and at 768×512 (resized by Gaea), the glass bottle (golden), and the full-bleed scene, which stays opaque and warns](contact-sheet.jpg)

## Found on the way

- **It doesn't always work, so the warning matters.** The same sticker prompt at 768×512 came back transparent for seeds 8,
  11 and 12 and opaque for 7 and 9, even after the retry. A scene that fills the frame is opaque every time. The glass
  bottle came out transparent at seed 7, against the package's note that glass is unreliable.
- **A retry costs a second denoise.** An image that needs the second phrase takes about 48 s at 1024² int8, against about
  25 s.
- **Gaea forwards worker warnings** except `size_snapped`, which the normalizer replaces with its own sizes
  (`GaeaEngine.attach`).

## Not covered

- **Layer decomposition** (the Design-Layer checkpoint, `layerDecompose`): no MES operation returns an image's layers. It
  needs an Image-profile operation.
- **Other lanes with transparency.** Only int8 was checked. The package's declared footprints include a transparent run
  at 1024², and the lanes share the code path.
