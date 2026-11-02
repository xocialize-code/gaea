# AB-T-0418: before 1.0 (G4 order 6)

Three pieces, each below:
- **The plugins:** every plugin rebuilt on mlx-engine-swift v0.73.1 and released from CI, then updated in a running
  Gaea through `gaea plugins update`.
- **The wired limit (AB-T-0380):** decided, done. Workers keep their weights wired while they run.
- **The operator's guide,** in [README.md](../../../README.md#running-a-server).

## The plugins on mlx-engine-swift v0.73.1

Each plugin's floor moved to `from: "0.73.1"`, its resolved pin to v0.73.1 (4604160), and its version up one patch.
Nothing else changed. v0.74.0 was out by then; it only adds contract 1.59.0's speech-edit kinds, so the plugins
stayed on the release the plan named and AB-R-0697 measured.

**How to tell a bundle links 0.73.1:** its worker imports `mincore` and `msync`, which only the fixed probe calls,
and its manifest's engine contract is 1.58.0. The manifest's `engine.version` still says 0.72.0, a constant in
GaeaPluginKit, since the engine has no runtime version; asked of mlx-engine as AB-A-0248.

### Swift 6.3.3's builds segfault: CI moved to Xcode 27

The first CI releases (GitHub's `macos-26` runner, Xcode 26.6, Swift 6.3.3) of Z-Image 0.1.1 and FLUX.2 Klein 0.2.2
crashed in their first run:
- `EXC_BAD_ACCESS (SIGSEGV)` at `0xfffffffffffffff8`;
- in `swift_task_localValuePushImpl`, under `ZImageT2IPackage.run` and `Klein4BT2IPackage.run`, where each model
  package pushes a task-local value of its own (`ZImageProgress.$sink.withValue`).

What was ruled out:
- **Gaea:** they crash the same over GPP with no Gaea (`gpp-run`), wired or not.
- **Wiring:** Z-Image 0.1.1 crashes with `GAEA_UNWIRED=1`, and 0.1.0 runs wired.
- **The source:** the same 0.1.1 source built on this Mac (Xcode 27.2, Swift 6.4.2) runs.

Releases whose packages push no task-local of their own ran: the demo 0.3.3, Boogu 0.1.1 and ACE-Step 0.1.1. Z-Image
and Klein had only ever been released from builds on this Mac before; their CI runs had built but never published.

What was done:
- Z-Image 0.1.1 and Klein 0.2.2 were marked pre-releases with a note, so Gaea's installer skips them. The other 17
  runs were cancelled before they published.
- Every plugin's workflow now runs on GitHub's `xcode-27` image (Xcode 27, Swift 6.4, a public preview), and the
  template's README and AUTHORING.md say so.
- Z-Image 0.1.2 and Klein 0.2.3 are the Xcode 27 builds. The 17 cancelled versions, never published, were tagged again
  on the commit with the new workflow.
- Forge's first Xcode 27 build failed: media-bridge 0.40.0 sets `CIRAWDecoderVersion.version9` unguarded, which the
  macOS 27.2 SDK marks macOS 27 or newer. media-bridge 0.40.1 is that fix alone (AB-A-0230); forge moved to it.

| Plugin | From | To | Built with |
|---|---|---|---|
| [demo](https://github.com/xocialize-code/gaea-plugin-demo/releases/tag/v0.3.3) | 0.3.2 | 0.3.3 | Xcode 26.6, Swift 6.3.3 |
| [z-image](https://github.com/xocialize-code/gaea-plugin-z-image/releases/tag/v0.1.2) | 0.1.0 | 0.1.2 (0.1.1, Xcode 26, withdrawn) | Xcode 27.2 RC, Swift 6.4.2 |
| [flux2-klein](https://github.com/xocialize-code/gaea-plugin-flux2-klein/releases/tag/v0.2.3) | 0.2.1 | 0.2.3 (0.2.2, Xcode 26, withdrawn) | Xcode 27.2 RC, Swift 6.4.2 |
| [qwen-image](https://github.com/xocialize-code/gaea-plugin-qwen-image/releases/tag/v0.2.1) | 0.2.0 | 0.2.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [boogu](https://github.com/xocialize-code/gaea-plugin-boogu/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 26.6, Swift 6.3.3 |
| [ming-image](https://github.com/xocialize-code/gaea-plugin-ming-image/releases/tag/v0.3.1) | 0.3.0 | 0.3.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [forge](https://github.com/xocialize-code/gaea-plugin-forge/releases/tag/v0.2.1) | 0.2.0 | 0.2.1 | Xcode 27.2 RC, Swift 6.4.2; media-bridge 0.40.1 |
| [prompt-enhance](https://github.com/xocialize-code/gaea-plugin-prompt-enhance/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [mage-vl](https://github.com/xocialize-code/gaea-plugin-mage-vl/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [kokoro](https://github.com/xocialize-code/gaea-plugin-kokoro/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [qwen3-tts](https://github.com/xocialize-code/gaea-plugin-qwen3-tts/releases/tag/v0.2.1) | 0.2.0 | 0.2.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [step-audio-editx](https://github.com/xocialize-code/gaea-plugin-step-audio-editx/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [moss-soundeffect](https://github.com/xocialize-code/gaea-plugin-moss-soundeffect/releases/tag/v0.1.2) | 0.1.1 | 0.1.2 | Xcode 27.2 RC, Swift 6.4.2 |
| [ace-step](https://github.com/xocialize-code/gaea-plugin-ace-step/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 26.6, Swift 6.3.3 |
| [rife](https://github.com/xocialize-code/gaea-plugin-rife/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [seedvr2](https://github.com/xocialize-code/gaea-plugin-seedvr2/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [ltx](https://github.com/xocialize-code/gaea-plugin-ltx/releases/tag/v0.1.2) | 0.1.1 | 0.1.2 | Xcode 27.2 RC, Swift 6.4.2 |
| [mage-flow](https://github.com/xocialize-code/gaea-plugin-mage-flow/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [sensenova](https://github.com/xocialize-code/gaea-plugin-sensenova/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [moss-image](https://github.com/xocialize-code/gaea-plugin-moss-image/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [qwen-image-21](https://github.com/xocialize-code/gaea-plugin-qwen-image-21/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |
| [flux3-klein](https://github.com/xocialize-code/gaea-plugin-flux3-klein/releases/tag/v0.1.1) | 0.1.0 | 0.1.1 | Xcode 27.2 RC, Swift 6.4.2 |

The demo's, Boogu's and ACE-Step's first CI builds, on Xcode 26, ran in this order's checks and were kept; their
repos build on Xcode 27 from now on.

## The wired limit (AB-T-0380): done

Gaea's scheduler configured every worker with `wiresWeights: false` (AB-T-0377 found it), so MLX's wired limit stayed
0 in workers while an in-process engine coordinates it. It is now on. `GAEA_UNWIRED=1` turns it off.

**Why it is safe.** The engine raises a worker's wired limit only while that worker runs, to its resident weights and
that run's transient, capped at the worker's ceiling (Gaea's budget, min'd with Metal's recommended working set), and
drops it to 0 when the run ends. Gaea runs one GPU job at a time (G-13), so one worker at a time holds it, for a job
the governor admitted. At the default budget (103 GB on 128 GB) that ceiling is below the in-process engine's own
automatic one (112 GB), which v0.9.1 ran with.

**Speed:** TierBench v0.10.0's upscale and restore suites through Gaea with forge 0.2.0, against v0.9.1's run from
AB-T-0377 ([wired/](wired)):

| Model | Unwired / v0.9.1 | Wired / v0.9.1 |
|---|---|---|
| Nacre ×4 | 1.17 | 0.98 |
| Nacre ×2 | 1.19 | 0.97 |
| DRUNet | 1.18 | 0.97 |
| SCUNet | 1.51 | 0.95 |
| Every other forge model | 0.91 to 1.11 | 0.90 to 1.05 |

All 145 outputs are byte-identical wired and unwired ([compare-wired-unwired.md](wired/compare-wired-unwired.md)).
TierBench was built from v0.10.0's source on media-engine-spec 0.9.1, since v0.10.0's own pin can't read Gaea's
`assets` feature.

**Three heavy plugins.** `tools/acceptance-governor.sh` (Qwen-Image, Z-Image and Klein under a 70 GB budget), wired
and unwired, with the Mac's wired memory sampled every half second ([governor-wired/](wired/governor-wired),
[governor-unwired/](wired/governor-unwired)):

| | Wired | Unwired |
|---|---|---|
| Checks | 14 of 14 | 14 of 14 |
| The same jobs took | 680 s | 820 s |
| The Mac's wired memory while Qwen-Image-Edit runs | about 81 GB | 33 to 45 GB |
| Its peak (at a load) | 95 GB | 82 GB |

Idle, the Mac has 8 GB wired. The plan's test, "no machine-wide wired total above the budget", can't be met as
written: `vm_stat`'s wired count includes Metal's resident allocations, which pass the 70 GB budget unwired too. What
wiring adds is Edit's own working set held resident during its run, about what the governor admitted for it, and the
limit drops when the run ends.

## The operator's guide

[README.md, "Running a server"](../../../README.md#running-a-server): starting it (app, headless, ports, pairing),
plugins, models (opt-in, the models root, lanes, adapters), memory (the budget, admission, peaks, wiring), trust,
updates, and crashes, including macOS's own "quit unexpectedly" dialog for a worker.

## Updating every plugin in a running Gaea

`tools/acceptance-plugin-updates.sh` against Gaea 0.15.0, 181 of 181 ([acceptance-updates.log](acceptance-updates.log)):
1. **Previous releases:** all 22 installed from GitHub at their previous version, and `gaea plugins check` found each
   one's new release.
2. **An update while a job runs:** Z-Image was updated while it drew four 1024² images. The update said it would switch
   when idle, the row showed it pending, the job finished on 0.1.0, and then Z-Image ran 0.1.2 keeping 0.1.0
   ([z-image-during-update.json](jobs/z-image-during-update.json)).
3. **The other 21** updated at once. Each kept its previous version, and each new bundle imports `mincore` and `msync`
   with a manifest naming contract 1.58.0.
4. **Rollback:** `gaea plugins rollback` took each of the 22 back to its previous version and, run again, forward.
5. **A job on each, on the new version** ([jobs/](jobs)): image, audio and video, LTX's compact24 opted in with its
   licence accepted, and the five research plugins on the research store. The prompt enhancer's result names no
   plugin version, so its run is shown by its worker's session transcript, which is named by version.
6. **Sessions:** all 24 GPP transcripts the run recorded pass `tools/validate.py`.

[plugins-after.txt](plugins-after.txt) is `gaea plugins` at the end; [crashes-after.txt](crashes-after.txt) shows none.

### Found on the way

- **A renamed repo and a token:** a release built before the move to xocialize-code names `xocialize/...` in its
  manifest. Gaea asks GitHub whether the two names are one repo, and GitHub answers the old name with a 301 to
  `repositories/<id>`. URLSession drops `Authorization` on every redirect, so with `GAEA_GITHUB_TOKEN` set the
  follow-up went out anonymous, and once this Mac's 60 anonymous calls an hour were spent it got 403: MOSS-Image 0.1.0
  and prompt-enhance 0.1.0 were refused. `GitHubReleaseSource` now keeps the token on a redirect within the API host,
  never on one to another host (an asset's storage).
- **GitHub's anonymous answers:** without a token, GitHub served a release list for LTX without 0.1.2 (whose tag had
  been moved) while the authenticated list had it, and 60 calls an hour don't cover 22 plugins. The acceptance runs with
  `GAEA_GITHUB_TOKEN`, and the guide says a server with many plugins should set it.
