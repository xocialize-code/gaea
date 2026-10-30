# AB-T-0390: Ming-Image Design-Layer through Gaea (image.decompose)

| | |
|---|---|
| **Date** | 2026-10-30 |
| **Plugin** | [gaea-plugin-ming-image 0.3.0](https://github.com/xocialize-code/gaea-plugin-ming-image/releases/tag/v0.3.0) (abeec2e), adding `ming-image-layer` over ming-image-swift 0.3.1's `MingImageLayerPackage`, on GaeaPluginKit 0.6.0. Notarized (submission 71265fc3-…) and stapled |
| **Gaea** | 0.8.0: MESKit 0.6.0, pixel-agency-normalizer 0.2.0, kit 0.6.0 |
| **Spec** | MES Image §3.2, from RFC 0004 (accepted with amendments, media-engine-spec 8a5c871, AB-A-0228) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every layer, the job records and the golden outputs are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0390` |

## What it took

| Piece | Where | What |
|---|---|---|
| The operation | media-engine-spec v0.6.0 (mlx-apps, AB-A-0228) | `image.decompose`: layers front-most first, straight-alpha RGBA at the input's size, `layer_count`, opt-in `composite`, IMAGE-014 to 016 |
| The route | pixel-agency-normalizer v0.2.0 (mlx-apps, AB-A-0229) | `ModelCapability.layerDecompose`, `ModelResult.layers`, §3.2's refusals, sizes and alpha rule. Desktop and pixel-agency-image-engine moved to it (7175347, 7f7c751) once media-bridge 0.40.1 fixed their Xcode 27.2 build (AB-A-0230) |
| The manifest | GaeaPluginKit 0.6.0, GPP-1 §4.3, `schemas/v1/manifest.schema.json` | `limits.max_layer_count` and an offer's `supports` (`composite`), named after RFC 0004's A5 |
| The model | gaea-plugin-ming-image 0.3.0 | `ming-image-layer` on `image.decompose`, int8 (default), bf16 and int4 lanes, at most 12 layers, `quality: draft` at the 512 bucket, the composite on request |
| The host | `GaeaModelHost` | maps `layerDecompose` onto the offer: sends no size, the count as `layer_count`, asks for the composite when the offer makes one, and returns every layer |

## Result

| Done = | Result |
|---|---|
| Over GPP, byte for byte | **Pass, 13 of 13** ([golden.log](golden.log)): the 8 Design cases as before, and 5 decompose cases where every layer and the composite match `ming-inproc --decompose` file by file. The cases cover 4 layers at 1024 and at 512, int4 at 512, a 3-layer plan, and the 1280×720 poster |
| Through Gaea, installed from GitHub | **Pass, 16 of 16** ([acceptance.log](acceptance.log), `tools/acceptance-ming-layer.sh`, `REPO_FROM=github`): see the list below |
| Conformance | **Conforms with the suite's job timeout raised to 900 s: 43 passed, 0 failed, 4 skipped** ([report](conformance-900s/report.md)). IMAGE-014 and 015 pass, and IMAGE-016 reports the 4 layers recompose to the input within 2.29/255 per channel (the composite, 2.49/255). With v0.6.0's suite as shipped it fails 4 on time alone ([report](conformance/report.md)), asked of mlx-apps as AB-A-0231 |

What the 16 acceptance checks cover:
- **The offer:** `image.decompose` lists `ming-image-layer`, with `layer_count` up to 12 and `composite` among the outputs.
- **The jazz poster** into 4 layers plus the composite, all at 1024². All five files match the in-process run pixel for pixel.
- **The 1280×720 poster** gives four layers at 1280×720.
- **A 3-layer plan** returns 3 layers.
- **`draft`** runs the 512 bucket and still returns 1024².
- **Refusals:**
  - `layer_count` 13 is 422 `out_of_limits`;
  - a plan that contradicts `layer_count` is 400;
  - `outputs` without `layers` is 400.
- **A transparent sticker** stays clear in every layer, with `alpha_reapplied`.

| Job (int8) | Worker drew | Worker run |
|---|---|---|
| 4 layers, 1024² poster | 1024² | 336 s |
| 4 layers, 1280×720 poster | 1280×720 | 280 s |
| 3-layer plan, 1024² poster | 1024² | 265 s |
| 4 layers, `draft` | 512² | 59 s |
| 2 layers, `draft`, transparent sticker | 512² | 39 s |

With a plan, front-most first, the model splits the poster as asked: the headline, the saxophone, and the background.

![The poster, then the plan's three layers over a checkerboard: headline, saxophone, background](plan-sheet.jpg)

Without a plan it chooses for itself, and its split is rough. The layers below follow the poster and the composite: the
saxophone appears in two layers, and one layer is the whole background.

![The poster, the composite, then four unplanned layers](unplanned-sheet.jpg)

## Found on the way

- **Gaea's normalizer re-encodes every input**, and only a PNG it wrote comes back byte for byte. The worker's own PNG
  of the poster changed in 922 samples by 1. That's invisible, but it changes a decomposition entirely, so the first
  parity checks failed with layer differences up to 217. The acceptance now decomposes a poster Gaea wrote
  (`fixtures/poster-gaea-1024.png`), which matches exactly.
- **Decomposition is slow:** about 6 minutes for 4 layers at 1024 and 1 minute at 512, which agrees with the port's
  131–137 s at 512. The conformance suite waits 180 s per job (AB-A-0231).
- **Without a plan the layers are poor.** A plan matters more here than a prompt does for generation. A prompt-enhance
  profile that writes the plan from the image would fit Image §1.9 (the reference uses a vision-language model for it),
  and the normalizer leaves `prompt_enhance` undeclared on decompose until one exists.

## Not covered

- **bf16 decompose** wasn't run (int8 and int4 were). The lanes share the code path, and the package's footprints
  declare bf16.
- **A plan written by a model** (prompt enhancement for decompose): no layer planner exists yet.
