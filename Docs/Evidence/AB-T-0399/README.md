# AB-T-0399: ACE-Step 1.5 as a Gaea plugin (audio.compose)

| | |
|---|---|
| **Date** | 2026-10-31 |
| **Plugin** | [gaea-plugin-ace-step 0.1.0](https://github.com/xocialize-code/gaea-plugin-ace-step/releases/tag/v0.1.0) (f2ff147), on mlx-ace-step-swift 0.3.0 and GaeaPluginKit 0.8.0. Built, signed, notarized and stapled by its release workflow |
| **Gaea** | 0.9.3 (589400b): a compose repaint outside its source is 422 `out_of_limits` |
| **Spec** | MES Audio 0.1 §3.5, §4.1, §4.2 (media-engine-spec v0.7.0) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every WAV, job record and session are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0399` |
| **Weights** | the int8 lane's four bundles, copied into MLXEngine's store from mlx-engine's converter output (`mlxengine-audio/WIP/acestep-port/weights`), under the mlx-community names the package resolves |

## What it took

| Piece | Where | What |
|---|---|---|
| The host | Gaea 0.9.3 | Audio §3.5 says a repaint span must lie inside the source, which only the source's length can tell, so Gaea checks it beside the input lengths it measures since 0.9.2. Outside is 422 `out_of_limits` on `edit` |
| The plugin | gaea-plugin-ace-step 0.1.0 | One model, `ace-step-1.5`, on `audio.compose`, with lanes int8 (the default), bf16 and int4. 48 kHz stereo, 10 to 600 s. Listed below |
| The package | none | mlx-ace-step-swift 0.3.0 as released (`Capability.music`): every MES compose feature but a score. No ask was needed |

What the plugin offers:
- **Songs from a caption and lyrics.** MES section tags are written as ACE-Step's (`[pre-chorus]` → `[Pre-Chorus]`,
  directions kept). Untagged lyrics are one `[Verse]`. Another bracketed line is dropped with `section_unsupported`, and no
  lyrics make an instrumental.
- **Language:** the planner's 50.
- **Anchors** are pinned, and the settled ones come back as `effective.anchors`.
- **Timestamps:** the LRC lines, as the `timestamps` output.
- **A reference's timbre**, and `cover`, `repaint` and `extend` of a source.
- **Edit lengths.** An edit's song is cut to its MES length: the source's, plus an extend's `before_s` and `after_s`. The
  package decodes whole latent windows, so an extend of 1 + 2 + 1.5 s came back 5.12 s, with the 4.5 s song at its start.
- **No score:** `supports.score` is absent, so `planning` and a score are refused by MESKit's gate.
- **One quality tier:** the DiT is a turbo distilled to eight steps.

## Result

| Done = | Result |
|---|---|
| Over GPP, byte for byte | **Pass, 17 of 17** ([golden.log](golden.log)): eight seeded songs, each `ace-step-inproc`'s WAV and of the MES length; the pinned anchors come back; every session passes the validator |
| Through Gaea, installed from GitHub | **Pass, 21 of 21** ([acceptance.log](acceptance.log), `tools/acceptance-ace-step.sh`, `REPO_FROM=github`): see the list below |
| Conformance | **With every G1 plugin and the five audio plugins: 65 passed, 0 failed, 10 skipped; Base 0.1, Image 0.1 and Audio 0.1 conform** ([report](conformance/report.md)), under v0.7.0's suite as shipped. AUDIO-011, 012 and 013 now run and pass, so all 14 Audio tests run. The skips are paired mode, expiry waits, Image's decompose (ming-image-layer isn't in this set) and BASE-017 (no unseeded model) |

The golden cases (int8):
- a 10 s song;
- a 30 s waltz with 96 bpm, F# minor and 3/4 pinned;
- a 15 s instrumental;
- a 12 s Chinese song;
- a 10 s song with a reference;
- a 2 s source (cut from a song this model made) covered at 0.7, repainted from 0.5 to 1.5 s, and extended by 1 s before
  and 1.5 s after (4.5 s, 216 000 frames).

What the 21 acceptance checks cover:
- **The offer:** `audio.compose` lists `ace-step-1.5` with 50 languages, instrumental, reference, the three edits, the
  anchors, timestamps, the eight sections, 48 kHz stereo and 10 to 600 s, and no score.
- **Songs:**
  - a 10 s song with timestamps: its facts, effective seed, duration, language and anchors; its lines timed in order;
  - an instrumental;
  - pinned anchors reported back;
  - a reference from an asset;
  - an unknown section tag dropped with `section_unsupported`.
- **Edits on an uploaded source:** extend to 216 000 frames; repaint and cover at the source's 96 000.
- **Refusals:**
  - a score, `planning`, a 5 s song and Klingon are each 422;
  - a repaint past the source's end is 422 `out_of_limits` on `edit`;
  - an edit without a source, and a source without an edit, are each 400.
- **Parity:** the song, the extend and the repaint through Gaea are `ace-step-inproc`'s byte for byte.

| Job (int8, warm) | Worker |
|---|---|
| A 10 s song | 5.8 s |
| A 30 s song, anchors pinned | 5.6 s |
| A 15 s instrumental | 6.4 s |
| Cover, repaint or extend of a 2 s source | 0.4 s |
| The first job through Gaea (worker launch, prepare, a 10 s song) | 7.8 s from submit to settled |

The planner's plan dominates a short song, so 10 s and 30 s take about as long. In-process the worker peaks at 9.4 GB
RSS; through the plugin check its phys_footprint was 11.5 GB after a 10 s song and peaked at 13.2 GB.

## Found on the way

- **The package's edits come back longer than asked** (whole latent windows, 40 ms each, rounded up to a multiple). The
  plugin cuts them to the MES length. The package could crop to the padded source's length itself.
- **The edit keeps the source's shape, not its level.** The extend's middle and the repaint's kept parts correlate with the
  source at 1.000, but at −0.5 to +0.6 dB, because the package normalizes every song's peak to −1 dBFS. Audio §3.5 says
  the source "plays unchanged"; a level-preserving splice would need the package to skip its normalization on edits.
- **Gaea had no way to bound a repaint by its source.** MESKit checks the span's own length (`max_repaint_s`); only the
  engine knows the source's. 0.9.3 does.

## Not covered

- **The bf16 and int4 lanes.** Their bundles weren't copied into the store; they share the code path, and their
  footprints are declared.
- **A song's duration when none is asked for.** The planner decides it, and Gaea reports it; no case pinned it.
- **Listening.** The songs were compared byte for byte, timed and measured, not listened to.
