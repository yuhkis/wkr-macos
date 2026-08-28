import Foundation

/// One countable key press, reduced to the least that still identifies a key
/// on a keyboard picture.
///
/// This is deliberately not a keystroke record. It has no position in a
/// sequence, no timestamp finer than the calendar day it is filed under, and no
/// text. Two presses of the same key are indistinguishable, which is the whole
/// point: a heatmap needs totals, and totals are all this carries.
///
/// `isShifted` is part of the identity because JIS prints two different
/// characters on most keys and a Corne routes Shift through its own thumb keys,
/// so `2` and `"` are worth telling apart. No other modifier is recorded; see
/// `KeyFrequencyRecorder` for why events carrying Command, Control or Option
/// are not counted at all.
public struct KeyIdentity: Hashable, Sendable, Codable {
    /// macOS virtual key code, as delivered by `CGEventField.keyboardEventKeycode`.
    public let keyCode: UInt16
    public let isShifted: Bool

    public init(keyCode: UInt16, isShifted: Bool = false) {
        self.keyCode = keyCode
        self.isShifted = isShifted
    }
}

/// A calendar day in the local time zone, as `YYYY-MM-DD`.
///
/// Days are the coarsest bucket that still answers "how has this changed since
/// I moved a key", which is the question the report exists for. Nothing finer
/// is stored, so the file cannot reconstruct when within a day anything was
/// typed.
public struct KeyFrequencyDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The on-disk shape of the tally.
///
/// Arrays rather than dictionaries so the JSON is stable, diffable and
/// readable: a user who wants to know exactly what wkr-macos keeps about them
/// can open the file and see integers.
public struct KeyFrequencyStore: Equatable, Sendable, Codable {
    public struct Entry: Equatable, Sendable, Codable {
        /// macOS virtual key code.
        public let keyCode: UInt16
        public let isShifted: Bool
        public let count: Int

        public init(keyCode: UInt16, isShifted: Bool, count: Int) {
            self.keyCode = keyCode
            self.isShifted = isShifted
            self.count = count
        }

        public var identity: KeyIdentity {
            KeyIdentity(keyCode: keyCode, isShifted: isShifted)
        }
    }

    public struct Day: Equatable, Sendable, Codable {
        public let date: String
        public let entries: [Entry]

        public init(date: String, entries: [Entry]) {
            self.date = date
            self.entries = entries
        }
    }

    /// Bumped whenever the meaning of the fields changes. A reader that finds a
    /// version it does not know starts over rather than guessing, because a
    /// misread tally would be silently wrong in a picture.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let days: [Day]

    public init(schemaVersion: Int = KeyFrequencyStore.currentSchemaVersion, days: [Day]) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    public static let empty = KeyFrequencyStore(days: [])
}

/// Per-day counts, held in memory while the app runs.
///
/// A value type with no reference to the file: the recorder owns when anything
/// is written, because `AGENTS.md` forbids file I/O inside the event tap
/// callback and this is what the callback touches.
public struct KeyFrequencyTally: Equatable, Sendable {
    /// Nothing is dropped unless the user asks for a window.
    ///
    /// This started as a 180-day cap on the reasoning that a tally should not
    /// become an open-ended record. That was the wrong trade. The feature is
    /// opt-in, so anyone it runs for has already decided they want the data;
    /// the file holds no text, no order and no time finer than a day, which is
    /// where the privacy of this format actually comes from; and a day of
    /// counts measures about 3 KB, so a decade of them is a few tens of
    /// megabytes. Against that, silently deleting a measurement someone chose
    /// to collect is itself a harm — and the one question this tally is best
    /// placed to answer, whether a layout change moved the load, is the
    /// question that needs the oldest data.
    ///
    /// A window is still available for anyone who wants one; it is just not
    /// imposed. `nil` means keep everything.
    public static let defaultRetainedDays: Int? = nil

    /// A single day cannot hold more distinct keys than a keyboard has, so this
    /// is far above any honest value. It exists so that a stuck or malicious
    /// event source cannot grow the map without bound.
    public static let maximumIdentitiesPerDay = 512

