# AB-T-0374: research image models as opt-in, named-only Gaea plugins

| | |
|---|---|
| **Date** | 2026-10-28/29 |
| **Plugins** | Five new repos under xocialize, each Developer ID signed, notarized and published as v0.1.0; see the table below |
| **Host** | Gaea 0.6.0, Release, `dist/Gaea.app` from this repo, in a fresh `GAEA_HOME` (`/tmp/g74*`: the operator socket's path must stay under 104 bytes) |
| **Reference engine** | pixel-agency-image-engine v0.9.1 (fd93d86), Release, `--allow-research --no-advertise` on the same models root |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Weights** | `/Volumes/DEV_VOL1/models/gaea-research-store`, a flat MLXEngine store (see "Weights") |
| **Script** | [`tools/acceptance-research.sh`](../../../tools/acceptance-research.sh) with [`tools/acceptance-research.jobs`](../../../tools/acceptance-research.jobs) |

## The plugins

| Repo, release | Package (exact pin) | Models | Licence of the weights |
|---|---|---|---|
| [xocialize/gaea-plugin-mage-flow v0.1.0](https://github.com/xocialize/gaea-plugin-mage-flow/releases/tag/v0.1.0) (`0d7f824`, zip `c6dcd6b94c2cdfc1…`) | mage-flow-swift 0.12.0 | `mage-flow`, `mage-flow-turbo` (generate); `mage-flow-edit`, `mage-flow-edit-turbo`, `mage-flow-edit-base` (edit, 1–3 refs) | MIT |
| [xocialize/gaea-plugin-sensenova v0.1.0](https://github.com/xocialize/gaea-plugin-sensenova/releases/tag/v0.1.0) (`e1e1f9f`, `0de114c6e40704cd…`) | sensenova-u1-swift 0.5.3 | `sensenova-u1`, `sensenova-u1-fast`, `sensenova-u1-fast-v1` (generate, and edit from 1 ref) | Apache-2.0 |
| [xocialize/gaea-plugin-moss-image v0.1.0](https://github.com/xocialize/gaea-plugin-moss-image/releases/tag/v0.1.0) (`0963c00`, `c34a11c4d2c83fac…`) | moss-image-swift 0.3.0 | `moss-image-sft`, `moss-image-base` (generate) | Apache-2.0 |
| [xocialize/gaea-plugin-qwen-image-21 v0.1.0](https://github.com/xocialize/gaea-plugin-qwen-image-21/releases/tag/v0.1.0) (`bc45aa0`, `bfeba87e7215f5fe…`) | qwen-image21-swift 0.2.0 | `qwen-image-2.1` (Turbo), `qwen-image-2.1-base` (generate, and edit from 1–10 refs) | Qwen Research |
| [xocialize/gaea-plugin-flux3-klein v0.1.0](https://github.com/xocialize/gaea-plugin-flux3-klein/releases/tag/v0.1.0) (`d042576`, `6cd05812ae2799d7…`) | flux3-klein-swift 0.6.1 | `flux-3-klein` (generate, and edit from 1–10 refs) | FLUX Kommunity |

- **What every repo resolves:** GaeaPluginKit 0.3.0, mlx-engine-swift 0.73.0 and mlx-swift 0.32.3.
- **MOSS-Image:** it entered the catalog in mlx-image-runtime 0.7.0, so it is in scope.
- **Lanes,** with the default first:
  - Mage-Flow: bf16, int8, int4. Edit Turbo has int8 and int4 only.
  - SenseNova: int8, plus bf16 on the base and int4 on the fast tiers.
  - MOSS: bf16/bf16 and int8/int8.
  - Qwen 2.1: bf16.
  - FLUX 3: bf16, int8, int4.
  - Footprints are in each `release/<family>/manifest.json`.

## Result

| Done = | Result | Evidence |
|---|---|---|
| The notarized release passes gaea-plugin-check | **Pass, five of five** | `scripts/release.sh` in each repo: gaea-plugin-check ALL PASS with every `.build` hidden, and the bare worker fails on the metallib. Then notarytool Accepted, stapled, `spctl` "Notarized Developer ID". See [release/](release) for each family's `check.log`, `check-session.gpp`, `notary.json` and `manifest.json`. |
| Its offers are named-only | **Pass, 13 of 13 models** | `/mes/v0/operations` after install ([github/operations.json](github/operations.json)): every research model is `named_only: true` and never `default`. A request naming no model reached FLUX.2 Klein (`klein-4b-base`), not a research model ([github/job-default.json](github/job-default.json)). The two restricted families were off until enabled, which is opt-in ([github/models-before.txt](github/models-before.txt)), and say `commercial_use: false`. |
| Gaea runs one job for it by name | **Pass, 16 jobs over 13 models** | Installed by repo URL from the GitHub releases, anonymously; each job names its model ([github/acceptance.log](github/acceptance.log), `job-*.json`). |
| A seeded request is byte-identical to the plugin's in-process reference | **Pass, 16 of 16** | Each plugin as Gaea installed it from GitHub, driven by gaea-plugin-check with the request Gaea's normalizer sent its worker (lane, params, seed, input bytes), against `<x>-inproc` on the same models root. |

**[`tools/acceptance-research.sh`](../../../tools/acceptance-research.sh), from GitHub: 47 passed, 0 failed.**

| Job | Model | Operation | Lane | Size | Worker run (s) | In-process run (s) | Plugin = in-process (sha256) | Gaea's output (sha256) |
|---|---|---|---|---|---|---|---|---|
| `mf-turbo` | `mage-flow-turbo` | image.generate | bf16 | 512x512 | 0.47 | 0.47 | `4366f63d8a47` | `4366f63d8a47` |
| `mf-flow` | `mage-flow` | image.generate | bf16 | 512x512 | 3.48 | 3.47 | `aa61b7cfcce6` | `aa61b7cfcce6` |
| `mf-edit-turbo` | `mage-flow-edit-turbo` | image.edit | int8 | 512x512 | 1.02 | 0.97 | `209bb8f7ba9a` | `209bb8f7ba9a` |
| `mf-edit` | `mage-flow-edit` | image.edit | bf16 | 512x512 | 8.12 | 6.91 | `ef1bae58f87d` | `ef1bae58f87d` |
| `mf-edit-base` | `mage-flow-edit-base` | image.edit | bf16 | 512x512 | 10.21 | 10.18 | `9064bb442998` | `9064bb442998` |
| `moss-sft` | `moss-image-sft` | image.generate | bf16 | 512x512 | 29.75 | 31.44 | `6e91b8c46f6d` | `c17d3b52b9d7` |
| `moss-base` | `moss-image-base` | image.generate | bf16 | 512x512 | 27.16 | 27.29 | `2f729f46222a` | `2b9ec57c8118` |
| `q21-gen` | `qwen-image-2.1` | image.generate | bf16 | 512x512 | 6.37 | 6.31 | `bd84d69f62df` | `9f0563a96369` |
| `q21-base` | `qwen-image-2.1-base` | image.generate | bf16 | 512x512 | 13.42 | 13.14 | `30217a680841` | `385f678c8d30` |
| `q21-edit` | `qwen-image-2.1` | image.edit | bf16 | 512x512 | 6.62 | 6.54 | `9185d9fc550c` | `3c155874593d` |
| `f3-gen` | `flux-3-klein` | image.generate | bf16 | 512x512 | 13.80 | 13.76 | `f3d9abeed172` | `f3d9abeed172` |
| `f3-edit` | `flux-3-klein` | image.edit | bf16 | 512x512 | 15.35 | 15.18 | `293d70549d12` | `293d70549d12` |
| `sn-base-gen` | `sensenova-u1` | image.generate | int8 | 512x512 | 12.13 | 12.09 | `beb5102a8693` | `1c91f22bf13d` |
| `sn-fast-gen` | `sensenova-u1-fast` | image.generate | int8 | 512x512 | 1.15 | 1.15 | `ad4d604129cc` | `de2f6a7bb941` |
| `sn-fastv1-gen` | `sensenova-u1-fast-v1` | image.generate | int8 | 512x512 | 1.16 | 1.15 | `868941b0c1c8` | `0efdf20bd3aa` |
| `sn-fast-edit` | `sensenova-u1-fast` | image.edit | int8 | 512x512 | 1.33 | 1.27 | `83544accd4cd` | `c53f301d5089` |

- **Requests.** Seeded, at the models' default steps and guidance, with `prompt_enhance: off` for SenseNova and MOSS.
  Edits take the job named in the jobs file as their input, with an explicit 512² size.
- **Timings.** They are Release, warm in each process, on the M5 Max. They are listed for orientation only: the
  receipt claims no timing.
- **Gaea's own output.** Gaea's image normalizer re-encodes some outputs, so where Gaea's sha256 differs, the pixels
  were compared:
  - **SenseNova and MOSS: pixels identical.** Their packages write RGB PNGs, which the normalizer returns as RGBA.
  - **Qwen-Image-2.1: at most 1 level apart** in 1,576–2,912 of the 1,048,576 channel values. That is the
    normalizer's handling of the model's native alpha.
  - Mage-Flow and FLUX 3 come back as the same bytes.
- **Against pixel-agency-image-engine v0.9.1:** all 16 of Gaea's outputs are byte-identical to v0.9.1's for the same
  MES requests by name. This is reported (`INFO` in the log), not counted.

## Found on the way

- **The checker binary.**
  - The kit checkout's own `.build/release/gaea-plugin-check` is from 2026-10-27 and predates `--model`. Given a
    model, it ran the plugin's first offer instead.
  - The acceptance uses each plugin repo's checker, which `check-plugin.sh` builds from kit 0.3.0.
  - The stale binary's runs re-materialized Mage-Flow's components into the research store (DEV_VOL1) before they
    were stopped. Every file kept its full size.
- **An mlx-engine probe bug (AB-A-0220).**
  - A models root spelled with a different case from the folder on disk (`/Volumes/DEV_VOL1/models` for `Models`)
    makes `WeightSourceProbe.flatDirectory` report complete snapshots missing: GPP `not_materialized` for
    Qwen-Image-2.1.
  - Packages that check with `fileExists` (Mage-Flow, MOSS, FLUX 3) were unaffected.
  - Filed to mlx-engine. Not blocking.
- **v0.9.1 and Gaea size an edit differently** when the request gives no size:
  - v0.9.1 sends the package no size, so Mage-Flow renders at its own 1024² default and the normalizer scales the
    result back.
  - Gaea's host sends the first image's size.
  - The two Mage-Flow edits then differ: seen in the first run, matched once the size was explicit.
  - This is a host-level difference, not the plugin's. Recorded for AB-T-0377's parity work.
- **Prompt enhancement:** v0.9.1 rewrites SenseNova and MOSS prompts by default (`prompt_enhance: auto` with the
  vendor profiles on Qwen3.5-9B). Gaea did too only where the LLM plugin is installed, so the seeded comparison sends
  `prompt_enhance: off`.
- **Not reproduced:** in an earlier run, FLUX 3's edit differed from v0.9.1's while matching in-process. In the
  final run it matched. The cause wasn't established.

## For the host (not changed here: AB-T-0377 owns `Sources/`)

1. **Opt-in follows the licence only.**
   - `PluginOffers.offer` and `GaeaHost`'s `models list` and `enable` derive opt-in from the weight licence.
   - A permissive model whose offers say `named_only` (Mage-Flow, SenseNova, MOSS) is therefore *on* once installed:
     reachable only by name, but not opt-in.
   - PRD R5 and PLG-11 ask opt-in for research models. The host could read a manifest flag, or treat an
     all-`named_only` model as opt-in.
2. **`best` erase and the creative upscale.**
   - The normalizer's table names `mage-flow-edit-turbo` as the `best` eraser (`eraseByTier`) and the creative
     upscale's editor.
   - Because the plugin's `image.edit` offer is named-only, Gaea's descriptors mark the model named-only for
     `image.erase` too (`GaeaEngine.descriptors` falls back to the `image.edit` route), and `defaultModel` keeps
     `best` erase on LaMa.
   - That erase route also needs Mage-VL (the namer), which AB-T-0377 is adding as a plugin.
   - If the operator wants v0.9.1's `best` erase, either of these restores it:
     - the plugin gains a non-named-only `image.erase` offer for `mage-flow-edit-turbo`;
     - the host stops inheriting named-only from `image.edit` for erase.
   - It is a decision, not a fix.
3. **`CLAUDE.md`'s "Where things are" table** has no rows for the five research plugin repos.

## One repo per family, not a shared research plugin

- **One worker per plugin.** Gaea runs one worker process per plugin: `Scheduler.slots` is keyed by plugin, and
  that worker prepares every lane the plugin has. A shared research plugin would put Mage-Flow, SenseNova, MOSS, Qwen
  2.1 and FLUX 3 in one process: evicted as one, crashed as one, and charged as one tenant by the governor.
- **One licence posture per release.** The families' weight licences differ: MIT, Apache-2.0, Qwen Research and FLUX
  Kommunity. Separate releases keep a restricted family's terms out of the permissive ones' release notes and
  README. An update to one model doesn't re-release the others.
- **Independent pins.** Each repo pins its package exactly at the version pixel-agency-image-engine v0.9.1 resolves,
  and resolves mlx-engine-swift on its own.

## Licence gate

Each family passed the fleet's licence verdicts before its plugin was published. The plugins are Apache-2.0 (G-21)
and ship no weights.

| Family | Weights | Verdict | In Gaea |
|---|---|---|---|
| Mage-Flow | MIT (Microsoft, mirrored at mage-flow-community) | Permissive: AB-D-0059, AB-R-0466, AB-R-0469 | Named-only; on once installed |
| SenseNova-U1.5 | Apache-2.0 | Permissive, port-viable: AB-D-0043, AB-R-0493 | Named-only; on once installed |
| MOSS-Image | Apache-2.0 | Shipping approved: AB-D-0150 | Named-only; on once installed |
| Qwen-Image-2.1 | Qwen Research licence: non-commercial, research and evaluation only | Research tier only, never default: AB-D-0085 | Named-only and opt-in; `commercial_use: false` |
| FLUX 3 Klein | FLUX Kommunity v1.0 | Restricted, named-only, `commercial_use: false` with the Qualifying-User notice: AB-D-0151 | Named-only and opt-in; `commercial_use: false` |

**The operator's authorization (2026-10-29).** The operator authorized research-licensed models for this task, in
the gaea main session: "You are authorized for research." The gate therefore passes the research and non-commercial
weight licences, the Qwen Research licence and FLUX Kommunity v1.0, as `--allow-research` does on
pixel-agency-image-engine. The operator accepts their terms. Every offer still states its licence truthfully, is
named-only, and says `commercial_use: false` where the weights aren't permissive. LoRAs are not part of this task;
they are adapters on base models in a separate work order.

**Each verdict's source.** The licence was read from the source below, and the manifest's `weightLicense` (what Gaea
keys named-only and opt-in on) and the offers' MES licence were checked against it, in
`release/<family>/manifest.json`.

| Family | Source of the licence | Package `weightLicense` | Offer licence (MES) |
|---|---|---|---|
| Mage-Flow | <https://huggingface.co/mage-flow-community/Mage-Flow/blob/main/LICENSE>; the Hub card says `license: mit` (read 2026-10-29) | `MIT` (all 5 models) | `MIT`, `commercial_use: true` |
| SenseNova-U1.5 | <https://huggingface.co/sensenova/SenseNova-U1.5-8B-MoT>: the card says `license: apache-2.0`, as does the mirror's README in the store (`models--mlx-community--SenseNova-U1.5-8B-MoT-8bit/README.md`) | `Apache-2.0` (all 3) | `Apache-2.0`, `commercial_use: true` |
| MOSS-Image | <https://huggingface.co/OpenMOSS-Team/MOSS-Image-SFT>; the mirror's `LICENSE` (Apache License 2.0) in `models--mlx-community--MOSS-Image-SFT-bf16/` | `Apache-2.0` (both) | `Apache-2.0`, `commercial_use: true` |
| Qwen-Image-2.1 | <https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE>; the mirror's `LICENSE` ("Qwen RESEARCH LICENSE AGREEMENT", release date September 20, 2026) and `NOTICE` in `models--xocialize--Qwen-Image-2.1/` | `LicenseRef-Qwen-Research` (both) | `LicenseRef-Qwen-Research`, `commercial_use: false`, notice "non-commercial research and evaluation use only. Built with Qwen." |
| FLUX 3 Klein | <https://huggingface.co/black-forest-labs/flux-3-image-klein/blob/main/LICENSE.md>; the snapshot's `LICENSE.md` ("FLUX Kommunity License v.1.0") in `models--mlx-community--flux-3-image-klein-bf16/` | `LicenseRef-FLUX-Kommunity-1.0` | `LicenseRef-FLUX-Kommunity-1.0`, `commercial_use: false`, the Kommunity notice (non-commercial; commercial outputs only for Qualifying Users who filter and disclose; never train on outputs) |

## How "named-only" and "opt-in" come about

- **From the licence.** Gaea derives an offer's named-only *and* opt-in state from the package's weight licence
  (`PluginOffers.offer`: not permissive → `named_only`, off until the operator enables it). That covers Qwen-Image-2.1
  (`LicenseRef-Qwen-Research`) and FLUX 3 Klein (`LicenseRef-FLUX-Kommunity-1.0`).
- **From the plugin.** For the permissive families every manifest offer's `model` says `"named_only": true` and has
  no `default`. Gaea keeps that (`PluginOffers.routes`), marks the descriptor's model named-only and never default
  (`GaeaEngine.descriptors`), and neither its own routing (`GaeaModelHost.route`) nor the normalizer
  (`defaultModel`'s candidates) picks it without a name.
- **Every restricted family's offers say `named_only` too,** so the manifest states it whatever the host derives.

## Weights

`/Volumes/DEV_VOL1/models/gaea-research-store` is a flat MLXEngine store. Nothing was downloaded onto the Satechi
volume.

- **Symlinked from existing snapshots:**
  - DEV_VOL1's store: SenseNova-U1.5 8bit, bf16, 8step-8bit, 8step-4bit and 8step-v2-8bit; Mage-Flow Turbo and Edit
    Turbo artifacts; Edit Turbo's components;
  - MLXEngine's store: Mage-Flow-Turbo's components (with the bf16 DiT), `xocialize/Qwen-Image-2.1`,
    `xocialize/Qwen-Image-2.1-Turbo`, `Qwen/Qwen3-VL-8B-Instruct`, and `FLUX.2-klein-4B-bf16` (for the default-route
    check);
  - `mlxengine-image/WIP/flux3-klein-inapp/store`: `flux-3-image-klein-bf16`, `-pup-8bit`, and the NSFW classifier.
- **Downloaded to DEV_VOL1 on 2026-10-28,** anonymously from public Hugging Face repos, about 66 GB:
  - `mlx-community/MOSS-Image-SFT-bf16` at `ea698e99` (25 GB);
  - `mlx-community/MOSS-Image-Base-bf16` at `56e5c1f9`, transformer only (9.5 GB);
  - `mage-flow-community/Mage-Flow`, `-Edit` and `-Edit-Base` components (16 GB each), and their `xocialize/*-mlx`
    folded adaLN.
