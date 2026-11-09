# MES conformance report

| | |
|---|---|
| **Engine** | Gaea (`eng_gaea_dustin_s_mac_studio_xpkayp`) · gaea 1.4.0 |
| **URL** | http://127.0.0.1:17691/mes/v0 · open |
| **Profiles** | mesh 0.1 |
| **Features** | uploads, sse, grants, previews, websocket, mcp, assets |
| **Suite** | MES conformance 0.1 · 2026-11-09T19:06:11Z |
| **Result** | 10 passed · 0 failed · 2 skipped |
| **Base 0.1** | ✅ conforms |
| **Mesh 0.1** | ✅ conforms for the operations offered |

| Test | Checks | Spec | Result |
|---|---|---|---|
| MESH-001 | Descriptors match the profile table: required inputs and outputs of the right kinds, only vocabulary parameters | Mesh §3, §6 | ✅ pass |
| MESH-002 | Offers' supports keys have the profile's types and their limits are the profile's fields | Mesh §4 | ✅ pass |
| MESH-003 | Mesh outputs are GLB by the conventions, report vertices, faces and bounds, the file agrees, and flat results are warned | Mesh §1.1, §1.2, §1.6, §1.8, Base §10.1 | ✅ pass: trellis2-512: 2528 vertices, 958 faces, 1024 px texture; trellis2-1024: 2420 vertices, 916 faces, 1024 px texture; trellis2-1536: 2420 vertices, 916 faces, 1024 px texture |
| MESH-004 | Placement: centered at the origin, grounded at Y = 0, the longest extent size_m | Mesh §1.4 | ✅ pass |
| MESH-005 | Every mesh output comes with a preview: a square PNG of at least 512 px with transparent pixels | Mesh §1.7 | ✅ pass |
| MESH-006 | generate: faces within max_faces; the offer's gates and limits refuse; texture_size with vertex colours is 400; effective reports | Mesh §2, §3.1, §4 | ✅ pass: texture_size with vertex_colors 400, trellis2-512 min_faces 422, trellis2-512 texture 422, trellis2-512 texture_size 422, trellis2-1024 min_faces 422, trellis2-1024 texture 422, trellis2-1024 texture_size 422, trellis2-1536 min_faces 422, trellis2-1536 texture 422, trellis2-1536 texture_size 422 |
| MESH-007 | generate: background removal is gated; a cut-out image is used as it is and reported as alpha | Mesh §1.10, §3.1 | ✅ pass: every offer removes backgrounds |
| MESH-008 | on_flat takes warn and fail; a result refused for flatness fails input_invalid with reason degenerate_result | Mesh §1.8 | ✅ pass |
| MESH-009 | Disclosure and licences: a generated mesh says ai_generated; an offer's attribution is in asset.copyright | Mesh §1.11, §1.12, Base §10.2 | ✅ pass: trellis2-512: "Built with DINOv3"; trellis2-1024: "Built with DINOv3"; trellis2-1536: "Built with DINOv3" |
| MESH-010 | seed is reported; the same seed reproduces the same mesh where the offer is deterministic | Mesh §1.14 | ✅ pass: mesh.generate / trellis2-512: the same seed gave identical files |
| MESH-011 | rig: geometry kept; one skin with joints and weights on every primitive; weights sum to 1; templates named; gates refuse | Mesh §3.2, §4.1 | ➖ skip: the engine offers none of mesh.rig |
| MESH-012 | rig input: a GLB with an embedded texture is accepted; bytes that aren't a GLB are input_invalid | Mesh §1.1, §3.2 | ➖ skip: the engine offers none of mesh.rig |
