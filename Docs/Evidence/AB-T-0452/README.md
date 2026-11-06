# AB-T-0452: the IndexTTS 2.5 plugin (G5 order 1)

[gaea-plugin-indextts](https://github.com/xocialize-code/gaea-plugin-indextts) v0.1.1 runs bilibili's IndexTTS 2.5 on
MES Audio 0.1 `audio.speak` through Gaea 1.0.0. It is built from mlx-indextts2-swift 0.6.0 and mlx-engine-swift 0.74.1,
on the fleet's mlx-swift fork (0.33.0, which carries the leak fix). All runs were on an M5 Max (128 GB, macOS 27.3),
with the plugin from its CI-built, notarized GitHub release.

## Results

**`tools/acceptance-indextts.sh`: 44 passed, 0 failed** (`acceptance.log`). Each case clones the plugin's fixture
(`scripts/fixtures/ref-en.wav`, 4.8 s), kept as an asset.

- **The offer:** `indextts-2.5` beside `kokoro-82m`. It takes `voice_ref` only, five languages, nine emotion labels
  with intensity, `speed` and `target_duration`, at 22.05 kHz, and declares `x-indextts.emotion_vector`.
- **Byte for byte against `indextts-inproc`:** plain English on fp16 and on the int8 lane (`x-gaea.lane`), happy at
  0.8, the emotion vector, a 4 s fit around a half-second pause, speed 1.3, Chinese and Spanish.
- **Effective values:** the language and seed, the emotion and `x-indextts.emo_alpha`. The fit lands within 0.1 s
  with no `duration_missed`. Japanese and Arabic are detected from their script.
- **Routing:** a `voice_ref` with no model named goes to IndexTTS; plain text goes to Kokoro.
- **The reference cache (MES Base §13):**
  - a second job on the asset gives the same WAV;
  - the run carries the asset id, and deleting the asset sends `asset_removed`;
  - the same clip as an upload, keyed by its job and evicted after, gives the same WAV.
- **Reference formats:** 24-bit, float and FLAC are accepted. Stereo is mixed down (`audio_downmixed`), and a 30 s clip
  is trimmed to 20 s (`voice_ref_trimmed`).
- **Refused at submit (422):** no `voice_ref`, French, `excited`, and a three-weight vector (by the declared schema).
- **Failed at run:** a label with a vector (`invalid_request`), and a 5 s target around a 5 s pause (`out_of_limits`).
- **Transcripts:** every recorded GPP session passes `validate.py`.

**Timings:** a cold first job took 3.6 s from submit to settled (launch, prepare fp16, speak). Warm runs took 1.7–2.3 s
for 4–5 s of speech. In-process: prepare 0.7 s, run 2.8 s, max RSS 4.6 GB.

**In the plugin repo:** `scripts/golden.sh` passes 16/16 over GPP against in-process, and `scripts/check-plugin.sh`
passes, including the metallib control.

## What it found

- **Both packages kept a voice cache MES forbids.** mlx-indextts2-swift 0.5.0 and mlx-voxcpm2-tts-swift 0.5.0 kept
  the last reference's conditioning keyed by its bytes, which MES Base §13 rules 4 and 6 forbid. mlx-audio added
  Qwen3's caller-keyed cache and its eviction in 0.6.0 of both (AB-A-0251), and v0.1.0 was held for it.
- **0.1.0 left its extension undeclared.** MES carries an extension in a request's `extensions`, admitted only when an
  offer declares it in `params` (Base §6.2). 0.1.0 declared none, so Gaea refused the emotion vector at submit; 0.1.1
  declares it.
