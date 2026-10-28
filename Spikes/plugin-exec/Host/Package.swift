// swift-tools-version: 6.0
import PackageDescription

// The spike's stand-in for Gaea: discovers plugins from a catalog, downloads, verifies the
// Developer ID signature against our Team ID, installs, launches and drives the worker.
let package = Package(
    name: "GaeaPluginHost",
    platforms: [.macOS(.v15)], // LightweightCodeRequirements / Process.launchRequirement need 14.4
    targets: [
        .executableTarget(
            name: "GaeaPluginHost",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
