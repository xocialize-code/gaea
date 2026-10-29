// swift-tools-version: 6.2
import PackageDescription

// AB-T-0375: Pixel Agency Desktop's ticket runner (PixelAgencyCore, linked from its checkout, unchanged) against real
// Gaea servers.
let package = Package(
    name: "desktop-gaea-check",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "/Volumes/Satechi/Development/pixel-agency-desktop"),
        .package(url: "https://github.com/xocialize/pixel-agency-library.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(name: "desktop-gaea-check", dependencies: [
            .product(name: "PixelAgencyCore", package: "pixel-agency-desktop"),
            .product(name: "ImageLibrary", package: "pixel-agency-library"),
        ]),
    ]
)
