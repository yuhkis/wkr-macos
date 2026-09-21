import CoreGraphics
import XCTest
import WKRCore
@testable import WKRMacOS

final class FrequencyPersistenceTests: XCTestCase {
    private func onMain(_ body: () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.sync(execute: body) }
    }

    func testAsyncBatchesAndFinalFlushDoNotLoseOrDuplicateCounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("key-frequency.json")
        let recorder = try XCTUnwrap(KeyFrequencyRecorder(enabled: true, storeURL: url))
        onMain {
            recorder.recordKeyDown(keyCode: 0, flags: [], isAutorepeat: false)
            recorder.flushAsync()
            recorder.recordKeyDown(keyCode: 0, flags: .maskShift, isAutorepeat: false)
            recorder.flushAsync()
            recorder.recordKeyDown(keyCode: 0, flags: [], isAutorepeat: false)
            XCTAssertTrue(recorder.flush())
            XCTAssertTrue(recorder.flush())
        }
        let store = try XCTUnwrap(KeyFrequencyRecorder.loadStore(at: url))
        XCTAssertEqual(KeyFrequencyTally(store: store).total, 3)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testFailedWriteIsRetriedWithoutDroppingThePendingBatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("blocked")
        try Data("synthetic blocker".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("key-frequency.json")
        let recorder = try XCTUnwrap(KeyFrequencyRecorder(enabled: true, storeURL: url))
        onMain {
            recorder.recordKeyDown(keyCode: 0, flags: [], isAutorepeat: false)
            recorder.flushAsync()
            XCTAssertFalse(recorder.flush())
        }
        try FileManager.default.removeItem(at: blocker)
        onMain {
            recorder.recordKeyDown(keyCode: 0, flags: [], isAutorepeat: false)
            XCTAssertTrue(recorder.flush())
        }
        let store = try XCTUnwrap(KeyFrequencyRecorder.loadStore(at: url))
        XCTAssertEqual(KeyFrequencyTally(store: store).total, 2)
    }

    func testFailedArchiveNeverMergesDifferentLayoutsAndRetriesSafely() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("key-frequency.json")
        let archive = KeyFrequencyRecorder.archiveDirectory(for: url)
        var old = KeyFrequencyTally()
        old.record(KeyIdentity(keyCode: 0), on: KeyFrequencyDay(date: Date()), layout: "synthetic-old-layout")
        let bytes = try JSONEncoder().encode(old.snapshot())
        try bytes.write(to: url)
        try Data("synthetic archive blocker".utf8).write(to: archive)
        let recorder = try XCTUnwrap(KeyFrequencyRecorder(enabled: true, storeURL: url, layout: "synthetic-new-layout"))
        onMain {
            XCTAssertEqual(recorder.rotateIfLayoutChanged(), .failed)
            recorder.recordKeyDown(keyCode: 1, flags: [], isAutorepeat: false)
            XCTAssertFalse(recorder.flush())
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        try FileManager.default.removeItem(at: archive)
        onMain { XCTAssertTrue(recorder.flush()) }
        let current = try XCTUnwrap(KeyFrequencyRecorder.loadStore(at: url))
        XCTAssertEqual(KeyFrequencyTally(store: current).total, 1)
        let archives = try FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil)
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archives.first)), bytes)
    }

}
