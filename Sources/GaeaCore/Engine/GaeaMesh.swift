import CoreGraphics
import Foundation
import GaeaProtocol
import ImageIO
import simd
import MESCore
import MESEngineCore
import UniformTypeIdentifiers

// MARK: - The Mesh profile

/// The Mesh profile (MES Mesh 0.1, media-engine-spec v0.11.0, AB-T-0467). Every mesh offer runs as itself, as audio and
/// video offers do: MESKit validates, gates and routes the request from the offers' own `supports` and `limits`
/// (`MeshProfileRules`), and reads each result's facts and checks it for flatness. The worker runs its model and writes a
/// GLB; Gaea does what the profile asks of the engine around it:
///
/// - **The object** (§1.10, §3.1): an image with transparency is already cut out, and the worker is told so; an opaque
///   one is cut out where the offer can, else used whole with `background_kept`.
/// - **Placement and size** (§1.4): the result is centred (or stood on Y = 0) and scaled to `size_m`, by a root node over
///   the scene, so the model's own vertices are kept as it wrote them.
/// - **Disclosure and licences** (§1.11, §1.12): `asset.extras.mes` and `asset.copyright` in the file.
/// - **The preview** (§1.7): a square PNG of the result, rendered by Gaea with the mesh's own texture, on transparent.
extension GaeaEngine {
    /// The preview's side in pixels: 768, drawn at twice that and scaled down.
    static let meshPreviewSize = 768

    /// One descriptor per Mesh operation some enabled plugin offers.
    func meshDescriptors(_ routes: [PluginRoute]) -> [Descriptor] {
        let mesh = routes.filter { $0.manifestOffer.profile == MeshProfile.id }
        return Set(mesh.map(\.operation)).sorted().compactMap { operation in
            Self.meshDescriptor(operation, routes: mesh.filter { $0.operation == operation })
        }
    }

    static func meshDescriptor(_ operation: String, routes: [PluginRoute]) -> Descriptor? {
        guard let spec = MeshProfile.operations.operations[operation], !routes.isEmpty else { return nil }
        let models = Self.audioModels(routes)
        let inputs = spec.inputs.sorted { $0.key < $1.key }.map { name, io -> InputSpec in
            let types: [String]? = switch io.kind {
            case .image: ["image/png", "image/jpeg", "image/webp", "image/heic", "image/tiff"]
            case .mesh: [MeshProfile.mediaType]
            default: nil
            }
            return InputSpec(name: name, kind: io.kind, required: io.required ?? false, max: io.kind == .text ? nil : 1, mediaTypes: types)
        }
        var properties: [String: MESValue] = [:]
        for (order, name) in spec.vocabulary.enumerated() {
            guard case .object(var schema)? = MeshProfile.vocabularySchema(name, operation: operation) else { continue }
            schema["x-mes-ui"] = .object(meshUI(name, order: order))
            properties[name] = .object(schema)
        }
        let outputs = spec.outputs.sorted { $0.key < $1.key }.map { name, io in
            OutputSpec(name: name, kind: io.kind, mediaTypes: io.kind == .mesh ? [MeshProfile.mediaType] : ["image/png"], min: 1, max: 1)
        }
        let tiers = QualityTier.allCases.filter { tier in models.contains { $0.qualityTiers.contains(tier) } }
        return Descriptor(
            operation: operation, profile: MeshProfile.id, profileVersion: MeshProfile.version, title: meshTitle(operation),
            summary: nil, inputs: inputs,
            params: .object(["type": "object", "additionalProperties": false, "properties": .object(properties)]),
            outputs: outputs, limits: audioLimits(models), qualityTiers: tiers, models: models, remote: .init(possible: false))
    }

    static func meshTitle(_ operation: String) -> String {
        ["mesh.generate": "Make a 3D model", "mesh.rig": "Rig a 3D model"][operation] ?? operation
    }

    static func meshUI(_ name: String, order: Int) -> [String: MESValue] {
        let widgets = ["seed": "seed", "quality": "picker", "resolution": "picker", "max_faces": "stepper", "texture": "picker",
                       "texture_size": "picker", "background": "picker", "placement": "picker", "size_m": "stepper",
                       "on_flat": "picker", "skeleton": "picker"]
        let labels = ["max_faces": "Most faces", "texture_size": "Texture size", "size_m": "Size (m)", "on_flat": "If it comes out flat"]
        var hints: [String: MESValue] = ["label": .string(labels[name] ?? name.replacingOccurrences(of: "_", with: " ").capitalized),
                                         "order": .number(Double(order))]
        if let widget = widgets[name] { hints["widget"] = .string(widget) }
        if ["seed", "resolution", "on_flat", "texture"].contains(name) { hints["advanced"] = true }
        return hints
    }

