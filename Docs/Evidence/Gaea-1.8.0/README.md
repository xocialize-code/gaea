# Gaea 1.8.0 and gaea-plugin-trellis2 0.2.0: Pixal3D, detail maps, valid normals

2026-11-15, Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3). A Release build of Gaea 1.8.0 (`f4d3b55`), run headless on
throwaway homes and ports, and then the released app; mes-conformance from media-engine-spec v0.14.0.

mlx-3d's mlx-trellis2-swift went from 0.12.1 to 0.17.0 (AB-A-0286): unit normals, a normal map and an ambient-occlusion
map as options, and Pixal3D. Pixal3D's camera is typed on mlx-engine-swift 0.79.0 (contract 1.64.0), so Gaea, the kit
and the plugin moved to it together.

## What changed

- **Gaea 1.8.0:** on mlx-engine-swift 0.79.0. Nothing else changes in the host.
- **GaeaPluginKit 0.14.0:** on the same engine; `ImageTo3DRequest.cameras` reaches a plugin's model.
- **gaea-plugin-trellis2 0.2.0** (`9aad418`, needs Gaea 1.8.0):
  - `pixal3d-1024` and `pixal3d-1536` on `mesh.generate`, by name only. `x-pixal3d.fov` is the photo's horizontal field
    of view, 20° by default, 1° to 119°.
  - Each Pixal3D model has two lanes that give the same GLB: `bf16` (71.3 and 76.2 GB) and `bf16-lowmem` (60.3 and
    65.2 GB), which keeps the flow weights in bf16.
  - `x-trellis2.normal_map` and `x-trellis2.ao_map` on every model, off by default.
  - Every normal is unit length.

The lanes were first named `fp32` and `bf16`. `tools/validate.py` refused that manifest: a lane that resolves a quant is
named after it (GPP-1 §4.7), and both lanes read bf16 weights.

## Results

| Run | Result | Log |
|---|---|---|
| Plugin unit tests | 6 passed | |
| Gaea unit tests | 113 passed | |
| `scripts/golden.sh`: the signed bundle over GPP against `trellis2-inproc` | 20 passed, 0 failed | [golden.log](golden.log) |
| Acceptance, the plugin's local build through a stand-in | 39 passed, 0 failed | [acceptance-standin.log](acceptance-standin.log) |
| Acceptance, `FULL=1`, the plugin's 0.2.0 release from GitHub (notarized) | 41 passed, 0 failed | [acceptance-github.log](acceptance-github.log) |
| Acceptance through the released app: `Gaea-1.8.0.zip` from GitHub (sha256 `407e1e9f…fdb70342`, Gatekeeper: Notarized Developer ID), the plugin from GitHub | 39 passed, 0 failed | [acceptance-released.log](acceptance-released.log) |
| Conformance with all 28 published plugins from GitHub and the 7 opt-in models | 107 passed, 0 failed, 9 skipped: Base, Image, Audio, Video and Mesh 0.1 conform | [conformance-all.md](conformance-all.md), [conformance-plugins.txt](conformance-plugins.txt) |

What the acceptance's new section shows (`tools/acceptance-trellis2.sh`, section 7):

- **Detail maps.** A default mesh has neither map. With both extensions the materials carry a normal and an occlusion
  texture and the mesh carries `TANGENT`; `effective` reports both; the face count is the plain run's.
- **Normals.** Every normal in the GLB is unit length.
- **Pixal3D by name.** `pixal3d-1024` runs on its `bf16` lane at 20°, and its geometry and texture are
  `trellis2-inproc`'s, byte for byte. An unnamed request never runs it.
- **Lanes.** `bf16-lowmem`, named, gives the `bf16` lane's buffers, byte for byte.
- **Field of view.** 49° gives another mesh. 150° is refused when it arrives.
- **Fallback.** With a 70 GB budget the `bf16` lane (71.3 GB) doesn't fit, and the job runs on `bf16-lowmem` with a
  `lane_fallback` warning and the same buffers.

The 9 conformance skips are the usual ones: paired mode (4), expiry waits (2), no Video offer with previews (1), and no
`mesh.rig` offer (2). The run used `JOB_TIMEOUT=900`, which `tools/conformance-with.sh` now passes to the suite.

## Times on this Mac

| Model | Job | Time |
|---|---|---|
| `trellis2-512` | 20,000 faces, 512 texture | 31 s |
| `trellis2-512` with both maps | the same | 32 s |
| `trellis2-1024` (quality best) | 100,000 faces, 1024 texture | 112 s |
| `trellis2-1536` | 100,000 faces, 2048 texture | 334 s |
| `pixal3d-1024`, `bf16` | 60,000 faces, 1024 texture, 20° | 148 s |
| `pixal3d-1024`, `bf16-lowmem` | the same | 149 s |
| `pixal3d-1024`, `bf16` | the same at 49° | 113 s |

The two Pixal3D lanes took the same time here. mlx-3d measured `bf16-lowmem` 8 to 15 % slower (AB-R-0870).

## The pictures

The fox photo (`Tests/Fixtures/fox.png`), previews rendered by Gaea:

- [pixal3d-1024-preview.png](pixal3d-1024-preview.png): Pixal3D at 1024, in the photo's view.
- [trellis2-1024-preview.png](trellis2-1024-preview.png): stock TRELLIS.2 at 1024, front-facing. It kept a slab of the
  ground under the fox.

## Not covered

- **`pixal3d-1536`.** It was offered and listed with its charges, but no job ran on it: neither the acceptance nor
  `golden.sh` without `FULL=1` makes one.
- **Memory.** The workers' peaks weren't measured here. The charges are mlx-trellis2-swift's declared footprints plus
  BiRefNet's 0.9 GB.
- **Khronos glTF validator.** Only the unit length of the normals was checked, not a validator run.
- **A real photo with a known lens.** The field of view was checked only for taking effect, not for which value suits
  a given photo.
- **Conformance and the `FULL=1` cases through the released app.** They ran on the local Release build of `f4d3b55`;
  the released app (`982d035`, the same sources) ran the acceptance without `FULL=1`.
