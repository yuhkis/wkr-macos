// swift-tools-version: 6.2
import PackageDescription
import Foundation

let v1 = ProcessInfo.processInfo.environment["WKR_BUILD_FLAVOR"] == "v1"
let flags: [SwiftSetting] = v1 ? [.define("WKR_V1")] : []
var targets: [Target] = [
    .target(name: "WKRCore", swiftSettings: flags),
    .target(name: "WKRPracticeUI", dependencies: ["WKRCore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("WebKit")]),
    .executableTarget(name: "WKRMacOS", dependencies: ["WKRCore", "WKRPracticeUI"],
        swiftSettings: flags,
        linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon"), .linkedFramework("WebKit")]),
    .executableTarget(name: "WKRPractice", dependencies: ["WKRCore", "WKRPracticeUI"],
        linkerSettings: [.linkedFramework("AppKit")]),
]
if v1 {
    targets += [
        // Keep v1-dependent expectations with their frozen layout.
        // Only status text and daily-store schema use the current shared contract.
        .testTarget(name: "WKRV1CoreTests", dependencies: ["WKRCore"],
            path: "Legacy/wkr-macos-v1/Tests/WKRCoreTests",
            exclude: ["ConversionStatusTests.swift", "KeyFrequencyTests.swift"]),
        .testTarget(name: "WKRCoreTests", dependencies: ["WKRCore"],
            exclude: ["ControlShortcutPolicyTests.swift", "EnglishFallbackJournalTests.swift",
                      "KeyFrequencyReportRendererTests.swift", "KeyboardGeometryTests.swift",
                      "SecureInputLogFieldsTests.swift", "UnicodeInjectionGateTests.swift", "VialKeymapTests.swift",
                      "IOTrialTests.swift", "LoanwordColumnsTrialTests.swift", "LongVowelTrialTests.swift",
                      "PublicLayoutTests.swift", "ThreeKeyTrialTests.swift", "VuSmallWaTrialTests.swift",
                      "WKRTransducerTests.swift", "WakaraKeyLegendTests.swift"]),
        .testTarget(name: "WKRV1PublicTests", dependencies: ["WKRMacOS", "WKRCore"], swiftSettings: flags),
    ]
} else {
    targets += [
        .testTarget(name: "WKRCoreTests", dependencies: ["WKRCore"]),
        .testTarget(name: "WKRMacOSTests", dependencies: ["WKRMacOS", "WKRCore", "WKRPracticeUI"]),
    ]
}
let package = Package(name: "WKRMacOS", platforms: [.macOS(.v14)],
    products: [.library(name: "WKRCore", targets: ["WKRCore"]),
               .executable(name: "WKRMacOS", targets: ["WKRMacOS"]),
               .executable(name: "WKRPractice", targets: ["WKRPractice"])],
    targets: targets, swiftLanguageModes: [.v5])
