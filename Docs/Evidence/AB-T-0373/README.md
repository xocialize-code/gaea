# AB-T-0373: G1 parity, TierBench against Gaea and pixel-agency-image-engine v0.9.1

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Gaea** | 0.5.0 (ffe2242), Release, `dist/Gaea.app`, with every G1 plugin from its GitHub release: z-image 0.1.0, flux2-klein 0.1.0, qwen-image 0.1.1, forge 0.1.1, prompt-enhance 0.1.0. Default lanes: Klein bf16, Z-Image int4, Flash int8 |
| **Old engine** | pixel-agency-image-engine v0.9.1 (fd93d86), Release, built from a worktree of the tag; the headless engine, its own default state and enabled set |
| **Bench** | pixel-agency-image-engine `Tools/TierBench` at v0.10.0 (09b5a0b), Release |
| **Corpus** | `mlxengine-image/corpus` (DIV2K, GrabCut); the removal gate's prepared set `mlxengine-image/WIP/removal-gate/data/prepared` |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2. Weights in MLXEngine's store, already on disk. One engine on the machine at a time |
| **Scripts** | [`tools/parity-run.sh`](../../../tools/parity-run.sh) (one TierBench run), [`tools/parity-compare.swift`](../../../tools/parity-compare.swift) (pairs two runs: bytes, pixels, PSNR, median warm time, routing), [`tools/parity-seeded.py`](../../../tools/parity-seeded.py) (seeded jobs for what TierBench sends unseeded) |

## Result

| Done = | Result |
|---|---|
| Per tier, outputs match for the same models and seeds | **Pass.** Every seeded output is byte-identical: TierBench's 441, and the 12 seeded jobs for the edits and tiers TierBench sends without a seed. The 15 TierBench outputs that differ are all unseeded requests. |
| Wall time within 10 % of the old engine | **Pass for every warm median** (0.95 to 1.08). Two single first-use samples in the tiers suite exceed 10 %. Both have a named cause, and each passes when rerun seeded on fresh engines (below). |
| Every exceedance has a named cause | **Yes**, below. |

Both runs used the same suites (tiers, upscale ×4 and ×2, restore, segment, generate, edits, erase), and generate and
erase were limited to the models both serve (`MODELS=z-image-turbo,klein-4b,z-image,klein-4b-base,qwen-image-flash,mi-gan,lama`).
v0.9.1 ran 646 records in 38 minutes, Gaea 481 in 33. Neither run had an error, apart from TierBench's judge, which
calls `image.score` and `image.describe`, operations Gaea doesn't serve (see "What Gaea doesn't serve").

- [compare.md](compare.md): every group, plus the routing table.
- [pairs.json](pairs.json): every pair.
- [gaea/](gaea) and [engine/](engine): each run's summary, records, log and operations.

## Outputs and warm times

The medians are TierBench's warm runs, `provenance.timings.run_ms`.

| Suite | Model | Pairs | Same bytes | Gaea (ms) | v0.9.1 (ms) | Ratio |
|---|---|---|---|---|---|---|
| upscale ×4 | RealPLKSR / HEART / NERVE | 7 each | 21/21 | 213 / 526 / 130 | 211 / 530 / 124 | 1.01 / 0.99 / 1.05 |
| upscale ×2 | RealPLKSR / HEART / NERVE | 7 each | 21/21 | 579 / 2022 / 194 | 572 / 1998 / 188 | 1.01 / 1.01 / 1.03 |
| restore denoise | NAFNet / SCUNet / Restormer | 8, 7, 7 | 22/22 | 184 / 1185 / 2796 | 179 / 1152 / 2754 | 1.03 / 1.03 / 1.02 |
| restore deblur | NAFNet / Restormer motion / defocus | 8, 7, 7 | 22/22 | 157 / 2786 / 2786 | 148 / 2738 / 2736 | 1.06 / 1.02 / 1.02 |
| segment, one click | SAM 2.1 / EdgeTAM | 51 each | 102/102 | 44 / 40 | 46 / 42 | 0.96 / 0.95 |
| generate 1024² | Z-Image Turbo | 9 | 9/9 | 11204 | 11029 | 1.02 |
| | Klein 4B (prompts rewritten by the enhancer in both) | 9 | 9/9 | 7296 | 7035 | 1.04 |
| | Klein 4B Base | 9 | 9/9 | 74779 | 76801 | 0.97 |
| | Qwen-Image Flash | 9 | 9/9 | 14109 | 13661 | 1.03 |
| | Z-Image | 9 | 9/9 | 72293 | 69700 | 1.04 |
| erase (gate, objd and eff masks) | MI-GAN arm (LaMa, draft) / LaMa (standard) | 104 each | 208/208 | 171 / 402 | 167 / 388 | 1.02 / 1.04 |
| edits: extend | LaMa, draft / standard / best | 2 each | 6/6 | 252 / 619 / 619 | 248 / 597 / 595 | 1.02 / 1.04 / 1.04 |
| edits: erase | LaMa, standard | 2 | 2/2 | 435 | 428 | 1.02 |
| edits: edit and fill | Klein 4B, four tiers | 2 each | unseeded | 13380 to 13399 | 12347 to 12418 | 1.08 |

The generate outputs include the prompt rewrites. Klein's short prompts were rewritten by Qwen3.5 4B in both engines,
and the images are byte-identical, so the rewrites were too.

### Seeded jobs on fresh engines

TierBench's edits and tiers send no seed. So [`tools/parity-seeded.py`](../../../tools/parity-seeded.py) sends the
same requests with seed 7, three times on a freshly started engine: the first run is the model's first use.
[seeded/compare.md](seeded/compare.md):

