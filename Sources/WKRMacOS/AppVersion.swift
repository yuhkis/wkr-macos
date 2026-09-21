import Foundation
import WKRCore

enum AppVersion {
    static let release = "0.8.0-public.beta.5"
    static let bundleIdentifier = "io.github.yuhkis.wkr-macos.public"
    static var display: String { "WKR macOS Public \(release) / 配列 \(WKRLayout.layoutVersion) / 練習 \(PracticeMetadata.version)" }
}
