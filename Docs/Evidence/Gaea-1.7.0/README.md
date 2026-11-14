# Gaea 1.7.0: `mesh.generate_part` (AB-T-0482)

2026-11-13, Mac Studio (Mac17,14). Gaea 1.7.0 on media-engine-spec v0.14.0 (RFC 0009) and mlx-engine-swift 0.78.0; a
debug build run headless on a throwaway home and port, plugins served by `tools/release-standin.py`; mes-conformance
built from media-engine-spec v0.14.0. The first two runs are from before the release; the third, on 2026-11-14, is the
released app.

| Run | Plugin | Result | Report |
|---|---|---|---|
| The demo's stand-in | gaea-plugin-demo 0.5.0, built and signed locally | 56 passed, 0 failed, 60 skipped: Base, Image, Audio and Mesh 0.1 conform | [conformance-demo.md](conformance-demo.md) |
| HairDeck | gaea-plugin-hairdeck 0.1.0, mlx-3d's local signed build of `6277b71`; weights from a local models root | 41 passed, 1 failed, 74 skipped: Mesh 0.1 conforms | [conformance-hairdeck.md](conformance-hairdeck.md) |
| **The release** | Gaea-1.7.0.zip from GitHub (sha256 `3aec82f1…f3e9e1`, Gatekeeper: Notarized Developer ID, stapled), headless on a throwaway home; gaea-plugin-demo 0.5.0 installed by repo URL from GitHub | 56 passed, 0 failed, 60 skipped: Base, Image, Audio and Mesh 0.1 conform; MESH-013 to 018 pass | [conformance-released.md](conformance-released.md) |

- **MESH-013 to MESH-018 pass in both runs**, and so do MESH-001 to 003, 005, 009 and 010. HairDeck accepts the suite's
  body (`Fixtures.body()`): its item is at y 1.38 to 1.61 m with 47 joints under `J_Bip_C_Head`, the same seed gives the
  same file, and an opaque picture is cut out (BiRefNet) and reported `background: remove`.
- **The one failure, IMAGE-007 in the HairDeck run, is the suite's request.** With no other seeded operation on the
  engine it sends `mesh.generate_part` without a `subject_box`, which an offer that requires one refuses (422). Told to
  mlx-apps on AB-A-0280.
- **The first demo run failed MESH-014**: the stand-in wrote its `WEIGHTS_0` accessor wrongly. Fixed in the demo, and
  the host's test now checks the weights.
- **Memory** ([hairdeck-memory.txt](hairdeck-memory.txt)): the plugin's lane declares 4.20 GB. Gaea measured the worker
  holding 5.35 to 5.63 GB on cut-out pictures and 10.27 GB once BiRefNet had run. The budget was 103 GB, so nothing
  was refused; the declaration is mlx-3d's to raise (AB-A-0278).
- Unit tests: `swift test` 109/109; `tools/validate.py` OK; `tools/test_validator.py` 78/78.