| Job | Gaea first / warm (ms) | v0.9.1 first / warm (ms) | Same bytes |
|---|---|---|---|
| generate draft 512² (Klein 4B, prompt rewritten) | 4448 / 2808, 2856 | 4212 / 2710, 2715 | 3 of 3 |
| generate standard 512² (Z-Image Turbo) | 3761 / 2715, 2736 | 4831 / 2605, 2606 | 3 of 3 |
| edit, Klein 4B, a 1024² photo | 12859 / 12861, 12919 | 12566 / 12528, 12561 | 3 of 3 |
| fill, Klein 4B, a 1024² photo and a centre mask | 12883 / 12870, 12879 | 12549 / 12803, 12705 | 3 of 3 |

## Routing

Each tier picks the same model in both engines for every operation Gaea serves, with one exception:

| Operation | Tier | Gaea | v0.9.1 | Why |
|---|---|---|---|---|
| `image.erase` | best | LaMa | Mage-Flow Edit Turbo | Mage-Flow is a research model, coming as a named-only plugin (AB-T-0374). Until then the normalizer's best erase falls back to LaMa. |

## Exceedances and their causes

| Where | Ratio | Cause |
|---|---|---|
| tiers, generate draft (Klein 4B), one unseeded run | 1.17 (5210 against 4445 ms) | **The first job after Gaea started.** It launched two workers, the enhancer's and Klein's, and each first launch took 0.30 to 0.35 s to say hello ([gaea/server.log](gaea/server.log)). Later launches take 0.01 s, since the bundle's code signature has been checked once. v0.9.1 runs both in-process. Rerun seeded on fresh engines, the same first use is 1.06 (4448 against 4212 ms), and the warm runs 1.04 to 1.05. |
| tiers, generate standard (Z-Image Turbo), one unseeded run | 1.11 (4081 against 3674 ms) | **First use, a single sample.** Rerun seeded on fresh engines, Gaea's first use is faster (3761 against 4831 ms), and the warm runs are 1.04 to 1.05. |

Within 10 %, but measured anyway:
- **Klein edit and fill in the edits suite, 1.08.** About 1 s of the 13 s:
  - **The worker,** about 0.3 s (2.6 %). Seeded on fresh engines, the edit is 12.86 to 12.92 s against 12.53 to 12.56 s.
  - **Other workers resident,** another 0.2 to 0.5 s. In TierBench's run, Qwen Flash and Z-Image had been loaded
    before the edits, and the governor had evicted Klein to fit Z-Image, then relaunched it. Staged the same way
    (Flash, Z-Image and Klein Base loaded first, 69 GB charged), the warm edit was 13.07 and 13.09 s. Its output is
    byte-identical to v0.9.1's (sha256 `6a11c7c9876590e4…`).
  - **v0.9.1 has no such cost,** since all its models share one process.
- **Faster on Gaea: a forge model's first use.** In the tiers suite, SAM 2.1 took 70 against 920 ms, NERVE 230 against
  880 ms, BiRefNet 365 against 1350 ms. It isn't the page cache. Rerun with the cache warm for both, v0.9.1's first
  NERVE was 1103 ms against Gaea's 341 ms, its first BiRefNet 6081 against 412 ms, and its first HEART 6627 against
  2209 ms. Gaea's 341 ms includes launching the forge worker. The warm runs are the same in both. The cause on
  v0.9.1's side wasn't looked into, since it favours Gaea.

## What Gaea doesn't serve yet

These are on v0.9.1 and not in any G1 work order. Parity here covers the models both serve.

| | On v0.9.1 | Where it stands |
|---|---|---|
| Operations | `image.relight` (CIDNet), `image.colorize` (DDColor), `image.describe` (Mage-VL), `image.score` (SigLIP2 IQA) | Not in Plan §5 G1. CIDNet, DDColor and SigLIP2 are ForgeCore models gaea-plugin-forge leaves out (its README, "Models ForgeCore registers that the task didn't list"). TierBench's judge needs `score` and `describe`. |
| Restore | DRUNet denoise | The same ForgeCore list |
| Upscale | SeedVR2, Nacre, VOSR2, Anime4K | SeedVR2 is in G3 (Plan, VID-4). The others aren't planned. |
| Generate, edit, fill, extend, erase | SenseNova U1, Mage-Flow (and its edit models), MOSS-Image | AB-T-0374, named-only |

## Notes

- **TierBench's footprint column reads 0.0 on both runs.** It finds the engine with `pgrep -f pixel-agency-image-engine`,
  which here matched more than the engine. Gaea's memory is in its ledger: with Klein, Flash and Z-Image loaded, it
  read 30.5, 24.6 and 14.1 GB. v0.9.1's Z-Image Turbo resident was 13 GB, its int4 lane: the same lane as Gaea's
  default.
- **Background load.** A DeckCraftNative test (another session's `swiftpm-testing-helper`) held one CPU core
  throughout both runs. It was the same for both engines. The models run on the GPU.
- **A wrong licence link, found in passing.** Gaea's job provenance gives `qwen3.5-4b`'s `terms_url` as the
  Qwen3.5-0.8B hub page.
  - **The cause is on Gaea's side.** `GaeaModelHost` takes a model's source repo from its package's provenance, and
    mlx-qwen-llm-swift's package names `mlx-community/Qwen3.5-0.8B-MLX-8bit` there for every size.
  - **The model's own checkpoint is in its manifest:** the default lane's `weightSources` lists
    `mlx-community/Qwen3.5-4B-MLX-4bit`.
  - **It changes no output or timing here.** It isn't fixed in 0.5.0.
