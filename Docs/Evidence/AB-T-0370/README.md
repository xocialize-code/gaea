# AB-T-0370: gaea-plugin-prompt-enhance, the LLM plugin

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Plugin** | [xocialize/gaea-plugin-prompt-enhance v0.1.0](https://github.com/xocialize/gaea-plugin-prompt-enhance/releases/tag/v0.1.0): Developer ID, notarized (Accepted), Gatekeeper "Notarized Developer ID". On GaeaPluginKit 0.3.0, mlx-qwen-llm-swift 0.6.2, prompt-enhance-kit-swift 0.7.0 and mlx-engine-swift 0.73.0; Apache-2.0 |
| **Host** | Gaea 0.5.0, Release, `dist/Gaea.app` |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Scripts** | Over GPP: the plugin repo's `scripts/golden.sh`, **6 of 6 profiles the same text** ([golden/golden.log](golden/golden.log)). Through Gaea, from the GitHub release: [`tools/acceptance-prompt-enhance.sh`](../../../tools/acceptance-prompt-enhance.sh), **13 passed, 0 failed** ([acceptance.log](acceptance.log)) |

## How it fits

- **The plugin** carries prompt-enhance-kit's image-model profiles and Qwen3.5 4B and 9B, at int4, as
  pixel-agency-image-engine runs them. Gaea calls one helper, `x-gaea.prompt.enhance`, and never offers it to clients.
  The helper runs the kit's enhancer, and the backbone's answers come over the worker's own engine. A structured
  profile's second draft, when its compiler rejects the first, is a second engine call in the same job.
- **The profiles stay in the plugin.** Its manifest lists only the facts each profile's decision reads: its models,
  policy and tasks, whether it answers JSON, suggests a size or lays out a canvas, and when a prompt goes as typed. This
  is the new `profiles` field of a helper, GPP-1 §4.4.
- **Gaea decides when to call.** `GaeaPromptEnhancer` is the image normalizer's `PromptEnhancing`. It reads those facts
  from the live plugins, and applies prompt-enhance-kit's own decision to them: the task, a structured prompt, the
  policy, and the detailed-prompt length. Only when a rewrite is due does it run the helper through the scheduler, like
  any job. The backbones are the normalizer's `llm` models, so `image.enhance_prompt` previews on them.

## Acceptance

| Done = | Result | Evidence |
|---|---|---|
| gaea-plugin-check reports ALL PASS on the notarized release | **Pass** | `scripts/release.sh`: ALL PASS with every `.build` hidden (the Klein profile on the 4B, greedy, outcome `enhanced`). The bare-worker control fails on the metallib. Notarization Accepted; `spctl` "Notarized Developer ID". |
| For each profile, greedy decoding gives the same text as in-process | **Pass, 6 of 6** | `golden.sh` runs each profile's rewrite at temperature 0 and seed 42, over GPP on the signed bundle and in-process (`prompt-inproc`: MLXServeEngine, the same backbone, enhancer and sampling), and compares the texts. On the 4B: `flux2-klein`, `qwen-image`, `z-image` and `mage-flow`. On the 9B: `sensenova-u1.5` (Render JSON) and `moss-image` (a layout for a 1024² canvas). |
| The normalizer calls the helper only where a profile asks for enhancement | **Pass** | Through Gaea, counted from the plugin's recorded GPP session; see below. |
| A receipt: cold start and tokens per second | **Filed** | See below. |

### When the helper runs (through Gaea)

| Request | Profile, policy | Outcome | Helper called |
|---|---|---|---|
| Klein 4B, a short prompt, `prompt_enhance: auto` | `flux2-klein`, recommended | `enhanced` | yes |
| Klein 4B, a 70-word prompt, `auto` | `flux2-klein` (60 words or more go as typed) | `passed_through` | no |
| Z-Image Turbo, a short prompt, `auto` | `z-image`, optional | `not_recommended` | no |
| Z-Image Turbo, `prompt_enhance: on` | `z-image` | `enhanced` | yes |
| Klein 4B, `prompt_enhance: off` | | `off` | no |
| `image.enhance_prompt` for Klein 4B | `flux2-klein` | the rewrite as data, `applied` | yes |

The helper ran exactly three times ([acceptance.log](acceptance.log), [sessions](sessions)), and every image job
succeeded. The rewrite is reported in `effective.model_params.prompt_enhancement`
([job-klein-auto.json](job-klein-auto.json)).

With every G1 plugin installed (Qwen-Image, Z-Image, Klein, the forge pack and this one), Gaea's conformance:

| Mode | Passed | Failed | Skipped | Report |
|---|---|---|---|---|
| Open | **37** | 0 | 7 | [conformance-open.md](conformance-open.md) |
| Paired | **40** | 0 | 4 | [conformance-paired.md](conformance-paired.md) |

`enhance_prompt` (IMAGE-011) and `prompt_enhance` (IMAGE-012) now run and pass. What's left skipped:
- adapters (BASE-013, BASE-029, IMAGE-013), which Gaea doesn't route to plugins yet;
- output expiry (BASE-071);
- in the open run, the three paired-mode tests.

### Cold start and tokens per second

From `prompt-inproc`, the same rewrite as the plugin's, greedy ([golden](golden)). mlx-qwen-llm-swift reports no usage
(asked of mlx-think as AB-A-0217). The tokens are therefore counted with the model's own tokenizer, over the whole
engine call, prefill included.

| Profile | Backbone | Load | Rewrite | Cold, from launch | Tokens | Tokens/s |
|---|---|---|---|---|---|---|
| `flux2-klein` | 4B | 0.72 s | 1.20 s | 2.65 s | 178 | 148 |
| `qwen-image` | 4B | 0.72 s | 1.25 s | 2.70 s | 171 | 137 |
| `z-image` | 4B | 0.74 s | 0.78 s | 2.24 s | 95 | 122 |
| `mage-flow` | 4B | 0.73 s | 1.30 s | 2.75 s | 200 | 154 |
| `sensenova-u1.5` | 9B | 0.76 s | 19.76 s | | 1,502 | 76 |
| `moss-image` | 9B | 0.76 s | 8.61 s | | 556 | 65 |

Over GPP, each first rewrite on a cold worker took the same time as in-process (1.21 s against 1.20 s for Klein,
19.83 s against 19.76 s for SenseNova). The worker peaked at 4.65 GB on the 4B (`check-plugin.sh`).

## What changed

- **GaeaPluginKit 0.3.0.**
  - `EngineOperation(op, perform:)` runs itself, with an `EngineSession` on its model's package: as many engine calls
    as it decides to make, with progress relayed.
  - `PluginManifest.Helper.profiles` lists a prompt helper's profile facts.
  - The manifest schema and GPP-1 §4.4 say so.
- **Gaea 0.5.0.**
  - `GaeaPromptEnhancer`.
  - The backbones as `llm` models in `GaeaModelHost`.
  - `PluginOffers.liveHelpers()`.
  - 3 new tests of the decision against the kit's cases; 24 of 24 pass.
- **The normalizer fixes its preview's backbones when it is made**, before any plugin is read. So Gaea always lists
  the two backbones the normalizer and Pixel Agency use, `qwen3.5-4b` and `qwen3.5-9b`, and one is offered only while
  a plugin serves it. A plugin with other backbone ids would show up for rewrites but not for the preview, until Gaea
  learns them.

## Not covered here

- **Edit instructions** aren't rewritten: an edit's rewriter would need to see the image (`needs_vision`), as on
  pixel-agency-image-engine.
- **Decode-only tokens per second** wait on AB-A-0217.
- **The decision is copied.** Gaea's copy of the kit's decision (`GaeaPromptEnhancer.decision`) has to follow the kit.
  The helper applies the kit's own decision again under `auto`. So a divergence could make Gaea skip a prompt the kit
  would rewrite, but never rewrite one the kit would skip.
