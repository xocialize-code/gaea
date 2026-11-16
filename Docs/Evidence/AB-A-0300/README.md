# AB-A-0300: prompt enhancement for Fibo 2.0 through Gaea

2026-11-15, Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3). gaea-plugin-prompt-enhance 0.1.2 and
gaea-plugin-fibo2 0.2.1, through the released Gaea 1.9.0.

mlx-think asked for two things (AB-A-0300): the prompt enhancer on prompt-enhance-kit-swift 0.8.0, whose `fibo2`
profile writes the long JSON captions (VGL) Fibo 2.0 Dev was trained on; and a way for an edit's instruction to be
rewritten, which `fibo2` does from the words alone. The first is released. The second is built on Gaea's side and
waits on two other packages.

## What changed

- **gaea-plugin-prompt-enhance 0.1.2** (`31ceb1f`): prompt-enhance-kit-swift 0.7.0 → 0.8.0, nothing else. Its manifest
  now lists `fibo2` for `fibo-2-dev` on `qwen3.5-9b`: recommended at any length, a prompt that is already JSON goes as
  typed. `scripts/golden.sh` checks its caption and its edit instruction; `prompt-inproc` takes `--task`.
- **GaeaPluginKit 0.16.0** (`234ed30`): a prompt profile's `text_only_tasks`, the tasks it rewrites without seeing
  the job's pictures (GPP-1 §4.4, the manifest schema).
- **Gaea, on main, not released** (`a22a42b`, `3b0cbb9`):
  - `GaeaPromptEnhancer.decision` sends an edit's instruction to the helper only when the profile lists `imageEdit`
    in `text_only_tasks`. It has no effect yet (see "Not done").
  - An Image model's speed class comes from its plugin's offer where the normalizer states none. Fibo 2.0 Dev now
    shows `slow` and Edit Turbo `standard`; before, neither showed one (mlx-image raised it on AB-A-0297).
  - `tools/acceptance-fibo-enhance.sh`.

## Results

| Run | Result | Log |
|---|---|---|
| Gaea unit tests | 117 passed | |
| GaeaPluginKit tests | 43 passed | |
| Plugin `scripts/golden.sh`: every profile greedy, the signed bundle over GPP against `prompt-inproc` | 8 passed, 0 failed | [golden.log](golden.log) |
| Fibo acceptance, the plugin's local build through a stand-in, Gaea 1.9.0 | 13 passed, 0 failed | [acceptance-standin.log](acceptance-standin.log) |
| Fibo acceptance, the plugin's 0.1.2 release from GitHub (notarized), the released Gaea 1.9.0 app | 13 passed, 0 failed | [acceptance-github.log](acceptance-github.log) |
| The enhancer's original acceptance (`tools/acceptance-prompt-enhance.sh`: Klein and Z-Image), 0.1.2 from GitHub, the released Gaea 1.9.0 app | 13 passed, 0 failed | [acceptance-profiles.log](acceptance-profiles.log) |

What `tools/acceptance-fibo-enhance.sh` shows, with Fibo at 8 steps and 512² to keep its runs short:

- **A short prompt is rewritten.** "a fox in the snow" under `auto` becomes one VGL caption of 5,231 characters
  ([caption.json](caption.json)) on `qwen3.5-9b`, first attempt. The job warns `prompt_rewritten`, reports the caption
  in `effective.prompt`, and lists the backbone as a helper with the role `prompt_enhance`.
- **The caption is what ran.** Sent back as the prompt, it is passed through without calling the helper and gives
  the same picture byte for byte.
- **`off`** sends the text as typed; **`on`** rewrites; **`image.enhance_prompt`** returns the caption as data.
- **An edit's instruction goes as typed** (`needs_vision`), as before.
- The local build and the published release gave the same caption and the same picture.

Times, from the recorded sessions:

| Step | Time |
|---|---|
| One caption through Gaea (warm backbone, sampled at 0.2) | 79 to 93 s |
| One caption in `golden.sh` (greedy, 1,321 tokens, cold worker) | 48.8 s |
| Fibo's edit instruction in `golden.sh` (23 tokens) | 2.6 s |
| Fibo 2.0 Dev, 8 steps at 512² | 27 to 29 s |

A caption takes about half of the normalizer's 180 s limit for structured rewrites. Past the limit the prompt goes as
typed with a warning.

## Not done

- **Edit instructions rewritten through Gaea** (AB-T-0496). Two things are in the way:
  - The image normalizer answers `needs_vision` for every edit before it asks any enhancer (pixel-agency-normalizer
    0.4.0, `RunPlan.rewrite`). Asked of mlx-apps: AB-A-0303.
  - The plugin can't state `text_only_tasks` until it is on GaeaPluginKit 0.16.0, which is on mlx-engine-swift
    0.80.0. mlx-qwen-llm-swift 0.6.2 doesn't compile against that engine (two switches over `Quant` lack `.mxfp8` and
    `.nvfp4`), so the plugin stays on 0.73.1. Asked of mlx-think on AB-A-0300. The plugin's 0.2.0 is on a local
    branch, `text-only-fact`.
- **The speed class through a released Gaea.** It was checked on a local Release build of main.
- **Fibo at its own settings.** Nothing here ran 50 steps at 1024², and nothing judged whether a caption makes a
  better picture than the plain prompt: that is mlx-think's gate (AB-R-0901).
- **SenseNova's, MOSS-Image's, Qwen-Image's and Mage-Flow's profiles through Gaea.** `golden.sh` covers their text
  over GPP; only Klein's, Z-Image's and Fibo's ran through Gaea on 0.1.2.
