# AB-T-0397: Step-Audio-EditX as a Gaea plugin (audio.edit_speech)

| | |
|---|---|
| **Date** | 2026-10-31 |
| **Plugin** | [gaea-plugin-step-audio-editx 0.1.0](https://github.com/xocialize-code/gaea-plugin-step-audio-editx/releases/tag/v0.1.0) (3539061), on mlx-step-audio-editx-swift 0.2.1 and GaeaPluginKit 0.8.0. Built, signed, notarized and stapled by its release workflow (9 m 32 s) |
| **Gaea** | 0.9.2 (2645695): input lengths an audio offer bounds are 422 `out_of_limits` |
| **Spec** | MES Audio 0.1 §3.3, §4.1, §4.2 (media-engine-spec v0.7.0) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every WAV, job record and session are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0397` |

## What it took

| Piece | Where | What |
|---|---|---|
| The host | Gaea 0.9.2 | MESKit gates a request, not its media, so Gaea measures audio inputs against the offer: `edit_speech`'s take against `max_duration_s`, and `compose`'s source and reference against `max_source_s` and `max_reference_s`. Longer is 422 `out_of_limits` on the input, never trimmed |
| The plugin | gaea-plugin-step-audio-editx 0.1.0 | One model, `step-audio-editx`, on `audio.edit_speech`, with lanes int8 (the default) and bf16. Five kinds (listed below). The transcript is required and its cues are read as the model's tags; `keeps_length` is false; takes run 0.5 to 90 s |
| The package | none | mlx-step-audio-editx-swift 0.2.1 as released: `Capability.speechEdit`, `SpeechEditRequest` over the kit's engine session, its seed honoured, its flow noise fixed per load. No ask was needed |

The five kinds and how they map onto upstream:
- **emotion:** MES's 15 labels onto upstream's (`neutral` is `remove`, `afraid` is `fear`, `humorous` is `humour`, and so on).
- **style:** MES's 9 styles onto upstream's (`normal` is `remove`, `narration` is `story`, `conversational` is `chat`).
- **add_cue:** laugh, sigh, breath and hesitation as upstream's tags, placed at the start, at the end, or inline in `text`.
  The new transcript comes back as the `transcript` output, `{text}`.
- **denoise.**
- **trim_silence:** upstream's `vad`.

## Result

| Done = | Result |
|---|---|
| Over GPP, byte for byte | **Pass, 21 of 21** ([golden.log](golden.log)): nine seeded edits, each `editx-inproc`'s WAV; the three `add_cue` runs return the new transcript; every session passes the validator |
| Through Gaea, installed from GitHub | **Pass, 31 of 31** ([acceptance.log](acceptance.log), `tools/acceptance-step-audio-editx.sh`, `REPO_FROM=github`, beside Kokoro): see the list below |
| Conformance | **With every G1 plugin, Kokoro, Qwen3-TTS and Step-Audio-EditX: 61 passed, 0 failed, 14 skipped; Base 0.1, Image 0.1 and Audio 0.1 conform** ([report](conformance/report.md)), under v0.7.0's suite as shipped. AUDIO-009 (edit_speech) now runs and passes, and AUDIO-004 now carries its formats through an edit |

The golden cases (int8, takes spoken by Kokoro-82M, in the plugin's `Tests/Fixtures`):
- angry, afraid, whisper and narration;
- a laugh at the end, a breath inline and a sigh at the start;
- denoise on a take with white noise about 25 dB under the speech;
- trim_silence on a take padded with 1.5 s of silence at each end.

What the 31 acceptance checks cover:
- **The offer:** `audio.edit_speech` lists `step-audio-editx` with 5 kinds, 15 emotions, 9 styles, 4 cues,
  `transcript: required`, `keeps_length: false` and 90 s. The `transcript` output is optional.
- **Edits with no model named:**
  - angry, `fearful` (resolved to `afraid`, run as upstream's `fear`), whisper, a laugh at the end, denoise and
    trim_silence are each `editx-inproc`'s WAV byte for byte;
  - the laugh returns `{text: "… [laugh]"}`, and an emotion edit returns no transcript;
  - trim_silence shortens the padded take.
- **Assets:** a take Kokoro spoke through Gaea, kept as an asset and edited sad twice at seed 4, gives the same WAV, and
  it is `editx-inproc`'s.
- **Formats:** 24-bit, float, FLAC and stereo takes are accepted. Output at 48 kHz 24-bit is converted, with
  `audio_resampled`.
- **Refusals:**
  - a speed edit, the emotion `calm`, the cue `cough` and an edit without a transcript are each 422
    `unsupported_parameter`;
  - a 95 s take is 422 `out_of_limits` on `audio`;
  - an emotion edit without its emotion, and a denoise with an emotion, are each 400;
  - an `add_cue` whose `text` lacks the cue is refused by the worker (`invalid_request`).

What the edits did to the takes (golden, measured on the output):

| Edit | Take | Output |
|---|---|---|
| denoise | 4.38 s, noise floor −31.4 dBFS | 3.96 s, −57.7 dBFS |
| trim_silence | 7.38 s, 1.90 s of silence before the first word | 3.24 s, 0.08 s |
| angry, whisper, laugh | 3.85 to 4.38 s | 3.72 to 4.20 s: said again, so the length moves |

| Job (int8, warm) | Take | Run |
|---|---|---|
| angry | 3.85 s | 2.2 s |
| a laugh at the end | 4.38 s | 2.5 s |
| denoise | 4.38 s | 2.5 s |
| trim_silence | 7.38 s | 2.0 s |
| The first job through Gaea (worker launch, prepare with the warm-up edit, the edit) | 3.85 s | 4.8 s from submit to settled |

In-process the worker peaks at 6.1 GB. The first prepare on this Mac took 12.9 s and later ones 2.0 s: the package's
one-second warm-up edit compiles its kernels, and Metal keeps them between processes.

## Found on the way

- **Gaea didn't bound input media.** MES leaves the length of inputs to the engine (Audio §4.1), and Gaea passed every
  take to the worker, whose refusal reached the client as a 400. Gaea 0.9.2 measures them and answers 422
  `out_of_limits`, which is what Audio §4.2 says.
- **A worker's refusal carries no `param`.** The `add_cue` without its cue is a 400 with the worker's message, but no
  param. GPP's error `detail.param` could be passed through; it would matter more as plugins refuse more.
- **MESKit's message reads "A emotion edit needs 'emotion'."** A grammar slip in `AudioProfileRules`, owed to
  media-engine-spec.

## Not covered

- **The bf16 lane** wasn't run. It shares the code path, and the package's footprint (10.3 GB) is declared.
- **Upstream's other 24 styles and 6 tags** (`older`, `child`, `[Surprise-oh]`, …) have no MES label. The profile names
  `x-stepfun.style` as the way to offer them, and this plugin doesn't yet.
- **Whether the words survive.** The model says the take again, so its words can drift (AB-L-0119). No ASR check was run.
  The output was compared byte for byte and measured, but not listened to.
