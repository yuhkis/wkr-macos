import XCTest
@testable import WKRMacOS
@testable import WKRPracticeUI
import WKRCore

final class PublicBoundaryTests: XCTestCase {
    func testOldPrivateDefaultsCannotEnableResearchOrPracticePage() throws {
        let name="wkr-public-test-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        defaults.set("on",forKey:"DetailedLog")
        defaults.set("records-what-i-type",forKey:"DetailedLogAcknowledged")
        defaults.set("unlimited",forKey:"DetailedLogUntil")
        defaults.set(true,forKey:"KeyPairTiming")
        defaults.set(true,forKey:"RulePairCount")
        defaults.set(true,forKey:"ShiftEnterAttribution")
        defaults.set("on",forKey:"RSftEnterDisplay")
        defaults.set("80",forKey:"ShiftEnterWindowMS")
        defaults.set("5",forKey:"PracticeLimitMinutes")
        defaults.set("all",forKey:"DetailedLogRetentionDays")
        defaults.set("untrusted.html",forKey:"PracticePagePath")
        let config=try AppConfiguration.parse(arguments:["WKRPublic"],defaults:defaults)
        XCTAssertFalse(config.keyFrequencyEnabled)
        XCTAssertEqual(config.action,.run)
        XCTAssertEqual(config.outputModeName,"prefix")
        XCTAssertEqual(KeyFrequencyRecorder.bundleIdentifier,"io.github.yuhkis.wkr-macos.public")
        XCTAssertTrue(KeyFrequencyRecorder.defaultStoreURL()!.path.contains("wkr-macos.public/"))
    }
    func testUnsupportedCLIIsRejectedBeforeStartingAnything() {
        for flag in ["--detailed-log","--detailed-log-report","--detailed-log-purge","--key-pair-timing","--rule-pair-report","--rule-pair-count","--shift-enter-attribution","--practice-page","--practice-log", "--keyboard-status", "--detailed-log-acknowledge", "--detailed-log-until", "--detailed-log-retention", "--detailed-log-dir", "--before", "--all", "--n", "--top", "--pair", "--practice-limit", "--rsft-enter-display", "--shift-enter-window-ms"] {
            XCTAssertThrowsError(try AppConfiguration.parse(arguments:["WKRPublic",flag,"on"]))
        }
        XCTAssertNoThrow(try AppConfiguration.parse(arguments:["WKRPublic","--practice-only"]))
    }
    func testEngineLeaseExcludesSecondEngineAndReleasesOnExit() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        var first:EngineLease?=EngineLease(url:url)
        XCTAssertNotNil(first);XCTAssertNil(EngineLease(url:url))
        first=nil
        XCTAssertNotNil(EngineLease(url:url))
    }
    func testLeaseRejectsSymbolicLinks() throws {
        let base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:base) }
        let target=base.appendingPathComponent("target");try Data().write(to:target)
        let link=base.appendingPathComponent("link");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        XCTAssertNil(EngineLease(url:link))
    }
    func testProgressStoresOnlyValidatedAggregatesAndDeletes() throws {
        let base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:base) }
        let store=PracticeProgressStore(url:base.appendingPathComponent("practice-progress.json"))
        XCTAssertNil(try store.load())
        let raw: [String:Any]=["schemaVersion":2,"layoutVersion":WKRLayout.layoutVersion,"text":"synthetic input","time":123,"lessons":["vowels":["completed":1,"bestAccuracy":95,"wrong":"synthetic","keys":["x"]]]]
        let value=try XCTUnwrap(PracticeProgress.validated(JSONSerialization.data(withJSONObject:raw)))
        try store.save(value)
        let object=try JSONSerialization.jsonObject(with:Data(contentsOf:store.url)) as! [String:Any]
        XCTAssertEqual(Set(object.keys),["schemaVersion","layoutVersion","lessons"])
        let lesson=(object["lessons"] as! [String:[String:Int]])["vowels"]!
        XCTAssertEqual(Set(lesson.keys),["completed","bestAccuracy"])
        let mode=try FileManager.default.attributesOfItem(atPath:store.url.path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(mode.intValue,0o600)
        try store.delete();XCTAssertNil(try store.load())
    }
    func testCorruptProgressIsNotOverwritten() throws {
        let base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:base) }
        let store=PracticeProgressStore(url:base.appendingPathComponent("progress.json"))
        let bad=Data("unreadable".utf8);try bad.write(to:store.url)
        XCTAssertThrowsError(try store.save(.empty));XCTAssertEqual(try Data(contentsOf:store.url),bad)
    }
    func testNewProgressSchemaKeepsTheOldFileSeparate() throws {
        XCTAssertEqual(PracticeProgressStore().url.lastPathComponent, "practice-progress-v2.json")
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let previous = base.appendingPathComponent("practice-progress.json")
        let old = Data("{\"schemaVersion\":1,\"layoutVersion\":\"2.0.0-beta.1\",\"lessons\":{}}".utf8)
        try old.write(to: previous)
        XCTAssertNil(PracticeProgress.validated(old))
        let current = PracticeProgressStore(url: base.appendingPathComponent("practice-progress-v2.json"))
        try current.save(.empty)
        try current.delete()
        XCTAssertEqual(try Data(contentsOf: previous), old)
    }

}
