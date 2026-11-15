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

## HairDeck 0.1.0 from GitHub through the released Gaea (2026-11-14)

AB-T-0482's item 6. Gaea-1.7.0.zip from GitHub (the notarized app above), headless on a throwaway home and port;
`gaea-plugin-hairdeck` 0.1.0 installed by repo URL from its public release (`8645c82`, mlx-hairdeck-swift 0.2.1);
models root `/Volumes/DEV_VOL1/Models`. The picture is the plugin's own `Tests/Fixtures/girl.png` (768 × 1024, cut
out), the box `{0.048, 0.03, 0.934, 0.941}` ([36, 30, 755, 995] px), the body `vrmdeveloper/src/assets/Spec.vrm`, seed 42.
Evidence: [hairdeck-0.1.0/](hairdeck-0.1.0/acceptance.log).

| Run | Result |
|---|---|
| `tools/acceptance-hairdeck.sh` (`REPO_FROM=github`) | **30 passed, 1 failed** (31 checks, with Item Studio's `mergeVrm`): the failure is the merged hair not settling within the merge tool's 1 cm, the same for the in-process item (below) |
| mes-conformance v0.14.0 with only HairDeck installed | 41 passed, 1 failed, 74 skipped: Base and Mesh 0.1 conform; MESH-001 to 003, 005, 009, 010 and 013 to 018 pass; the failure is IMAGE-007, the suite's request (AB-A-0280) ([conformance.md](hairdeck-0.1.0/conformance.md)) |

- **The item is `hairdeck-inproc`'s** in four cases: the cut-out picture, `physics: false`, `texture: none`, and an
  opaque JPEG matted by BiRefNet. In each the BIN chunk is the same byte for byte and every JSON member but `asset`
  is equal: Gaea stamps the item and changes nothing else. 15,160 vertices, 36,836 faces, a 1064 px texture, 30
  springs, skinned under `J_Bip_C_Head`.
- **Inputs**: a HEIC with transparency arrives as an upright PNG and runs as `alpha`; the opaque JPEG as `remove`.
- **Refusals**: no box 422, a box outside the picture or without area 400, no body 400, vertex colours 422, a part
  the model doesn't make 422, a body that isn't a GLB refused at submit, `mesh.generate` 404 (not offered).
- **The weights are public**: on the first run `xocialize/hairdeck-mlx` wasn't under the models root, Gaea said so at
  install, and the first job downloaded it anonymously (`prepare_ms` 50,080). The log kept here is the second run.
- **The merge** (`mlx-hairdeck-swift/tools/check_merged_vrm.mjs` with Item Studio's `vrmMerge.js`,
  `xocialize-code/vrmx-studio` `9123c46`, passed as `VRMMERGE`; [merge.txt](hairdeck-0.1.0/merge.txt)): the item goes
  into Spec under one head bone, its chains intact, the hair within 2.4e-7 m of where the item put it, and **its
  springs are carried**: the merged file has 32 (the body's 2 and the item's 30) and the hair swings (the ends lag by
  up to 0.39 m in a 50° head turn). **The tool's own verdict still fails, on settling**: 2.5 s after the turn the
  ends are 1.82 cm from rest against its 1 cm limit. The in-process item gives the same figure, so this is the item's
  springs or the tool's limit, mlx-3d's either way (AB-A-0278). The first run, with the older copy in
  `VRMXA_Specification` (`0d8f1ce`, no spring-bone code), carried none of the item's springs; the log kept here is
  the re-run.
- **Memory** ([hairdeck-memory.txt](hairdeck-memory.txt)): the plugin's lane declares 4.20 GB. Gaea measured the worker
  holding 5.35 to 5.63 GB on cut-out pictures and 10.27 GB once BiRefNet had run. The budget was 103 GB, so nothing
  was refused; the declaration is mlx-3d's to raise (AB-A-0278).
- Unit tests: `swift test` 109/109; `tools/validate.py` OK; `tools/test_validator.py` 78/78.

## HairDeck 0.1.0 from GitHub through the released Gaea (2026-11-14)

AB-T-0482's item 6. Gaea-1.7.0.zip from GitHub (the notarized app above), headless on a throwaway home and port;
`gaea-plugin-hairdeck` 0.1.0 installed by repo URL from its public release (`8645c82`, mlx-hairdeck-swift 0.2.1);
models root `/Volumes/DEV_VOL1/Models`. The picture is the plugin's own `Tests/Fixtures/girl.png` (768 × 1024, cut
out), the box `{0.048, 0.03, 0.934, 0.941}` ([36, 30, 755, 995] px), the body `vrmdeveloper/src/assets/Spec.vrm`, seed 42.
Evidence: [hairdeck-0.1.0/](hairdeck-0.1.0/acceptance.log).

