extension PhysicalKey {
    public var jisCharacter: Character {
        if rawValue.count == 1, let character = rawValue.first {
            return character
        }
        switch self {
        case .leftBrace: return "{"
        case .rightBrace: return "}"
        case .shiftedDigit1: return "!"
        case .shiftedDigit2: return "\""
        case .shiftedDigit3: return "#"
        case .shiftedDigit4: return "$"
        case .shiftedDigit5: return "%"
        case .shiftedDigit6: return "&"
        case .shiftedDigit7: return "'"
        case .shiftedDigit8: return "("
        case .shiftedDigit9: return ")"
        case .jisUnderscore: return "_"
        case .shiftedMinus: return "="
        case .shiftedSemicolon: return "+"
        case .jisYen: return "\u{00A5}"
        case .shiftedJisYen: return "|"
        case .shiftedAt: return "`"
        case .shiftedCaret: return "~"
        case .shiftedComma: return "<"
        case .shiftedPeriod: return ">"
        default:
            return "\u{FFFD}"
        }
    }
}

public enum EnglishFallbackTrigger: String, Equatable, Sendable, CaseIterable {
    case disabled = "off"
    case eisuBurst = "eisu+eisu"
    case eisuReturn = "eisu+return"
    case eisuTab = "eisu+tab"

    public static let `default` = EnglishFallbackTrigger.eisuBurst

    public static let burstSettleSeconds = 0.25

    public static let minimumBurstPresses = 2
}

public struct EnglishFallbackJournal: Equatable, Sendable {
    public struct Snapshot: Equatable, Sendable {
        public let keys: [PhysicalKey]
        public let romajiCharacterCount: Int

        public init(keys: [PhysicalKey], romajiCharacterCount: Int) {
            self.keys = keys
            self.romajiCharacterCount = romajiCharacterCount
        }
    }

    public static let defaultKeyLimit = 12

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
        case .boundary, .romanTransliteration, .backspace:
            clear()
        case let .reset(reason):
            if reason != .inputSourceChanged {
                clear()
            }
        }
    }

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
            invalidate()
            return
        }

        var streamedCharacters = 0
        var deletionUnits = 0
        for action in result.actions {
            switch action {
            case let .romaji(value):
                streamedCharacters += value.count
            case let .backspace(count):
                deletionUnits += count
            case .unicode:
                invalidate()
                return
            }
        }

        if deletionUnits > 0 {
            guard result.deletedRomajiCharacters > 0,
                  result.deletedRomajiCharacters <= romajiCharacterCount
            else {
                invalidate()
                return
            }
            romajiCharacterCount -= result.deletedRomajiCharacters
        }

        keys.append(key)
        romajiCharacterCount += streamedCharacters
        lastRecordedAt = now

        if keys.count > keyLimit {
            invalidate()
        }
    }

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
