import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog
import WKRCore

/// Holds the key frequency tally in memory and owns the one file it is ever
/// written to.
///
/// The split of responsibilities here is the whole point of the type. The event
/// tap callback may do nothing but add one to an integer, because `AGENTS.md`
/// forbids file I/O, network I/O and heavy work inside it; a stalled callback is
/// removed by the system and takes conversion down with it. So `recordKeyDown`
/// and `recordFlagsChanged` touch memory only, and every path that opens a file
/// hangs off a timer on the main run loop instead.
///
/// What leaves the process is an aggregate and nothing else. There is no key
/// sequence, no order, no text and no timestamp finer than the calendar day, so
/// the file cannot be replayed into what was typed. That is not a side effect of
/// the format — it is why `KeyIdentity` and `KeyFrequencyDay` are shaped the way
/// they are, and this recorder must not widen either of them.
///
/// When in doubt it counts nothing. A press that might be a shortcut, a press
/// under a modifier this tool does not model, a key it cannot name, a home
/// directory it cannot resolve: all of those produce an undercount, which makes
/// a heatmap slightly pale, rather than a guess, which makes it wrong in a way
/// the user cannot see.
final class KeyFrequencyRecorder {
    /// Fixed so the TCC-visible bundle identifier and the on-disk location stay
    /// the same string; `AGENTS.md` pins the identifier to keep the permission
    /// grant stable across rebuilds, and a tally under a second name would be
    /// invisible to the report command.
    static let bundleIdentifier = "io.github.yuhkis.wkr-macos"
    static let storeFileName = "key-frequency.json"

    /// Two minutes. A crash or a forced quit therefore loses at most two minutes
    /// of counts, while the write itself stays far away from the typing path:
    /// at this spacing the file is touched a few hundred times a day, never
    /// while a key is being handled.
    static let flushInterval: TimeInterval = 120

