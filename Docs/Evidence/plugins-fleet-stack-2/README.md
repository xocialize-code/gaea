# The ten plugins left on the old stack, moved to the fleet's mlx-swift 0.33 (2026-11-25)

The fleet moved to `xocialize/mlx-swift` 0.33.x on 2026-11-19 (AB-D-0264): upstream 0.33 with the vendored MLX's
head-dim-split SDPA routes off, which abort or give wrong attention on M5. Twenty plugins were rebuilt then
([mlx-swift-0.33.1-plugins](../mlx-swift-0.33.1-plugins/README.md)) and four more with Gaea 1.10.0. Ten were not: each
was last released on 2026-11-02 (AB-T-0418, mlx-engine-swift 0.73.1). This page is their move.

None of the ten named mlx-swift at its root, so each took whatever its dependencies' `ml-explore/mlx-swift` URL
resolved: unpatched upstream 0.33.0 in three, 0.32.3 in seven. Each now names `xocialize/mlx-swift` `from: "0.33.1"`,
mlx-engine-swift `from: "0.82.1"` and GaeaPluginKit `from: "0.14.1"` at its root, as gaea-plugin-seedvr2 and
gaea-plugin-kokoro do, and each resolves mlx-swift 0.33.2, mlx-engine-swift 0.83.0 (contract 1.67.0) and
GaeaPluginKit 0.16.0.

| Plugin | Release | Was | mlx-swift before | Kit before | Model package | min_gaea |
|---|---|---|---|---|---|---|
| gaea-plugin-rife | 0.1.2 | 0.1.1 | ml-explore 0.33.0 | 0.9.0 | mlx-rife-swift 0.8.0 | 0.10.0 |
| gaea-plugin-moss-soundeffect | 0.1.3 | 0.1.2 | ml-explore 0.33.0 | 0.8.0 | mlx-moss-soundeffect-swift 0.4.0 | 0.9.2 |
| gaea-plugin-ace-step | 0.1.2 | 0.1.1 | ml-explore 0.33.0 | 0.8.0 | mlx-ace-step-swift 0.3.0 | 0.9.2 |
| gaea-plugin-boogu | 0.1.2 | 0.1.1 | ml-explore 0.32.3 | 0.5.0 | boogu-image-swift 0.5.0 | 0.7.0 |
| gaea-plugin-ming-image | 0.3.2 | 0.3.1 | ml-explore 0.32.3 | 0.6.0 | ming-image-swift 0.3.1 | 0.7.0 |
| gaea-plugin-moss-image | 0.1.2 | 0.1.1 | ml-explore 0.32.3 | 0.3.0 | moss-image-swift 0.3.0 | 0.2.0 |
| gaea-plugin-qwen-image | 0.2.2 | 0.2.1 | ml-explore 0.32.3 | 0.5.0 | qwen-image-edit-swift **0.12.0** (was 0.11.0) | 0.7.0 |
| gaea-plugin-qwen-image-21 | 0.1.2 | 0.1.1 | ml-explore 0.32.3 | 0.3.0 | qwen-image21-swift 0.2.0 | 0.2.0 |
| gaea-plugin-mage-flow | **0.1.3** | 0.1.1 | ml-explore 0.32.3 | 0.3.0 | mage-flow-swift 0.12.0 | 0.2.0 |
| gaea-plugin-mage-vl | 0.1.2 | 0.1.1 | ml-explore 0.32.3 | 0.3.0 | mage-vl-swift **0.4.1** (was 0.4.0) | 0.6.0 |

Every model package's newest tag admits mlx-swift 0.33, so no plugin stopped and no ask was filed. Two model packages
moved because a newer tag existed: mage-vl-swift 0.4.1 adds only a LICENSE file, and qwen-image-edit-swift 0.12.0
changes only its Turbo package, which the plugin doesn't link. Under them, mlx-swift-lm resolves 3.33.0 (was 3.32.3),
mlx-exact-conv-swift 0.1.2 (0.1.1), qwen3vl-mlx-swift 0.7.1 (0.6.0), qwen25vl-mlx-swift 0.5.1 (0.5.0) and
flux2-vae-mlx-swift 0.8.0 (0.7.0), wherever a graph has them.

