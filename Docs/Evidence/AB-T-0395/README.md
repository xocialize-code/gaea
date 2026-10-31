# AB-T-0395: G2's exit — Audio conformance passes, and Gaea Lab covers audio

| | |
|---|---|
| **Date** | 2026-10-31 |
| **Gaea** | 0.9.3 (589400b), with the five audio plugins installed from GitHub: Kokoro 0.1.0, Qwen3-TTS 0.2.0, Step-Audio-EditX 0.1.0, MOSS-SoundEffect 0.1.1, ACE-Step 0.1.0 |
| **Gaea Lab** | on pixel-agency-run 0.2.0 (b70fb99, AB-A-0234, receipt AB-R-0684) and media-engine-spec 0.8.0 |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every WAV, report and session are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0395` |

## Done =

| Part | Result |
|---|---|
| mes-conformance Audio 0.1 conforms with every G2 plugin | **Yes:** 65 passed, 0 failed, 10 skipped with every G1 plugin and the five audio plugins, under media-engine-spec v0.7.0's suite as shipped; Base, Image and Audio 0.1 conform, and all 14 Audio tests run and pass ([AB-T-0399's report](../AB-T-0399/conformance/report.md), AB-R-0683) |
| Lab runs speak (streamed), design, edit, generate and compose against Gaea | **Yes, 30 of 30** ([lab-audio.log](lab-audio.log), `tools/lab-audio.sh`): through `lab-run` (the Lab's `RunSession` over its `EnginePool`) and through the app itself |
| Receipt | AB-R-0685 |

## What it took

| Piece | Where | What |
|---|---|---|
| The run workflow | pixel-agency-run 0.2.0 (mlx-apps, AB-A-0234, through a chip) | Audio in the workflow Gaea Lab and Pixel Agency Desktop share. Audio inputs are MESFormsUI's audio wells. The voice picker gets the model's voices and samples. Audio results play in the canvas, and data results show as text. A streamed run plays as it arrives, with Stop releasing the job, and its final file is still collected. `pa-run --stream` |
| The pool | Gaea Lab (db51faa) | `EnginePool` on media-engine-spec 0.8.0. An asset is kept on every server under one pool id, and a job gets the chosen server's own copy. Voices come from the server that lists them for the model, and so do their samples |
| The Lab | Gaea Lab | Adopts pixel-agency-run 0.2.0. `lab-run --stream <output>` writes the chunks as they arrive, and `lab-run --voices` lists a model's voices through the pool. `GaeaLabApp --snapshot … --operation audio.speak \| audio.compose` renders an audio run |

## What the run shows

Through `lab-run`, against a fresh Gaea with the five plugins installed by repo URL:
- **speak on Kokoro, streamed:** the first chunk came about 1 s after submitting. The chunks written as they arrived are
  the final file's samples, byte for byte.
- **speak on Qwen3-TTS** with Ryan and an angry delivery.
- **design_voice:** two samples.
- **edit_speech:** a laugh added at the end, with the new transcript saved as the transcript output.
- **generate:** two 1.5 s sounds of 72 000 frames each.
- **compose:** a 10 s stereo song of 480 000 frames, with its timed lines saved.
- **Voices:** the pool lists Kokoro's 28 voices and Qwen3-TTS's 9.
- Every recorded GPP session passes the validator.

Through the app (`GaeaLabApp --snapshot`), on "Every server":
- **Speak on Kokoro, with the voice Heart:** streamed in 3 chunks, the first after 0.75 s; the take, 6.4 s, then plays
  back ([light](lab-audio.speak-after-light.png), [dark](lab-audio.speak-after-dark.png),
  [before](lab-audio.speak-before-light.png)).
- **Compose on ACE-Step:** the song's player (10 s, 48 kHz stereo) and its timestamps as a text result
  ([light](lab-audio.compose-after-light.png), [dark](lab-audio.compose-after-dark.png)).

## Found on the way

- **Pixel Agency Desktop needs one line for MESClientKit 0.8.0.** MESClientKit's new public `AssetLibrary` makes
  `AssetLibrary.SweepReport` (Desktop's `Sources/PixelAgencyCore/Desktop.swift:59`) ambiguous with ImageLibrary's. The
  fix is to qualify it. The chip built Desktop with it (93/93 tests pass on pixel-agency-run 0.2.0) but didn't commit in
  Desktop. It's mlx-apps' follow-up, and any Desktop resolve that reaches media-engine-spec 0.8.0 hits it.
- **An audio input with `max` above 1** takes one file in the Lab, because MESFormsUI's `AudioInputWell` holds one. No
  Audio 0.1 operation has such an input today.
- **The run script itself raced Gaea's shutdown** on its first runs: it copied a worker's session before Gaea had closed
  it. `tools/lab-audio.sh` now waits for Gaea to exit before it copies.

## Not covered here

- **Barge-in through the Lab against Gaea.** pixel-agency-run's tests cover a cancel on the first chunk against the mock
  (1 chunk passed, the job cancelled). Through Gaea, Kokoro's acceptance covers a release mid-stream (AB-T-0393). The two
  weren't run together.
- **The notarized Lab build** (`scripts/build-lab.sh`) wasn't rebuilt. The run used the release build from `swift build`.
