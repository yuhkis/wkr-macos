import XCTest
@testable import WKRCore

final class KeyFrequencyTests: XCTestCase {
    private let a = KeyIdentity(keyCode: 0x00)
    private let shiftedA = KeyIdentity(keyCode: 0x00, isShifted: true)
    private let day1 = KeyFrequencyDay(rawValue: "2026-08-25")
    private let day2 = KeyFrequencyDay(rawValue: "2026-08-26")

    func testShiftIsPartOfTheIdentity() {
        var tally = KeyFrequencyTally()
        tally.record(a, on: day1)
        tally.record(shiftedA, on: day1)
        tally.record(shiftedA, on: day1)

        XCTAssertEqual(tally.count(of: a, on: day1), 1)
        XCTAssertEqual(tally.count(of: shiftedA, on: day1), 2)
        XCTAssertEqual(tally.total, 3)
    }

    func testCountsAreFiledUnderTheirOwnDay() {
        var tally = KeyFrequencyTally()
        tally.record(a, on: day1)
        tally.record(a, on: day2)
        tally.record(a, on: day2)

        XCTAssertEqual(tally.count(of: a, on: day1), 1)
        XCTAssertEqual(tally.count(of: a, on: day2), 2)
        XCTAssertEqual(tally.recordedDays, [day1, day2])
    }

    /// The write path is load, merge, write, so a tally that loses counts on
    /// the way through would quietly under-report forever.
    func testStoreRoundTripPreservesEveryCount() {
        var tally = KeyFrequencyTally()
        tally.record(a, on: day1)
        tally.record(shiftedA, on: day1)
        tally.record(KeyIdentity(keyCode: 0x31), on: day2)

        let reloaded = KeyFrequencyTally(store: tally.snapshot())
        XCTAssertEqual(reloaded, tally)
        XCTAssertEqual(reloaded.total, 3)
    }