All runs were on a Mac Studio (M5 Max, 128 GB, macOS 27.3), Release builds signed for team CFZS6RXUCP, through the
published Gaea 1.10.0 (`/Volumes/DEV_VOL1/Evidence/gaea-1.10.0/released/app/Gaea.app`), first with the local build
served by `tools/release-standin.py`, then with the notarized release from GitHub. Full outputs are on
`/Volumes/DEV_VOL1/Evidence/gaea-plugin-<name>-<version>/`.

## What the move turned up

- **Every old manifest named a stale engine** (AB-L-0366): mlx-engine-swift 0.72.0, contract 1.58.0, in all ten, though
  each linked 0.73.1. The kits they resolved (0.3.0 to 0.9.0) hard-coded it. Each new manifest says 0.83.0 and 1.67.0.
- **mage-flow's 0.1.2 was never released; 0.1.3 is the release.** mage-flow-swift declares typed adapters on its
  surfaces, and the kit this resolves (0.16.0; 0.1.1 resolved 0.3.0) turns that into `adapter_support` on all five
  offers. The plugin's `generate` and `edit` don't put a run's adapters on their requests, so Gaea would have let an
  operator register a Mage-Flow LoRA and the worker would have refused every run that carried it. The tag `v0.1.2` was
  pushed with that manifest; its release run was cancelled before it published, and the tag stays without a release.
  0.1.3 takes the declaration (and the surface's `adapters` parameter) off each model's manifest (`withoutAdapters`
  in MagePlugin.swift, as LTX 0.2.0 does): no offer says it takes adapters, as in 0.1.1. Carrying them through is a
  follow-up. No other plugin of the ten gained an offer field.
- **How far seeded outputs moved depends on where the plugin started.**
  - **From upstream 0.33.0, nothing moved.** rife (4 framemd5 hashes), moss-soundeffect (7 WAVs) and ace-step (8 WAVs)
    give, case for case, the hashes of their goldens of 2026-10-31
    ([AB-T-0402](../AB-T-0402/golden.log), [AB-T-0398](../AB-T-0398/golden.log), [AB-T-0399](../AB-T-0399/golden.log)).
    For these cases the fork's patch and 0.33.2 change nothing.
  - **From 0.32.3, every seeded image moved**, as the first two waves found. Boogu's 3 golden hashes and Ming-Image's 8
    differ from [AB-T-0387](../AB-T-0387/golden.log)'s and [AB-T-0390](../AB-T-0390/golden.log)'s. Against the
    pictures Gaea returned in October ([AB-T-0374](../AB-T-0374/README.md), [AB-T-0368](../AB-T-0368/README.md)):
    Qwen-Image Flash 49.6 dB PSNR; Mage-Flow 39.9 (Turbo) and 41.7 dB, its edits 29.2 to 33.5 dB; MOSS-Image 30.5 (SFT)
    and 35.2 dB (Base); Qwen-Image 2.1 44.6 dB, its 2.1 edit 37.8 dB and 2.1 Base 25.4 dB. An edit starts from a
    picture that has itself moved. Any pixel-exact reference made on the old stack is stale.
  - **The three furthest pairs were looked at.** Mage-Flow's edit (29.2 dB, a lighthouse in snow) and MOSS-Image SFT
    (30.5 dB, the "GAEA" poster) are the same pictures with different fine texture. Qwen-Image 2.1 Base (25.4 dB,
    "a glass teapot on a wooden table, studio light", seed 42) is the same scene with one part changed: October's
    teapot has a looped handle and no visible spout, today's a short spout where the handle was. Both are sound
    pictures of the prompt; 2.1 Base is the many-step model of the ten and drifts furthest. Boogu's new generate and
    edit and Ming-Image's new poster (which have no October picture to compare) were looked at too and are sound, the
    poster's lettering exact.
  - **Gaea against in-process is unchanged**: byte for byte or pixel for pixel wherever it was before.
- **Three of Gaea's acceptance scripts had drifted from Gaea** (they were last run in October). `tools/` wasn't edited
  here (another session's files); the changes below were made in a scratch copy, or the failures are reported as they
  are. They are follow-ups for the host:
  - **`acceptance-research.sh`, stand-in mode,** files the local bundles under the owner `xocialize`, but every
    manifest names `xocialize-code`, so Gaea refuses the install ("the manifest's repo … isn't … the repo it was
    added from"). Its first moss-image run failed on that, 1 passed and 6 failed
    ([moss-image-local-research-run1.log](moss-image-local-research-run1.log)).
  - **`acceptance-research.jobs` sends `"prompt_enhance":"off"`** on the moss-image and sensenova generate jobs. Gaea
    1.10.0 with no prompt enhancer installed has no such parameter on `image.generate` and answers
    `unsupported_parameter`, so both moss-image jobs were refused at submit
    ([run 2](moss-image-local-research-run2.log), 6 passed, 2 failed). `acceptance-plugin-updates.sh` sends the same
    parameter and wasn't run.
  - The research runs below used a copy with those two things changed and nothing else
    ([research-sh.diff](research-sh.diff), [research-jobs.diff](research-jobs.diff)): the stand-in's folder is
    `xocialize-code`, and the two moss-image jobs drop `prompt_enhance` (with no enhancer the prompt goes as typed,
    which is what `off` asked for and what moss-inproc gets).
  - **`acceptance-qwen.sh` expects Gaea 0.2.2's answers in three checks**, and all three fail on Gaea 1.10.0 with the
    local build and with the release alike:
    1. it wants `qwen-image-edit` offered for standard and best; Gaea's tiers come from pixel-agency-normalizer's
       table, which lists it on `image.edit` for best (`OperationTable.swift`: `"qwen-image-edit": [.best]`);
    2. it reads `references` at the top of `result.effective`; Gaea 1.10.0 keeps the worker's own values under
       `model_params["x-gaea.worker"].effective`, where they are what they were in October (`references: 2`, 1024²,
       20 steps, guidance 4);
    3. it wants a 1280×768 edit returned at 1312×800 with `size_snapped`; the worker still draws 1312×800, and Gaea
       returns the input's 1280×768 and drops the worker's `size_snapped` (GaeaEngine.swift: "the normalizer's sizes
       stand").
    The plugin's manifest is the previous release's but for the engine and the version
    ([manifest-diffs/qwen-image.txt](manifest-diffs/qwen-image.txt)), so its offers didn't change. The checks that
    test the plugin pass: Flash and the two-reference edit are byte for byte qwen-inproc's.
  - **Log headers say "Gaea ," with no version** when `APP` is an absolute path (the scripts read
    `$PWD/$APP/Contents/Info`). The app is the published 1.10.0.
- **Gaea has no acceptance for Mage-VL alone.** `acceptance-coverage.sh` needs a G1 home and expects mage-vl 0.1.0
  and forge 0.2.0. Mage-VL went through Gaea in a probe written for this page (below).
- **Timings here aren't receipts.** The GPU was shared with other sessions' jobs for part of the day: Ming-Image's
  1024 decomposition took 546 s in one golden case against 357 s in October, and Qwen-Image-Edit's cold two-reference
  edit 608 s against 554 s.

## Manifests

[manifest-diffs/](manifest-diffs/) compares each new `dist/manifest.json` with the previous release's. In every one
the engine moves (0.72.0 → 0.83.0, contract 1.58.0 → 1.67.0, and each package's `contractVersion` minor 58 → 67) and
the plugin's version. Beyond that:
- ace-step lists one feature set's members in another order (`referenceAudio`, `sourceAudio`, `timestamps`);
- mage-flow 0.1.3's package surfaces no longer declare adapters (above); its offers are 0.1.1's.

`min_gaea` is unchanged in all ten.

## Results

| Plugin | `check-plugin.sh` | `golden.sh` | Through Gaea 1.10.0, local build | Through Gaea 1.10.0, from GitHub |
|---|---|---|---|---|
| rife 0.1.2 | pass | 8/8 ([log](rife-golden.log)) | 18/18 | 18/18 ([log](rife-github.log), `acceptance-rife.sh`) |
| moss-soundeffect 0.1.3 | pass | 13/13 ([log](moss-soundeffect-golden.log)) | 23/23 | 23/23 ([log](moss-soundeffect-github.log), `acceptance-moss-soundeffect.sh`) |
| ace-step 0.1.2 | pass | 17/17 ([log](ace-step-golden.log)) | 21/21 | 21/21 ([log](ace-step-github.log), `acceptance-ace-step.sh`) |
| boogu 0.1.2 | pass | 3/3 ([log](boogu-golden.log)) | 20/20 | 20/20 ([log](boogu-github.log), `acceptance-boogu.sh`, beside z-image 0.2.2) |
| ming-image 0.3.2 | pass | 13/13 ([log](ming-image-golden.log)) | 24/24, and decompose 16/16 | 24/24 ([log](ming-image-github.log), `acceptance-ming-image.sh`) and 16/16 ([log](ming-image-github-ming-layer.log), `acceptance-ming-layer.sh`) |
| moss-image 0.1.2 | pass | none in the repo | 11/11 (third run; the first two were the script, above) | 11/11 ([log](moss-image-github-research.log), `acceptance-research.sh` copy) |
| qwen-image 0.2.2 | pass | 2/2 ([log](qwen-image-golden.log)) | 10 passed, 3 failed (the script's three, above) | 10 passed, 3 failed, the same three ([log](qwen-image-github.log), `acceptance-qwen.sh`) |
| qwen-image-21 0.1.2 | pass | none in the repo | 13/13 | 13/13 ([log](qwen-image-21-github-research.log), `acceptance-research.sh` copy) |
| mage-flow 0.1.3 | pass | none in the repo | 17/17 | 17/17 ([log](mage-flow-github-research.log), `acceptance-research.sh` copy) |
| mage-vl 0.1.2 | pass | 6/6 ([log](mage-vl-golden.log)) | probe 8/8 | probe 8/8 ([log](mage-vl-github-probe.log)) |

`*-check-summary.txt` hold each check's lines and its metallib control, `*-local*.log` the runs with the local build,
`*-steps.txt` each step's exit status and time.

- **Every released worker names the engine it links**: in the sessions the from-GitHub runs recorded, each of the
  ten says mlx-engine-swift 0.83.0, contract 1.67.0 and GaeaPluginKit 0.16.0 in its hello.
- **Each from-GitHub run installed the new release**: the sessions it recorded are named for it
  (`com.xocialize.gaea.rife-0.1.2-…gpp` and so on), and the research and Boogu runs list it in `models.txt`. That
  matters for rife, moss-soundeffect and ace-step, whose outputs the old releases would also have matched.
- **mage-flow 0.1.2's build** passed its check and the same acceptance, 17/17
  ([mage-flow-0.1.2-local-research.log](mage-flow-0.1.2-local-research.log)), before its manifest was read.
- **The research acceptance's comparison with pixel-agency-image-engine v0.9.1** didn't run: the script skips it when
  that engine's build isn't there, and it isn't. It was reported, never counted, and v0.9.1 is on the old stack.
- **The Mage-VL probe** ([magevl-probe.sh](magevl-probe.sh)): Gaea 1.10.0 with only gaea-plugin-mage-vl, installed by
  repo URL; `image.describe` is offered with `mage-vl` as its default; two photos (the plugin's fox and face
  fixtures) described through MES, each answer with a caption, alt text and tags, from plugin version 0.1.2; the
  worker's hello names mlx-engine-swift 0.83.0; the text the worker returned through Gaea is mage-vl-inproc's for the
  same photo and the normalizer's describe question (the plugin's fixture of it; Gaea removes the worker's own inputs
  after a run, so the photo given to mage-vl-inproc is the fixture, not Gaea's re-encoding of it); the recorded
  session passes `tools/validate.py`. Its first run ([mage-vl-local-probe-run1.log](mage-vl-local-probe-run1.log), 4
  passed, 4 failed) failed on the probe's own mistakes: it read the description from a place Gaea 1.10.0 doesn't put
  it and tried to copy inputs that were already gone. Both jobs had succeeded.

## Not covered

- Gaea versions older than 1.10.0 weren't driven. `min_gaea` is unchanged on the reading above: the manifests differ
  from the previous releases' only in the engine's version and contract.
- A Mage-Flow adapter: 0.1.3 offers none, as 0.1.1 did.
- Ming-Image's and Boogu's pictures weren't compared with October's beyond their hashes (the old golden pictures
  aren't kept).
- sensenova's and flux3-klein's rows of the research acceptance weren't run; they moved on 2026-11-19.

## Follow-ups

- `tools/acceptance-research.sh` (the stand-in's owner folder), `tools/acceptance-research.jobs` and
  `tools/acceptance-plugin-updates.sh` (`prompt_enhance` without an enhancer), `tools/acceptance-qwen.sh` (three
  checks written for Gaea 0.2.2), and the headers' version when `APP` is absolute.
- gaea-plugin-mage-flow: put a run's adapters on its requests (`job.adapterRefs()`), check it with a real Mage-Flow
  LoRA, and put the declaration back.
- CLAUDE.md has no rows for gaea-plugin-mage-flow, gaea-plugin-mage-vl, gaea-plugin-moss-image and
  gaea-plugin-qwen-image-21; none was added here.
