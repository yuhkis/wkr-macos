import Foundation

public struct KeyIdentity: Hashable, Sendable, Codable {
    public let keyCode: UInt16
    public let isShifted: Bool

    public init(keyCode: UInt16, isShifted: Bool = false) {
        self.keyCode = keyCode
        self.isShifted = isShifted
    }
}

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

public struct KeyFrequencyStore: Equatable, Sendable, Codable {
    public struct Entry: Equatable, Sendable, Codable {
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

    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let days: [Day]

    public init(schemaVersion: Int = KeyFrequencyStore.currentSchemaVersion, days: [Day]) {
        self.schemaVersion = schemaVersion
        self.days = days
    }

    public static let empty = KeyFrequencyStore(days: [])
}

public struct KeyFrequencyTally: Equatable, Sendable {
    public static let defaultRetainedDays: Int? = nil

    public static let maximumIdentitiesPerDay = 512

    private var days: [KeyFrequencyDay: [KeyIdentity: Int]]

    public init() {
        self.days = [:]
    }

    public init(store: KeyFrequencyStore) {
        guard store.schemaVersion == KeyFrequencyStore.currentSchemaVersion else {
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

    public mutating func merge(_ other: KeyFrequencyTally) {
        for (day, counts) in other.days {
            days[day, default: [:]].merge(counts) { $0 + $1 }
        }
    }

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
                .sorted { lhs, rhs in
                    lhs.keyCode == rhs.keyCode
                        ? (!lhs.isShifted && rhs.isShifted)
                        : lhs.keyCode < rhs.keyCode
                }
            return KeyFrequencyStore.Day(date: day.rawValue, entries: entries)
        }
        return KeyFrequencyStore(days: sortedDays)
    }

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
