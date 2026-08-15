extension PhysicalKey {
    /// The character this key carries when its `rawValue` already is that
    /// character, which covers the letters, digits and unshifted punctuation
    /// the fallback needs. Keys whose `rawValue` is a description rather than a
    /// character (`Shift+1`, `JIS-Yen`) return `nil`; resolving those belongs to
    /// the macOS layer, which can ask the current ASCII-capable keyboard layout.
    public var unshiftedASCIICharacter: Character? {
        rawValue.count == 1 ? rawValue.first : nil
    }
}

/// The physical keys typed since the last commit boundary, together with the
/// number of standard romaji characters WKR streamed for them.
///
/// Apple Japanese Input's `英数` connect-back returns the raw romaji it
/// received, and that is what WKR synthesised rather than what the user pressed:
/// `T` `H` `I` `N` `G` comes back as `layunnh`. Replacing that text needs both
/// the physical keys and the exact number of characters to remove, and neither
/// is recoverable from the IME afterwards. The rationale, the measurements this
/// is bounded by, and the conditions that must fail closed are in
/// `docs/design.md` section 8.
///
/// The journal only records. It never decides to act, and it holds nothing but
/// key identities and a count, which stay in memory.
public struct EnglishFallbackJournal: Equatable, Sendable {
    public struct Snapshot: Equatable, Sendable {
        /// Physical keys in the order they were pressed.
        public let keys: [PhysicalKey]
        /// Characters to remove before inserting the English reading. Equal to
        /// the romaji WKR streamed for `keys`, which is what the connect-back
        /// puts on screen.
        public let romajiCharacterCount: Int

        public init(keys: [PhysicalKey], romajiCharacterCount: Int) {
            self.keys = keys
            self.romajiCharacterCount = romajiCharacterCount
        }
    }

    /// Twelve keys produce at most twelve kana, because every rule consumes at
    /// least one key. A pre-edit of that length was measured on 2026-08-14 not
    /// to commit any part of itself without Space, Return or punctuation, so
    /// staying at or below it keeps `romajiCharacterCount` equal to what the
    /// connect-back shows. Raising this needs the same measurement repeated at
    /// the longer length first, because a partial commit is invisible to WKR.
    public static let defaultKeyLimit = 12

    /// Backstop for a pre-edit that is left on screen and returned to much
    /// later. Every context change already clears the journal on its own.
    public static let defaultLifetimeSeconds: Double = 30

    private let keyLimit: Int
    private let lifetimeSeconds: Double

    private var keys: [PhysicalKey] = []
    private var romajiCharacterCount = 0
    private var isUsable = true
    private var lastRecordedAt: Double?

    public init(
        keyLimit: Int = defaultKeyLimit,
        lifetimeSeconds: Double = defaultLifetimeSeconds
    ) {
        precondition(keyLimit > 0, "The English fallback journal needs room for at least one key")
        precondition(lifetimeSeconds > 0, "The English fallback journal needs a positive lifetime")
        self.keyLimit = keyLimit
        self.lifetimeSeconds = lifetimeSeconds
    }

    /// Feed every event together with the result the transducer returned for
    /// it, in the order the controller applied them.
    public mutating func record(
        _ event: WKRInputEvent,
        result: TransitionResult,
        at now: Double
    ) {
        if hasExpired(at: now) {
            clear()
        }

        switch event {
        case let .physical(key):
            record(key, result: result, at: now)
        case .boundary, .backspace:
            // Space, Return, Tab and punctuation end the pre-edit WKR was
            // counting, and Backspace changes it by an amount measured in
            // display units rather than romaji characters.
            clear()
        case let .reset(reason):
            // `英数` reaches the controller as an input source change, and that
            // is exactly the key the user presses on the way to the fallback,
            // so the journal has to outlive it. The conversion gate still
            // closes; only the recorded keys stay.
            if reason != .inputSourceChanged {
                clear()
            }
        }
    }

    /// What the fallback may replace, or `nil` when it must not fire.
    public func snapshot(at now: Double) -> Snapshot? {
        guard isUsable, !keys.isEmpty, romajiCharacterCount > 0, !hasExpired(at: now) else {
            return nil
        }
        return Snapshot(keys: keys, romajiCharacterCount: romajiCharacterCount)
    }

    public mutating func clear() {
        keys.removeAll()
        romajiCharacterCount = 0
        isUsable = true
        lastRecordedAt = nil
    }

    private mutating func record(_ key: PhysicalKey, result: TransitionResult, at now: Double) {
        guard isUsable else { return }

        guard result.disposition == .suppress else {
            // The original key reached Apple Japanese Input as well, so the
            // characters WKR streamed are no longer the whole pre-edit.
            invalidate()
            return
        }

        var streamedCharacters = 0
        for action in result.actions {
            switch action {
            case let .romaji(value):
                streamedCharacters += value.count
            case .unicode, .backspace:
                // A Unicode injection commits on the spot instead of joining
                // the romaji Apple Japanese Input can connect back, and a
                // backspace count is in display units. Neither can be
                // reconciled with the text the connect-back produces.
                invalidate()
                return
            }
        }

        keys.append(key)
        romajiCharacterCount += streamedCharacters
        lastRecordedAt = now

        if keys.count > keyLimit {
            // Beyond the measured pre-edit length a partial commit cannot be
            // ruled out, and WKR has no way to observe one.
            invalidate()
        }
    }

    /// Stop offering a snapshot until a boundary or a reset starts a new
    /// pre-edit. The recorded keys are dropped at the same time.
    private mutating func invalidate() {
        keys.removeAll()
        romajiCharacterCount = 0
        isUsable = false
        lastRecordedAt = nil
    }

    private func hasExpired(at now: Double) -> Bool {
        guard let lastRecordedAt else { return false }
        return now - lastRecordedAt >= lifetimeSeconds
    }
}
