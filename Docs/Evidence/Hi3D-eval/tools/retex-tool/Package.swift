// swift-tools-version: 5.12
import PackageDescription

let package = Package(
    name: "retex-tool",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "/Volumes/Satechi/Development/mlxengine-3d/PROD/trellis/mlx-trellis2-swift"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.31.5"),
    ],
    targets: [
        .executableTarget(name: "retex", dependencies: [
            .product(name: "TRELLIS2", package: "mlx-trellis2-swift"),
            .product(name: "MLX", package: "mlx-swift"),
        ], swiftSettings: [.interoperabilityMode(.Cxx)]),
        .executableTarget(name: "unwrap", dependencies: [
            .product(name: "TRELLIS2", package: "mlx-trellis2-swift"),
            .product(name: "MLX", package: "mlx-swift"),
        ], swiftSettings: [.interoperabilityMode(.Cxx)]),
    ]
)
