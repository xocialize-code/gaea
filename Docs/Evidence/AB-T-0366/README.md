# AB-T-0366: Gaea's Image profile on the image normalizer

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Host** | Gaea 0.4.0, Release, `dist/Gaea.app`, on [pixel-agency-normalizer 0.1.0](https://github.com/xocialize/pixel-agency-normalizer) (AB-T-0359) and MESKit 0.5.0 |
| **Plugins** | From their GitHub releases: [qwen-image 0.1.1](https://github.com/xocialize/gaea-plugin-qwen-image/releases/tag/v0.1.1), [z-image 0.1.0](https://github.com/xocialize/gaea-plugin-z-image/releases/tag/v0.1.0), [flux2-klein 0.1.0](https://github.com/xocialize/gaea-plugin-flux2-klein/releases/tag/v0.1.0) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Suite** | MESKit 0.5.0's `mes-conformance engine`, suite 0.1: 31 BASE and 13 IMAGE tests |

## Acceptance

| Done = | Result | Evidence |
|---|---|---|
| `mes-conformance engine` passes every BASE and IMAGE test, open and paired, with the G1 plugins installed | **Pass: Base 0.1 and Image 0.1 conform, open and paired, 0 failed** | Open: **33 passed, 0 failed, 11 skipped** ([report](conformance-open.md), [json](conformance-open.json)). Paired, with `--pair`: **36 passed, 0 failed, 8 skipped** ([report](conformance-paired.md), [json](conformance-paired.json)). The skips are listed below. |
| The mock normalizer is deleted | **Done** | `MockImageEngine`, the mock offers and the `MockEngineCore` dependency are gone from GaeaCore. |
| The report is under this folder, in the format of pixel-agency-image-engine's live reports | **Done** | `mes-conformance` writes that format; both reports are here. |

**Before** (Gaea 0.3.0, the same plugins, open): 25 passed, **7 failed**, 12 skipped
([report](conformance-0.3.0-open-before.md)). Every failure was an `image.edit` on the suite's small fixtures (64×48):
Klein's offer refuses a side under 256 px. The profile also keeps the input's size, which no plugin did on its own.

**The skips:**
- **Operations no installed plugin offers yet:** IMAGE-002 (upscale) and IMAGE-004 (matte) wait for the forge pack,
  AB-T-0369. IMAGE-011 and IMAGE-012 (`enhance_prompt`, `prompt_enhance`) wait for the LLM plugin, AB-T-0370.
- **Adapters:** BASE-013, BASE-029 and IMAGE-013. No offer lists adapters, because Gaea doesn't route them to plugins
  yet.
- **BASE-071:** outputs live 3600 s, and the suite only waits up to 30 s.
- **Open mode only:** BASE-005, BASE-006 and BASE-090 are paired-mode tests, and pass in the paired run.

"Every BASE and IMAGE test" therefore holds for every test the installed plugins can be asked to run. The rest come
with AB-T-0369 and AB-T-0370.

## How it fits together

- **The normalizer is Gaea's Image profile.** `GaeaEngine`'s descriptors, validation, default model and runs are
  pixel-agency-normalizer's `ImageNormalizer`, the host half of pixel-agency-image-engine (Plan §3.3). It validates,
  chooses the model by tier and content, plans the job and applies the profile's rules:
  - sizes snapped to the model's envelope, with the input's size kept;
  - inputs made upright and sRGB, with `color_converted`;
  - black-mask pixels kept exactly, and alpha re-applied;
  - the seed reported.
- **Its models are the plugins' offers.** `GaeaModelHost` makes one `ModelCard` per enabled plugin model, with:
  - its capabilities, from the operations it offers;
  - its licence and envelope, from the offers' limits;
  - its steps, from the offer's `x-…steps` default.

  Each model call the normalizer makes runs as the plugin's offer of that capability's operation (`textToImage` →
  `image.generate`, `imageEdit` → `image.edit`, …). The worker keeps the model-specific mapping. The images go through
  the job's spool as PNGs, and the prompt as a text file.
- **Small images.** Below an offer's smallest side (Klein: 256 px), the host runs the call larger, keeping the aspect,
  and scales the result back to the size the normalizer asked for. The suite's 64×48 edit runs at 352×256.
- **The table is the normalizer's.** OperationTable already names these models and their measured tiers:
  - `image.generate` defaults to Z-Image Turbo;
  - `image.edit`, `image.fill` and `image.extend` default to Klein 4B, with Qwen-Image-Edit at `best`.

  Edit-capable models now also serve fill and extend, which the plugins never offered themselves.
- **Gaea's additions to each descriptor:**
  - each model's licence as its plugin states it (Flash keeps NVIDIA's notice);
  - the image count from the offers (`max_images`);
  - the `x-gaea.lane` extension;
  - the plugins' own `x-` options.

  A plugin's named-only offer stays named-only on every operation that runs through it. Z-Image's image-to-image isn't
  an instruction editor, so it is named-only for edit, fill and extend ([operations.json](operations.json)).
- **Requests reach the right worker.** The request's lane and options reach each model call through a task-local
  `NormalizerScope`, and the worker runs come back onto the result:
  - `x-gaea.worker`, with `calls` when there were several;
  - the plugin's `x-` effective values;
  - its warnings and any `lane_fallback`.

## Regression checks

- **Pixels unchanged.** Z-Image Turbo 1024², seed 42, through the normalizer is **pixel-identical** to AB-T-0365's
  image: 0 of 4,194,304 samples differ. That image was itself byte-identical to in-process z-image-swift. The file's
  bytes differ now, since the normalizer encodes its outputs tagged sRGB and upright (Image §1.3, §1.4)
  ([regression/turbo.json](regression/turbo.json)).
- **Lanes and options get through.** `x-gaea.lane: int8` with `x-zimage.steps: 6` runs lane int8 at 6 steps, and
  1000² comes back 992² with the normalizer's `size_snapped` ([regression/lane.json](regression/lane.json)).
- **`count` 2** is two worker calls, seeds 7 and 8, with two different images
  ([regression/count.json](regression/count.json)).
- **The scheduler.** `tools/acceptance-scheduler.sh` passes 19 of 19 on 0.4.0: eviction, the SIGKILL requeue and lane
  fallback ([regression/acceptance-scheduler.log](regression/acceptance-scheduler.log)). Its demo job is now
  `demo-gradient`, since `demo-matmul` has no offer and only the mock offered it.

## What changed besides

- `tools/acceptance-g0.sh` and `tools/acceptance-offers.sh` say at the top that their `demo-matmul` checks, which ran
  through the mock, fail by design since 0.4.0.
- **The console's Models page** lists each model's roles as the live descriptors offer them.
- **Tests.** Two new ones, for the host's size rule and the capability map; 21 of 21 pass.

## Not covered here

- **The engine's tiers and Residency as the scheduler's policy** (the task's third bullet) needed nothing more:
  - the tiers are the normalizer's OperationTable, used as is;
  - memory belongs to Gaea's scheduler on MLXMemoryPolicy (AB-T-0371), so the host keeps the normalizer's residency
    hooks at their defaults, which hold nothing resident.
- **Prompt enhancement** waits on the LLM plugin (AB-T-0370); the normalizer runs without an enhancer.
- **16-bit and raw-pixel images** don't cross to plugins yet: the host refuses `rawBGRA8` and `rawRGBA16`. Only the
  forge pack's 16-bit upscalers would send them.
- **Adapters** aren't routed to plugins.
