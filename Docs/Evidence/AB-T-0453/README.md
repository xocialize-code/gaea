# AB-T-0453: the VoxCPM2 plugin (G5 order 2)

[gaea-plugin-voxcpm2](https://github.com/xocialize-code/gaea-plugin-voxcpm2) v0.1.0 runs OpenBMB's VoxCPM2 on MES
Audio 0.1 `audio.speak` and `audio.design_voice` through Gaea 1.0.0. It is built from mlx-voxcpm2-tts-swift 0.6.0 and
mlx-engine-swift 0.74.1, on the fleet's mlx-swift fork. All runs were on an M5 Max (128 GB, macOS 27.3), with the
plugin from its CI-built, notarized GitHub release, installed beside Kokoro and IndexTTS 2.5.

## Results

**`tools/acceptance-voxcpm2.sh`: 44 passed, 0 failed** (`acceptance.log`).

- **The offers:** `voxcpm2` on `audio.speak` has a default voice, `voice_ref`, `voice_ref_text: optional`, 30
  languages, emotions and descriptions, and 48 kHz; it declares no `speed` and no `target_duration`. On
  `audio.design_voice` it takes 1–4 samples in 12 languages.
- **Byte for byte against `voxcpm2-inproc`:** the default voice, happy with a pause, a delivery description, Chinese, a
  clone of the fixture, its continuation clone, two designed samples, and the first sample cloned back from its asset
  with its text.
- **Effective values:** each speak reports its voice mode (`default`, `clone`, `continuation`), and a design reports
  its seed and sample text. An intensity is ignored with `emotion_intensity_ignored`.
- **The reference cache (MES Base §13):** a second job on the asset gives the same WAV; the run carries the asset id;
  deleting the asset sends `asset_removed`.
- **Routing:** with no model named, among Kokoro, IndexTTS and VoxCPM2:
  - a description with no reference goes to VoxCPM2;
  - a reference with a description goes to VoxCPM2;
  - a reference with `target_duration_s` goes to IndexTTS;
  - `design_voice` goes to VoxCPM2.
- **Reference formats:** 24-bit, float and FLAC are accepted. Stereo is mixed down, and a 30 s clip is trimmed to 20 s,
  each with its warning.
- **Refused at submit (422):** `excited`, Ukrainian, Thai for a design (no sample sentence), `target_duration_s`, and
  five samples.
- **Transcripts:** every recorded GPP session passes `validate.py`.

**Timings:** a cold first job took 3.8 s from submit to settled. In-process: prepare 0.5 s, and 2.5 s for 5.4 s of
speech.

**In the plugin repo:** `scripts/golden.sh` passes 17/17 byte for byte over GPP against in-process, and
`scripts/check-plugin.sh` passes, including the metallib control.

## Notes

- **One model on two operations.** One `voxcpm2` model backs both offers, so the 9.3 GB checkpoint loads once. GPP-1
  §4.7 allows a model on several operations.
- **Language.** VoxCPM2 takes no language input, so `language` is a gate. It is reported in `effective` only when the
  request names it.
- **Gates checked before the plugin runs.** The offer's gates (emotion labels, languages, no duration control) are
  enforced by MESKit at submit, as the routing and refusal checks show.
