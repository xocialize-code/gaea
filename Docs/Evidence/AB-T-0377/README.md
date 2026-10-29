# AB-T-0377: G1 coverage, what pixel-agency-image-engine v0.9.1 serves and Gaea didn't

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Gaea** | 0.6.0, Release, `dist/Gaea.app`, Developer ID |
| **Plugins** | [gaea-plugin-forge v0.2.0](https://github.com/xocialize/gaea-plugin-forge/releases/tag/v0.2.0) and [gaea-plugin-mage-vl v0.1.0](https://github.com/xocialize/gaea-plugin-mage-vl/releases/tag/v0.1.0), both notarized (Accepted, Gatekeeper "Notarized Developer ID"), on [GaeaPluginKit 0.3.1](https://github.com/xocialize/gaea-plugin-kit/releases/tag/v0.3.1). The other G1 plugins as in AB-T-0373: z-image 0.1.0, flux2-klein 0.1.0, qwen-image 0.1.1, prompt-enhance 0.1.0 |
| **Old engine** | pixel-agency-image-engine v0.9.1 (fd93d86), Release, the AB-T-0373 worktree build |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2. Weights in MLXEngine's store, already on disk |
| **Gaea home** | A copy of AB-T-0373's (`/tmp/g371r/main` → `/tmp/g377/main`, bundle paths repointed), so that one stays as it was. forge updated to 0.2.0 and mage-vl added there by repo URL |
| **Scripts** | [`tools/acceptance-coverage.sh`](../../../tools/acceptance-coverage.sh), [`tools/coverage-routing.py`](../../../tools/coverage-routing.py); AB-T-0373's [`tools/parity-run.sh`](../../../tools/parity-run.sh) and [`tools/parity-compare.swift`](../../../tools/parity-compare.swift); the plugins' own `scripts/golden.sh` |

## Result

| Done = | Result | Evidence |
|---|---|---|
| Each new model's notarized release passes gaea-plugin-check, and its output over GPP is byte-identical to in-process (text for describe, the value for score) | **Pass.** forge 0.2.0: **25 of 25** (23 images byte-identical, 2 scores the same value), on the released bundle. mage-vl 0.1.0: **6 of 6** the same text. Both `check-plugin.sh` ALL PASS with every `.build` hidden | [forge-golden/golden.log](forge-golden/golden.log), [mage-vl-golden/golden.log](mage-vl-golden/golden.log) |
| Through Gaea, each tier routes relight, colorize, describe, score, restore and upscale to the model v0.9.1 picks | **Pass, 43 of 43** jobs on the same model, and **43 of 43** the same output | [coverage-compare.md](coverage-compare.md) |
| `parity-run.sh` rerun with singles, upscale, restore and generate (the judge): seeded outputs match, warm medians within 10 % or a named cause | **Pass, with named causes.** All **278 of 278** paired outputs byte-identical: 287 pairs across singles, upscale ×4 and ×2, restore, the 45 seeded generations, and the judge's 40 scores and 40 descriptions. Warm medians 0.72 to 1.08, except Nacre ×4 1.15, Nacre ×2 1.16 and DRUNet 1.22: Gaea's workers run with MLX's wired limit off (below, AB-T-0380) | [parity/compare.md](parity/compare.md), [parity/pairs.json](parity/pairs.json) |
| Conformance with every G1 plugin passes as many tests as AB-T-0370's (37 open, 40 paired) or more | **Pass: 37 open, 40 paired**, 0 failed, the same as AB-T-0370 | [conformance-open/report.md](conformance-open/report.md), [conformance-paired/report.md](conformance-paired/report.md) |
| Desktop's auto-describe and score run against Gaea | **Pass.** Desktop's own `AutoDescriber`, pointed at Gaea, described 3 of 3 imported photos. Its face recovery scored each face crop through Gaea's `image.score`. `desktop-snapshot agency-live` generated, exported and described on Gaea | [desktop/](desktop) |
| A receipt, `--package gaea` | **AB-R-0649**, Gaea 0.6.0 | |

The acceptance through Gaea, from the GitHub releases: **11 of 11** ([acceptance/acceptance.log](acceptance/acceptance.log)).

## What was added

| | Model (id) | Plugin | Notes |
|---|---|---|---|
| `image.relight` | HVI-CIDNet (`cidnet-relight`) | forge 0.2.0 | ForgeCore's registration; `strength` passes through |
| `image.colorize` | DDColor (`ddcolor-colorize`) | forge 0.2.0 | |
| `image.score` | SigLIP2 IQA (`siglip2-quality`) | forge 0.2.0 | 32 patches, ForgeCore's `FORGE_IQA_PATCHES` default |
| `image.describe` | Mage-VL 4B int8 (`mage-vl`) | mage-vl 0.1.0 | v0.9.1's configuration; the normalizer's question arrives as the `question` text input |
| `image.restore` | DRUNet (`drunet-denoise`) | forge 0.2.0 | By name, as on v0.9.1 |
| restore's `scratches` | BOPBTL (`bopbtl-defects`) | forge 0.2.0 | A helper, `x-gaea.image.defects`, which Gaea calls before LaMa inpaints the defects. Not an MES operation |
| `image.upscale` | Anime4K VL (`anime4k-upscale`), VOSR2 (`vosr2-upscale`), Nacre (`nacre-upscale`) | forge 0.2.0 | By name. VOSR2 and Nacre run behind ForgeCore's text-legibility guard, as v0.9.1's `EngineImageEnhancer` runs them |

SeedVR2 stays in G3 (VID-4).

### Gaea 0.6.0

- **describe and score answer with data.** `GaeaModelHost.run` returns describe's reply as `.text`, and score's value
  with its subscores as `.score`. An upscale behind a guard comes back as `.upscaled(image, model:)`, naming what made it.
- **The defect helper.** Restore's scratches route `defectDetect` to the plugin helper `x-gaea.image.defects`.
- **The licence link.** A model's source repo, for `terms_url` and the console, is now its default lane's
  `weightSources` entry with role `checkpoint`, falling back to the package's provenance. `qwen3.5-4b` now links to
  `mlx-community/Qwen3.5-4B-MLX-4bit`, not the 0.8B (acceptance check 11). Unit test
  `theSourceRepoIsTheDefaultLanesCheckpoint`; `swift test`: 25 tests in 7 suites pass.

### GaeaPluginKit 0.3.1

`EngineSession.run(_:model:)`: a self-running operation can call another engine model of its plugin, at its default
lane. Nacre's guard needs it: when the guard protects words, a Nacre job also runs NERVE and composites its pixels
under the words. Golden's `nacre-sign` exercises that route ("Nacre + NERVE (protected words)"), byte-identical to
ForgeCore in-process and to v0.9.1.

### The guarded upscalers

`guardedUpscale` in the forge pack does what `EngineImageEnhancer.upscaleReporting` does for a generative stills tier:
the same image hops (PNG → CGImage → 8-bit raw → CGImage), the guard's verdict with
`EngineTextGuardedUpscaler.measuredPolicy(for:)` (word protection on for Nacre, nothing for VOSR2), then the generative
tier, NERVE, or both composited with `TextLegibilityGuard.composite`. It reports `upscale_model` with
`EngineImageEnhancer`'s names, which Gaea records as `effective.model_params.ran`, as v0.9.1 does. The worker links
ForgeCore for this and for Anime4K VL's package, which lives in ForgeCore, and registers only the pack's models.

## Found on the way: BOPBTL hangs under the hardened runtime

Over GPP, BOPBTL's run never ended. In-process it took 0.9 s.

- **The cause.** BOPBTL's package pins a CPU stream. On a CPU stream, MLX JIT-compiles the fused kernels of compiled
  functions into a dylib and `dlopen`s it. Library validation, part of the hardened runtime, refuses that unsigned
  dylib. The CPU stream then waits forever on the GPU event (sampled: `Scheduler::wait_event`), with no crash and no
  error.
- **Reproduced outside Gaea.** `forge-inproc`, signed with `-o runtime`, hangs the same way.
  `com.apple.security.cs.disable-library-validation` lets it run; `allow-jit` and `allow-unsigned-executable-memory`
  don't. Uncompiled (`MLX_DISABLE_COMPILE=1`), it runs and gives the same mask, byte for byte.
- **The fix in the pack.** The defect helper runs with `MLX.compile(enable: false)` around the call. This keeps the
  hardened runtime whole, and it needs no C++ compiler on the server, which the JIT silently needs. The worker runs one
  job at a time, so the global switch touches no other model.
- **Asked.** AB-A-0218 to mlx-image (fix it in mlx-bopbtl-swift) and mlx-apps: a notarized Pixel Agency engine that
  serves scratches hangs the same way. v0.9.1's unsigned Release build runs it (1.5 s), which is why AB-T-0373 didn't
  see it.

## Licence gates

Every weight passed the engine's licence gate at registration (`licenseEnforcement` advisory, permissive policy), as
in v0.9.1, and each offer states its package's declared weight licence.

| Model | Weights | Licence | Source |
|---|---|---|---|
| HVI-CIDNet | `mlx-community/HVI-CIDNet-Generalization-fp32` | MIT | Fediory/HVI-CIDNet |
| DDColor | `mlx-community/DDColor-modelscope-fp16` | Apache-2.0 | |
| SigLIP2 IQA | `mlx-community/siglip2-base-patch16-224-8bit`; the IQA head ships in the package | Apache-2.0 | |
| DRUNet | `mlx-community/DRUNet-color-fp32` | MIT | cszn/DPIR (mlx-drunet-swift PORT-STATUS) |
| BOPBTL | `mlx-community/BOPBTL-scratch-detection-fp32-mlx` | MIT | Microsoft; cleared by review (PORT-QUEUE P7) |
| Anime4K VL | none: Metal shaders compiled into the binary | MIT | bloc97/Anime4K, xocialize/anime4k-metal |
| VOSR2 | `mlx-community/VOSR2-fp16` | Apache-2.0, undisclosed corpus | Posture A (AB-D-0105) |
| Nacre | `xocialize/nacre-v1-mlx` | Apache-2.0 | xocialize's own, Commons CC0/PD/CC BY (AB-R-0396) |
| Mage-VL 4B | `mlx-community/Mage-VL-8bit` | Apache-2.0 | microsoft/Mage-VL |

## Per model, over GPP and in-process

From the golden checks on the released bundles (one call each on a 256² fixture, a warm worker over GPP and one
in-process call; timing evidence is the parity run below, not this).

| Model | Over GPP | In-process | Worker footprint |
|---|---|---|---|
| HVI-CIDNet (a dark 256²) | 0.11 s | 0.07 s | 0.95 GB |
| DDColor (grey 256²) | 0.14 s | 0.14 s | 2.82 GB |
| SigLIP2 IQA | 0.03 s | 0.02 s | 0.88 GB |
| DRUNet | 0.09 s | 0.06 s | 2.16 GB |
| BOPBTL (uncompiled over GPP) | 0.60 s | 0.64 s | 2.39 GB |
| Anime4K VL ×4 | 0.06 s | 0.06 s | 0.24 GB |
| VOSR2 ×4 | 1.71 s | 1.79 s | 5.71 GB |
| Nacre ×4 | 5.54 s | 4.76 s | 1.48 GB |
| Nacre ×2, the sign (protected words: Nacre and NERVE) | 6.00 s | 4.94 s | 1.05 GB |
| Mage-VL, the normalizer's question on the fox | 0.76 s | 0.75 s | 6.26 GB |

## Parity with v0.9.1

Both engines ran TierBench v0.10.0 Release with the same suites (`singles upscale restore generate`, generate limited
to the models both serve as in AB-T-0373), one engine on the machine at a time: v0.9.1 from 05:59 to 06:34Z, Gaea from
06:34 to 07:06Z. A watcher sampled for other GPU jobs every 20 s and found none ([quiet-steps.log](quiet-steps.log)).
v0.9.1 ran 301 records, Gaea 287 (SeedVR2 is only on v0.9.1), with no errors on either.

| Suite | Operation | Model | Tier | Pairs | Same bytes | Same pixels | Worst PSNR (dB) | Max diff | Gaea warm (ms) | Engine warm (ms) | Ratio | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| singles | image.relight | cidnet-relight | - | 3 | 3/3 | 3/3 | ∞ | 0 | 701 | 658 | 1.07 |  |
| singles | image.colorize | ddcolor-colorize | - | 3 | 3/3 | 3/3 | ∞ | 0 | 249 | 264 | 0.94 |  |
| singles | image.matte | birefnet-matte | - | 3 | 6/6 | 6/6 | ∞ | 0 | 460 | 641 | 0.72 |  |
| singles | image.describe | mage-vl | - | 3 | 3/3 | 3/3 | ∞ | 0 | 1110 | 1485 | 0.75 |  |
| singles | image.score | siglip2-quality | - | 3 | 3/3 | 3/3 | ∞ | 0 | 102 | 116 | 0.88 |  |
| upscale-x4 | image.upscale | realplksr-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 221 | 219 | 1.01 |  |
| upscale-x4 | image.upscale | anime4k-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 94 | 99 | 0.95 |  |
| upscale-x4 | image.upscale | heart-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 527 | 552 | 0.95 |  |
| upscale-x4 | image.upscale | nacre-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 5321 | 4614 | 1.15 |  |
| upscale-x4 | image.upscale | nerve-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 129 | 153 | 0.84 |  |
| upscale-x4 | image.upscale | vosr2-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1654 | 1627 | 1.02 |  |
| upscale-x2 | image.upscale | realplksr-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 581 | 582 | 1.00 |  |
| upscale-x2 | image.upscale | anime4k-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 105 | 112 | 0.94 |  |
| upscale-x2 | image.upscale | heart-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2015 | 2087 | 0.97 |  |
| upscale-x2 | image.upscale | nacre-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 14521 | 12516 | 1.16 |  |
| upscale-x2 | image.upscale | nerve-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 194 | 193 | 1.01 |  |
| upscale-x2 | image.upscale | vosr2-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1683 | 1661 | 1.01 |  |
| restore-denoise | image.restore | nafnet-restore | - | 8 | 8/8 | 8/8 | ∞ | 0 | 189 | 189 | 1.00 |  |
| restore-denoise | image.restore | scunet-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1330 | 1229 | 1.08 |  |
| restore-denoise | image.restore | restormer-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2865 | 2824 | 1.01 |  |
| restore-denoise | image.restore | drunet-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 378 | 310 | 1.22 |  |
| restore-denoise | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| restore-deblur | image.restore | nafnet-restore | - | 8 | 8/8 | 8/8 | ∞ | 0 | 156 | 147 | 1.06 |  |
| restore-deblur | image.restore | restormer-motion | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2855 | 2791 | 1.02 |  |
| restore-deblur | image.restore | restormer-defocus | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2893 | 2770 | 1.04 |  |
| restore-deblur | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| generate | image.generate | z-image-turbo | - | 9 | 9/9 | 9/9 | ∞ | 0 | 11364 | 11164 | 1.02 |  |
| generate | image.generate | klein-4b | - | 9 | 9/9 | 9/9 | ∞ | 0 | 7469 | 7180 | 1.04 |  |
| generate | image.generate | klein-4b-base | - | 9 | 9/9 | 9/9 | ∞ | 0 | 72967 | 76641 | 0.95 |  |
| generate | image.generate | qwen-image-flash | - | 9 | 9/9 | 9/9 | ∞ | 0 | 13722 | 13540 | 1.01 |  |
| generate | image.generate | z-image | - | 9 | 9/9 | 9/9 | ∞ | 0 | 68896 | 68988 | 1.00 |  |
| judge | image.score | siglip2-quality | - | 40 | 40/40 | 40/40 | ∞ | 0 | 93 | 99 | 0.94 |  |
| judge | image.describe | mage-vl | - | 40 | 40/40 | 40/40 | ∞ | 0 | 1212 | 1215 | 1.00 |  |

The medians are TierBench's warm runs, `provenance.timings.run_ms`. Routing, from the paired keys: every operation and
tier picked the same model on both (the coverage jobs check the tiers one by one: [coverage-compare.md](coverage-compare.md)).

### Exceedances and their cause

| Where | Ratio | Cause |
|---|---|---|
| upscale ×4, Nacre | 1.15 (5321 against 4614 ms) | **Gaea's workers run with MLX's wired limit off.** |
| upscale ×2, Nacre | 1.16 (14521 against 12516 ms) | The same |
| restore denoise, DRUNet | 1.22 (378 against 310 ms) | The same |

- **What differs.** Gaea's scheduler configures every worker with `wiresWeights: false`
  ([Scheduler.swift:492](../../../Sources/GaeaCore/Workers/Scheduler.swift)), so the worker's MLXServeEngine runs with
  `WiredLimitConfiguration.disabled` and MLX's wired limit stays 0. An in-process engine, v0.9.1 or `forge-inproc`,
  coordinates it (`.automatic`).
- **Measured over GPP with no Gaea in between** ([`tools/gpp-warm-time.py`](../../../tools/gpp-warm-time.py) on the
  released forge bundle, warm runs; [timing-probe/](timing-probe)):

  | | Worker, wiring off (as Gaea) | Worker, wiring on | In-process |
  |---|---|---|---|
  | DRUNet, 768² | 0.29 to 0.30 s | 0.23 to 0.24 s | 0.22 s |
  | Nacre ×2, 512² | 15.5 s | 12.43 to 12.48 s | 12.4 s |

- **Ruled out on the way.** The progress lines Nacre sends at every diffusion step of every tile (100 for a ×2): a sink
  bound in-process the way the worker relays them changed nothing (12.41 to 12.46 s against 12.37 to 12.96 s). The
  hardened runtime: `forge-inproc` signed with it ran DRUNet at the same warm speed. MLX's buffer cache: both cap it at
  min(2 GB, 5 % of the budget).
- **Why it isn't flipped here.** The wired limit is process-wide, and wired pages can't be reclaimed. Several workers each
  wiring up to the whole budget could wire more than the machine has, which panics the kernel (WiredLimitPolicy's
  warning). AB-T-0356 measured with wiring off on purpose. **AB-T-0380** is the follow-up: a wired ceiling the governor
  admits across workers.
- **Most models don't notice.** NAFNet, Restormer, SCUNet, HEART, RealPLKSR, NERVE, Anime4K, VOSR2, the generators and
  the judge are 0.72 to 1.08 with wiring off.

## Conformance

With every G1 plugin installed (Qwen-Image, Z-Image, Klein, prompt-enhance, forge 0.2.0 and Mage-VL), on Gaea 0.6.0:

| Mode | Passed | Failed | Skipped | Report |
|---|---|---|---|---|
| Open | **37** | 0 | 7 | [conformance-open/report.md](conformance-open/report.md) |
| Paired | **40** | 0 | 4 | [conformance-paired/report.md](conformance-paired/report.md) |

The skips are AB-T-0370's: adapters (BASE-013, BASE-029, IMAGE-013), which Gaea doesn't route to plugins yet; output
expiry (BASE-071); and in the open run, the three paired-mode tests.

## Desktop against Gaea

Pixel Agency Desktop (02c8d64), Release, against Gaea 0.6.0 on loopback (`PA_ENGINE_URL=http://127.0.0.1:17762/mes/v0`):

- **Auto-describe.** Desktop's own `AutoDescriber`, run as its auto-describe test runs it but with Gaea in the engine
  directory instead of the mock ([desktop/autodescribe-live](desktop/autodescribe-live)). It found Gaea offering
  `image.describe`, and described 3 of 3 imported photos (a DIV2K street scene, the face, the fox) in 6.1 s: a caption,
  alt text and tags on each, tickets `requester=auto-describe`
  ([desktop/autodescribe-live.log](desktop/autodescribe-live.log)).
- **Score.** `desktop-snapshot faces-live`: ×4 at Best, then face recovery at 50 % with GFPGAN, then RestoreFormer++, then a
  run cancelled in its face pass. Before restoring, Desktop's `TicketEnhancer` scored each face crop on Gaea's
  `image.score` (3 SigLIP2 runs in the forge session, 0.886), found it below its sharp-face bar, and restored it: "faces:
  1 of 1 restored". The cancel left no stored variant ([desktop/faces-live.log](desktop/faces-live.log)).
- **agency-live.** A branded generation on Z-Image Turbo, its export with the AI disclosure, and its description by
  Mage-VL on Gaea, in 3.2 s: "A vibrant orange and teal mug sits on a wooden table by a window."
  ([desktop/agency-live.log](desktop/agency-live.log)).

## Notes

- **Mage-VL's lane label.** mage-vl-swift's configuration carries its own quant type, so the engine resolves the int8
  lane with `footprintQuant: "bf16"`. The bytes are int8's (5.5 GB resident, 6.5 GB transient), so admission is right.
  The plugin names the lane `int8`. Asked of mlx-think as AB-A-0219.
- **The coverage jobs' times aren't a timing comparison.** Each is one sample, mostly a model's first use, and
  AB-T-0374's Gaea ran Klein on the same Mac during Gaea's run.
- **What's committed.** Each run's records, logs, operations and summary, as in AB-T-0373. The output images (708 MB)
  aren't: `pairs.json` keeps each pair's byte and pixel comparison, and `coverage.json` each job's sha256 and values.
- **A shared `dist/`.** AB-T-0374's session launched `dist/Gaea.app` at 22:50, after this task built 0.6.0 there.
