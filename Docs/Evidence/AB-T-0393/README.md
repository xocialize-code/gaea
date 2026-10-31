# AB-T-0393: Kokoro-82M, the first audio plugin (with AB-T-0391 and AB-T-0392)

| | |
|---|---|
| **Date** | 2026-10-31 |
| **Plugin** | [gaea-plugin-kokoro 0.1.0](https://github.com/xocialize-code/gaea-plugin-kokoro/releases/tag/v0.1.0) (c455d4c), on mlx-kokoro-tts-swift 0.5.0 and GaeaPluginKit 0.7.1. Built, signed, notarized (submission 823ad76e-…) and stapled by its release workflow, the first MLX plugin released by CI from scratch (AB-T-0382) |
| **Gaea** | 0.9.0 (35de472): MESKit 0.7.0, GaeaPluginKit 0.7.1 |
| **Spec** | MES Audio 0.1 and Base §7.2, §11 (media-engine-spec v0.7.0, AB-A-0232); GPP-1 §3.3.1, §3.3.2, §4.3 |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every WAV, the job records and the event streams are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0393` |

## What it took

| Piece | Where | What |
|---|---|---|
| The protocol | GPP-1, `schemas/v1`, `tools/validate.py` (AB-T-0391) | `run.streams` and `run.assets`, `asset_removed`. A streamed output's chunks are PCM files, `pcm_f32le` or `pcm_s16le`, and the result lists it as `streamed`. An offer's MES `supports` and `limits` go in its `model`, and its preset voices in `voices`. The validator checks chunk numbering and the streamed result |
| The kit | GaeaPluginKit 0.7.0, 0.7.1 (AB-T-0391) | `RunContext.emit`, `EngineSession.emit` (floats, or 16-bit as the package made them), `EngineSession.stream` for a `StreamEmitting` package, `Output.streamed`, `Job.streams` and `Job.assets`, `onAssetRemoved` |
| The host | `GaeaAudio`, `AudioPCM` (AB-T-0392) | Audio offers run as themselves. Descriptors come from AudioProfile's tables and the offers' own keys, and `AudioProfileRules` gates and routes. Gaea converts each chunk to the client's stream plan (with `AVAudioConverter`, its state kept across chunks) and each file to the request's `output`; 16-bit chunks already in the client's format pass through. `voices()` reads the offers, and `assetRemoved()` reaches the running audio workers. A streaming run is never requeued |
| The plugin | gaea-plugin-kokoro 0.1.0 | `audio.speak`, 28 English voices. The text is cut into sentence pieces of at most 300 characters, with `[pause Ns]` as silence. Each piece streams as soon as it's drawn, and MLX's random state is seeded per job |

## Result

| Done = | Result |
|---|---|
| Over GPP, byte for byte | **Pass, 8 of 8** ([golden.log](golden.log)): four seeded jobs on the signed bundle and through `kokoro-inproc`: one piece, three with a pause, nine pieces of a 2,000-character text, and seed 0. Their sessions pass the validator |
| Through Gaea, installed from GitHub | **Pass, 34 of 34** ([acceptance.log](acceptance.log), `tools/acceptance-kokoro.sh`, `REPO_FROM=github`): see the list below |
| Conformance | **With every G1 plugin and Kokoro: 58 passed, 0 failed, 17 skipped; Base 0.1, Image 0.1 and Audio 0.1 conform** ([report](conformance/report.md)), under media-engine-spec v0.7.0's suite as shipped. The streaming tests (BASE-053 to 057, including a release mid-stream) and AUDIO-001 to 007 and 014 pass. The skips are the operations no plugin offers yet (design_voice, edit_speech, generate, compose) and paired mode |

What the 34 acceptance checks cover:
- **The offer:** `audio.speak` lists `kokoro-82m` with streaming, 28 voices and `max_text_chars` 4000. `GET …/voices` lists the voices, `af_heart` the default, and the engine reports Audio 0.1 and the `streaming` and `assets` features.
- **Voices:** `af_heart` at seed 42 is a 24 kHz mono 16-bit WAV, and kokoro-inproc's byte for byte. So are `am_adam`, `bf_emma` and `bm_lewis`, and each sounds different. Every one of the 28 voices speaks.
- **Streaming:** the `job.output_chunk` events are numbered in order, the last final, and they rebuild the job's WAV exactly. The same request without streaming is that WAV byte for byte, and so is kokoro-inproc's.
- **The client's format:** a `pcm_f32le` stream at 48 kHz stereo gives a 32-bit float WAV as long as the 24 kHz one, and a file at 16 kHz 24-bit; both warn `audio_resampled`.
- **Text:** `[pause 2s]` adds two seconds of digital silence. An unsupported cue (`[laugh]`) is dropped with `cue_unsupported`. A 2,000-character text is drawn in pieces, byte for byte as in process. A different seed gives different audio, and a job without one reports the seed it used.
- **Refusals:** a voice reference, an unknown voice, an emotion and French are 422 `unsupported_parameter`, 4,001 characters is 422 `out_of_limits`, and no text is 400.
- **Barge-in:** a streamed 4,000-character job deleted at its first chunk settles `cancelled` 0.05 s later. The worker's run ends `cancelled`, and the next job is the first `af_heart` WAV again.

| Job (bf16, warm) | Speech | Run |
|---|---|---|
| One sentence, one piece | 5.35 s | 0.35 s |
| Three pieces with a pause | 10.8 s | 0.78 s |
| 2,000 characters, nine pieces | 121.7 s | 2.7 s |
| The first job, cold (worker launch, prepare, speak) | 5.35 s | 1.4 s from submit to settled |

## Found on the way

- **Kokoro isn't deterministic on its own.** Its sine source draws its phase and noise from MLX's global random state,
  so two runs of the same text differ. The worker seeds that state with the job's seed before the first piece. That
  makes the model seeded (`supports.seed` true) and makes parity byte for byte.
- **Floats lose 16-bit samples.** The package returns a 16-bit WAV. Sent as floats and converted back, a sample like
  16384 can come back as 16383. Kit 0.7.1 sends 16-bit chunks as they are, and Gaea passes them to a `pcm_s16le`
  client untouched.
- **A directory symlink in MLXEngine's store fails the store probe** with "Not a directory". Kokoro's 339 MB snapshot
  is copied into the store from `/Volumes/DEV_VOL1/Models/Models` instead.
- **The plugin's CI checks out Gaea's spec at main**, so a release that needs new schema fields must follow the Gaea
  push. The first run of v0.1.0 failed validation for that reason, and the re-run passed.
- **The suite reports "Image 0.1: conforms" for an engine with no Image offer.** With Kokoro alone, Gaea offers no
  Image operation, and the report still says the profile conforms. A note for mlx-apps.
- **The worker's footprint after a run is about 2.75 GB** against the 500 MB its package declares, most of it MLX's
  buffer cache. Gaea charges an idle worker the larger of the two.

## Not covered

- **Assets with a plugin that caches.** Kokoro has no voice reference, so nothing is keyed by an asset id yet.
  `run.assets` and `asset_removed` are unit-tested in the kit and the host. They are exercised end to end with the
  first cloning plugin (Qwen3-TTS, AB-T-0394).
- **Gaea Lab on audio.** It waits on MESClientKit's assets, voices and chunks, committed by mlx-apps but not released
  yet (AB-T-0395).
