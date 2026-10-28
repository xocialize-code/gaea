// swift-tools-version: 6.0
import PackageDescription

// Writes the engine-owned half of a Gaea manifest (`models[]`: the PackageManifest and each lane's
// ResolvedLane) with MLXEngine's own Codable types, so the schema's fixtures are the engine's
// encoding rather than a hand copy of it. MLXToolKit is MLX-free; nothing here loads a model.
let package = Package(
    name: "gaea-manifest-gen",
    platforms: [.macOS("26.0")], // mlx-engine-swift 0.72.0 requires macOS 26,
    dependencies: [
        .package(url: "https://github.com/xocialize/mlx-engine-swift.git", from: "0.72.0"),
    ],
    targets: [
        .executableTarget(
            name: "gaea-manifest-gen",
            dependencies: [.product(name: "MLXToolKit", package: "mlx-engine-swift")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