    func testEncodedStoreIsStableAcrossRuns() throws {
        var first = KeyFrequencyTally()
        var second = KeyFrequencyTally()
        // Same counts, recorded in a different order.
        for identity in [a, shiftedA, KeyIdentity(keyCode: 0x31)] {
            first.record(identity, on: day1)
        }
        for identity in [KeyIdentity(keyCode: 0x31), shiftedA, a] {
            second.record(identity, on: day1)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(
            try encoder.encode(first.snapshot()),
            try encoder.encode(second.snapshot())
        )
    }

    /// A file written by a future version must be discarded, not guessed at. A
    /// misread tally is wrong in a picture the user cannot check.
    func testUnknownSchemaVersionIsDiscarded() {
        let store = KeyFrequencyStore(
            schemaVersion: KeyFrequencyStore.currentSchemaVersion + 1,
            days: [
                .init(date: day1.rawValue, entries: [
                    .init(keyCode: 0x00, isShifted: false, count: 99),
                ]),
            ]
        )
        XCTAssertTrue(KeyFrequencyTally(store: store).isEmpty)
    }

    func testMergeAddsRatherThanReplaces() {
        var onDisk = KeyFrequencyTally()
        onDisk.record(a, on: day1)
        onDisk.record(a, on: day1)

        var inMemory = KeyFrequencyTally()
        inMemory.record(a, on: day1)
        inMemory.record(a, on: day2)

        onDisk.merge(inMemory)
        XCTAssertEqual(onDisk.count(of: a, on: day1), 3)
        XCTAssertEqual(onDisk.count(of: a, on: day2), 1)
    }

    func testPruneKeepsExactlyTheRetentionWindow() {
        var tally = KeyFrequencyTally()
        let today = KeyFrequencyDay(rawValue: "2026-08-27")
        let window = KeyFrequencyTally.days(endingOn: today, count: 3)
        XCTAssertEqual(window.map(\.rawValue), ["2026-08-25", "2026-08-26", "2026-08-27"])

        for day in window {
            tally.record(a, on: day)
        }
        tally.record(a, on: KeyFrequencyDay(rawValue: "2026-08-24"))
        XCTAssertEqual(tally.recordedDays.count, 4)

        tally.prune(retainedDays: 3, today: today)
        XCTAssertEqual(tally.recordedDays, window)
    }

    /// Nothing is dropped by default. A measurement someone chose to collect
    /// must not disappear on its own, and the oldest days are exactly the ones
    /// a layout comparison needs.
    func testDefaultRetentionKeepsEveryDay() {
        var tally = KeyFrequencyTally()
        let today = KeyFrequencyDay(rawValue: "2026-08-29")
        let ancient = KeyFrequencyDay(rawValue: "2019-01-01")
        tally.record(a, on: ancient)
        tally.record(a, on: today)

        tally.prune(today: today)
        XCTAssertEqual(tally.recordedDays, [ancient, today])
        XCTAssertNil(KeyFrequencyTally.defaultRetainedDays)
    }

    /// A window still works for anyone who asks for one — it is just not
    /// imposed.
    func testAnExplicitWindowStillDropsOlderDays() {
        var tally = KeyFrequencyTally()
        let today = KeyFrequencyDay(rawValue: "2026-08-29")
        tally.record(a, on: KeyFrequencyDay(rawValue: "2026-08-01"))
        tally.record(a, on: today)

        tally.prune(retainedDays: 7, today: today)
        XCTAssertEqual(tally.recordedDays, [today])
    }

    func testPruneWithNoRetentionClearsEverything() {
        var tally = KeyFrequencyTally()
        tally.record(a, on: day1)
        tally.prune(retainedDays: 0, today: day1)
        XCTAssertTrue(tally.isEmpty)
        // `nil` is the opposite instruction and must not be confused with zero.
        var kept = KeyFrequencyTally()
        kept.record(a, on: day1)
        kept.prune(retainedDays: nil, today: day2)
        XCTAssertFalse(kept.isEmpty)
    }

    /// The cap exists so a stuck or hostile event source cannot grow the map
    /// without bound. Keys already present must keep counting past it, or a
    /// busy day would freeze the numbers it already had.
    func testIdentityCapStopsNewKeysButNotExistingOnes() {
        var tally = KeyFrequencyTally()
        for index in 0..<KeyFrequencyTally.maximumIdentitiesPerDay {
            tally.record(KeyIdentity(keyCode: UInt16(index)), on: day1)
        }
        let overflow = KeyIdentity(keyCode: UInt16(KeyFrequencyTally.maximumIdentitiesPerDay))
        tally.record(overflow, on: day1)
        XCTAssertEqual(tally.count(of: overflow, on: day1), 0)

        tally.record(a, on: day1)
        XCTAssertEqual(tally.count(of: a, on: day1), 2)
    }

    func testDayFromDateUsesTheLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 27
        components.hour = 23
        components.minute = 59
        let date = try XCTUnwrap(calendar.date(from: components))
        XCTAssertEqual(
            KeyFrequencyDay(date: date, calendar: calendar).rawValue,
            "2026-08-27"
        )
    }

    /// Nothing in the persisted shape may carry order or a time of day. This
    /// test is the guard on the promise `AGENTS.md` and `docs/design.md`
    /// section 9 make, so a field added later has to come past it.
    func testPersistedShapeCarriesNoOrderAndNoTimeOfDay() throws {
        var tally = KeyFrequencyTally()
        tally.record(a, on: day1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let text = String(decoding: try encoder.encode(tally.snapshot()), as: UTF8.self)

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "days"])

        let days = try XCTUnwrap(object["days"] as? [[String: Any]])
        let day = try XCTUnwrap(days.first)
        XCTAssertEqual(Set(day.keys), ["date", "entries"])
        XCTAssertEqual(day["date"] as? String, "2026-08-25")

        let entries = try XCTUnwrap(day["entries"] as? [[String: Any]])
        for entry in entries {
            XCTAssertEqual(Set(entry.keys), ["keyCode", "isShifted", "count"])
        }
        // Every date is a bare calendar day. An ISO timestamp would carry a
        // time of day, which this format must never gain.
        for day in days {
            let date = try XCTUnwrap(day["date"] as? String)
            XCTAssertNotNil(
                date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression),
                "\(date) is not a bare calendar day"
            )
        }
        XCTAssertFalse(text.contains("T00:"), "no clock time may appear in the store")
    }
}
