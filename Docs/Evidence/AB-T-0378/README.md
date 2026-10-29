# AB-T-0378: adapters (LoRAs) on Gaea

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Gaea** | 0.7.0, Release, `dist/Gaea.app` (commits bfbc89d, 235d0a6, a4a990b, f928b03, and this one's host fixes), with every G1 plugin from its GitHub release: qwen-image 0.2.0 and flux2-klein 0.2.0 (AB-T-0381, adapters), z-image 0.1.0, forge 0.2.0, prompt-enhance 0.1.0, mage-vl 0.1.0 |
| **Kit** | GaeaPluginKit 0.5.0 (48b6966) in both adapter plugins |
| **Old engine** | pixel-agency-image-engine v0.9.1 (fd93d86), Release, `--allow-research` (its 27 Qwen adapters are `candidate`), its own scratch state |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2. One engine on the machine at a time. Adapter files in MLXEngine's store (`<models root>/adapters/<sha256>/`), shared by both engines |
| **Scripts** | [`tools/adapters-e2e.py`](../../../tools/adapters-e2e.py) (offer, run, refusals), [`tools/parity-adapters.py`](../../../tools/parity-adapters.py) (every offered adapter once, seeded, and `--compare`), [`tools/contact-sheet.swift`](../../../tools/contact-sheet.swift) |
| **Images** | The full-size PNGs (316 MB) are kept off the repo at `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0378/`; every output's sha256 is in the `adapters.json` files here |

## Result

| Done = | Result |
|---|---|
| A LoRA added by its Hugging Face URL appears in its base model's MES offer: id, strength range, licence and notes | **Pass.** `gaea adapters add https://huggingface.co/furaidosu/pchan-concept-qwen-image-lora --model qwen-image-flash --file pchan-concept-qwen-image.safetensors` pinned 4c3ae447…, read diffusers-peft from the file's header and CreativeML-OpenRAIL-M from the card, and Flash's `image.generate` offer lists it with strength 0–2, that licence, its terms link and the notice ([e2e/e2e.json](e2e/e2e.json)) |
| A request naming it runs on the base model's plugin, and provenance.adapters lists it with licence, revision and strength | **Pass.** Succeeded in 31.5 s, the file's download included; `provenance.adapters` has its id, title, licence, revision 4c3ae447… and strength 0.8 |
| Unknown adapters, out-of-range strengths and policy failures are refused at submit | **Pass.** 422 `unsupported_parameter` for an unknown id, 422 `out_of_limits` for strength 3.5, and 422 for `qwen-image:martha`, opt-in and switched off |
| v0.9.1's adapters give byte-identical seeded output through Gaea and through v0.9.1 | **Pass for all 34.** The 27 Qwen-Image Flash adapters at 1024² and the 7 FLUX.2 Klein 4B edit adapters (two of them ic) on a 1024² photo, with a no-adapter control, are byte-identical, with the same prompt, revision and licence ([compare.md](compare.md), [klein-1024/compare.md](klein-1024/compare.md)). On a 2040×1356 photo Klein differs, **the control too**: not adapters, filed as AB-T-0383 (below) |
| Conformance runs BASE-013, BASE-029 and IMAGE-013 and passes them, open and paired, with every G1 plugin | **Pass.** Open 40 passed, 0 failed, 4 skipped; paired 43, 0, 1 (AB-T-0377: 37 and 40). All three run and pass in both ([conformance-open](conformance-open/report.md), [conformance-paired](conformance-paired/report.md)) |
| Evidence and a receipt | This folder; the receipt is filed with `--package gaea` |

## What was built

- **The contract** (GPP-1 §3.3, §4.3, §4.8; schemas; `tools/validate.py`): an offer's `adapter_support` says which adapters its model takes; `adapters_meta` gives each shipped adapter's format and pinned source; `run.adapters` carries the request's id and strength with the kind, format and source Gaea adds, and an ic adapter's slot images. The worker keeps no catalog. GaeaPluginKit 0.4.0 has the types; 0.5.0 (AB-T-0381) applies them through MLXServeEngine's typed adapter API.
- **Registration by Hugging Face URL** (`HuggingFaceAdapter`): pins the commit, takes the file's sha256 and size from the hub's LFS record, the licence and trigger from the card, and the format from the safetensors header (a ranged read). Kept in gaea.sqlite (migration v2); unknown, research and gated licences are opt-in (`adapter:<id>` in the enabled set). The live test gives v0.9.1's exact pins for `peter-chan-s-concept-art`.
- **Offers and runs** (`PluginOffers.adapters`, `GaeaModelHost`): shipped and registered adapters on the normalizer's cards, `adapterSupport` and `adapterRevisions` on routes; both run paths send what the worker fetches.
- **Operator**: `gaea adapters list | add | enable | disable | remove`, and Settings › Adapters in the app.

## Parity

| Set | Adapters | Same bytes | Same prompt | Median run, Gaea / v0.9.1 (ms) |
|---|---|---|---|---|
| Qwen-Image Flash int8, `image.generate` 1024², seed 7 | 27 (23 from xocialize/qwen-image-flash-loras, 4 upstream; diffusers-peft and kohya) | 27 | 27 | 12042 / 12021 (1.00) |
| FLUX.2 Klein 4B bf16, `image.edit` on a 1024² crop of DIV2K 0831, seed 7 | 7 (bfl-fused and diffusers-peft; refcontrol-pose and tryon are ic) + a no-adapter control | 8 | 8 | 11971 / 11960 (1.00) |
| The same Klein edits on the full 2040×1356 photo | 7 + control | **0** | 8 | 19.3 s / 12.8 s for the control |

[qwen-sheet.jpg](qwen-sheet.jpg) and [klein-sheet.jpg](klein-sheet.jpg) show Gaea's outputs. Both engines rewrite the short
prompt with Qwen3.5 4B (Image §1.9) and then add the adapter's trigger, so most style adapters show only lightly over the
long photographic rewrite; it is the same in both.

### What went wrong on the way

- **The first run matched 0 of 34** ([gaea-no-enhancer/](gaea-no-enhancer/adapters.json)). The scratch Gaea had only the
  demo, Qwen and Klein plugins, so it had no prompt enhancer: v0.9.1 rewrote the prompt and Gaea didn't. With every G1
  plugin installed, the prompts and the Qwen bytes matched. `parity-adapters.py` now records `effective.prompt`.
- **Klein on a large input differs without adapters.** At 1024² the 7 adapters and the control are byte-identical; on
  the 2040×1356 original all 8 differ with identical prompts, and Gaea's control takes 19.3 s against 12.8 s. Gaea
  likely runs Klein at the input's full size where v0.9.1 lets the package choose. AB-T-0373 used a 1024² input, so it
  didn't see this. Filed as **AB-T-0383**, which blocks the G1 exit (AB-T-0375).
- **IMAGE-013 failed twice before it passed**, both in the host: an ic edit whose images all fill the adapter's slots
  sent `images: []` (now left out), and then ran at its tiny slot image's size (now sized from the first slot image, scaled
  to the offer's smallest side like any small edit).

## The plugin side (AB-T-0381)

[plugins/](plugins): the golden runs over GPP against in-process MLXServeEngine, byte-identical (Flash with two stacked
adapters, AB-R-0651; a Klein edit with an ic and a plain adapter, AB-R-0652), the plugin checks and both published
manifests. Both plugins were released locally with the `mlx-notary` profile: CI builds no metallib (AB-T-0382).

## Notes

- **Operator-registered adapters are plain only.** GPP carries no ic slots or footprint, and the engine refuses an ic
  adapter without one, so `gaea adapters add` registers plain adapters. ic adapters come from plugin catalogs.
- **Klein's Apache adapters read as `allowed`**: a permissive SPDX id with a notice (the author's NOTICE) is `allowed`,
  another `yes` is `conditional`, as v0.9.1's registries say.
- **A shipped adapter's kind, format and source must match the plugin's pin**, or the worker refuses the run.
