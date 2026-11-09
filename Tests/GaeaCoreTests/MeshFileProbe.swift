import Foundation
import MESCore
import Testing
@testable import GaeaCore

/// A dev probe, not a check: GAEA_MESH_PROBE=<glb> runs a real model's GLB through Gaea's mesh path (problems, facts,
/// placement, stamp, preview) and writes <glb>.placed.glb and <glb>.preview.png beside it.
@Suite struct MeshFileProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GAEA_MESH_PROBE"] != nil)) func probe() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GAEA_MESH_PROBE"]!)
        var glb = try GLB(data: Data(contentsOf: url))
        print("problems:", glb.problems())
        let facts = try glb.facts()
        print("facts:", facts.vertices, facts.faces, facts.bounds, facts.textureSize as Any, "thinness", facts.bounds.thinness)
        try GaeaEngine.place(&glb, grounded: false, size: 1)
        GaeaEngine.stamp(&glb, license: License(spdx: "LicenseRef-DINOv3", commercialUse: .yes, attribution: "Built with DINOv3"),
                         title: "TRELLIS.2 512", generated: true)
        try glb.data().write(to: url.appendingPathExtension("placed.glb"))
        let start = Date()
        let image = try MeshRender.preview(glb, size: 768)
        print("preview in", Date().timeIntervalSince(start), "s")
        try MeshRender.writePNG(image, to: url.appendingPathExtension("preview.png"), comment: "AI-generated with TRELLIS.2 512.", copyright: "Built with DINOv3")
    }
}
