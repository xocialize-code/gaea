# AB-T-0455: the AuK plugin (G5 order 5)

[gaea-plugin-auk](https://github.com/xocialize-code/gaea-plugin-auk) v0.1.1 runs Tencent Hunyuan's AuK and AuK-Flash
through Gaea 1.1.1 on MES Audio 0.1, including media-engine-spec v0.10.0's RFC 0006. Its operations are:
- `audio.speak` (cloning);
- `audio.design_voice`;
- `audio.edit_speech` (14 kinds, with no transcript needed);
- `audio.separate`.

It is built from mlx-auk-swift, GaeaPluginKit 0.11.1 and mlx-engine-swift 0.74.1, on the fleet's mlx-swift fork. All
runs were on an M5 Max (128 GB, macOS 27.3). The plugin came from its CI-built, notarized GitHub release and was
installed beside the demo plugin.

## Results

**`tools/acceptance-auk.sh`: 50 passed, 0 failed** (`acceptance.log`).

- **Restricted (G-27):**
  - Both models start off, and AuK offers nothing until the operator runs `gaea models enable`.
  - Once enabled, every offer is named-only, under `LicenseRef-Qwen-Research` with `commercial_use: false`,
    `accepted_required` and `user_accept_required`, and carries a notice.
  - A job without `policy.accepted` is 422 `policy_unmet` (`terms_not_accepted`).
  - A `separate` job naming no model runs on the demo's separator, never on AuK.
- **Every operation succeeds:**
  - speak: a clone with its transcript, and a 4.0 s fit;
  - design_voice;
  - edit_speech: all 14 of AuK's kinds, including `dereverb` and the `hum` cue from MES 0.10;
  - separate: the second speaker by order and by the words they say, the singing, and on Base every voice.
- **Edit details:**
  - A replace returns the edited transcript.
  - A hum at the start returns the transcript with the cue first.
  - Speed 1.4 is snapped to AuK's 1.5 with `param_adjusted`.
- **Stems:** each is named by its stem, is the mixture's length to the frame, and is reported in `effective.stems`.
- **Byte for byte against `auk-inproc`:** the clone, the fit, a design sample, the replace, the emotion edit, both
  speaker picks, and Base's voices.
- **Refused at submit:**
  - 422 `unsupported_parameter`: a cue placed inline (`cue_placement: edge`), removing every cue
    (`remove_all_cues: false`), `trim_silence`, and the `voices` stem on AuK-Flash;
  - 400: the speaker stem without a pick.
- **Failed when the job runs:**
  - A 38.9 s take and a 38.9 s mixture fail `out_of_limits` on `audio`. Gaea measures media when the job runs (as for
    Step-Audio-EditX), not at submit.
  - A Mandarin edit on the int4 lane is refused, naming `x-gaea.lane` (G-30).
- **Transcripts:** every recorded GPP session passes `validate.py`.

**Timings:**
- A cold first job took 2.26 s from submit to settled: launch, prepare on int8, and speak.
- In-process, the clone took 1.14 s to prepare and 0.53 s to make 4 s of speech, at 7.8 GB peak RSS.
- With both models loaded, the worker's ledger showed 13.9 GB `phys_footprint`, a 18.9 GB peak, and 17.6 GB charged
  (`ledger.txt`).

**In the plugin repo:**
- `scripts/golden.sh` passes 31/31 byte for byte over GPP against in-process.
- `scripts/check-plugin.sh` passes, including the metallib control.

## What AuK exposed, and the fixes

1. **Gaea 1.1.0 couldn't install it.** Gaea decoded manifests with mlx-engine-swift 0.73's types. AuK's speech-edit
   control lists contract 1.59.0's operations (`dereverberate`, `hum`), so its manifest failed to decode.
   - **Gaea 1.1.1** builds on mlx-engine-swift 0.74.1 and GaeaPluginKit 0.11.0, the versions the plugins build on.
   - A unit test now decodes AuK's published manifest and every example manifest.
   - **Rule:** Gaea's engine pin must be at least the newest one any released plugin builds on.
2. **Stems were 13 ms short.** AuK works in 20 ms latent frames, so a 5.553 s mixture came back as 5.54 s stems. MES
   Audio §3.6 says a stem is the mixture's length.
   - **GaeaPluginKit 0.11.1:** given the mixture, `AudioSeparations.outputs` pads or cuts each PCM stem to the
     mixture's length at the stem's own rate. A stem off by more than 0.1 s is the model's error.
   - **AuK 0.1.1** passes the mixture. `auk-inproc` does the same, so the golden check stays byte for byte.
3. **Length limits are checked when the job runs.**
   - MESKit reads the request, not its media, so a take or mixture over `max_duration_s` is accepted (201). It then
     fails with `out_of_limits` on `audio` when the job runs.
   - This is how Step-Audio-EditX's acceptance already treated it. The acceptance checks it that way.

## Conformance (`conformance/`)

MES v0.10.0's `mes-conformance` against Gaea 1.1.1, with all 25 public plugins from GitHub and AuK's two models
enabled (`ALL=1 ENABLE="auk-flash auk" tools/conformance-with.sh`, in `conformance/`): **72 passed, 10 failed, 13 skipped.** Image and
Video conform. Base and Audio don't, and every failure has one cause, which is in the suite, not in Gaea:
- AuK's offers need users' acceptance. The tests that name a model build their own request without
  `policy.accepted`, so each gets 422 `policy_unmet` before the check it means to make. The tests are BASE-015,
  BASE-016, BASE-056, AUDIO-006, AUDIO-008, AUDIO-009 and AUDIO-015 to AUDIO-018.
- `Suite.acceptance(d)` exists but is used only by `minimalRequest`.
- **Asked of `mlx-apps` as AB-A-0252** (send acceptance on every request, as a client whose user accepted).
  Conformance with every plugin and AuK enabled waits on it, in order 6.
- With acceptance sent, Gaea gives the codes those tests expect, as the acceptance's refusals show.
- **With AuK installed but off**, and LTX's four tiers enabled as in AB-T-0454, Gaea 1.1.1 conforms with all 25
  plugins: **88 passed, 0 failed, 7 skipped**, the same as 1.1.0 (`conformance-auk-off/`).
- LTX's tiers need users' acceptance too, but don't trip this. The video tests build their requests with acceptance,
  and the Base and Audio tests that name a model reach AuK first.

## Files

- `acceptance.log`: the run.
- `operations-before.json` and `operations.json`: the operations before and after enabling AuK.
- `job-*.json`, `edit-*.json` and `sep-*.json`: each job.
- `gaea-*.wav`: their outputs.
- `inproc-*`: the in-process runs.
- `route-separate.json`: the unnamed separate job.
- `sessions/`: the recorded GPP sessions.
- `ledger.txt`: the memory ledger after the run.
