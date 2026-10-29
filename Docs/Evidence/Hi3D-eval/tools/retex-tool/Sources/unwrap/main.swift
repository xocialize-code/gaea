import Foundation
import MLX
import MLXMesh

// Parallel xatlas unwrap (the port's MeshBake lane): unwrap <in.npz-dir> — reads verts.npy/faces.npy,
// writes vmap.npy (int32), faces_uv.npy (int32), uv.npy (float32) into the same directory.
setvbuf(stdout, nil, _IONBF, 0)
let dir = CommandLine.arguments[1]
func url(_ n: String) -> URL { URL(fileURLWithPath: "\(dir)/\(n).npy") }
let mesh = Mesh(vertices: try loadArray(url: url("verts")).asType(.float32),
                faces: try loadArray(url: url("faces_in")).asType(.int32))
let t = Date()
let uv = try mesh.uvUnwrapParallel()
try save(array: uv.vertexMap.asType(.int32), url: url("vmap"))
try save(array: uv.mesh.faces.asType(.int32), url: url("faces_uv"))
try save(array: uv.uvs.asType(.float32), url: url("uv"))
print(String(format: "unwrap: %d faces -> %d verts, %d charts in %.1fs", mesh.faceCount, uv.mesh.vertexCount, uv.charts.count, -t.timeIntervalSinceNow))
