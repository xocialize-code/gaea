# Gaea 1.6.0: audio.separate by description (MES 0.13.0, RFC 0008)

Asked for by AB-A-0271 on 2026-11-11, for the SAM-Audio plugin (`gaea-plugin-sam-audio`, AB-T-0470).

**What changed:** media-engine-spec from 0.13.0 (resolved `f496931`); `GaeaEngine.checkSpans` refuses a span past the
mixture's end once Gaea has read the mixture; form hints for `describe` and `spans`; the vendored MES descriptor
schema is 0.13.0's. MESEngineKit 0.13.0 does the rest (the request's rules, the gates, the plan's stems and spans).
mlx-engine-swift stays at 0.74.1: the plugin's manifest (engine contract 1.62.0) decodes with it.

**Unit tests:** 103/103 (`swift test`), three of them new in `AudioTests`: a described-target offer's descriptor and
stems, a span past the mixture, and the SAM-Audio plugin's own manifest decoded from its checkout.

**Validators:** `tools/validate.py` OK and `tools/test_validator.py` 78/78; the SAM-Audio manifest validates, and a
copy with `supports.watermark: "Audio Seal!"` fails.

**Conformance** (mes-conformance from media-engine-spec v0.13.0; a debug build of this commit, headless, on a MacBook
Pro, with the demo plugin 0.4.0 from GitHub):

- [conformance-audio-019-021.md](conformance-audio-019-021.md): AUDIO-019 to 021, 3 passed. Only one branch ran for
  real: `describe` sent to `demo-separator`, which has no `described_target`, was refused 422. The other branches need
  an offer with `described_target`, and none was installed.
- [conformance-demo.md](conformance-demo.md): the whole suite, 42 passed, 0 failed, 68 skipped.

## With the signed SAM-Audio plugin (2026-11-11, later the same day)

The plugin's CI signed 0.1.0 (`967173f`, `minGaea` 1.6.0) with Developer ID in its build-and-check mode
(run 43128827291, nothing published). That run then failed at the transcript check: `schemas/v1/engine.schema.json`
didn't allow `externalBytes` and `externalTenants`, which mlx-engine-swift 0.77.0 writes in a worker's memory report.
The schema now allows them. The run stopped before notarizing, so the bundle is signed, not notarized.

On the MacBook Pro, with that signed bundle and `mlx-community/sam-audio-base-swift-fp16` downloaded by the worker:

- **`scripts/check-plugin.sh`** ([sam-audio-check.log](sam-audio-check.log)): passed. Signature, launch under the
  launch requirement, hello, prepare, a described separation, the memory report, the transcript, and the control (the
  bare worker finds no metallib). The prepare took 892 s because it downloaded the weights.
- **`scripts/golden.sh`** ([sam-audio-golden.log](sam-audio-golden.log)): 5/5 stems byte for byte the same as
  `sam-audio-inproc`, each 384,000 frames.
- **Through Gaea 1.6.0** (a debug build, headless; the plugin installed from the release stand-in, enabled, with
  users' acceptance):
  - [conformance-sam-audio-019-021.md](conformance-sam-audio-019-021.md): AUDIO-019 to 021 with SAM-Audio alone, 3
    passed, every branch a described-only offer has.
  - [conformance-demo-sam-audio.md](conformance-demo-sam-audio.md): the whole suite with the demo plugin beside it,
    42 passed, 1 failed, 67 skipped. AUDIO-019 to 021 passed with every branch. The failure is BASE-019: the suite
    names `sam-audio-base` with acceptance but sends no `describe`, and Gaea refuses it (422), as RFC 0008 says an
    engine does. The suite's minimal request needs a description for a described-only offer (asked of mlx-apps).

## The released plugin (SAM-Audio 0.1.0, 2026-11-11)

`gaea-plugin-sam-audio` v0.1.0 (`92b7f4a`, release run 43133528519): signed, notarized and stapled, sha256
`d39bd7776a92…`. Since the bundle tested above it gained a copy of the SAM License in `Contents/Resources/LICENSE`,
which the release attaches too: that licence allows redistribution only with a copy.

With the released Gaea 1.6.0 (`Gaea-1.6.0.zip`, notarized) on the MacBook Pro, the demo plugin 0.4.0 and SAM-Audio
0.1.0 installed from GitHub, `sam-audio-base` enabled:

- [conformance-released.md](conformance-released.md): AUDIO-019 to 021 passed; BASE-019 failed as above (the suite's
  request, AB-A-0273).
- [sam-audio-golden-released.log](sam-audio-golden-released.log): `scripts/golden.sh` on the installed bundle, 5/5
  byte for byte, the same hashes as the bundle tested before the licence was added.

**Not tested:** the whole conformance suite with every plugin (`ALL=1 tools/conformance-with.sh`), an acceptance
script of this plugin's own, and its speed (AB-R-0828: not established through the engine).
