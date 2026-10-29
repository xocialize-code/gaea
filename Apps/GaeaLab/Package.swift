// swift-tools-version: 6.2
import PackageDescription

// Gaea Lab (G-14, CLI-3, AB-T-0372): the reference MES client. It is Pixel Agency Lite's run workflow
// (pixel-agency-run) over every server it knows at once: an engine pool whose jobs MESClientKit's EnginePicker sends to
// the server that offers the model and its adapters (G-19), with LoRAs chosen per run.
//
//   GaeaLabCore   EnginePool (one EngineConnection over many servers) and the run's adapter choices.
//   GaeaLab       the app: Lite's workflow window, the servers, and a LoRA panel. The binary is GaeaLabApp, so it can't
//                 collide with lab-run on a case-insensitive volume.
//   lab-run       the same workflow without a window: the MES client conformance suite drives it, and so do recorded
//                 runs across several servers.
let package = Package(
    name: "GaeaLab",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GaeaLabCore", targets: ["GaeaLabCore"]),
        .executable(name: "GaeaLabApp", targets: ["GaeaLabApp"]),
        .executable(name: "lab-run", targets: ["LabRun"]),
    ],
    dependencies: [
        .package(url: "https://github.com/xocialize/pixel-agency-run.git", from: "0.1.0"),
        .package(url: "https://github.com/xocialize/media-engine-spec.git", from: "0.5.0"),
        .package(url: "https://github.com/xocialize/DesignScaffold.git", from: "0.25.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "GaeaLabCore", dependencies: [
            .product(name: "PixelAgencyRun", package: "pixel-agency-run"),
            .product(name: "MESClientKit", package: "media-engine-spec"),
            .product(name: "MESCore", package: "media-engine-spec"),
        ]),
        .executableTarget(name: "GaeaLabApp", dependencies: [
            "GaeaLabCore",
            .product(name: "PixelAgencyRun", package: "pixel-agency-run"),
            .product(name: "PixelAgencyRunUI", package: "pixel-agency-run"),
            .product(name: "DesignScaffold", package: "DesignScaffold"),
        ]),
        .executableTarget(name: "LabRun", dependencies: [
            "GaeaLabCore",
            .product(name: "PixelAgencyRun", package: "pixel-agency-run"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "GaeaLabCoreTests", dependencies: [
            "GaeaLabCore",
            .product(name: "MESCore", package: "media-engine-spec"),
        ]),
    ]
)
