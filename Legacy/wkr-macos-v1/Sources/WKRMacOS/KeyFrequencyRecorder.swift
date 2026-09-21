import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog
import WKRCore

final class KeyFrequencyRecorder {
    static let bundleIdentifier = "io.github.yuhkis.wkr-macos.v1-archive"
    static let storeFileName = "key-frequency.json"

    static let flushInterval: TimeInterval = 120

    private static let uncountableFlags: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskAlphaShift,
    ]

    private static let modifierMasks: [CGKeyCode: CGEventFlags] = [
        CGKeyCode(kVK_Shift): .maskShift,
        CGKeyCode(kVK_RightShift): .maskShift,
        CGKeyCode(kVK_Control): .maskControl,
        CGKeyCode(kVK_RightControl): .maskControl,
        CGKeyCode(kVK_Option): .maskAlternate,
        CGKeyCode(kVK_RightOption): .maskAlternate,
        CGKeyCode(kVK_Command): .maskCommand,
        CGKeyCode(kVK_RightCommand): .maskCommand,
        CGKeyCode(kVK_CapsLock): .maskAlphaShift,
        CGKeyCode(kVK_Function): .maskSecondaryFn,
    ]

    private let storeURL: URL
    private let retainedDays: Int?

    private var tally = KeyFrequencyTally()
    private var previousFlags: CGEventFlags = []
    private var flushTimer: Timer?

    private let calendar = Calendar.current
    private var cachedDay: KeyFrequencyDay?
    private var cachedDayStart = Date.distantFuture
    private var cachedDayEnd = Date.distantPast

    init?(
        enabled: Bool,
        storeURL: URL? = nil,
        retainedDays: Int? = KeyFrequencyTally.defaultRetainedDays
    ) {
        guard enabled else { return nil }
        guard let url = storeURL ?? Self.defaultStoreURL() else { return nil }
        self.storeURL = url
        self.retainedDays = retainedDays
    }

    static func defaultStoreURL() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        return base
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(storeFileName, isDirectory: false)
    }


    func recordKeyDown(keyCode: CGKeyCode, flags: CGEventFlags, isAutorepeat: Bool) {
        guard !isAutorepeat else { return }
        guard flags.intersection(Self.uncountableFlags).isEmpty else { return }
        tally.record(
            KeyIdentity(keyCode: UInt16(keyCode), isShifted: flags.contains(.maskShift)),
            on: currentDay()
        )
    }

    func recordFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) {
        let previous = previousFlags
        previousFlags = flags
        guard let mask = Self.modifierMasks[keyCode] else { return }
        guard flags.contains(mask), !previous.contains(mask) else { return }
        tally.record(KeyIdentity(keyCode: UInt16(keyCode)), on: currentDay())
    }

    func forgetModifierState() {
        previousFlags = []
    }

    private func currentDay() -> KeyFrequencyDay {
        let now = Date()
        if let cachedDay, now >= cachedDayStart, now < cachedDayEnd {
            return cachedDay
        }
        let day = KeyFrequencyDay(date: now, calendar: calendar)
        if let interval = calendar.dateInterval(of: .day, for: now) {
            cachedDayStart = interval.start
            cachedDayEnd = interval.end
        } else {
            cachedDayStart = .distantFuture
            cachedDayEnd = .distantPast
        }
        cachedDay = day
        return day
    }


    func startFlushing() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard flushTimer == nil else { return }
        let timer = Timer(timeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            self?.flush()
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    func flushAndStop() {
        dispatchPrecondition(condition: .onQueue(.main))
        flushTimer?.invalidate()
        flushTimer = nil
        flush()
    }

    @discardableResult
    func flush() -> Bool {
        guard !tally.isEmpty else { return true }

        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            AppLog.logger.error("key-frequency flush=failed stage=directory")
            return false
        }

        let existing: KeyFrequencyTally
        switch Self.readStore(at: storeURL) {
        case .absent:
            existing = KeyFrequencyTally()
        case let .decoded(store):
            existing = KeyFrequencyTally(store: store)
        case .unusable:
            existing = KeyFrequencyTally()
        case .unreadable:
            AppLog.logger.error("key-frequency flush=failed stage=read")
            return false
        }

        var merged = existing
        merged.merge(tally)
        merged.prune(retainedDays: retainedDays, today: currentDay())

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(merged.snapshot()) else {
            AppLog.logger.error("key-frequency flush=failed stage=encode")
            return false
        }

        let temporaryURL = directory.appendingPathComponent(
            ".\(storeURL.lastPathComponent).\(UUID().uuidString)",
            isDirectory: false
        )
        do {
            try data.write(to: temporaryURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryURL.path
            )
            if fileManager.fileExists(atPath: storeURL.path) {
                _ = try fileManager.replaceItemAt(
                    storeURL,
                    withItemAt: temporaryURL,
                    options: .usingNewMetadataOnly
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: storeURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            AppLog.logger.error("key-frequency flush=failed stage=write")
            return false
        }

        let dayCount = merged.recordedDays.count
        tally = KeyFrequencyTally()
        AppLog.logger.notice("key-frequency flush=ok days=\(dayCount, privacy: .public)")
        return true
    }


    static func loadStore(at url: URL) -> KeyFrequencyStore? {
        guard case let .decoded(store) = readStore(at: url) else { return nil }
        guard store.schemaVersion == KeyFrequencyStore.currentSchemaVersion else { return nil }
        return store
    }

    static func resetStore(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private enum StoreRead {
        case absent
        case decoded(KeyFrequencyStore)
        case unusable
        case unreadable
    }

    private static func readStore(at url: URL) -> StoreRead {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return (error as? CocoaError)?.code == .fileReadNoSuchFile ? .absent : .unreadable
        }
        guard let store = try? JSONDecoder().decode(KeyFrequencyStore.self, from: data) else {
            return .unusable
        }
        return .decoded(store)
    }
}
