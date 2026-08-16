/// Keeps a Unicode injection from being sent when it cannot arrive.
///
/// `CGEvent.keyboardSetUnicodeString` events reach the application only while
/// Apple Japanese Input has no pre-edit. With one open the event is discarded
/// and **nothing observable happens**: the keystroke is simply lost, and the
/// user has no way to tell why. Measured 2026-08-16 across all 67 Unicode
/// rules; the rationale and the alternatives that were rejected are in
/// `docs/design.md` section 5.4.
///
/// The gate answers one question — is the pre-edit empty right now — by
/// counting the romaji WKR itself streamed. A provisional letter such as the
/// `y` of the `Y` layer does not count against the injection, because the same
/// batch deletes it before injecting.
///
/// It holds a character count and nothing else. No keys, no text.
public struct UnicodeInjectionGate: Equatable, Sendable {
    public struct Decision: Equatable, Sendable {
        /// What to post. Identical to the input unless an injection was
        /// removed.
        public let result: TransitionResult
        /// True when a Unicode injection was removed because a pre-edit was
        /// open. The caller logs it: silently doing nothing is the failure this
        /// gate exists to make visible.
        public let droppedUnicode: Bool
    }

    private var streamedRomajiCharacters = 0

    public init() {}

    /// Whether the pre-edit is known to be empty, so an injection would arrive.
    public var preEditIsEmpty: Bool {
        streamedRomajiCharacters == 0
    }

    public mutating func decide(
        _ event: WKRInputEvent,
        _ result: TransitionResult
    ) -> Decision {
        // Backspaces in this batch remove what WKR streamed for the sequence
        // being completed, so they are gone before the injection is posted.
        let removedHere = result.actions.reduce(0) { partial, action in
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

    /// Drop the count. Every reset reason ends the pre-edit or means WKR has
    /// lost track of it, and both call for starting over.
    public mutating func clear() {
        streamedRomajiCharacters = 0
    }

    private mutating func record(_ event: WKRInputEvent, _ result: TransitionResult) {
        for action in result.actions {
            switch action {
            case let .romaji(value):
                streamedRomajiCharacters += value.count
            case let .backspace(count):
                streamedRomajiCharacters = max(0, streamedRomajiCharacters - count)
            case .unicode:
                // It arrived, which means the pre-edit was empty, and it
                // commits on the spot without opening a new one.
                streamedRomajiCharacters = 0
            }
        }

        switch event {
        case .boundary(.enter):
            // Return commits the pre-edit. Space converts without committing,
            // and whether punctuation, Tab or a Shift+letter mode switch
            // commits is unmeasured, so those keep the count. Believing the
            // pre-edit is gone when it is not costs a lost keystroke; keeping
            // the count costs a symbol the user can retype after committing.
            streamedRomajiCharacters = 0
        case .boundary, .backspace, .physical, .reset:
            break
        }
    }
}
