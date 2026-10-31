# AB-T-0396: Qwen3-TTS as a Gaea plugin (speak, clone, design_voice)

| | |
|---|---|
| **Date** | 2026-10-31 |
| **Plugin** | [gaea-plugin-qwen3-tts 0.2.0](https://github.com/xocialize-code/gaea-plugin-qwen3-tts/releases/tag/v0.2.0) (d38b026), on mlx-qwen3-tts-swift 0.7.0 and GaeaPluginKit 0.8.0. Built, signed, notarized (submission 9d29bd5d-…) and stapled by its release workflow. 0.1.0 (speak and design only) was released the same way first |
| **Gaea** | 0.9.1 (9ae59ea): audio inputs reach workers as canonical 16-bit WAVs |
| **Spec** | MES Audio 0.1 §3.1, §3.2 and Base §8.1, §13 rule 6 (media-engine-spec v0.7.0); GPP-1 §3.3.2 |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every WAV and job record are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0396` |

## What it took

| Piece | Where | What |
|---|---|---|
| The clone cache | mlx-qwen3-tts-swift 0.7.0, qwen3-tts-mlx-swift 0.2.0 (mlx-audio, AB-A-0233, receipt AB-R-0679) | The package kept the last clone prompt across calls, keyed by the reference's bytes, which MES Base §13 rules 4 and 6 forbid. Now `metaData["voiceCacheKey"]` keys the reference's bytes-only features (the speaker embedding, the codec codes), an empty-text request with `evictVoiceCacheKeys` drops them, and the seed reaches both clone paths |
| The kit | GaeaPluginKit 0.8.0 | `onAssetRemoved(asset, resident)`: `ResidentEngine.run(request, model:)` sends a package its own eviction call while it is loaded, and does nothing when it isn't |
| The host | Gaea 0.9.1 | Audio inputs take WAV at any depth, FLAC, MP3 and AAC. One that is already a canonical 16-bit WAV passes untouched, and any other is decoded with AVAudioFile and written as one, because the package's loader reads only that |
| The plugin | gaea-plugin-qwen3-tts 0.2.0 | Three 1.7B checkpoints, each on int8 (the default), bf16 and int4. `qwen3-tts` (CustomVoice) speaks with nine voices, E12 emotion labels or a described delivery, in ten languages. `qwen3-tts-clone` (Base) clones from `voice_ref`, in context with `voice_ref_text` and from the embedding without it. A reference is keyed by its asset id (evicted on `asset_removed`) or by its job (evicted at the end). `qwen3-tts-design` (VoiceDesign) gives `count` samples at seed + i. MLX's random state is seeded before every generation |

## Result

| Done = | Result |
|---|---|
| Over GPP, byte for byte | **Pass, 15 of 15** ([golden.log](golden.log)): Ryan neutral and angry, Aiden with a described delivery, Vivian in Chinese with a pause, two designed samples, and the first sample cloned in context and from its embedding, each `qwen3-inproc`'s WAV. Their sessions pass the validator |
| Through Gaea, installed from GitHub | **Pass, 39 of 39** ([acceptance.log](acceptance.log), `tools/acceptance-qwen3-tts.sh`, `REPO_FROM=github`, beside Kokoro): see the list below |
| Conformance | **With every G1 plugin, Kokoro and Qwen3-TTS: 60 passed, 0 failed, 15 skipped; Base 0.1, Image 0.1 and Audio 0.1 conform** ([report](conformance/report.md)), under v0.7.0's suite as shipped. These now run and pass where they skipped before: AUDIO-004 (WAV at 16 and 24 bits, float, FLAC), AUDIO-005 (voice → kokoro-82m, voice_ref → qwen3-tts-clone, neither → kokoro-82m), AUDIO-006 (labels), AUDIO-008 (design, its seed, and a sample cloned), and BASE-032 (assets used by two jobs, then deleted) |

What the 39 acceptance checks cover:
- **The offers:** `audio.speak` lists `qwen3-tts` with 9 voices, the emotions, descriptions and 10 languages, and `qwen3-tts-clone` with `voice_ref`, an optional transcript and 30 s at most, beside `kokoro-82m`. `audio.design_voice` lists `qwen3-tts-design`, 4 samples at most.
- **Speech:** Ryan, Ryan angry, Aiden with a described delivery and Vivian in Chinese with a pause are each `qwen3-inproc`'s WAV byte for byte. An emotion's intensity is ignored, with `emotion_intensity_ignored`.
- **Routing with no model named:** a Qwen voice goes to Qwen and a Kokoro voice to Kokoro. An emotion or French goes to Qwen, and plain English to the default.
- **Design:** two samples at seed 7 and 8 come back with the sample text, each in-process's byte for byte. Five is 422.
- **Cloning:**
  - **Through an asset:** the first designed sample, kept as an asset, clones back in context, `qwen3-inproc`'s byte for byte. A second job on the asset gives the same WAV. The worker's run carries the asset id, and deleting the asset (204) sends `asset_removed`.
  - **From the embedding alone:** without the text, the x-vector clone is in-process's byte for byte.
  - **Input formats:** 24-bit WAV, float WAV and FLAC references are accepted.
  - **Long and stereo references:** a stereo reference is mixed down, and a 40 s one trimmed to 30 s, each with its warning.
- **Refusals:** an emotion outside the list, Dutch, and a Qwen voice on Kokoro are each 422. A voice with a `voice_ref` and `voice_ref_text` without a `voice_ref` are each 400.

| Job (int8, warm) | Speech | Run |
|---|---|---|
| Ryan, one sentence | 6.7 s | 2.1 s |
| Ryan angry | 4.6 s | 1.5 s |
| Two designed samples | 9.0 s | 3.0 s |
| A clone in context, a short line | 4.4 s | 1.4 s |
| The first job, cold (worker launch, prepare, speak) | 6.7 s | 4.2 s from submit to settled |

## Found on the way

- **The package's clone cache broke MES's rules on inputs**, so cloning waited on mlx-audio (AB-A-0233). Plugin 0.1.0
  shipped speak and design first, and 0.2.0 added cloning on the fixed package.
- **The package reads only canonical 16-bit WAVs.** A 24-bit, float, extensible or FLAC reference failed inside the
  worker. Gaea now gives every audio input to workers in that one form, and AUDIO-004 passes.
- **Qwen's talker samples from MLX's global random state**, as Kokoro's sine source does. The worker seeds it before
  every generation, and the package now passes its own seed to the clone paths.
- **The cached reference saves little on a short line.** In the run from GitHub the two clone jobs took 1.48 s and
  1.37 s. The 3.8 s of the first stand-in run was the model's first kernels, not the reference's encoding.
- **Gaea reads GitHub through one place.** `GAEA_GITHUB_API` is the server's setting, not the CLI's, so a stand-in run
  serves every plugin it installs: the Qwen acceptance puts Kokoro's published release in the stand-in too.

## Not covered

- **Streaming.** The package has no `StreamEmitting` yet (the ask's optional part), so no Qwen offer streams.
- **bf16 and int4 lanes** weren't run. They share the code path, and the package's footprints declare them.
- **Asset expiry** (BASE-034) needs the suite's `--max-ttl-wait 75` and was skipped. Deletion (BASE-032 and the
  acceptance) sends the same `asset_removed`.
