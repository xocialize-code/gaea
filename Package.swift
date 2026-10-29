// swift-tools-version: 6.2
import PackageDescription

// Gaea: the MES media server whose models are plugins (Docs/Gaea - PRD.md, Docs/Gaea - Plan.md §2).
//
//   GaeaOperator  the local operator API's wire types and its client (a Unix socket on this Mac only, G-17).
//                 Foundation only: the `gaea` CLI links nothing else.
//   GaeaCore      the host: the plugin manager (repo URLs, releases, sha256, signature, versions side by side),
//                 GPP workers (spec/GPP-1.md, the H side), the scheduler and memory ledger, gaea.sqlite, the MES
//                 front end's engine with the G0 mock normalizer, and the operator API server. Links no MLX:
//                 manifests are decoded with MLXToolKit through GaeaPluginKit's GaeaProtocol.
//   GaeaConsole   the console's backends over GaeaCore, for MESEngineUI (Queue, Models, Plugins, System).
//   GaeaApp       the app (Gaea.app): menu bar, console and server; `--headless` runs the server alone (SRV-10).
//   GaeaCLI       `gaea`, the CLI: status, logs and plugin commands over the operator API.
let package = Package(
    name: "gaea",
    platforms: [.macOS(.v26)], // mlx-engine-swift's MLXToolKit requires macOS 26
    products: [
        // The app's binary is GaeaApp: on a case-insensitive volume `Gaea` and `gaea` would be one file.
        .executable(name: "GaeaApp", targets: ["GaeaApp"]),
        .executable(name: "gaea", targets: ["GaeaCLI"]),
        .library(name: "GaeaCore", targets: ["GaeaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/xocialize/media-engine-spec.git", from: "0.5.0"),
        // The Image profile's host half, MLX-free: operation table, validation, plans (AB-T-0359, G-20).
        .package(url: "https://github.com/xocialize/pixel-agency-normalizer.git", from: "0.1.0"),
        // GaeaProtocol only: the MLX-free manifest types and GPP vocabulary. Its MLXToolKit is the only engine code
        // the host links.
        .package(url: "https://github.com/xocialize-code/gaea-plugin-kit.git", from: "0.3.0"),
        .package(url: "https://github.com/xocialize/mlx-engine-swift.git", from: "0.73.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "GaeaOperator"),
        .target(
            name: "GaeaCore",
            dependencies: [
                "GaeaOperator",
                .product(name: "GaeaProtocol", package: "gaea-plugin-kit"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
                // The governor's admission and eviction rules, shared with MLXServeEngine (AB-D-0170), MLX-free.
                .product(name: "MLXMemoryPolicy", package: "mlx-engine-swift"),
                .product(name: "PixelAgencyNormalizer", package: "pixel-agency-normalizer"),
                .product(name: "MESCore", package: "media-engine-spec"),
                .product(name: "MESEngineKit", package: "media-engine-spec"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "GaeaConsole",
            dependencies: [
                "GaeaCore",
                .product(name: "MESEngineUI", package: "media-engine-spec"),
            ]
        ),
        .executableTarget(name: "GaeaApp", dependencies: ["GaeaCore", "GaeaConsole"]),
        .executableTarget(name: "GaeaCLI", dependencies: ["GaeaOperator"]),
        .testTarget(
            name: "GaeaCoreTests",
            dependencies: [
                "GaeaCore", "GaeaOperator",
                .product(name: "GaeaProtocol", package: "gaea-plugin-kit"),
                .product(name: "MESCore", package: "media-engine-spec"),
                .product(name: "MESEngineKit", package: "media-engine-spec"),
                .product(name: "PixelAgencyNormalizer", package: "pixel-agency-normalizer"),
            ]
        ),
    ]
)
