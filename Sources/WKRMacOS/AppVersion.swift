import Foundation
import WKRCore

enum AppVersion {
    #if WKR_V1
    static let release = "0.7.1-public.1"
    static let bundleIdentifier = "io.github.yuhkis.wkr-macos.v1"
    static let name = "WKR macOS v1"
    static let supportsPractice = false
    #else
    static let release = "0.8.0-public.beta.6"
    static let bundleIdentifier = "io.github.yuhkis.wkr-macos.public"
    static let name = "WKR macOS Public"
    static let supportsPractice = true
    #endif
    static var display: String { name + " " + release + " / 配列 " + WKRLayout.layoutVersion +
        (supportsPractice ? " / 練習 " + PracticeMetadata.version : "") }
}
