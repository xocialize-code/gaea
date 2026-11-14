import CoreGraphics
import Foundation
import ImageIO
import MESCore
import Testing
import UniformTypeIdentifiers
import GaeaProtocol
import MLXToolKit
@testable import GaeaCore

/// A part made to fit a body (`mesh.generate_part`, AB-T-0482): what Gaea does to the worker's GLB, and to the request.
///
/// The fixture is a real HairDeck hair item (mlx-hairdeck-swift `out/ex02_spec.glb`, AB-R-0850): cards skinned to a
/// head bone and 34 chain bones, a colour texture on an MToon material, and 13 springs in `VRMC_springBone`.
@Suite struct MeshPartTests {
    static let item = repoRoot.appending(path: "Tests/Fixtures/meshes/hairdeck-hair-item.glb")
    static let dino = License(spdx: "LicenseRef-DINOv3", commercialUse: .yes, attribution: "Built with DINOv3")

    /// Read, stamped and written, the item keeps its BIN chunk byte for byte and every JSON member but `asset`:
    /// nodes, the skin and its inverse bind matrices, the spring bones, the material's extension, `extensionsUsed`.
    @Test func aSkinnedItemWithSpringBonesSurvivesTheStamp() throws {
        let original = try GLB(data: Data(contentsOf: Self.item))
        #expect(original.problems().isEmpty, "the item keeps Mesh §1.1–1.2")
        var glb = original
        GaeaEngine.stamp(&glb, license: Self.dino, title: "HairDeck", generated: true)
        let read = try GLB(data: glb.data())

        #expect(read.bin == original.bin)
        #expect(Set(read.json.keys) == Set(original.json.keys))
        for (key, value) in original.json where key != "asset" {
            #expect(read.json[key] == value, "\(key) changed")
        }
        // The things a client merging the item into a VRM depends on, by name.
        #expect(read.array("nodes").count == 36 && read.array("skins").count == 1)
        #expect(read.json["scenes"] == original.json["scenes"], "no root node was added")
        #expect(!read.array("nodes").contains { $0["name"]?.stringValue == "mes_placement" })
        let skin = try #require(read.object("skins", 0))
        #expect(skin["joints"]?.arrayValue?.count == 35)
        #expect(read.object("nodes", skin["skeleton"]?.intValue ?? -1)?["name"]?.stringValue == "J_Bip_C_Head")
        let bind = try #require(skin["inverseBindMatrices"]?.intValue)
        #expect(try read.floats(accessor: bind) == original.floats(accessor: bind))
        let primitive = try #require(read.primitives().first)
        for attribute in ["JOINTS_0", "WEIGHTS_0"] {
            let accessor = try #require(primitive.attributes[attribute])
            #expect(read.object("accessors", accessor) == original.object("accessors", accessor))
        }
        let springs = read.json["extensions"]?["VRMC_springBone"]?["springs"]?.arrayValue
        #expect(springs?.count == 13)
        #expect(read.json["extensions"] == original.json["extensions"])
        #expect(read.json["extensionsUsed"]?.arrayValue?.compactMap(\.stringValue).sorted() == ["VRMC_materials_mtoon", "VRMC_springBone"])
        #expect(read.json["extensionsRequired"] == nil)
        #expect(read.object("materials", 0)?["extensions"] == original.object("materials", 0)?["extensions"])

        // Where it is: the same bounds, to the bit. It was never placed.
        #expect(try read.facts() == original.facts())
        #expect(try read.facts().joints == 35)

        // And what the stamp did write: `asset` alone.
        #expect(read.asset["version"] == original.asset["version"])
        #expect(read.asset["generator"]?.stringValue == "Gaea \(Gaea.version) (HairDeck)")
        #expect(read.asset["copyright"]?.stringValue == "Built with DINOv3. LicenseRef-DINOv3")
        #expect(read.mesExtras["ai_generated"] == true && read.mesExtras["model"] == "HairDeck")
        #expect(read.mesExtras["attribution"] == "Built with DINOv3")
    }

    /// The preview is of the part where it is: Gaea draws it without moving it.
    @Test func theItemPreviews() throws {
        let glb = try GLB(data: Data(contentsOf: Self.item))
        let image = try MeshRender.preview(glb, size: 128)
        var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
        let ctx = CGContext(data: &pixels, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 128 * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        let opaque = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 200 }.count
        #expect(opaque > 128 * 128 / 10, "the hair fills a good part of the square")
        #expect(pixels[3] == 0, "on transparent")
    }

