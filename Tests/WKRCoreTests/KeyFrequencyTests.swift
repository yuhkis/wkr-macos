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
    ///
    /// Discarding it is only half the answer, and the reader is the wrong place
    /// for the other half: the file still has to survive. The recorder refuses
    /// such a file at the point it reads it and moves it aside rather than
    /// writing over what it could not understand.
    func testUnknownSchemaVersionIsDiscarded() {
        let store = KeyFrequencyStore(
            schemaVersion: KeyFrequencyStore.readableSchemaVersions.upperBound + 1,
            days: [
                .init(date: day1.rawValue, entries: [
                    .init(keyCode: 0x00, isShifted: false, count: 99),
                ]),
            ]
        )
        XCTAssertTrue(KeyFrequencyTally(store: store).isEmpty)
    }

    /// A file written before the field existed has no `layouts`; every day in
    /// it was counted under the one table that existed then, and reading it
    /// must say so rather than leave the days unnamed.
    func testUnmarkedDaysAreFiledUnderTheTableThatWroteThem() {
        let store = KeyFrequencyStore(
            schemaVersion: 1,
            days: [.init(date: day1.rawValue, entries: [.init(keyCode: 0x00, isShifted: false, count: 3)])]
        )
        let tally = KeyFrequencyTally(store: store)
        XCTAssertEqual(tally.count(of: a, on: day1), 3)
        XCTAssertEqual(tally.layouts(on: day1), [KeyFrequencyStore.layoutBeforeMarking])
        XCTAssertEqual(tally.layouts(on: day2), [])
    }

    /// The field decodes whether or not it is there, and the version a single
    /// build stamped is read rather than discarded.
    func testDayLayoutsDecodeWhetherOrNotTheFieldIsPresent() throws {
        let decoder = JSONDecoder()
        let old = try decoder.decode(
            KeyFrequencyStore.self,
            from: Data(#"{"schemaVersion":1,"days":[{"date":"2026-08-25","entries":[]}]}"#.utf8)
        )
        XCTAssertEqual(old.days.first?.layouts, [])
        let new = try decoder.decode(
            KeyFrequencyStore.self,
            from: Data(#"{"schemaVersion":2,"days":[{"date":"2026-08-25","entries":[],"layouts":["x"]}]}"#.utf8)
        )
        XCTAssertEqual(new.days.first?.layouts, ["x"])
    }

    /// The day a layout change is installed is counted under both tables, in
    /// the order they wrote, and stays that way through a merge with the file.
    func testADayRemembersEveryTableThatCountedIntoIt() {
        var onDisk = KeyFrequencyTally()
        onDisk.record(a, on: day1, layout: "old")
        var sinceLaunch = KeyFrequencyTally()
        sinceLaunch.record(a, on: day1, layout: "new")
        sinceLaunch.record(a, on: day2, layout: "new")

        var merged = onDisk
        merged.merge(sinceLaunch)
        XCTAssertEqual(merged.layouts(on: day1), ["old", "new"])
        XCTAssertEqual(merged.layouts(on: day2), ["new"])

        let reread = KeyFrequencyTally(store: merged.snapshot())
        XCTAssertEqual(reread, merged)
        XCTAssertEqual(reread.snapshot().days.map(\.layouts), [["old", "new"], ["new"]])
    }

    // MARK: - Rotation

    private func store(_ days: [(String, [String], Int)]) -> KeyFrequencyStore {
        KeyFrequencyStore(days: days.map { date, layouts, count in
            .init(
                date: date,
                entries: count > 0 ? [.init(keyCode: 0x00, isShifted: false, count: count)] : [],
                layouts: layouts
            )
        })
    }

    /// A tally holds one layout's counts. Anything else is moved aside, and the
    /// day a change lands — which carries both names — is exactly the day that
    /// has to move.
    func testRotationIsNeededOnlyWhenAnotherTableCounted() {
        XCTAssertFalse(KeyFrequencyRotation.isNeeded(for: store([("2026-09-11", ["new"], 5)]), layout: "new"))
        XCTAssertTrue(KeyFrequencyRotation.isNeeded(for: store([("2026-09-11", ["old"], 5)]), layout: "new"))
        XCTAssertTrue(
            KeyFrequencyRotation.isNeeded(
                for: store([("2026-09-11", ["new"], 5), ("2026-09-12", ["old", "new"], 5)]),
                layout: "new"
            )
        )
        XCTAssertFalse(KeyFrequencyRotation.isNeeded(for: .empty, layout: "new"))
    }

    /// A day with no counts names nothing worth keeping, so an empty shell of a
    /// file must not send the tally to the archive on every launch.
    func testRotationIgnoresDaysWithNoCounts() {
        XCTAssertFalse(KeyFrequencyRotation.isNeeded(for: store([("2026-09-11", ["old"], 0)]), layout: "new"))
    }

    /// Days written before the field existed are not unnamed: they were counted
    /// under the one table in existence then, which is a different table now.
    func testRotationTreatsUnmarkedDaysAsTheTableBeforeMarking() {
        XCTAssertTrue(KeyFrequencyRotation.isNeeded(for: store([("2026-09-11", [], 5)]), layout: "new"))
        XCTAssertFalse(
            KeyFrequencyRotation.isNeeded(
                for: store([("2026-09-11", [], 5)]),
                layout: KeyFrequencyStore.layoutBeforeMarking
            )
        )
    }

    /// The name says which days are inside, so a folder of archives reads as a
    /// timeline without opening any of them.
    func testArchiveNameCarriesTheDaysItCovers() {
        XCTAssertEqual(
            KeyFrequencyRotation.archiveBaseName(for: store([("2000-01-01", ["a"], 1), ("2000-01-02", ["a"], 1)])),
            "key-frequency-2000-01-01_2000-01-02"
        )
        XCTAssertEqual(
            KeyFrequencyRotation.archiveBaseName(for: store([("2026-09-12", ["a"], 1)])),
            "key-frequency-2026-09-12"
        )
        XCTAssertNil(KeyFrequencyRotation.archiveBaseName(for: .empty))
        XCTAssertNil(KeyFrequencyRotation.archiveBaseName(for: store([("2026-09-12", ["a"], 0)])))
    }

    /// The dates come out of a file and the name becomes a path, so a `date`
    /// that is not a calendar day is never used as one.
    func testArchiveNameRefusesDatesThatAreNotCalendarDays() {
        XCTAssertNil(KeyFrequencyRotation.archiveBaseName(for: store([("../../escape", ["a"], 1)])))
        XCTAssertNil(KeyFrequencyRotation.archiveBaseName(for: store([("2026-9-1", ["a"], 1)])))
        XCTAssertNil(KeyFrequencyRotation.archiveBaseName(for: store([("20xx-09-01", ["a"], 1)])))
        // A good day among bad ones still names the file after itself.
        XCTAssertEqual(
            KeyFrequencyRotation.archiveBaseName(for: store([("../x", ["a"], 1), ("2026-09-01", ["a"], 1)])),
            "key-frequency-2026-09-01"
        )
    }

    /// An archive written over an older archive would destroy the one copy of
    /// those counts, so a taken name is never reused and "no free name" is an
    /// answer the caller has to handle.
    func testFreeFileNameStepsAsideAndGivesUpRatherThanOverwrite() {
        XCTAssertEqual(KeyFrequencyRotation.freeFileName(base: "t", isTaken: { _ in false }), "t.json")
        XCTAssertEqual(
            KeyFrequencyRotation.freeFileName(base: "t", isTaken: { $0 == "t.json" }),
            "t-2.json"
        )
        XCTAssertEqual(
            KeyFrequencyRotation.freeFileName(base: "t", isTaken: { $0 == "t.json" || $0 == "t-2.json" }),
            "t-3.json"
        )
        XCTAssertNil(KeyFrequencyRotation.freeFileName(base: "t", isTaken: { _ in true }))
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
        XCTAssertEqual(Set(day.keys), ["date", "entries", "layouts"])
        XCTAssertEqual(day["date"] as? String, "2026-08-25")
        // The one field that is not a count names a rule table, and nothing
        // about a keystroke.
        XCTAssertEqual(day["layouts"] as? [String], [WKRLayout.layoutIdentifier])

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
