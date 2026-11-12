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

**Not tested:** a described-target job through Gaea from request to stems (AUDIO-019 and 021 with an offer to run
them on). The SAM-Audio plugin is unsigned, so Gaea can't install it, and the Mac this ran on has no Developer ID
certificate to sign it or a stand-in in the demo plugin. Run `mes-conformance --only AUDIO-019,AUDIO-020,AUDIO-021`
again with the signed plugin installed and accepted.