| Run | Result |
|---|---|
| `tools/acceptance-hairdeck.sh` (`REPO_FROM=github`) | **30 passed, 1 failed** (31 checks, with Item Studio's `mergeVrm`): the failure is the merged hair not settling within the merge tool's 1 cm, the same for the in-process item (below) |
| mes-conformance v0.14.0 with only HairDeck installed | 41 passed, 1 failed, 74 skipped: Base and Mesh 0.1 conform; MESH-001 to 003, 005, 009, 010 and 013 to 018 pass; the failure is IMAGE-007, the suite's request (AB-A-0280) ([conformance.md](hairdeck-0.1.0/conformance.md)) |

- **The item is `hairdeck-inproc`'s** in four cases: the cut-out picture, `physics: false`, `texture: none`, and an
  opaque JPEG matted by BiRefNet. In each the BIN chunk is the same byte for byte and every JSON member but `asset`
  is equal: Gaea stamps the item and changes nothing else. 15,160 vertices, 36,836 faces, a 1064 px texture, 30
  springs, skinned under `J_Bip_C_Head`.
- **Inputs**: a HEIC with transparency arrives as an upright PNG and runs as `alpha`; the opaque JPEG as `remove`.
- **Refusals**: no box 422, a box outside the picture or without area 400, no body 400, vertex colours 422, a part
  the model doesn't make 422, a body that isn't a GLB refused at submit, `mesh.generate` 404 (not offered).
- **The weights are public**: on the first run `xocialize/hairdeck-mlx` wasn't under the models root, Gaea said so at
  install, and the first job downloaded it anonymously (`prepare_ms` 50,080). The log kept here is the second run.
- **The merge** (`mlx-hairdeck-swift/tools/check_merged_vrm.mjs` with `VRMXA_Specification/reference/web/fitting/vrmMerge.js`,
  [merge.txt](hairdeck-0.1.0/merge.txt)): the item goes into Spec under one head bone, its chains intact, the hair
  within 2.4e-7 m of where the item put it. **Its springs are not carried**: the merged file has the body's 2 springs
  and none of the item's 30. The in-process item gives the same result, so this is the merge, not Gaea's stamp: the
  `vrmMerge.js` in this tree (`0d8f1ce`) has no spring-bone code. mlx-3d's README says the check passed with a
  `mergeVrm` "extended to carry an item's spring bones"; that version isn't in the tree. Asked on AB-A-0278.
- **Memory** ([memory.txt](hairdeck-0.1.0/memory.txt)): the lane declares 5.50 GB. The worker held 6.01 GB on cut-out
  pictures and 10.44 GB after BiRefNet had run (10.26 GB on the re-run). BiRefNet's lane (0.9 + 7.2 GB) is not in HairDeck's declared figure.
- **Times**: a warm job ran in 0.9 to 1.1 s when the GPU was free, and in 12 to 18 s while another session's LTX
  probe was running on this Mac. The slow ones are that, not the plugin.
- **Not run**: the suite with every plugin (`ALL=1 tools/conformance-with.sh`) on 1.7.0. The Mac's GPU was shared
  with another session's measurements.

## HairDeck 0.1.1 from GitHub through the released Gaea (2026-11-15)

The same run on `gaea-plugin-hairdeck` 0.1.1 (`37fb717`, GaeaPluginKit 0.13.1, still mlx-hairdeck-swift 0.2.1),
installed by repo URL from its public release; the same picture, box, body and seed; the merge by Item Studio's
`vrmMerge.js` (`VRMMERGE`) and mlx-3d's check tool at `12f24cd`, which judges rest at 5 s.
Evidence: [hairdeck-0.1.1/](hairdeck-0.1.1/acceptance.log).

| Run | Result |
|---|---|
| `tools/acceptance-hairdeck.sh` (`REPO_FROM=github`) | **32 passed, 0 failed** (the 31 checks of 0.1.0's re-run and one on memory) |
| mes-conformance v0.14.0 with only HairDeck installed | 41 passed, 1 failed, 74 skipped: Base and Mesh 0.1 conform; MESH-001 to 003, 005, 009, 010 and 013 to 018 pass; the failure is IMAGE-007, the suite's request (AB-A-0280) ([conformance.md](hairdeck-0.1.1/conformance.md)) |

- **The item** is `hairdeck-inproc`'s byte for byte in the same four cases, and the same item as 0.1.0's (15,160
  vertices, 36,836 faces, 30 springs). `hairdeck-inproc` here is the build of 14 November, before 0.1.1; the package
  it links didn't change.
- **Memory** ([memory.txt](hairdeck-0.1.1/memory.txt)): the lane declares **11.00 GB** (BiRefNet charged by
  `.composing(…, charged: true)`). The worker's peak footprint with BiRefNet run was 10.29 GB, and Gaea's log has no
  "held … past" line, where 0.1.0 logged 10.26 GB past 5.50 GB. At rest after jobs the worker holds 4.9 to 5.4 GB.
- **The merge** ([merge.txt](hairdeck-0.1.1/merge.txt)): 32 springs in the merged file (2 of the body, 30 of the
  item), the ends lag by up to 0.39 m, 1.82 cm from rest at 2.5 s (one soft chain) and at rest by 5 s: CHECK PASSED.
- **Refusals and inputs** as on 0.1.0. Warm jobs ran in 0.9 to 1.0 s.
- **Not run**: the suite with every plugin (`ALL=1`).