    /// The box is a share of the upright image, so a turned image reaches the worker upright; an upright PNG or JPEG
    /// goes as sent.
    @Test func aTurnedImageReachesTheWorkerUpright() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gaea-part-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // 6 wide, 2 high, its left third red: stored pixels.
        var pixels = [UInt8](repeating: 255, count: 6 * 2 * 4)
        for y in 0..<2 { for x in 0..<2 { pixels[(y * 6 + x) * 4 + 1] = 0; pixels[(y * 6 + x) * 4 + 2] = 0 } }
        let image = CGImage(width: 6, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 24,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        func write(_ name: String, type: UTType, orientation: Int?) throws -> URL {
            let url = dir.appending(path: name)
            let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
            var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
            if let orientation { properties[kCGImagePropertyOrientation] = orientation }
            CGImageDestinationAddImage(dest, image, properties as CFDictionary)
            #expect(CGImageDestinationFinalize(dest))
            return url
        }
        #expect(try GaeaEngine.uprightImage(write("plain.png", type: .png, orientation: nil), into: dir) == nil)
        #expect(try GaeaEngine.uprightImage(write("plain.jpg", type: .jpeg, orientation: 1), into: dir) == nil)
        let tiff = try #require(try GaeaEngine.uprightImage(write("plain.tiff", type: .tiff, orientation: nil), into: dir))
        #expect(tiff.pathExtension == "png")

        // Orientation 6: the stored image is shown turned a quarter clockwise, so upright it is 2 wide and 6 high, and the
        // stored left (red) is at the top.
        let turned = try #require(try GaeaEngine.uprightImage(write("turned.jpg", type: .jpeg, orientation: 6), into: dir))
        let source = try #require(CGImageSourceCreateWithURL(turned as CFURL, nil))
        let upright = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(upright.width == 2 && upright.height == 6)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect((properties?[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        var out = [UInt8](repeating: 0, count: 2 * 6 * 4)
        let ctx = CGContext(data: &out, width: 2, height: 6, bitsPerComponent: 8, bytesPerRow: 8,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(upright, in: CGRect(x: 0, y: 0, width: 2, height: 6))
        func isRed(row: Int) -> Bool { out[row * 8] > 200 && out[row * 8 + 1] < 60 }
        #expect(isRed(row: 0) && !isRed(row: 5))
    }

    /// The demo plugin's stand-in (`demo-part`, gaea-plugin-demo 0.5.0), as its worker wrote it over GPP for a VRoid
    /// body whose head bone is 1.37 m up: within Mesh §1.1–1.2, skinned, on the head, with and without its spring.
    @Test func theDemoStandInIsAPartGaeaServes() throws {
        for (name, joints, springs, textured) in [("demo-part-springs", 3, true, true), ("demo-part-plain", 1, false, false)] {
            var glb = try GLB(data: Data(contentsOf: repoRoot.appending(path: "Tests/Fixtures/meshes/\(name).glb")))
            #expect(glb.problems().isEmpty, "\(name): \(glb.problems())")
            let facts = try glb.facts()
            #expect(facts.joints == joints && facts.faces == 12)
            #expect((facts.textureSize != nil) == textured)
            #expect(facts.bounds.min[1] > 1.3 && facts.bounds.max[1] < 1.9, "above the head bone, in the body's metres")
            #expect(glb.object("nodes", 0)?["name"]?.stringValue == "J_Bip_C_Head")
            #expect((glb.json["extensions"]?["VRMC_springBone"] != nil) == springs)
            // The body's head bone, by MESKit's own rule, and every vertex fully bound (MESH-014).
            #expect(glb.bodyBone(for: MeshProfile.Part.hair)?.name == "J_Bip_C_Head")
            let weights = try glb.floats(accessor: try #require(glb.primitives().first?.attributes["WEIGHTS_0"]))
            #expect(weights.count == facts.vertices && weights.allSatisfy { abs($0.reduce(0, +) - 1) < 1e-6 })
            let before = glb
            GaeaEngine.stamp(&glb, license: License(spdx: "Apache-2.0", commercialUse: .yes), title: "Demo part", generated: true)
            let read = try GLB(data: glb.data())
            #expect(read.bin == before.bin && read.json["nodes"] == before.json["nodes"] && read.json["skins"] == before.json["skins"])
            #expect(read.mesExtras["ai_generated"] == true)
            #expect(try MeshRender.preview(read, size: 64).width == 64)
        }
    }

    /// The manifest of a plugin with a `characterPart` surface (contract 1.63.0) decodes: the demo's 0.5.0, and so
    /// HairDeck's. A Gaea on mlx-engine-swift before 0.78.0 can't read it.
    @Test func aCharacterPartManifestDecodes() throws {
        let data = try Data(contentsOf: repoRoot.appending(path: "Tests/Fixtures/manifests/demo-0.5.0.json"))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        let offer = try #require(manifest.offers.first { $0.operation == GaeaEngine.generatePart })
        #expect(offer.profile == MeshProfile.id && offer.modelID == "demo-part")
        let model = try #require(manifest.models.first { $0.id == "demo-part" })
        #expect(model.package.surfaces.first?.capability == .characterPart)
        #expect(model.package.surfaces.first?.characterPartControls?.requiresSubjectBox == true)
    }

    @Test func titleAndFormHints() {
        #expect(GaeaEngine.meshTitle(GaeaEngine.generatePart) == "Make a part for a character")
        #expect(GaeaEngine.meshUI("subject_box", order: 0)["widget"] == "box")
        #expect(GaeaEngine.meshUI("physics", order: 1)["label"] == "Spring bones")
    }
}
