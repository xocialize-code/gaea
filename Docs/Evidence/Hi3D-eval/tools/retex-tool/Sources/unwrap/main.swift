import Foundation
import MLX
import MLXMesh

// Parallel xatlas unwrap (the port's MeshBake lane): unwrap <in.npz-dir> — reads verts.npy/faces.npy,
// writes vmap.npy (int32), faces_uv.npy (int32), uv.npy (float32) into the same directory.
setvbuf(stdout, nil, _IONBF, 0)
let dir = CommandLine.arguments[1]
func url(_ n: String) -> URL { URL(fileURLWithPath: "\(dir)/\(n).npy") }
var mesh = Mesh(vertices: try loadArray(url: url("verts")).asType(.float32),
                faces: try loadArray(url: url("faces_in")).asType(.int32))
let t = Date()
// CLEAN="<minComponentArea>,<maxHolePerimeter>[,<repairNonManifold 0|1>]": CuMesh-style cleanup before the unwrap.
if let spec = ProcessInfo.processInfo.environment["CLEAN"] {
    let p = spec.split(separator: ",").compactMap { Float($0) }
    let before = (mesh.faceCount, mesh.boundaryLoops().count)
    mesh = mesh.removeDuplicateFaces()
    if p.count > 2, p[2] != 0 { mesh = mesh.repairNonManifoldEdges() }   // third field 1: split non-manifold edges
    mesh = mesh.removeSmallConnectedComponents(minArea: p[0]).fillHoles(maxHolePerimeter: p[1])
        .removeUnreferencedVertices()
    print("clean: \(before.0) faces, \(before.1) loops -> \(mesh.faceCount) faces, \(mesh.boundaryLoops().count) loops, \(mesh.componentCount()) components")
}
try save(array: mesh.vertices.asType(.float32), url: url("verts_clean"))
let uv = try mesh.uvUnwrapParallel()
try save(array: uv.vertexMap.asType(.int32), url: url("vmap"))
try save(array: uv.mesh.faces.asType(.int32), url: url("faces_uv"))
try save(array: uv.uvs.asType(.float32), url: url("uv"))
print(String(format: "unwrap: %d faces -> %d verts, %d charts in %.1fs", mesh.faceCount, uv.mesh.vertexCount, uv.charts.count, -t.timeIntervalSinceNow))
