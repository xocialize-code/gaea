// swift-tools-version: 6.2
import PackageDescription

// AB-T-0356: what running a model out of process costs. A harness, not a plugin: nothing here is
// published. Three executables share one dependency resolution, so the worker and the in-process
// baseline run the same z-image-swift, mlx-engine-swift and mlx-swift.
//
// - bench-worker: a GaeaPluginKit worker with Z-Image Turbo (int4) and a probe model (a trivial
//   GPU op, and a spool echo that reads and writes images and frame batches).
// - bench-host: a minimal GPP host. It launches the signed bundle under Process.launchRequirement,
//   drives it, times every phase and reads the worker's phys_footprint with proc_pid_rusage.
// - bench-inproc: the same Z-Image lane loaded by MLXServeEngine in the measuring process.
//
// scripts/build.sh builds Release into an internal-disk scratch folder and signs bench.gaeaplugin.
let package = Package(
    name: "gaea-bench-ab-t-0356",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/xocialize/gaea-plugin-kit.git", exact: "0.1.1"),
        .package(url: "https://github.com/xocialize/z-image-swift.git", exact: "0.5.4"),
        .package(url: "https://github.com/xocialize/mlx-engine-swift.git", exact: "0.72.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.5"),
    ],
    targets: [
        // MLX-free: clocks, phys_footprint, image coding. The host links only this.
        .target(name: "BenchShared"),
        .executableTarget(
            name: "bench-worker",
            dependencies: [
                "BenchShared",
                .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"),
                .product(name: "GaeaProtocol", package: "gaea-plugin-kit"),
                .product(name: "MLXZImage", package: "z-image-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
        .executableTarget(
            name: "bench-inproc",
            dependencies: [
                "BenchShared",
                .product(name: "MLXZImage", package: "z-image-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
                .product(name: "MLXServeCore", package: "mlx-engine-swift"),
                .product(name: "MLX", package: "mlx-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(name: "bench-host", dependencies: ["BenchShared"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
