# AB-T-0467: 3D in Gaea (MES Mesh 0.1) with TRELLIS.2

Gaea 1.4.0 serves MES Mesh 0.1's `mesh.generate` from plugin offers. Its first 3D plugin is gaea-plugin-trellis2 0.1.0.
On 2026-11-09 the operator decided 3D belongs in Gaea, not in a separate server, because one Mac's memory has to sit
under one scheduler.

All runs were on a Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3) with Release builds. The full outputs are on
`/Volumes/DEV_VOL1/Evidence/AB-T-0467`.

## What was built

| Piece | Version | What |
|---|---|---|
| media-engine-spec (mlx-apps) | v0.11.0, v0.12.0 | Mesh 0.1 (RFC 0007); `prepare_ms`, the idle policy and `resident_until` on `/health` (AB-A-0260, AB-A-0261) |
| pixel-agency-normalizer (mlx-apps) | v0.3.1 | RGB PNGs for opaque images (AB-A-0260) |
| mlx-trellis2-swift (mlx-3d) | v0.11.0 → v0.12.1 | Per-tier lanes with bounded footprints (AB-A-0262, AB-R-0811); per-request options, byte-identical GLBs for a seed, PBR maps (AB-A-0263, AB-R-0814); `decimateFaces` as a hard ceiling, weights loaded at prepare (AB-A-0265, AB-R-0815) |
| GaeaPluginKit | 0.12.0 | Companion models: a model prepares and lists the weights of another engine model it composes with (BiRefNet) |
| gaea-plugin-trellis2 | 0.1.0 | Three models, one per resolution (`trellis2-512` 38 GB, `trellis2-1024` 69 GB, `trellis2-1536` 72 GB), BiRefNet as a companion; engine 0.74.1 and the mlx-swift fork 0.32.4 pinned exactly |
| Gaea | 1.4.0 | `GaeaMesh`: background, placement and size, the disclosure and licences in the GLB, a 768² preview Gaea renders; `/health`'s idle policy; GPP-1 §3.3.4 |

## Results

- **The plugin against in-process, byte for byte** (`scripts/golden.sh`, [golden.log](golden.log)): 8/8. Four cases at
  512 (background removed, already cut out, kept whole, another seed and texture size) gave the same GLB over GPP on the
  signed bundle as in-process, and every transcript validates. The first run found a mesh over its face cap: 36,314 for a
  cap of 20,000. mlx-3d fixed it in v0.12.1 (AB-A-0265), and the same case now gives 19,774.
- **The acceptance, from GitHub** ([acceptance-github.log](acceptance-github.log)): 24/24.
  - The descriptor and its three tiers, and `/health`'s idle policy and `resident_until`.
  - The default request runs trellis2-512 in about 35 s.
  - The GLB follows Mesh §1.1–1.2. It carries the disclosure and "Built with DINOv3", is centred and 1 m long, and its
    facts agree with the file. `prepare_ms` is reported.
  - The preview is 768², transparent at the corners, and carries the comment and the copyright.
  - The geometry and texture are byte for byte trellis2-inproc's, CI's build against a local one.
  - Alpha, keep and grounded each behave as asked. The same seed gives the same model buffers.
  - Four refusals.
  - A preview server: with the 1024 and 1536 tiers disabled, only draft and standard are offered and `best` is refused;
    with a 51.54 GB budget only trellis2-512 is offered.
- **The acceptance, from a stand-in**, came before the release ([acceptance-standin.log](acceptance-standin.log)): 21/24.
  The three failures were in the checks, not in Gaea. ImageIO writes the PNG's text as XMP, Python has no AppKit
  here, and MESKit answers an unknown `texture_size` with 422 `out_of_limits`. All three were fixed with
  `tools/png-facts.py`.
- **Conformance with every published plugin and the opt-in models** ([conformance-all.md](conformance-all.md)): 93
  passed, 5 failed, 9 skipped. Base, Image, Audio and Video conform. The 5 failures were MESH-003, 004, 005, 009 and 010
  timing out at the suite's 180 s per job, with TRELLIS.2 jobs queued behind the first load. Rerun alone with
  `--job-timeout 900` ([conformance-mesh.md](conformance-mesh.md)), Mesh 0.1 conforms: 10 passed, and 2 skipped because
  nothing offers `mesh.rig`. MESH-003 made meshes on all three tiers, including the 1024 and 1536 cascades.
- **The preview** ([fox-preview.png](fox-preview.png)): the fox photo as TRELLIS.2 512 makes it, rendered by Gaea.

## What a TRELLIS.2 job costs

On this Mac, with BiRefNet in the same worker (AB-R-0811, AB-R-0814):

| Tier | Peak | Charged | Time |
|---|---|---|---|
| 512 | about 31 GB (34.7 GB with a 2048 texture) | 38 GB | 35 to 50 s warm |
| 1024 | about 61 GB | 69 GB | 8 to 9 min |
| 1536 | about 65 GB | 72 GB | 7 to 11 min |

The check script's 512 job peaked at 27.6 GB.

## Not covered

- A job at 1024 or 1536 at full detail. Conformance ran both cascades only at 1,000 faces, and the acceptance's
  `FULL=1` cases were not run.
- Determinism across different Macs or builds. mlx-3d expects identical bytes only for the same GPU, macOS and build.
- A worker crash seen before v0.12.1 (a GPU timeout in BiRefNet's first predict) wasn't reproduced after it. mlx-3d
  moved TRELLIS.2's weight loading to prepare, and BiRefNet's lazy load went to mlx-image as AB-A-0266.
- Orientation: TRELLIS.2 makes objects in its own front-facing frame, so a three-quarter photo comes out front-on.
  AB-A-0264 asks mlx-apps to make Mesh §1.3 promise only that the object's front faces +Z.
