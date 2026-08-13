// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WKRMacOS",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WKRCore", targets: ["WKRCore"]),
        .executable(name: "WKRMacOS", targets: ["WKRMacOS"]),
    ],
    targets: [
        .target(name: "WKRCore"),
        .executableTarget(
            name: "WKRMacOS",
            dependencies: ["WKRCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(name: "WKRCoreTests", dependencies: ["WKRCore"]),
    ],
    swiftLanguageModes: [.v5]
)
