// swift-tools-version: 6.2
import PackageDescription
// AB-T-0377: Pixel Agency Desktop's own AutoDescriber against a real engine (Gaea), on photos imported into a fresh
// library. Not committed anywhere; the evidence keeps its output.
let package = Package(
    name: "autodescribe-live", platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "/Volumes/Satechi/Development/pixel-agency-desktop"),
        .package(url: "https://github.com/xocialize/pixel-agency-run.git", from: "0.1.0"),
        .package(url: "https://github.com/xocialize/pixel-agency-library.git", from: "0.1.0"),
    ],
    targets: [.executableTarget(name: "autodescribe-live", dependencies: [
        .product(name: "PixelAgencyCore", package: "pixel-agency-desktop"),
        .product(name: "PixelAgencyRun", package: "pixel-agency-run"),
        .product(name: "ImageLibrary", package: "pixel-agency-library"),
    ], swiftSettings: [.swiftLanguageMode(.v5)])])
