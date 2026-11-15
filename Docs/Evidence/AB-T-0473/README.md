# AB-T-0473: Gaea's leftovers from the SAM-Audio work

2026-11-15, Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3). The released Gaea 1.8.0 app, headless on throwaway
homes; plugins from GitHub.

| Item | What was done | Result |
|---|---|---|
| 1. `TrustTests` race | `Releases.files` was a static dictionary every `manager()` call rewrote, while other suites (CrashTests, FirstUseTests, OperatorControlsTests) called it in parallel. It is now built once and never written again | `swift test` 20 runs in a row, 113 passed each, then one full run. The 20 ran with `GAEA_TEST_SKIP_TRAP=1` |
| 2. The kit's hard-coded engine version | GaeaPluginKit 0.14.1: the engine release in a manifest and `hello` is the linked MLXToolKit's own (`MLXEngineRelease.version`), as the contract already was | Kit tests 42 passed; tagged `v0.14.1` |
| 3. Gaea Lab on the current MES | `Apps/GaeaLab` on media-engine-spec 0.14.0; `--snapshot … --describe <sound>` renders a described separation | [lab-describe.log](lab-describe.log): 6 passed, 0 failed; [the form](lab-described-separation.png) |
| 4. SAM-Audio's acceptance and the run with every plugin | `tools/acceptance-sam-audio.sh` | [acceptance-sam-audio.log](acceptance-sam-audio.log): 32 passed, 0 failed. Conformance with all 28 plugins and `sam-audio-base` enabled: 107 passed, 0 failed, 9 skipped ([Gaea-1.8.0/conformance-all.md](../Gaea-1.8.0/conformance-all.md)) |

## Item 1: why the 20 runs skipped one test

`CrashTests.aTrapIsRecordedWithItsReport` makes the demo worker trap on purpose, and each run leaves two real crash
reports of `gaea-demo-worker` with macOS. `GAEA_TEST_SKIP_TRAP=1` skips it, so a loop doesn't leave forty. It runs by
default, and it ran in the full run after the loop.

## Item 4: what the SAM-Audio acceptance shows

SAM-Audio 0.1.0 from GitHub beside the demo:

- **Opt-in.** `sam-audio-base` is off until the operator enables it.
- **The offer.** The SAM licence (commercial use allowed, `accepted_required`, `user_accept_required`, a notice),
  `described_target`, `spans`, the `target` and `residual` stems, `stem_method: regenerated`, an AudioSeal watermark,
  at most 30 s.
- **Not named-only.** The licence allows commercial use, so Gaea doesn't mark the offer named-only. A separate job with
  a description and no model runs on SAM-Audio, the only offer that takes one. One with no description runs on the
  demo's separator.
- **Users' acceptance.** Without `policy.accepted` a job is 422 `policy_unmet` (`terms_not_accepted`), named or not.
- **Described separations.** "speech" (both stems), the target alone from untrimmed mixed-case text
  (`effective.describe` is "speech"), and "music" with two spans (`effective.spans` echoes them). Each stem is the
  mixture's length at 48 kHz mono, and byte for byte `sam-audio-inproc`'s. The same seed gives the same bytes.
- **Refusals.** No description, a description of 201 characters, 33 spans, a span that ends before it starts (400), a
  labelled stem with a description, a span past the mixture's end and a mixture of 32 s (both `out_of_limits` when the
  job runs).

Times: the first separation 9.0 s with the load, then 2.3 s for the 8 s mixture.

## Not covered

- **A notarized Gaea Lab build.** The Lab was built and run from the tree; `scripts/build-lab.sh` wasn't run.
- **How well SAM-Audio separates.** The checks are on the contract and on identity with the in-process run, not on
  the sound.
- **The watermark.** The offer declares it; nothing here detected it in the stems.
