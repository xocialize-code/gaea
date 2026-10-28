import Foundation
import MLXToolKit

// gaea-manifest-gen <model-set> — prints a JSON array for a manifest's `models[]`.
//   demo          the plugin-exec spike's demo worker (no MLXEngine package; a hand-declared manifest)
//   z-image-turbo z-image-swift 0.5.3's ZImageTurboT2IPackage manifest, one lane per quant tier

struct Lane: Encodable {
    let id: String
    let `default`: Bool
    let resolved: ResolvedLane
}

struct Model: Encodable {
    let id: String
    let title: String
    let package: PackageManifest
    let lanes: [Lane]
}

struct QuantLane: PackageConfiguration, QuantConfigured, WeightSourcing {
    var quant: Quant
    var sources: [WeightSource]
    var weightSources: [WeightSource] { sources }
    func missingWeightSources(storeRoot: URL?) -> [WeightSource] { sources }
    enum CodingKeys: CodingKey { case quant }
    init(quant: Quant, sources: [WeightSource]) { self.quant = quant; self.sources = sources }
    init(from decoder: Decoder) throws { fatalError("encode-only") }
    func encode(to encoder: Encoder) throws {}
}

struct Bundled: PackageConfiguration, BundledWeightSourcing {
    var bundledWeightSources: [BundledWeightSource] { [] }
}

func demo() -> [Model] {
    // The spike's matmul worker holds n×n fp32 operands; its measured peak was 2.37 GB
    // (Spikes/plugin-exec/README.md, check 5). Nothing is downloaded.
    let manifest = PackageManifest(
        license: LicenseDeclaration(weightLicense: .apache2, portCodeLicense: .apache2),
        provenance: Provenance(sourceRepo: "xocialize/gaea-plugin-demo", revision: "0.2.0", tier: 1),
        requirements: RequirementsManifest(
            footprints: [QuantFootprint(quant: .fp32, residentBytes: 0, peakActivationBytes: 2_370_000_000)],
            requiredBackends: [.metalGPU]),
        surfaces: [])
    return [Model(id: "demo-matmul", title: "Demo matmul (GPU smoke test)", package: manifest,
                  lanes: [Lane(id: "fp32", default: true,
                               resolved: ResolvedLane(manifest: manifest, configuration: Bundled()))])]
}

func zImageTurbo() -> [Model] {
    // Copied from z-image-swift 0.5.3 Sources/MLXZImage/ZImageTurboT2IPackage.swift:17 and
    // ZImageConfiguration.swift:96 (one bf16 snapshot every tier quantizes from).
    let manifest = PackageManifest(
        license: LicenseDeclaration(weightLicense: .apache2, portCodeLicense: .mit),
        provenance: Provenance(sourceRepo: "Tongyi-MAI/Z-Image-Turbo", revision: "main", tier: 1),
        requirements: RequirementsManifest(
            footprints: [
                QuantFootprint(quant: .bf16, residentBytes: 20_500_000_000, peakActivationBytes: 28_000_000_000),
                QuantFootprint(quant: .int8, residentBytes: 15_000_000_000, peakActivationBytes: 28_000_000_000),
                QuantFootprint(quant: .int4, residentBytes: 11_900_000_000, peakActivationBytes: 28_000_000_000),
            ],
            requiredBackends: [.metalGPU],
            os: OSRequirement(minMacOS: SemanticVersion(major: 26, minor: 0, patch: 0)),
            chipFloor: nil),
        specialties: [],
        surfaces: [
            T2IContract.descriptor(name: "z-image-turbo-t2i",
                                   summary: "Z-Image-Turbo 6B text-to-image: distilled 8-step at guidance 0.",
                                   modes: []),
            IEditContract.descriptor(name: "z-image-turbo-img2img",
                                     summary: "Z-Image-Turbo image-to-image; metaData[\"strength\"] 0–1.",
                                     modes: []),
        ])
    let sources = [WeightSource(role: "snapshot", repo: "mlx-community/Z-Image-Turbo-bf16", revision: "main",
                                matching: ["transformer/*", "text_encoder/*", "vae/*", "tokenizer/*",
                                           "scheduler/*", "*.json"])]
    let lanes = [(Quant.int4, true), (.int8, false), (.bf16, false)].map { quant, isDefault in
        Lane(id: quant.rawValue, default: isDefault,
             resolved: ResolvedLane(manifest: manifest, configuration: QuantLane(quant: quant, sources: sources)))
    }
    return [Model(id: "z-image-turbo", title: "Z-Image Turbo", package: manifest, lanes: lanes)]
}

let set = CommandLine.arguments.dropFirst().first ?? "demo"
let models: [Model]
switch set {
case "demo": models = demo()
case "z-image-turbo": models = zImageTurbo()
default:
    FileHandle.standardError.write(Data("unknown model set \(set)\n".utf8))
    exit(2)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(models))
FileHandle.standardOutput.write(Data("\n".utf8))
