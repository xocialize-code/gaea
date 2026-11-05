# G5 — More audio: IndexTTS 2.5, VoxCPM2 and AuK

Planned 2026-11-05 after 1.0.0, and approved by the operator the same day with every recommendation taken. The
decisions are G-27 to G-31 (AB-D-0209 to AB-D-0213); the Plan's §5 G5 summarizes this; each order is filed as a task
when it starts.

## Where each model stands

All three are ported to Swift-MLX and wrapped as MLXEngine packages by the `mlx-audio` area. Gaea's work is the
plugins, plus whatever MES and Gaea lack.

| | IndexTTS 2.5 | VoxCPM2 | AuK / AuK-Flash |
|---|---|---|---|
| Package | `mlx-indextts2-swift` v0.5.0 | `mlx-voxcpm2-tts-swift` v0.5.0 on `mlx-voxcpm-swift` v0.3.0 | `mlx-auk-swift` v0.3.0 |
| Engine surfaces | `tts` | `tts` | `tts`, `speechEdit`, `audioSeparation` |
| What it does | Clones from a reference in zh, en, ja, es and ar. Emotion is decoupled from the speaker: 8 labels, an intensity and an 8-weight vector. Exact duration control | A default voice; cloning from a clip, or continuation cloning with its transcript. Emotion and style from a label or a description; a voice designed from a description | Cloning, or a voice designed from a description. 14 kinds of speech edit with no transcript needed. Separation: one speaker by talking order or by their words, the singing, or every voice. en and zh |
| Output | 22.05 kHz mono | 48 kHz mono | 24 kHz mono |
| Memory | fp16 4.5 GB resident, 9.3 GB at peak; int8 and int4 lanes | about 11 GB (bf16 weights run as fp32: bf16 glitches on Metal); one lane; Pro chip or better | Encoder lanes bf16 / int8 / int4: 12.8 / 9.5 / 7.6 GB resident, or "staged" (one model in memory at a time): 10.8 / 7.7 / 6.4 GB at peak |
| Speed | — | — | Base RTF 0.89, Flash 0.13 |
| Weights' licence | bilibili Model Use Agreement: commercial use allowed below 100 M monthly users | Apache-2.0 | **Research only.** The DiT and VAE are MIT, but the required Qwen2.5-Omni-3B encoder is under the Qwen Research licence (AB-D-0153) |
| Limits | No default voice: a reference is required. Numbers aren't spelled out in zh and en | Voice design isn't named as such in the package; it comes from a description with no reference | Takes at most 30 s. The int4 encoder drops words in Mandarin edits (AB-D-0202). Flash makes up words for the "every voice" stem |

## What MES Audio 0.1 already covers

MES Audio 0.1's `edit_speech` was written with AuK's instruction set as its model, so most of AuK fits as it is.

- **IndexTTS 2.5 fits completely.**
  - `speak` with `voice_ref`, with `supports.voice_ref_text: unused` and no default voice.
  - `emotions`: its 8 labels are MES labels; `fearful` resolves to `afraid`.
  - `emotion_intensity` maps to its `emoAlpha`. The 8-weight vector is the extension `x-indextts.emotion_vector`, which
    the profile already names.
  - `target_duration` and `speed` are supported, and `languages` is `[zh, en, ja, es, ar]`.
- **VoxCPM2 fits completely.**
  - `speak` with `default_voice`, `voice_ref` and `voice_ref_text: optional` (continuation cloning).
  - `emotions` and `emotion_description`.
  - **`design_voice`** from a description with no reference.