    // MARK: Running

    /// One mesh offer, run as itself.
    func runMesh(_ route: PluginRoute, _ context: RunContext) async throws -> RunOutput {
        typealias P = MeshProfile.Param
        let workerDirectory = context.outputDirectory.appending(path: "worker", directoryHint: .isDirectory)
        let inputDirectory = context.outputDirectory.appending(path: "worker-inputs", directoryHint: .isDirectory)
        var params = route.manifestOffer.defaults?.objectValue ?? [:]
        for (key, value) in context.params { params[key] = value.gpp }
        var warnings: [Warning] = []
        let title = route.offer.title ?? route.model.title
        var inputs = context.inputs

        if route.operation == "mesh.generate" {
            // §1.10, §3.1: what the object is cut out of.
            guard case .file(let url, _)? = context.inputs[MeshProfile.Input.image]?.first else {
                throw MESError(.invalidRequest, "Input 'image' is missing.", param: MeshProfile.Input.image)
            }
            let canRemove = route.offer.supports(MeshProfile.SupportsKey.backgroundRemoval)?.boolValue == true
            let background: String
            if try Self.hasTransparency(url) {
                background = MeshProfile.alpha
            } else if let asked = context.param(P.background)?.stringValue {
                background = asked
            } else if canRemove {
                background = "remove"
            } else {
                background = "keep"
                warnings.append(Warning(code: MeshProfile.WarningCode.backgroundKept,
                                        message: "\(title) can't remove a background; the whole picture was used.", param: P.background))
            }
            params[P.background] = .string(background)
            // Workers read PNG or JPEG (GPP-1 §3.3.4): anything else ImageIO reads becomes a PNG, alpha kept.
            if !["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) {
                inputs[MeshProfile.Input.image] = [.file(try Self.workerPNG(url, into: inputDirectory), mediaType: "image/png")]
            }
            // §1.9: an offer's default above its limit (an operator's cap, Gaea 1.5.0) is reduced to it, with a warning;
            // a request's own value past the limit never gets here (MESKit refuses it).
            let limits = route.offer.limits
            if context.param(P.maxFaces) == nil, let most = limits?.value(MeshProfile.LimitField.maxFaces),
               let faces = params[P.maxFaces]?.doubleValue, faces > most {
                params[P.maxFaces] = .int(Int64(most))
                warnings.append(Warning(code: MeshProfile.WarningCode.facesReduced,
                                        message: "\(title) makes \(Int(faces)) faces by default; this server's limit cut them to at most \(Int(most)).",
                                        param: P.maxFaces))
            }
            if context.param(P.textureSize) == nil, let most = limits?.value(MeshProfile.LimitField.maxTextureSize),
               let size = params[P.textureSize]?.doubleValue, size > most {
                let allowed = (route.offer.supports(MeshProfile.SupportsKey.textureSizes)?.arrayValue?.compactMap(\.numberValue) ?? [most])
                    .filter { $0 <= most }.max() ?? most
                params[P.textureSize] = .int(Int64(allowed))
                warnings.append(Warning(code: MeshProfile.WarningCode.textureReduced,
                                        message: "\(title)'s \(Int(size)) px texture was made at \(Int(allowed)) px, this server's limit.",
                                        param: P.textureSize))
            }
            // The offer's one resolution, or the request's (MESKit's gate admits only one the offer lists).
            if params[P.resolution] == nil,
               let first = route.offer.supports(MeshProfile.SupportsKey.resolutions)?.arrayValue?.first?.numberValue {
                params[P.resolution] = .int(Int64(first))
            }
        } else if case .file(let url, _)? = context.inputs[MeshProfile.Input.mesh]?.first {
            // §1.1: a mesh input is a GLB this engine reads; §3.2: its faces within the offer's limit.
            let glb: GLB
            do { glb = try GLB(data: Data(contentsOf: url)) } catch {
                throw MESError(.inputInvalid, "Input 'mesh' isn't a GLB: \(error).", param: MeshProfile.Input.mesh)
            }
            let facts = try glb.facts()
            if let most = route.offer.limits?.value(MeshProfile.LimitField.maxInputFaces), Double(facts.faces) > most {
                throw MESError(.outOfLimits, "The mesh has \(facts.faces) faces; \(title) rigs at most \(Int(most)).",
                               param: MeshProfile.Input.mesh)
            }
        }

        let names = Set(route.extensions.map(\.name))
        let modelParams = context.extensions.filter { names.contains($0.key) }.mapValues(\.gpp)
        let job = WorkerJob(
            job: context.jobID, pluginID: route.plugin.id, model: route.model.id, operation: route.operation,
            namedLane: context.extensions[Self.laneExtension]?.stringValue, lanes: route.manifestOffer.lanes,
            params: params, inputs: try Self.inputPaths(inputs, writingTextTo: inputDirectory), modelParams: modelParams,
            seed: context.param(P.seed)?.intValue, outputDir: workerDirectory)
        let ran = try await schedule(job, title: route.plugin.title, context: context)

        var effective = ran.result["effective"]?.objectValue?.mapValues(\.mes) ?? [:]
        var outputs: [ProducedOutput] = []
        let produced = try Self.producedOutputs(result: ran.result, chunks: [], workerDirectory: workerDirectory,
                                                outputDirectory: context.outputDirectory, specs: context.descriptor.outputs)
        let placement = context.param(P.placement)?.stringValue ?? "centered"
        let size = context.param(P.size)?.numberValue ?? 1
        for output in produced {
            // The worker's own preview, if it wrote one, is replaced by Gaea's of the placed result.
            if output.name == MeshProfile.Output.preview { continue }
            guard output.kind == .mesh, let file = output.file else { outputs.append(output); continue }
            var glb: GLB
            do { glb = try GLB(data: Data(contentsOf: file)) } catch {
                throw MESError(.engineError, "\(title) wrote a mesh Gaea can't read: \(error).")
            }
            let problems = glb.problems()
            guard problems.isEmpty else {
                throw MESError(.engineError, "\(title) wrote a GLB that breaks Mesh §1.1–1.2: \(problems.joined(separator: "; ")).")
            }
            let generated = route.operation == "mesh.generate"
            if generated { try Self.place(&glb, grounded: placement == "grounded", size: size) }
            Self.stamp(&glb, license: route.offer.license, title: title, generated: generated)
            let meshURL = context.outputDirectory.appending(path: "\(output.name).glb")
            try glb.data().write(to: meshURL)
            if meshURL != file { try? FileManager.default.removeItem(at: file) }
            outputs.append(.mesh(meshURL, name: output.name))

            await context.reporter.progress(.running, phase: MeshProfile.Phase.render)
            let previewURL = context.outputDirectory.appending(path: "preview.png")
            let image = try MeshRender.preview(glb, size: Self.meshPreviewSize)
            try MeshRender.writePNG(image, to: previewURL, comment: generated ? MeshProfile.disclosure(model: title) : nil,
                                    copyright: Self.copyright(route.offer.license))
            outputs.append(.file(previewURL, name: MeshProfile.Output.preview, kind: .image, mediaType: "image/png",
                                 width: Self.meshPreviewSize, height: Self.meshPreviewSize))
        }
        if route.operation == "mesh.generate" {
            effective[P.placement] = .string(placement)
            effective[P.size] = .number(size)
            for key in [P.background, P.resolution] where effective[key] == nil { effective[key] = params[key]?.mes }
        }
        let seeded = route.offer.supports("seed")?.boolValue != false
        var output = RunOutput(outputs: outputs, effective: effective,
                               seed: seeded ? effective["seed"]?.intValue ?? context.param(P.seed)?.intValue : nil)
        Self.attach(ran, plugin: route.plugin, model: route.model.id, operation: route.operation, to: &output)
        for warning in warnings where !output.warnings.contains(warning) { output.warnings.append(warning) }
        return output
    }

