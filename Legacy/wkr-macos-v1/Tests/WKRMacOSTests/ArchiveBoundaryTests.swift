import XCTest
@testable import WKRMacOS

final class ArchiveBoundaryTests: XCTestCase {
    func testPrivateOptionsAreRejectedBeforeStarting() {
        for option in ["--detailed-log", "--key-pair-timing", "--rule-pair-count", "--shift-enter-attribution", "--rsft-enter-display", "--practice-page"] {
            XCTAssertThrowsError(try AppConfiguration.parse(arguments: ["WKRV1Archive", option, "on"]))
        }
    }
    func testSettingsAndCountsAreIsolatedAndDisabledByDefault() throws {
        let name = "wkr-archive-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for key in ["DetailedLog", "KeyPairTiming", "RulePairCount", "ShiftEnterAttribution", "RSftEnterDisplay"] {
            defaults.set("on", forKey: key)
        }
        let config = try AppConfiguration.parse(arguments: ["WKRV1Archive", "--version"], defaults: defaults)
        XCTAssertEqual(config.action, .version)
        XCTAssertFalse(config.keyFrequencyEnabled)
        XCTAssertEqual(KeyFrequencyRecorder.bundleIdentifier, "io.github.yuhkis.wkr-macos.v1-archive")
        XCTAssertTrue(KeyFrequencyRecorder.defaultStoreURL()!.path.contains("wkr-macos.v1-archive/"))
    }
    func testSharedLeaseRejectsConcurrentEngineAndReleases() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var first: EngineLease? = EngineLease(url: url)
        XCTAssertNotNil(first)
        XCTAssertNil(EngineLease(url: url))
        first = nil
        XCTAssertNotNil(EngineLease(url: url))
    }
    func testSharedLeaseRejectsSymlink() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let target = base.appendingPathComponent("target")
        try Data().write(to: target)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertNil(EngineLease(url: link))
    }
}
