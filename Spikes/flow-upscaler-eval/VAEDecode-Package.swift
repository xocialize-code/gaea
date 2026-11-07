// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "vaedec",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "/Volumes/Satechi/Development/mlxengine-image/PROD/flux2-vae-mlx-swift")],
    targets: [.executableTarget(name: "VAEDecode", dependencies: [.product(name: "Flux2VAE", package: "flux2-vae-mlx-swift")],
                                swiftSettings: [.swiftLanguageMode(.v5)])]
)
