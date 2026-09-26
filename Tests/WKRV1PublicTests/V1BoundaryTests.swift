import XCTest
import WKRCore
@testable import WKRMacOS

final class V1BoundaryTests: XCTestCase {
    func testV1IdentityAndLayoutAreIsolated() {
        XCTAssertEqual(WKRLayout.layoutVersion, "1.1.0")
        XCTAssertEqual(AppVersion.bundleIdentifier, "io.github.yuhkis.wkr-macos.v1")
        XCTAssertEqual(KeyFrequencyRecorder.bundleIdentifier, AppVersion.bundleIdentifier)
        XCTAssertFalse(AppVersion.supportsPractice)
    }
    func testFirstRunUsesAppleAndRecordingDefaultsOff() throws {
        let name = "synthetic-v1-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("on", forKey: "DetailedLog")
        let config = try AppConfiguration.parse(arguments: ["WKRV1"], defaults: defaults)
        XCTAssertFalse(config.keyFrequencyEnabled)
        XCTAssertEqual(config.inputSourceID, "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese")
    }
    func testV2PracticeAndPrivateOptionsAreRejected() {
        for flag in ["--practice-only", "--detailed-log", "--key-pair-timing", "--rsft-enter-display"] {
            XCTAssertThrowsError(try AppConfiguration.parse(arguments: ["WKRV1", flag]))
        }
    }
    func testSharedLeasePreventsConcurrentEngines() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var lease: EngineLease? = EngineLease(url: url)
        XCTAssertNotNil(lease); XCTAssertNil(EngineLease(url: url))
        lease = nil; XCTAssertNotNil(EngineLease(url: url))
    }
}