    /// An image as a PNG a worker reads, alpha kept.
    static func workerPNG(_ url: URL, into directory: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MESError(.inputInvalid, "Input 'image' isn't an image Gaea can read.", param: MeshProfile.Input.image)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let out = directory.appending(path: "image-0.png")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw MESError(.engineError, "Gaea couldn't convert the image for the model.")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw MESError(.engineError, "Gaea couldn't convert the image for the model.") }
        return out
    }

    /// Whether an image has a pixel that isn't fully opaque (Mesh §1.10).
    static func hasTransparency(_ url: URL) throws -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MESError(.inputInvalid, "Input 'image' isn't an image Gaea can read.", param: MeshProfile.Input.image)
        }
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let (w, h) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 255 }
    }

    /// Places the scene (Mesh §1.4): a new root node over the default scene's roots, scaling uniformly so the longest
    /// extent is `size` metres and moving the box's centre to the origin (or its lowest point to Y = 0).
    static func place(_ glb: inout GLB, grounded: Bool, size: Double) throws {
        let bounds = try glb.facts().bounds
        let (scale, offset) = MeshProfile.placement(bounds, grounded: grounded, size: size)
        let sceneIndex = glb.json["scene"]?.intValue ?? 0
        var scene = glb.object("scenes", sceneIndex) ?? [:]
        let nodes = glb.array("nodes")
        let roots = scene["nodes"]?.arrayValue?.compactMap(\.intValue)
            ?? Array(0..<nodes.count).filter { n in !nodes.contains { $0["children"]?.arrayValue?.contains(.number(Double(n))) == true } }
        let root = glb.append("nodes", .object([
            "name": "mes_placement",
            "children": .array(roots.map { .number(Double($0)) }),
            "scale": .array([.number(scale), .number(scale), .number(scale)]),
            "translation": .array(offset.map { .number($0) }),
        ]))
        scene["nodes"] = [.number(Double(root))]
        if glb.array("scenes").isEmpty {
            glb.json["scenes"] = .array([.object(scene)])
            glb.json["scene"] = 0
        } else {
            glb.set("scenes", sceneIndex, scene)
        }
    }

    /// The licence and disclosure in the file (Mesh §1.11, §1.12; Base §10.2 rule 2). `mesh.rig` keeps the input's and
    /// adds its own model as `rigged_with`.
    static func stamp(_ glb: inout GLB, license: License, title: String, generated: Bool) {
        var extras = glb.mesExtras
        if generated {
            extras["ai_generated"] = true
            extras["model"] = .string(title)
        } else {
            extras["rigged_with"] = .string(title)
        }
        var asset = glb.asset
        asset["generator"] = .string("Gaea \(Gaea.version) (\(title))")
        if license.attribution != nil || license.notice != nil || license.commercialUse != .yes {
            let previous = asset["copyright"]?.stringValue
            let own = copyright(license)
            asset["copyright"] = .string([previous, own].compactMap { $0 }.filter { !$0.isEmpty }.uniqued().joined(separator: "; "))
            extras["license"] = .string(license.spdx)
            if let notice = license.notice { extras["notice"] = .string(notice) }
            if let attribution = license.attribution { extras["attribution"] = .string(attribution) }
        }
        glb.asset = asset
        glb.mesExtras = extras
    }

    /// A licence's attribution, then its SPDX id (Base §10.2 rule 2's GLB row).
    static func copyright(_ license: License) -> String {
        [license.attribution, license.spdx].compactMap { $0 }.joined(separator: ". ")
    }
}

