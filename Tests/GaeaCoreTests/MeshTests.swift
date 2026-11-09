import CoreGraphics
import Foundation
import ImageIO
import MESCore
import Testing
import UniformTypeIdentifiers
@testable import GaeaCore

/// What Gaea does around a mesh worker (Mesh 0.1, AB-T-0467): placement, the file's disclosure and licences, the preview.
@Suite struct MeshTests {
    /// A textured box, 2 × 1 × 0.5 model units, off the origin: a model's own scale and placement.
    static func box(texture: (UInt8, UInt8, UInt8) = (200, 30, 30)) throws -> GLB {
        let (x0, y0, z0, x1, y1, z1): (Float, Float, Float, Float, Float, Float) = (3, -1, 0.25, 5, 0, 0.75)
        var positions: [[Float]] = [], normals: [[Float]] = [], uvs: [[Float]] = [], indices: [UInt32] = []
        let faces: [([Float], [[Float]])] = [
            ([0, 0, 1], [[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]]),
            ([0, 0, -1], [[x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0]]),
            ([1, 0, 0], [[x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1]]),
            ([-1, 0, 0], [[x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0]]),
            ([0, 1, 0], [[x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0]]),
            ([0, -1, 0], [[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]]),
        ]
        for (normal, corners) in faces {
            let base = UInt32(positions.count)
            positions += corners
            normals += Array(repeating: normal, count: 4)
            uvs += [[0, 1], [1, 1], [1, 0], [0, 0]]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        let size = 8
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) { pixels[i * 4] = texture.0; pixels[i * 4 + 1] = texture.1; pixels[i * 4 + 2] = texture.2 }
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = NSMutableData()
        let dest = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        _ = CGImageDestinationFinalize(dest)
        return GLB.mesh(positions: positions, normals: normals, indices: indices, uvs: uvs, texture: png as Data)
    }

    @Test func centredAndScaledToSize() throws {
        var glb = try Self.box()
        try GaeaEngine.place(&glb, grounded: false, size: 1)
        // Round-trip through the file, as a client reads it.
        let facts = try GLB(data: glb.data()).facts()
        for k in 0..<3 { #expect(abs(facts.bounds.center[k]) < 1e-6) }
        #expect(abs((facts.bounds.extents.max() ?? 0) - 1) < 1e-6)
        #expect(abs(facts.bounds.extents[1] - 0.5) < 1e-6)
        #expect(glb.problems().isEmpty)
    }

    @Test func groundedStandsOnZero() throws {
        var glb = try Self.box()
        try GaeaEngine.place(&glb, grounded: true, size: 1.8)
        let bounds = try GLB(data: glb.data()).facts().bounds
        #expect(abs(bounds.min[1]) < 1e-6)
        #expect(abs(bounds.center[0]) < 1e-6 && abs(bounds.center[2]) < 1e-6)
        #expect(abs((bounds.extents.max() ?? 0) - 1.8) < 1e-6)
    }

    @Test func disclosureAndAttributionInTheFile() throws {
        var glb = try Self.box()
        let license = License(spdx: "LicenseRef-DINOv3", commercialUse: .yes, attribution: "Built with DINOv3")
        GaeaEngine.stamp(&glb, license: license, title: "TRELLIS.2 (512)", generated: true)
        let read = try GLB(data: glb.data())
        #expect(read.mesExtras["ai_generated"] == true)
        #expect(read.mesExtras["model"] == "TRELLIS.2 (512)")
        #expect(read.mesExtras["attribution"] == "Built with DINOv3")
        #expect(read.asset["copyright"]?.stringValue == "Built with DINOv3. LicenseRef-DINOv3")
        #expect(read.asset["generator"]?.stringValue?.hasPrefix("Gaea ") == true)

        // A permissive licence with nothing to show leaves the copyright alone.
        var plain = try Self.box()
        GaeaEngine.stamp(&plain, license: License(spdx: "MIT", commercialUse: .yes), title: "Rigger", generated: false)
        #expect(plain.asset["copyright"] == nil)
        #expect(plain.mesExtras["rigged_with"] == "Rigger")
        #expect(plain.mesExtras["ai_generated"] == nil)
    }

    @Test func previewDrawsTheTexturedObjectOnTransparent() throws {
        var glb = try Self.box()
        try GaeaEngine.place(&glb, grounded: false, size: 1)
        let image = try MeshRender.preview(glb, size: 256)
        #expect(image.width == 256 && image.height == 256)
        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
        let ctx = CGContext(data: &pixels, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256 * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        func at(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let i = (y * 256 + x) * 4
            return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
        }
        #expect(at(2, 2).3 == 0, "a corner is transparent")
        let centre = at(128, 128)
        #expect(centre.3 == 255, "the object fills the middle")
        #expect(centre.0 > centre.1 * 2 && centre.0 > centre.2 * 2, "in its texture's red, lit")
        // Framed to fill most of the square: some opaque pixel within 20 px of an edge.
        let near = (0..<256).contains { at($0, 20).3 > 0 || at($0, 235).3 > 0 || at(20, $0).3 > 0 || at(235, $0).3 > 0 }
        #expect(near)
    }

    @Test func transparencyIsDetected() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gaea-mesh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ alpha: UInt8, _ name: String) throws -> URL {
            var pixels = [UInt8](repeating: 255, count: 4 * 4 * 4)
            pixels[3] = alpha
            if alpha < 255 { pixels[0] = 0; pixels[1] = 0; pixels[2] = 0 }
            let image = CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let url = dir.appending(path: name)
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            _ = CGImageDestinationFinalize(dest)
            return url
        }
        #expect(try GaeaEngine.hasTransparency(write(0, "cut.png")))
        #expect(try !GaeaEngine.hasTransparency(write(255, "opaque.png")))
    }
}