- **AuK** fits these surfaces as they are:
  - **`speak`:** cloning from `voice_ref`. `voice_ref_text` is optional and only sharpens the length.
  - **`design_voice`:** AuK's instruct TTS is a voice designed from a description, which is exactly `design_voice`.
  - **Thirteen of its 14 `edit_speech` kinds** (all but dereverb, S-2): `emotion`, `style` (whisper ⇄ normal), `replace_text`, `insert_text`,
    `remove_text`, `speed`, `pitch` and `volume` (snapped to AuK's trained steps with `param_adjusted`, §1.9),
    `timbre`, `de_accent`, `denoise`, and `add_cue` / `remove_cue`. `transcript: unused`; a transcript given is
    returned edited.

## The gaps AuK exposes (an MES change, owned by `mlx-apps`)

| # | Gap | Why | Proposal |
|---|---|---|---|
| S-1 | **`audio.separate`** | AuK's third surface. The profile lists separation under "Later" (§7) | **Input:** `audio` (the mixture). **Parameters:** `stems` (`speaker`, `singing`, `voices`, plus music stems `vocals`, `drums`, `bass`, `other` for the fleet's Demucs and Mel-RoFormer ports), and `speaker` `{ordinal}` or `{saying: text}`. **Output:** one audio per stem. **Supports:** `stems`, `speaker_selection`, and a Fact saying whether a stem is **regenerated** (AuK: not phase-aligned, so it can't be subtracted from the mixture) or **masked**. Conformance AUDIO-015 onwards |
| S-2 | `dereverb` edit kind | AuK dereverberates; MES has only `denoise` | Add `dereverb`, with no fields |
| S-3 | `hum` cue | AuK adds or removes humming | Register `hum` in §2.2 |
| S-4 | Where an `add_cue` goes | AuK only adds a cue at the start or end; MES also allows placing it inline in the transcript (`text`) | A supports key, e.g. `cue_placement: [edge]` or `[edge, inline]`; the other form is 422 |
| S-5 | `target_duration_s` for `edit_speech` | Content and speed edits change the length; AuK can fit a cue | Extend the vocabulary entry to `edit_speech`, gated by `supports.target_duration` |

Speaking from a description in one pass (Audio §3.1) can stay "Later": `design_voice` followed by `speak` covers it.

## Gaea and kit changes

- **The fix must stay pinned.** Each new plugin names the fleet's mlx-swift fork in its own `Package.swift` (AB-D-0208):
  all three packages name ml-explore's mlx-swift, which would otherwise win and drop the leak fix. This matters most
  for AuK in staged mode, which reloads its quantized encoder and DiT on every request.
- **Kit:** translating MES edits into `SpeechEditRequest` moves into GaeaPluginKit (0.11.0), because two editors now
  need it. Step-Audio-EditX moves onto it.
- **Host:** `audio.separate` in GaeaAudio:
  - the operation table and the vendored MES schemas;
  - several stem outputs, each with its facts;
  - canonical input conversion, as for `edit_speech`.
- **Lab and console:** MESEngineUI forms for `audio.separate` and the new kinds (`mlx-apps`), and `lab-run` coverage.

## Work orders

1. **IndexTTS 2.5 plugin** (`gaea-plugin-indextts`). The control case: it should need nothing new. The acceptance is
   modelled on Qwen3-TTS's:
   - clone, the 8 emotions with intensity, the vector extension and `target_duration_s`;
   - all 5 languages, and `[pause]` honoured by splitting;
   - refusals: no `voice_ref`, an unsupported language;
   - byte for byte against `indextts-inproc`.
2. **VoxCPM2 plugin** (`gaea-plugin-voxcpm2`):
   - `speak` with the default voice, a clone and a continuation clone;
   - emotion as a label and as a description;
   - `design_voice`, with a designed voice cloned back through an asset;
   - 48 kHz with format conversion;
   - its 11 GB footprint and chip floor admitted by the governor;
   - byte for byte against `voxcpm2-inproc`.
3. **MES 0.10: S-1 to S-5** (an ask to `mlx-apps`):
   - the RFC, the schemas, MESKit and the conformance tests;
   - MESEngineUI's forms.

   It can run in parallel with orders 1 and 2.
4. **Kit 0.11.0 and host:** the shared edit mapping; `audio.separate` in Gaea on MES 0.10. Released as Gaea 1.1.0.
5. **AuK plugin** (`gaea-plugin-auk`):
   - two models, `auk-flash` and `auk`, on `speak`, `design_voice`, `edit_speech` (14 kinds) and `separate`;
   - encoder lanes bf16 / int8 / int4, with int4 refused for Mandarin edits (or moved to int8; see D-4);
   - staged residency charged as AB-A-0246 measured;
   - restricted licence (D-1).

   The acceptance:
   - every edit kind, both speaker picks and the singing and voices stems;
   - Flash refusing the voices stem;
   - over 30 s refused with 422;
   - never routed to without being named;
   - byte for byte against `auk-inproc`.
6. **Exit:**
   - Gaea Lab on the new audio (`lab-audio.sh` extended);
   - conformance with every plugin;
   - a 1-hour soak of AuK's staged edits with live memory flat, checking the leak fix holds.

## Decisions (approved 2026-11-05: every recommendation, G-27 to G-31)

- **D-1, AuK's licence.** Gaea would publish a plugin whose weights are for research only.
  - **Recommended:** offer it **named-only, off until the operator enables it and accepts the terms**, marked
    `commercial_use: false`, with **users' acceptance required** (`user_accept_required`). That way every client user
    sees the research-only terms before a run, the way LTX's users' acceptance works.
  - The alternatives: operator acceptance only, or not shipping AuK publicly at all.
- **D-2, how the MES change happens.** Recommended: an ask to `mlx-apps` with S-1 to S-5, and a session started in
  `media-engine-spec` to do it, as AB-A-0249 was handled. The alternative is for Gaea to draft the RFC and `mlx-apps`
  to review it.
- **D-3, separation's scope.** Recommended: design `audio.separate` for music stems too, so the fleet's Demucs and
  Mel-RoFormer ports can be plugins later, but ship only AuK in G5. The alternative is AuK's three stems only.
- **D-4, int4 and Mandarin.** Recommended: an `edit_speech` job in `zh` on the int4 lane runs on int8 instead, with a
  warning when that lane is installed. Otherwise it's refused, never run on int4. The alternative is to refuse it
  outright.
- **D-5, order.** Recommended: start the MES change (order 3) now in its own session, and do IndexTTS and VoxCPM2 here
  meanwhile. AuK lands when MES 0.10 does. The alternative is AuK first and alone, slower but focused on the gaps.