// MARK: - The preview

/// The still every mesh output comes with (Mesh §1.7): orthographic, from azimuth 30° (from +Z towards +X) and elevation
/// 20°, framed to fill most of the square, on transparent; each pixel is the mesh's base colour (its texture, `COLOR_0`,
/// or its material's factor) lit by a key and a fill light. Drawn with a depth buffer at twice the size, then halved.
enum MeshRender {
    struct Texture {
        var width: Int, height: Int
        var pixels: [UInt8] // RGBA, straight alpha, row 0 at the top (glTF's v = 0)

        func sample(_ u: Float, _ v: Float) -> SIMD4<Float> {
            let fu = u - u.rounded(.down), fv = v - v.rounded(.down)
            let x = min(width - 1, max(0, Int(fu * Float(width)))), y = min(height - 1, max(0, Int(fv * Float(height))))
            let i = (y * width + x) * 4
            return SIMD4(Float(pixels[i]), Float(pixels[i + 1]), Float(pixels[i + 2]), Float(pixels[i + 3])) / 255
        }
    }

    static func decode(_ data: Data) -> Texture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let (w, h) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Texture(width: w, height: h, pixels: pixels)
    }

    static func preview(_ glb: GLB, size: Int) throws -> CGImage {
        let n = size * 2
        let az = 30.0 * Double.pi / 180, el = 20.0 * Double.pi / 180
        let toCamera = SIMD3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
        let right = simd_normalize(simd_cross(SIMD3<Double>(0, 1, 0), toCamera))
        let up = simd_cross(toCamera, right)
        let key = simd_normalize(toCamera + SIMD3(-0.4, 0.8, 0.2)), fill = simd_normalize(SIMD3(0.6, 0.2, -0.3))

        struct Part { var screen: [SIMD3<Float>]; var normals: [SIMD3<Float>]?; var uvs: [SIMD2<Float>]?; var colors: [SIMD4<Float>]?
                      var triangles: [UInt32]; var texture: Texture?; var factor: SIMD4<Float> }
        var parts: [Part] = []
        var textures: [Int: Texture] = [:]
        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        for p in glb.primitives() where p.mode == 4 {
            let world = try glb.worldPositions(p)
            var screen: [SIMD3<Float>] = []
            screen.reserveCapacity(world.count)
            for w in world {
                let v = SIMD3(w[0], w[1], w[2])
                let s = SIMD3(simd_dot(v, right), simd_dot(v, up), simd_dot(v, toCamera))
                lo = simd_min(lo, SIMD2(s.x, s.y)); hi = simd_max(hi, SIMD2(s.x, s.y))
                screen.append(SIMD3<Float>(s))
            }
            // Normals in camera space: the node's rotation (and any scale) applied, then renormalised.
            var normals: [SIMD3<Float>]?
            if let a = p.attributes["NORMAL"], let ns = try? glb.floats(accessor: a), ns.count == world.count {
                let m = p.world
                normals = ns.map { n in
                    let x = Double(n[0]), y = Double(n[1]), z = Double(n[2])
                    let w = SIMD3(m[0] * x + m[4] * y + m[8] * z, m[1] * x + m[5] * y + m[9] * z, m[2] * x + m[6] * y + m[10] * z)
                    let len = simd_length(w)
                    let u = len > 0 ? w / len : w
                    return SIMD3<Float>(Float(simd_dot(u, right)), Float(simd_dot(u, up)), Float(simd_dot(u, toCamera)))
                }
            }
            var uvs: [SIMD2<Float>]?
            if let a = p.attributes["TEXCOORD_0"], let ts = try? glb.floats(accessor: a), ts.count == world.count {
                uvs = ts.map { SIMD2($0[0], $0[1]) }
            }
            var colors: [SIMD4<Float>]?
            if let a = p.attributes["COLOR_0"], let cs = try? glb.floats(accessor: a), cs.count == world.count {
                colors = cs.map { SIMD4($0[0], $0[1], $0[2], $0.count > 3 ? $0[3] : 1) }
            }
            var factor = SIMD4<Float>(0.8, 0.8, 0.82, 1)
            var texture: Texture?
            if let m = p.material, let material = glb.object("materials", m), let pbr = material["pbrMetallicRoughness"]?.objectValue {
                if let f = pbr["baseColorFactor"]?.arrayValue?.compactMap(\.numberValue), f.count == 4 {
                    factor = SIMD4(f.map(Float.init))
                } else {
                    factor = SIMD4(1, 1, 1, 1)
                }
                if let t = pbr["baseColorTexture"]?["index"]?.intValue, let image = glb.object("textures", t)?["source"]?.intValue {
                    if textures[image] == nil, let (data, _) = try? glb.image(image), let decoded = decode(data) { textures[image] = decoded }
                    texture = textures[image]
                }
            }
            parts.append(Part(screen: screen, normals: normals, uvs: texture == nil ? nil : uvs, colors: colors,
                              triangles: try glb.triangles(p), texture: texture, factor: factor))
        }
        let span = max(hi.x - lo.x, hi.y - lo.y, 1e-9)
        let scale = Float(0.88 * Double(n) / span)
        let center = SIMD2<Float>(Float((lo.x + hi.x) / 2), Float((lo.y + hi.y) / 2))
        let half = Float(n) / 2

        var depth = [Float](repeating: -.infinity, count: n * n)
        var color = [SIMD4<Float>](repeating: .zero, count: n * n)
        let keyF = SIMD3<Float>(key), fillF = SIMD3<Float>(fill)
        for part in parts {
            let pts = part.screen.map { s in SIMD3(half + (s.x - center.x) * scale, half - (s.y - center.y) * scale, s.z) }
            var t = 0
            while t + 2 < part.triangles.count {
                let ia = Int(part.triangles[t]), ib = Int(part.triangles[t + 1]), ic = Int(part.triangles[t + 2])
                t += 3
                guard ia < pts.count, ib < pts.count, ic < pts.count else { continue }
                let a = pts[ia], b = pts[ib], c = pts[ic]
                let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
                guard abs(area) > 1e-12 else { continue }
                let x0 = max(0, Int(min(a.x, b.x, c.x).rounded(.down))), x1 = min(n - 1, Int(max(a.x, b.x, c.x).rounded(.up)))
                let y0 = max(0, Int(min(a.y, b.y, c.y).rounded(.down))), y1 = min(n - 1, Int(max(a.y, b.y, c.y).rounded(.up)))
                guard x0 <= x1, y0 <= y1 else { continue }
                let faceNormal: SIMD3<Float> = {
                    let fn = simd_cross(SIMD3(b.x - a.x, a.y - b.y, b.z - a.z), SIMD3(c.x - a.x, a.y - c.y, c.z - a.z))
                    let len = simd_length(fn)
                    return len > 0 ? fn / len : SIMD3(0, 0, 1)
                }()
                for y in y0...y1 {
                    let py = Float(y) + 0.5
                    for x in x0...x1 {
                        let px = Float(x) + 0.5
                        let w0 = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
                        let w1 = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
                        let w2 = 1 - w0 - w1
                        guard w0 >= 0, w1 >= 0, w2 >= 0 else { continue }
                        let z = w0 * a.z + w1 * b.z + w2 * c.z
                        let i = y * n + x
                        guard z > depth[i] else { continue }
                        var base = part.factor
                        if let uvs = part.uvs, let texture = part.texture {
                            let uv = w0 * uvs[ia] + w1 * uvs[ib] + w2 * uvs[ic]
                            base *= texture.sample(uv.x, uv.y)
                        }
                        if let colors = part.colors { base *= w0 * colors[ia] + w1 * colors[ib] + w2 * colors[ic] }
                        guard base.w > 0.02 else { continue }
                        var normal = faceNormal
                        if let ns = part.normals {
                            let s = w0 * ns[ia] + w1 * ns[ib] + w2 * ns[ic]
                            let len = simd_length(s)
                            if len > 0 { normal = s / len }
                        }
                        if normal.z < 0 { normal = -normal }
                        let light = 0.38 + 0.55 * max(0, simd_dot(normal, keyF)) + 0.22 * max(0, simd_dot(normal, fillF))
                        depth[i] = z
                        color[i] = SIMD4(simd_min(SIMD3(repeating: 1), SIMD3(base.x, base.y, base.z) * light), 1)
                    }
                }
            }
        }
        // Halve: each output pixel is the average of four, alpha included, written premultiplied.
        var out = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                var sum = SIMD4<Float>.zero
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    let c = color[(y * 2 + dy) * n + x * 2 + dx]
                    sum += SIMD4(c.x * c.w, c.y * c.w, c.z * c.w, c.w)
                }
                sum /= 4
                let o = (y * size + x) * 4
                out[o] = UInt8((sum.x * 255).rounded()); out[o + 1] = UInt8((sum.y * 255).rounded())
                out[o + 2] = UInt8((sum.z * 255).rounded()); out[o + 3] = UInt8((sum.w * 255).rounded())
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw MESError(.engineError, "Gaea couldn't draw the mesh's preview.") }
        return image
    }

    /// A PNG with its `Comment` and `Copyright` text (Base §10.2 rule 2, Mesh §1.11).
    static func writePNG(_ image: CGImage, to url: URL, comment: String?, copyright: String?) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw MESError(.engineError, "Gaea couldn't create the preview.")
        }
        var png: [CFString: Any] = [:]
        if let comment { png[kCGImagePropertyPNGComment] = comment }
        if let copyright, !copyright.isEmpty { png[kCGImagePropertyPNGCopyright] = copyright }
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyPNGDictionary: png] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw MESError(.engineError, "Gaea couldn't write the preview.") }
    }
}
