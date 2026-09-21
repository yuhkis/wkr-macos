public struct UnicodeInjectionGate: Equatable, Sendable {
    public struct Decision: Equatable, Sendable {
        public let result: TransitionResult
        public let droppedUnicode: Bool
    }

    private var streamedRomajiCharacters = 0

    public init() {}

    public var preEditIsEmpty: Bool {
        streamedRomajiCharacters == 0
    }

    public mutating func decide(
        _ event: WKRInputEvent,
        _ result: TransitionResult
    ) -> Decision {
        let removedHere = result.deletedRomajiCharacters > 0
            ? result.deletedRomajiCharacters
            : result.actions.reduce(0) { partial, action in
                guard case let .backspace(count) = action else { return partial }
                return partial + count
            }
        let carriesUnicode = result.actions.contains { action in
            guard case .unicode = action else { return false }
            return true
        }

        var decided = result
        var dropped = false
        if carriesUnicode, streamedRomajiCharacters - removedHere > 0 {
            decided = TransitionResult(
                actions: result.actions.filter { action in
                    guard case .unicode = action else { return true }
                    return false
                },
                disposition: result.disposition,
                stateCode: result.stateCode
            )
            dropped = true
        }

        record(event, decided)
        return Decision(result: decided, droppedUnicode: dropped)
    }

    public mutating func clear() {
        streamedRomajiCharacters = 0
    }

    private mutating func record(_ event: WKRInputEvent, _ result: TransitionResult) {
        var exactDeletedRomaji = result.deletedRomajiCharacters
        for action in result.actions {
            switch action {
            case let .romaji(value):
                streamedRomajiCharacters += value.count
            case let .backspace(count):
                let removed = exactDeletedRomaji > 0 ? exactDeletedRomaji : count
                streamedRomajiCharacters = max(0, streamedRomajiCharacters - removed)
                exactDeletedRomaji = 0
            case .unicode:
                streamedRomajiCharacters = 0
            }
        }

        switch event {
        case .boundary(.enter):
            streamedRomajiCharacters = 0
        case .boundary, .romanTransliteration, .backspace, .physical, .reset:
            break
        }
    }
}
