# AB-T-0398: MOSS-SoundEffect as a Gaea plugin (audio.generate)

| | |
|---|---|
| **Date** | 2026-10-31 |
| **Plugin** | [gaea-plugin-moss-soundeffect 0.1.1](https://github.com/xocialize-code/gaea-plugin-moss-soundeffect/releases/tag/v0.1.1) (7fccaa1), on mlx-moss-soundeffect-swift 0.4.0 and GaeaPluginKit 0.8.0. Built, signed, notarized and stapled by its release workflow. 0.1.0 was released the same way first, and failed AUDIO-002 (see below) |
| **Gaea** | 0.9.2 (2645695), unchanged |
| **Spec** | MES Audio 0.1 §3.4, §4.2 (media-engine-spec v0.7.0) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every WAV, job record and session are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0398` |

## What it took

The plugin is gaea-plugin-moss-soundeffect 0.1.1: one model, `moss-soundeffect`, on `audio.generate`, with lanes bf16
(the default) and int4. The package, mlx-moss-soundeffect-swift 0.4.0, is used as released: `Capability.soundEffect`,
seeded through the request. No host change and no ask were needed.

- **`duration_s` is exact to the frame.** The model is told the duration in its prompt, to a tenth of a second, and
  always denoises a full 30 s latent. So the worker asks for the duration rounded up to a tenth, and keeps
  `round(d × 48 000)` frames.
- **The package's own crop can come up a frame short.** It crops at `Int(48 000 × seconds)`, and floating point makes
  2.3 s 110 399 frames. The worker makes up as many as two frames by holding the last sample.
- **`count`** makes sound `i` at `seed + i`.
- **`quality`** picks the steps: draft 25, standard 50 and best 100 (the reference's).
- **Limits:** 0.5 to 30 s, at most 8 sounds.
- **Progress** reports each denoise step, then `decode`.

## Result

| Done = | Result |
|---|---|
| Over GPP, byte for byte | **Pass, 13 of 13** ([golden.log](golden.log), on 0.1.1): seven seeded sounds, each `moss-sfx-inproc`'s WAV and exact to the frame; every session passes the validator |
| Through Gaea, installed from GitHub | **Pass, 23 of 23** ([acceptance.log](acceptance.log), `tools/acceptance-moss-soundeffect.sh`, `REPO_FROM=github`, 0.1.1): see the list below |
| Conformance | **With every G1 plugin and the four audio plugins (Kokoro, Qwen3-TTS, Step-Audio-EditX, MOSS-SoundEffect): 62 passed, 0 failed, 13 skipped; Base 0.1, Image 0.1 and Audio 0.1 conform** ([report](conformance/report.md)), under v0.7.0's suite as shipped. AUDIO-010 (generate) now runs and passes |

The golden cases (bf16):
- rain at 1.5 s (draft);
- a door at 2.3 s (standard), where the package's crop is a frame short;
- two barks (count 2, seeds 7 and 8);
- a street with a negative prompt;
- glass at 1.0 s (best);
- a Chinese prompt at 1.55 s, which is told 1.6 s and cut to 74 400 frames.

What the 23 acceptance checks cover:
- **The offer:** `audio.generate` lists `moss-soundeffect` with draft, standard and best, 0.5 to 30 s, 8 sounds, and
  48 kHz mono.
- **Sounds with no model named:** rain, two barks, a street with a negative prompt, and a door at 2.3 s (standard). Each
  is `moss-sfx-inproc`'s WAV byte for byte and exact to the frame, and the barks differ.
- **Effective values:** `duration_s`, `seed`, `quality`, `count` and `x-moss.steps`. With no duration the sound is the
  default 10 s, reported, and an unseeded request reports its seed.
- **Progress:** the run reports 25 denoise steps, then decode.
- **Output:** 44.1 kHz 24-bit is converted, with `audio_resampled`, and keeps 1.5 s.
- **Refusals:** 0.4 s, 31 s, 9 sounds and a seed of 2³² are each 422 `out_of_limits`; no prompt is 400.

| Sound (bf16, warm) | Steps | Worker |
|---|---|---|
| draft, any duration | 25 | 9.5 s |
| standard | 50 | 18 s |
| best | 100 | 35 s |
| two draft sounds (count 2) | 2 × 25 | 19.2 s |
| The first job through Gaea (worker launch, prepare, a draft sound) | 25 | 10.8 s from submit to settled |

The time doesn't depend on the duration, because every sound denoises the full 30 s latent. The sounds have real levels,
−15 to −28 dBFS RMS. In-process the worker peaks at 7.9 GB RSS; through the plugin check, phys_footprint was 6.8 GB after
a draft sound and peaked at 11.6 GB.

## Found on the way

- **0.1.0 declared `max_text_chars` on its offer, and AUDIO-002 failed.** Audio §4.2 lists that limit for
  `design_voice`, `speak` and `edit_speech`, not `generate`. 0.1.1 dropped it. The worker still refuses a prompt over
  2,000 characters, as a 400.
  - A `generate` prompt is bounded by nothing a client can read. The profile could let `max_text_chars` bound the
    prompt too; that would be a spec change for mlx-apps.
- **The package's crop is a frame short at some durations** (`Int(48 000 × 2.3)` is 110 399). The plugin makes it up. The
  package could round instead of truncating.

## Not covered

- **The int4 lane** wasn't run, and its weights aren't on this Mac. Its footprint (5.4 GB resident) is declared.
- **The package's eviction:** its README notes Metal retains memory after `unload()`. Gaea's worker is a process of its
  own, so ending it reclaims everything, but eviction inside a live worker wasn't measured here.
- **Whether the sounds sound like their prompts.** They were compared byte for byte and measured for level, but not
  listened to.
