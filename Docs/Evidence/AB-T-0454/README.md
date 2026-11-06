# AB-T-0454: `audio.separate` and the shared edit mapping (G5 order 4), Gaea 1.1.0

MES v0.10.0 (RFC 0006, AB-A-0250) adds `audio.separate` and what AuK's editor needs. This order puts them in Gaea and
in GaeaPluginKit, ahead of the AuK plugin (order 5). Runs were on an M5 Max (128 GB, macOS 27.3).

## Gaea

- **`audio.separate` (Audio §3.6):** in `Sources/GaeaCore/Engine/GaeaAudio.swift`.
  - The descriptor's outputs are the stems the installed offers make, in the registry's order, each optional.
  - The mixture is bounded by the offer's `max_duration_s`: refused `out_of_limits`, never trimmed.
  - The worker is sent exactly the stems the plan names.
- **MESKit 0.10.0:** its `AudioProfileRules` gate stems, speaker picks, and `edit_speech`'s new keys (`dereverb`,
  `hum`, `cue_placement`, `remove_all_cues`, `target_duration_s`).
- **Tests:** `swift test` 81/81, including the separate descriptor and the mixture limit.
- **Examples:** the manifests and transcripts move to mlx-engine-swift 0.74.1 (contract 1.59.0). `tools/validate.py`
  and the 78 negative cases pass.

## GaeaPluginKit 0.11.0

- **`SpeechEdits.operation`:** every MES edit kind as the engine's `SpeechEditOperation`.
  - Labels come from the model's vocabulary, and speed, pitch and volume snap to its grids with `param_adjusted`.
  - An edge cue becomes `addNonverbal`, unless the plugin adds cues its own way through a hook.
  - Content edits return the new transcript.
- **`AudioSeparations`:** builds the separation request from a job, and writes each returned stem as an output named
  by it.
- **The engine:** moves to mlx-engine-swift 0.74.1, and manifests and hello say so.
- **Tests:** 31/31.

## The plugins

- **Step-Audio-EditX 0.1.2** moves its edit plan onto the kit. Every golden output is byte-identical to 0.1.1's: 9
  WAVs, with the same returned transcripts (golden 21/21). Its root now names the mlx-swift fork.
- **Demo 0.4.0** adds `demo-separator`, a masked stand-in. Its `vocals` stem is the mixture at half level and
  `instrumental` the rest, so the two add back to the mixture.

## Conformance (`conformance/`)

MES v0.10.0's `mes-conformance` against Gaea from main, with all 24 public plugins from GitHub (`ALL=1
tools/conformance-with.sh`): **88 passed, 0 failed, 7 skipped.** Base, Image, Audio and Video 0.1 conform.

- **AUDIO-015** (stems run, named, the mixture's length) and **AUDIO-016** (refusals) pass on `demo-separator`.
- **AUDIO-018** passes on `target_duration_s`.
- **AUDIO-017** passes vacuously: no separate offer here limits its mixture to 300 s or less. The refusal is covered by
  Gaea's unit test, and AuK's 30 s limit will exercise it in order 5.
