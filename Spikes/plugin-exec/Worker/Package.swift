// swift-tools-version: 6.0
import PackageDescription

// A Gaea model worker: a plain executable that runs MLX on the GPU and speaks the
// spike's JSON-lines protocol on stdin/stdout. Packaged as a signed .gaeaplugin bundle.
let package = Package(
    name: "gaea-demo-worker",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3"),
    ],
    targets: [
        .executableTarget(
            name: "gaea-demo-worker",
            dependencies: [.product(name: "MLX", package: "mlx-swift")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
