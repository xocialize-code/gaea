# AB-T-0401 and AB-T-0402: Gaea serves MES Video 0.1, and RIFE is its first video plugin

| | |
|---|---|
| **Date** | 2026-10-31 |
| **Gaea** | 0.10.0 (c59f5b3), on media-engine-spec v0.9.0 (Video 0.1, AB-A-0235) and GaeaPluginKit 0.9.0 |
| **Plugin** | [gaea-plugin-rife 0.1.0](https://github.com/xocialize-code/gaea-plugin-rife/releases/tag/v0.1.0) (7f277f7), on mlx-rife-swift 0.8.0. Built, signed, notarized and stapled by its release workflow |
| **Spec** | MES Video 0.1 §1.3, §1.7, §1.9, §3.5, §4 (media-engine-spec v0.9.0) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |
| **Large files** | every clip, job record and session are on `/Volumes/DEV_VOL1/Evidence/gaea/AB-T-0402` |

## What it took

**Gaea 0.10.0 (AB-T-0401)** serves the Video profile through `GaeaVideo`, as `GaeaAudio` serves Audio.
- **Descriptors** come from the video offers, with `output` offering MP4 in H.264 or HEVC. `VideoProfileRules` validates
  requests, and the kit applies the gates, limits and warnings.
- **Inputs:** video arrives at workers as a canonical MP4 (GPP-1 §3.3.3, Gaea 0.9.4), and audio as a canonical WAV. A
  source longer or larger than the offer's limits is 422 `out_of_limits`.
- **`interpolate`'s `fps`** becomes the nearest factor within `max_factor`, with `fps_adjusted`.
- **Outputs are finished as the profile asks:**
  - **Retimed:** a transformation's clip is put at its exact rate. The frames are copied, not re-encoded, onto a time
    base of the fps, by display rank, with B-frames kept.
  - **Sound and markings:** the source's AAC track goes back in (cut at whole packets inside the picture), with its
    comment and copyright.
  - **The codec asked for**, and the facts read from the file.

**gaea-plugin-rife 0.1.0 (AB-T-0402)** is one model, `rife-4.25`, on `video.interpolate`:
- factor 2 to 8, giving (N − 1) × factor + 1 frames, every source frame kept;
- up to 3840×2160 (the package tiles above 1080p) and 300 s;
- no seed, and deterministic.

Its in-process reference is `rife-inproc`.

## Result

| Done = | Result |
|---|---|
| Over GPP, against in-process | **Pass, 8 of 8** ([golden.log](golden.log)): factors 2, 4 and 8 on a 128×96, 17-frame clip, and factor 2 at 640×360. Each pair decodes to the same frames byte for byte (`framemd5`), with 33, 65, 129 and 95 frames. The MP4s differ only in their creation time, to the second |
| Through Gaea, installed from GitHub | **Pass, 18 of 18** ([acceptance.log](acceptance.log), `tools/acceptance-rife.sh`, `REPO_FROM=github`): see the list below |
| Conformance | **With every G1 plugin, the five audio plugins and RIFE: 72 passed, 0 failed, 19 skipped; Base 0.1, Image 0.1, Audio 0.1 and Video 0.1 conform** ([report](conformance/report.md)), under v0.9.0's suite as shipped. VIDEO-001 to 004, 012, 013 and 015 run and pass. The other Video tests skip until generate, extend, retake, upscale and previews have offers |

What the 18 acceptance checks cover:
- **The offer:** the handshake lists `video` 0.1, and `video.interpolate` lists `rife-4.25` with its limits, no seed, and
  `deterministic`.
- **Factor 2:**
  - 33 frames at exactly 48 fps (0.6875 s), 128×96, with effective factor, fps, size and frames;
  - the source's AAC track (48 kHz stereo) and its comment kept;
  - `rife-inproc`'s frames, decoded byte for byte.
- **Factor 4:** 65 frames at exactly 96 fps (0.677083 s, retimed by Gaea), `rife-inproc`'s frames.
- **`fps`:** 48 is factor 2 with no warning. 60 is factor 3 (72 fps, 49 frames), with `fps_adjusted`.
- **Codec and container:** `output.codec` `h264` gives H.264, still 33 frames with sound. A ProRes QuickTime input is
  converted and accepted.
- **Refusals:**
  - factor 9 is 422;
  - a 301 s source and a 4096-pixel-wide one are each 422 `out_of_limits` on `video`;
  - `factor` with `fps` is 400.

| Job (warm) | In-process | Through Gaea (worker) |
|---|---|---|
| 128×96, 17 frames, factor 2 | 0.77 s | 0.44 s |
| factor 4 | 1.02 s | 0.47 s |
| factor 8 | 1.69 s | — |
| 640×360, 48 frames, factor 2 | 2.27 s | — |
| The first job through Gaea (worker launch, prepare, interpolate, finish) | | 1.35 s from submit to settled |

The in-process runs are cold for the first case and include the package's Hugging Face check. The worker peaks at about
220 MB (110–150 MB RSS in-process).

## Found on the way

- **The package writes on a 1/600 time base.** A 48 fps clip came back at an average 48.06 fps and 96 fps at 96.06,
  where Video §1.3 and VIDEO-012 want the exact rate. The cause is frame-stream-native, under RIFE, SeedVR2 and FlashVSR.
  Gaea retimes every transformation's output, so it conforms now; the package could write on a time base of the fps.
- **An `AVAssetTrack` doesn't keep its asset alive.** Gaea's first remux let the source's asset go and the insert failed
  (-12780). It now holds both assets until the export ends.
- **ffprobe's `avg_frame_rate` misleads with B-frames.** It counts from the first decode time, which B-frames put below
  zero, so 33 frames at 48 fps read as 44. The stream's own duration (0.6875 s) is the check.
- **The package drops the source's sound** and fetches its weights with its own Hugging Face client, and it reports no
  progress. Gaea puts the sound back, as the profile allows. The rest is in the Video evaluation's §8, for mlx-video.

## Not covered

- **Progress and previews:** the package reports neither, so `media_s` and VIDEO-014 wait on it.
- **Colour and timing conversion:** an input outside BT.709 (`color_converted`) or with variable timing (`video_retimed`)
  isn't converted yet; every input here was SDR at a constant rate.
- **4K:** the package's tiling was measured at 3840×2160 in 3.0 GB (BRIDGE-VID-003). It wasn't run through Gaea.