    private var days: [KeyFrequencyDay: [KeyIdentity: Int]]

    public init() {
        self.days = [:]
    }

    public init(store: KeyFrequencyStore) {
        guard store.schemaVersion == KeyFrequencyStore.currentSchemaVersion else {
            // An unknown schema is discarded rather than interpreted. Losing a
            // tally is a nuisance; drawing a wrong one is a bug the user cannot
            // see.
            self.days = [:]
            return
        }
        var days: [KeyFrequencyDay: [KeyIdentity: Int]] = [:]
        for day in store.days {
            var counts: [KeyIdentity: Int] = [:]
            for entry in day.entries where entry.count > 0 {
                counts[entry.identity, default: 0] += entry.count
            }
            guard !counts.isEmpty else { continue }
            days[KeyFrequencyDay(rawValue: day.date), default: [:]]
                .merge(counts) { $0 + $1 }
        }
        self.days = days
    }

    public var isEmpty: Bool { days.isEmpty }

    public var total: Int {
        days.values.reduce(0) { $0 + $1.values.reduce(0, +) }
    }

    public mutating func record(_ identity: KeyIdentity, on day: KeyFrequencyDay) {
        var counts = days[day] ?? [:]
        if counts[identity] == nil, counts.count >= Self.maximumIdentitiesPerDay {
            return
        }
        counts[identity, default: 0] += 1
        days[day] = counts
    }

    public func count(of identity: KeyIdentity, on day: KeyFrequencyDay) -> Int {
        days[day]?[identity] ?? 0
    }

    public var recordedDays: [KeyFrequencyDay] {
        days.keys.sorted()
    }

    /// Fold another tally in, so a freshly loaded file and what has been typed
    /// since can be written back without losing either.
    public mutating func merge(_ other: KeyFrequencyTally) {
        for (day, counts) in other.days {
            days[day, default: [:]].merge(counts) { $0 + $1 }
        }
    }

    /// Drop everything outside the retention window, if there is one.
    ///
    /// Called before every write, so a window the user has set ages the file out
    /// without them having to remember. `nil` keeps every day, which is the
    /// default: see `defaultRetainedDays`.
    public mutating func prune(
        retainedDays: Int? = defaultRetainedDays,
        today: KeyFrequencyDay
    ) {
        guard let retainedDays else { return }
        guard retainedDays > 0 else {
            days.removeAll()
            return
        }
        let keep = Set(Self.days(endingOn: today, count: retainedDays))
        days = days.filter { keep.contains($0.key) }
    }

    public func snapshot() -> KeyFrequencyStore {
        let sortedDays = days.keys.sorted().map { day -> KeyFrequencyStore.Day in
            let entries = (days[day] ?? [:])
                .map { identity, count in
                    KeyFrequencyStore.Entry(
                        keyCode: identity.keyCode,
                        isShifted: identity.isShifted,
                        count: count
                    )
                }
                // Sorted so two runs with the same data produce the same bytes.
                .sorted { lhs, rhs in
                    lhs.keyCode == rhs.keyCode
                        ? (!lhs.isShifted && rhs.isShifted)
                        : lhs.keyCode < rhs.keyCode
                }
            return KeyFrequencyStore.Day(date: day.rawValue, entries: entries)
        }
        return KeyFrequencyStore(days: sortedDays)
    }

    /// The `count` calendar days ending on `today`, most recent last.
    public static func days(endingOn today: KeyFrequencyDay, count: Int) -> [KeyFrequencyDay] {
        guard count > 0 else { return [] }
        let calendar = Calendar.current
        var formatter = DateComponents()
        let parts = today.rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return [today] }
        formatter.year = parts[0]
        formatter.month = parts[1]
        formatter.day = parts[2]
        guard let end = calendar.date(from: formatter) else { return [today] }
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end)
                .map { KeyFrequencyDay(date: $0, calendar: calendar) }
        }
    }
}