    /// Key presses carrying any of these are never counted.
    ///
    /// These are the modifiers `EventTapController` refuses to convert under,
    /// and the two have to agree: a keystroke the transducer passed through
    /// untouched is not a wkr-layout keystroke, and drawing it on the layout
    /// picture would attribute a shortcut to a layer it never went through. The
    /// privacy argument points the same way — a tally of Command chords would
    /// start to describe which applications the user drives and how, which is
    /// well past "how often is this key under this finger".
    ///
    /// Shift is deliberately absent: it selects the other legend printed on a
    /// JIS key rather than issuing a command, so it becomes
    /// `KeyIdentity.isShifted`.
    ///
    /// `.maskSecondaryFn` is deliberately absent too, and that is the subtle
    /// one. Despite its name it is not a record of the user holding `fn`:
    /// `CGEventTypes.h` files it under "Special key identifiers", and macOS sets
    /// it on every event in the function-key group — the four arrows, Home, End,
    /// Page Up, Page Down, forward Delete, Help and F1 upward — whether or not
    /// `fn` was touched. Treating it as a modifier made the arrow keys
    /// permanently uncountable, which drew them cold on a board that lists them
    /// as ordinary keys: "never pressed" where the truth was "never counted".
    /// The cost of leaving it out is that a genuine `fn`+key chord is counted as
    /// the key; there is no bit that separates the two cases, and undercounting
    /// six navigation keys is the larger error.
    ///
    /// This set applies to key presses. `recordFlagsChanged` deliberately does
    /// not consult it — see the note there.
    private static let uncountableFlags: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskAlphaShift,
    ]

    /// Which modifier flag each modifier keycode owns.
    ///
    /// `CGEventFlags` says a modifier is down but not which side it is, so both
    /// halves of a pair map to the same mask. The consequence is stated where
    /// the edge is detected: the second of two Shifts held together is not
    /// counted.
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

    /// Every member below is touched from the event tap callback and from the
    /// main run loop. Both are the main thread in this app — the tap is added to
    /// the main run loop at startup and its callback runs there — so there is no
    /// lock. A `dispatchPrecondition` guards the two entry points that are
    /// allowed to be slow; the per-keystroke path deliberately has none, because
    /// the check would be work done inside the callback to prove something the
    /// callback's own registration already guarantees.
    private var tally = KeyFrequencyTally()
    private var previousFlags: CGEventFlags = []
    private var flushTimer: Timer?

    /// A snapshot rather than a fresh `Calendar.current` per press, because
    /// reading the current calendar builds one each time and that is real work
    /// in the callback. A time zone changed mid-session therefore keeps filing
    /// under the old day until the next launch, which moves at most one
    /// midnight boundary in a tally whose whole resolution is the day.
    private let calendar = Calendar.current
    private var cachedDay: KeyFrequencyDay?
    private var cachedDayStart = Date.distantFuture
    private var cachedDayEnd = Date.distantPast

    /// `nil` when frequency logging is off, so the caller can skip every code
    /// path with one optional check rather than asking a live object to ignore
    /// its input. It is also `nil` when the store location cannot be resolved:
    /// a recorder that can never write would accumulate counts that only ever
    /// get thrown away.
    init?(enabled: Bool, storeURL: URL? = nil) {
        guard enabled else { return nil }
        guard let url = storeURL ?? Self.defaultStoreURL() else { return nil }
        self.storeURL = url
    }

    /// `~/Library/Application Support/io.github.yuhkis.wkr-macos/key-frequency.json`.
    ///
    /// Asked for with `create: false` so that the directory comes into existence
    /// in exactly one place — the flush path, which creates it and sets its mode
    /// in the same breath. A directory created here would briefly carry whatever
    /// the umask says.
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

    // MARK: - Recording

    /// Add one press to the in-memory tally.
    ///
    /// The caller decides *whether* a press is in scope: this is called only
    /// while the conversion gate is open, and the gate — secure input, the
    /// permission state, the tap's own health, the active input source, the
    /// excluded-application list — lives in `EventTapController`. It is not
    /// re-checked here. Two copies of that decision would drift, and the copy
    /// that drifted would be the silent one, counting keystrokes from a session
    /// wkr was not converting at all.
    func recordKeyDown(keyCode: CGKeyCode, flags: CGEventFlags, isAutorepeat: Bool) {
        // Holding a key down is one press. The repeats describe how long a
        // finger rested, not how often it moved, and a single leaned-on
        // Backspace would otherwise dominate a whole day's picture.
        guard !isAutorepeat else { return }
        guard flags.intersection(Self.uncountableFlags).isEmpty else { return }
        tally.record(
            KeyIdentity(keyCode: UInt16(keyCode), isShifted: flags.contains(.maskShift)),
            on: currentDay()
        )
    }

    /// Add one modifier press, on its press edge only.
    ///
    /// A modifier arrives as a flags-changed event with no up/down field, so the
    /// edge has to be read out of the flags themselves: the key was pressed if
    /// its mask is set now and was not set before. Releases are the mirror image
    /// and are dropped, otherwise every Shift would count twice.
    ///
    /// Caps Lock needs no special case despite behaving differently. Its flag
    /// latches rather than tracking the key, so the press that turns it on is a
    /// transition into `.maskAlphaShift` and reads as a press, while the press
    /// that turns it off reads as a release and is not counted. Half of a Caps
    /// Lock pair is the honest answer available from the flags alone; claiming
    /// both would need state the tap cannot see.
    ///
    /// Two keys sharing a mask — left and right Shift held together — count once,
    /// because `CGEventFlags` carries no side. Undercounting the rarer hand is
    /// the fail-closed direction.
    ///
    /// `uncountableFlags` is not applied here, and the difference is deliberate.
    /// That set exists so a *letter* struck under Command is not filed as a
    /// keystroke; pressing Command itself is the keystroke, and on a split
    /// keyboard where Command, Control and Shift sit under the thumbs it is one
    /// of the most-worked keys on the board. What is recorded is that a modifier
    /// went down, never what was pressed with it, so it says nothing about which
    /// shortcut was used — which is what the privacy argument on that set is
    /// about.
    func recordFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) {
        let previous = previousFlags
        // Recorded even for keycodes that are not counted below, so that a
        // modifier this tool does not model still updates the baseline the next
        // edge is measured against.
        previousFlags = flags
        // An unknown keycode is left alone rather than guessed at. Keyboards
        // send flags-changed events for keys that are not in the table above,
        // and a name invented here would land on a cap in the picture.
        guard let mask = Self.modifierMasks[keyCode] else { return }
        guard flags.contains(mask), !previous.contains(mask) else { return }
        tally.record(KeyIdentity(keyCode: UInt16(keyCode)), on: currentDay())
    }

    /// Forget which modifiers were down.
    ///
    /// The baseline an edge is measured against is only updated by events this
    /// recorder actually receives, and it receives none while the conversion
    /// gate is closed. Without this, a Shift held as the user switches
    /// applications is never seen to come up, and the next press of it reads as
    /// "already down" and is dropped. Called wherever the gate closes, so the
    /// first modifier event after it reopens is treated as a fresh press.
    func forgetModifierState() {
        previousFlags = []
    }

    /// The day a press happening right now belongs to.
    ///
    /// Resolved at record time rather than at flush time so a session running
    /// through midnight files each press under the day it actually happened;
    /// a flush at 00:02 would otherwise move the evening's typing into the new
    /// day. The result is cached for the length of the day it names, because
    /// building the `YYYY-MM-DD` string allocates and the callback would pay for
    /// it on every keystroke. If the day's bounds cannot be computed the cache
    /// is left unusable, so the next press recomputes rather than reuses a
    /// window of unknown length.
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

    // MARK: - Flushing

    /// Begin writing the tally out periodically. Main run loop only.
    func startFlushing() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard flushTimer == nil else { return }
        let timer = Timer(timeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            self?.flush()
        }
        // `.common` rather than the default mode: a menu held open or a window
        // being dragged puts the run loop into a tracking mode, and a timer that
        // only fires in the default mode would stop for as long as that lasts —
        // exactly the moments when the user is not typing and the write is
        // cheapest.
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    /// Write what is held and stop the timer. Called from
    /// `applicationWillTerminate`, where an unwritten tally would be lost.
    func flushAndStop() {
        dispatchPrecondition(condition: .onQueue(.main))
        flushTimer?.invalidate()
        flushTimer = nil
        flush()
    }

    /// Load, merge, prune and write. `false` on any I/O failure, with the
    /// in-memory tally left intact so the next attempt still has the counts.
    @discardableResult
    func flush() -> Bool {
        // Nothing typed since the last write, so there is nothing to fold in.
        // Pruning is tied to writes on purpose: a tally that has stopped
        // changing is not rewritten every two minutes just to age one day out of
        // the window, and the next press brings the window forward.
        guard !tally.isEmpty else { return true }

        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Set separately, and only on our own directory, because
            // `createDirectory` applies attributes to what it creates and leaves
            // an existing directory alone — so a directory from an earlier build
            // would keep whatever mode it was born with. The parents are not
            // touched: they belong to macOS.
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            AppLog.logger.error("key-frequency flush=failed stage=directory")
            return false
        }

        // Read first, then merge, so counts written by another instance of the
        // app survive this write. The read-then-rename pair is not atomic across
        // processes and cannot be, so this narrows the losing window rather than
        // closing it; two instances are not a supported configuration anyway.
        let existing: KeyFrequencyTally
        switch Self.readStore(at: storeURL) {
        case .absent:
            existing = KeyFrequencyTally()
        case let .decoded(store):
            existing = KeyFrequencyTally(store: store)
        case .unusable:
            // Present but not decodable as a tally. There is nothing in it to
            // preserve, and refusing forever would mean never writing again.
            existing = KeyFrequencyTally()
        case .unreadable:
            // Present, and it may well hold counts. Overwriting it blind would
            // destroy them, so this attempt fails and the tally stays in memory.
            AppLog.logger.error("key-frequency flush=failed stage=read")
            return false
        }

        var merged = existing
        merged.merge(tally)
        merged.prune(
            retainedDays: KeyFrequencyTally.defaultRetainedDays,
            today: currentDay()
        )

        let encoder = JSONEncoder()
        // Readable and byte-stable: a user who wants to know exactly what this
        // keeps about them can open the file, and an unchanged tally produces an
        // unchanged file rather than a reshuffled one.
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(merged.snapshot()) else {
            AppLog.logger.error("key-frequency flush=failed stage=encode")
            return false
        }

        // Same directory as the target so the rename stays within one volume and
        // is therefore atomic: a reader either sees the whole previous tally or
        // the whole new one, never a half-written file. The name is dot-prefixed
        // so a partial write is not mistaken for a tally, and carries a UUID so
        // two writers cannot collide on it.
        let temporaryURL = directory.appendingPathComponent(
            ".\(storeURL.lastPathComponent).\(UUID().uuidString)",
            isDirectory: false
        )
        do {
            try data.write(to: temporaryURL)
            // Tightened before the rename, never after: this file records
            // something about how its owner types, and other users on the
            // machine have no business reading it — not even for the moment
            // between appearing and being chmod'ed.
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryURL.path
            )
            if fileManager.fileExists(atPath: storeURL.path) {
                // `.usingNewMetadataOnly` so the replacement keeps the mode just
                // set instead of inheriting the old file's, which may be looser
                // if it was copied in or written by an older build.
                _ = try fileManager.replaceItemAt(
                    storeURL,
                    withItemAt: temporaryURL,
                    options: .usingNewMetadataOnly
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: storeURL)
            }
        } catch {
            // The temporary file is removed even on failure; leaving one behind
            // per attempt would fill the directory with fragments of a tally.
            try? fileManager.removeItem(at: temporaryURL)
            AppLog.logger.error("key-frequency flush=failed stage=write")
            return false
        }

        // Cleared only after the rename succeeded. Everything held here is now
        // in the file, and keeping it would add it again at the next flush.
        let dayCount = merged.recordedDays.count
        tally = KeyFrequencyTally()
        // Outcome and shape only. A keycode or a per-key count in the log would
        // put in `log show` exactly what the file format goes out of its way not
        // to reveal.
        AppLog.logger.notice("key-frequency flush=ok days=\(dayCount, privacy: .public)")
        return true
    }

    // MARK: - Reading and resetting

    /// Read the persisted tally without starting a recorder, for the report
    /// command, which draws the file and must not begin counting to do so.
    static func loadStore(at url: URL) -> KeyFrequencyStore? {
        guard case let .decoded(store) = readStore(at: url) else { return nil }
        // The same gate `KeyFrequencyTally(store:)` applies. A file written by a
        // later version may decode into today's fields and mean something else,
        // and a report drawn from it would be wrong in a picture no one can
        // check against the source.
        guard store.schemaVersion == KeyFrequencyStore.currentSchemaVersion else { return nil }
        return store
    }

    /// Delete the persisted tally.
    ///
    /// Only the file. A recorder running in another process still holds its own
    /// counts and will write them at its next flush, so the reset command is
    /// documented as something to run with the app stopped rather than made to
    /// pretend otherwise here.
    static func resetStore(at url: URL) throws {
        let fileManager = FileManager.default
        // Nothing to delete is the state `reset` is asked to produce, so it is
        // not an error to report.
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Why a read produced no store, which the flush path has to tell apart:
    /// the first run and a corrupt file may be overwritten, an unreadable one
    /// may not.
    private enum StoreRead {
        case absent
        case decoded(KeyFrequencyStore)
        /// Present and readable, but not JSON this version understands.
        case unusable
        /// Present, and the bytes could not be obtained at all.
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
