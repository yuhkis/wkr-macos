public enum PhysicalKey: String, CaseIterable, Hashable, Sendable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case semicolon = ";"
    case comma = ","
    case period = "."
    case slash = "/"
    case colon = ":"
    case leftBracket = "["
    case rightBracket = "]"
    case leftBrace = "Shift+["
    case rightBrace = "Shift+]"
    case digit1 = "1"
    case digit2 = "2"
    case digit3 = "3"
    case digit4 = "4"
    case digit5 = "5"
    case digit6 = "6"
    case digit7 = "7"
    case digit8 = "8"
    case digit9 = "9"
    case digit0 = "0"
    case shiftedDigit1 = "Shift+1"
    case shiftedDigit2 = "Shift+2"
    case shiftedDigit3 = "Shift+3"
    case shiftedDigit4 = "Shift+4"
    case shiftedDigit5 = "Shift+5"
    case shiftedDigit6 = "Shift+6"
    case shiftedDigit7 = "Shift+7"
    case shiftedDigit8 = "Shift+8"
    case shiftedDigit9 = "Shift+9"
    case jisUnderscore = "JIS-_"
    case shiftedMinus = "Shift+-"
    case shiftedSemicolon = "Shift+;"
    case jisYen = "JIS-Yen"
    case shiftedJisYen = "Shift+JIS-Yen"
    case shiftedAt = "Shift+@"
    case shiftedCaret = "Shift+^"
    case shiftedComma = "Shift+,"
    case shiftedPeriod = "Shift+."
}

public enum BoundaryKey: Equatable, Sendable {
    case space
    case enter
    case tab
    case punctuation
    case other
}

public enum ResetReason: Equatable, Sendable {
    case escape
    case inputSourceChanged
    case applicationChanged
    case mouse
    case cursorMovement
    case modifiedKey
    case tapDisabled
    case secureInput
    case explicitStop
}

public enum WKRInputEvent: Equatable, Sendable {
    case physical(PhysicalKey)
    case boundary(BoundaryKey)
    /// Apple Japanese Input is about to transliterate the existing pre-edit to
    /// roman text. Drop WKR's pending continuation without completing the kana;
    /// in deferred mode, first expose only the same provisional romaji that
    /// prefix mode has already streamed.
    case romanTransliteration
    case backspace
    case reset(ResetReason)
}

public enum SyntheticAction: Equatable, Sendable {
    case romaji(String)
    /// Inject a literal Unicode string for symbols or kana that Apple Japanese
    /// Input cannot express reliably through a portable romaji sequence.
    case unicode(String)
    case backspace(count: Int)
}

public enum OriginalEventDisposition: Equatable, Sendable {
    /// Consume the original keyDown and its matching keyUp.
    case suppress
    /// Return the unmodified original event to the event stream.
    case passThrough
    /// Consume and repost the original after all synthetic actions.
    case repostAfterSynthetic
}

public enum TransitionStateCode: String, Equatable, Sendable {
    case idle
    case pendingPrefix
    case emittedTerminal
    case flushedBoundary
    case romanTransliteration
    case canceledPending
    case reset
    case passthrough
    case disabledBypass
    case optimisticReplacement
    case optimisticReplacementUnavailable
    /// A prefix-mode branch could not keep the already emitted romaji letters,
    /// so exactly those letters were deleted before the real output.
    case prefixRollback
}

public struct TransitionResult: Equatable, Sendable {
    public let actions: [SyntheticAction]
    public let disposition: OriginalEventDisposition
    public let stateCode: TransitionStateCode
    /// How many romaji characters this result's Backspaces take out of Apple
    /// Japanese Input's raw buffer.
    ///
    /// A `.backspace` count is in display units, and one unit is one raw letter
    /// in some branches and one composed kana in others, so the two numbers
    /// differ: taking back `や` is one Backspace but two characters. The
    /// English fallback needs the character figure, because that is what the
    /// `英数` connect-back puts on screen. `0` means the deletion cannot be
    /// expressed this way and callers must fail closed.
    public let deletedRomajiCharacters: Int

    public init(
        actions: [SyntheticAction] = [],
        disposition: OriginalEventDisposition,
        stateCode: TransitionStateCode,
        deletedRomajiCharacters: Int = 0
    ) {
        self.actions = actions
        self.disposition = disposition
        self.stateCode = stateCode
        self.deletedRomajiCharacters = deletedRomajiCharacters
    }
}

public struct NormalizedRule: Equatable, Sendable {
    public let id: String
    public let input: [PhysicalKey]
    public let kana: String
    public let action: SyntheticAction

    public init(id: String, input: [PhysicalKey], kana: String, romaji: String) {
        self.id = id
        self.input = input
        self.kana = kana
        self.action = .romaji(romaji)
    }

    public init(id: String, input: [PhysicalKey], text: String) {
        self.id = id
        self.input = input
        self.kana = text
        self.action = .unicode(text)
    }
}

public struct OptimisticDeletionProfile: Equatable, Sendable {
    private let backspacesByRuleID: [String: Int]

    public init(backspacesByRuleID: [String: Int]) {
        self.backspacesByRuleID = backspacesByRuleID
    }

    public func backspaceCount(for ruleID: String) -> Int? {
        backspacesByRuleID[ruleID]
    }

    /// Experimental until the complete layout has been exercised with physical
    /// keys in TextEdit, Notes, and Safari.
    public static let fullLayoutExperimental = WKRLayout.optimisticDeletionProfile
}

public enum OutputMode: Equatable, Sendable {
    case deferredRomaji
    case optimisticRomaji(OptimisticDeletionProfile)
    /// Stream the romaji letters that every reachable output of the current
    /// key sequence shares, exactly as plain romaji typing would show them, and
    /// append the remaining letters once the sequence is decided. Provisional
    /// kana are never displayed, so no kana has to be deleted and replaced.
    case prefixRomaji
}

/// Marker stored in `CGEventField.eventSourceUserData` by the macOS adapter.
/// Keeping the comparison in WKRCore makes re-entry behavior unit-testable
/// without importing Core Graphics.
public enum SyntheticEventTag {
    public static let value: Int64 = 0x574B_5250_304D_4143 // "WKRP0MAC"

    public static func matches(userData: Int64) -> Bool {
        userData == value
    }
}

private final class TrieNode {
    var children: [PhysicalKey: TrieNode] = [:]
    var output: NormalizedRule?
    /// Longest romaji prefix shared by every romaji output reachable from this
    /// node, including this node's own output. `nil` means the subtree has no
    /// romaji output at all, so prefix mode must not emit anything here.
    var sharedRomajiPrefix: String?
    /// The romaji prefix mode shows while this node is pending. `nil` means the
    /// node has no romaji to show at all, which applies to the `Y` symbol
    /// layer. See `computeSharedRomajiPrefix` for how much is streamed.
    var provisionalRomaji: String?
    /// How many Backspaces undo `provisionalRomaji`. A partial romaji prefix
    /// stays raw in the pre-edit buffer and costs one Backspace per letter,
    /// while a complete output has already composed into kana and costs one
    /// Backspace per kana.
    var provisionalDeletionUnits = 0
    /// True when some reachable output does not continue `provisionalRomaji`,
    /// so entering that branch has to delete the streamed letters first.
    var provisionalMayRollBack = false
}

public final class WKRTransducer {
    public static let fullRules: [NormalizedRule] = WKRLayout.rules
    /// `fullRules` without the `Y` symbol layer. `Y` then has no rule at all
    /// and passes through like any unassigned key, which is the interim
    /// behaviour until the key is given a new use.
    public static let rulesWithoutSymbolLayer: [NormalizedRule] =
        WKRLayout.rulesWithoutSymbolLayer

    private let root = TrieNode()
    private let mode: OutputMode
    private var currentNode: TrieNode?
    private var optimisticProvisional: NormalizedRule?
    /// Romaji letters already sent for the kana currently being typed.
    private var emittedRomaji = ""
    /// How many Backspaces undo `emittedRomaji` in the pre-edit buffer.
    private var emittedDeletionUnits = 0

    public init(
        mode: OutputMode = .deferredRomaji,
        rules: [NormalizedRule] = fullRules,
        symbolLayerProvisionalRomaji: [PhysicalKey: String] = WKRLayout.symbolLayerProvisionalRomaji
    ) {
        self.mode = mode
        for rule in rules {
            insert(rule)
        }
        Self.computeSharedRomajiPrefix(root)

        // Roots whose whole subtree is Unicode-only would show nothing while
        // pending. Give them an explicit letter so every key produces feedback.
        for (key, provisional) in symbolLayerProvisionalRomaji {
            guard let node = root.children[key], node.provisionalRomaji == nil else { continue }
            node.provisionalRomaji = provisional
            // A placeholder never composes, so each letter costs one Backspace.
            node.provisionalDeletionUnits = provisional.count
            node.provisionalMayRollBack = true
        }
    }

    public var hasPendingInput: Bool {
        currentNode != nil
    }

    @discardableResult
    public func reset() -> Bool {
        let hadPendingInput = hasPendingInput
        currentNode = nil
        optimisticProvisional = nil
        emittedRomaji = ""
        emittedDeletionUnits = 0
        return hadPendingInput
    }

    /// Romaji characters removed by the Backspaces of the result being built.
    /// Only `process` reads it, and only right after filling it in.
    private var deletedRomajiCharacters = 0

    public func process(_ event: WKRInputEvent, isEnabled: Bool = true) -> TransitionResult {
        deletedRomajiCharacters = 0
        let result = transition(event, isEnabled: isEnabled)
        guard deletedRomajiCharacters > 0 else { return result }
        return TransitionResult(
            actions: result.actions,
            disposition: result.disposition,
            stateCode: result.stateCode,
            deletedRomajiCharacters: deletedRomajiCharacters
        )
    }

    private func transition(_ event: WKRInputEvent, isEnabled: Bool) -> TransitionResult {
        guard isEnabled else {
            reset()
            return TransitionResult(disposition: .passThrough, stateCode: .disabledBypass)
        }

        switch event {
        case let .physical(key):
            if case .prefixRomaji = mode {
                return processPhysicalPrefix(key)
            }
            return processPhysical(key)
        case .boundary:
            if case .prefixRomaji = mode {
                return processBoundaryPrefix()
            }
            return processBoundary()
        case .romanTransliteration:
            return processRomanTransliteration()
        case .backspace:
            if case .prefixRomaji = mode {
                return processBackspacePrefix()
            }
            return processBackspace()
        case .reset:
            // Escape included: what is already in Apple Japanese Input's
            // pre-edit buffer belongs to the IME, so WKR only drops its own
            // state and lets the application see the unmodified key.
            reset()
            return TransitionResult(disposition: .passThrough, stateCode: .reset)
        }
    }

    private func insert(_ rule: NormalizedRule) {
        precondition(!rule.input.isEmpty, "A normalized WKR rule must contain at least one key")
        var node = root
        for key in rule.input {
            if node.children[key] == nil {
                node.children[key] = TrieNode()
            }
            node = node.children[key]!
        }
        precondition(node.output == nil, "Duplicate normalized WKR input: \(rule.input)")
        node.output = rule
    }

    private func processPhysical(_ key: PhysicalKey) -> TransitionResult {
        var actions: [SyntheticAction] = []

        while true {
            if let currentNode {
                if let child = currentNode.children[key] {
                    if let provisional = optimisticProvisional {
                        if child.output?.action == provisional.action {
                            optimisticProvisional = nil
                            enter(child, actions: &actions, emitOutput: false)
                            return TransitionResult(
                                actions: actions,
                                disposition: .suppress,
                                stateCode: .emittedTerminal
                            )
                        }
                        guard case let .optimisticRomaji(profile) = mode,
                              let count = profile.backspaceCount(for: provisional.id)
                        else {
                            reset()
                            return TransitionResult(
                                disposition: .suppress,
                                stateCode: .optimisticReplacementUnavailable
                            )
                        }
                        actions.append(.backspace(count: count))
                        optimisticProvisional = nil
                    }

                    enter(child, actions: &actions)
                    let state: TransitionStateCode
                    if actions.contains(where: { action in
                        if case .backspace = action { return true }
                        return false
                    }) {
                        state = .optimisticReplacement
                    } else if self.currentNode == nil {
                        state = .emittedTerminal
                    } else {
                        state = .pendingPrefix
                    }
                    return TransitionResult(actions: actions, disposition: .suppress, stateCode: state)
                }

                if case .deferredRomaji = mode, let output = currentNode.output {
                    actions.append(output.action)
                }
                self.currentNode = nil
                optimisticProvisional = nil
                continue // Reprocess the same physical key from the root.
            }

            guard let child = root.children[key] else {
                let disposition: OriginalEventDisposition = actions.isEmpty
                    ? .passThrough
                    : .repostAfterSynthetic
                return TransitionResult(
                    actions: actions,
                    disposition: disposition,
                    stateCode: .passthrough
                )
            }

            enter(child, actions: &actions)
            return TransitionResult(
                actions: actions,
                disposition: .suppress,
                stateCode: self.currentNode == nil ? .emittedTerminal : .pendingPrefix
            )
        }
    }

    private func enter(
        _ node: TrieNode,
        actions: inout [SyntheticAction],
        emitOutput: Bool = true
    ) {
        currentNode = node
        guard let output = node.output else { return }

        if node.children.isEmpty {
            if emitOutput {
                actions.append(output.action)
            }
            currentNode = nil
            optimisticProvisional = nil
            return
        }

        if case .optimisticRomaji = mode {
            if emitOutput {
                actions.append(output.action)
            }
            optimisticProvisional = output
        }
    }

    private func processBoundary() -> TransitionResult {
        guard let currentNode else {
            return TransitionResult(disposition: .passThrough, stateCode: .idle)
        }

        var actions: [SyntheticAction] = []
        if case .deferredRomaji = mode, let output = currentNode.output {
            actions.append(output.action)
        }
        reset()

        return TransitionResult(
            actions: actions,
            disposition: actions.isEmpty ? .passThrough : .repostAfterSynthetic,
            stateCode: actions.isEmpty ? .reset : .flushedBoundary
        )
    }

    // MARK: - prefix-romaji

    /// Post-order pass that stores, for every node, the romaji prefix shared by
    /// all romaji outputs in its subtree and the single letter prefix mode
    /// streams while the node is pending.
    @discardableResult
    private static func computeSharedRomajiPrefix(_ node: TrieNode) -> String? {
        var shared: String?
        if let output = node.output, case let .romaji(value) = output.action {
            shared = value
        }
        for child in node.children.values {
            guard let childPrefix = computeSharedRomajiPrefix(child) else { continue }
            shared = shared.map { commonPrefix($0, childPrefix) } ?? childPrefix
        }
        node.sharedRomajiPrefix = shared
        node.provisionalRomaji = provisionalRomaji(for: node, shared: shared)
        if let provisional = node.provisionalRomaji {
            node.provisionalDeletionUnits = deletionUnits(for: provisional, at: node)
            node.provisionalMayRollBack = !reachableOutputsAllStart(
                with: provisional,
                from: node
            )
        }
        return shared
    }

    /// How much of the eventual output is safe to show while the node is
    /// pending.
    ///
    /// - The shared prefix protects every branch, so one letter of it never has
    ///   to be taken back for a romaji branch.
    /// - Without a shared prefix, one letter still pays off when other branches
    ///   start with the same letter, as in the `X` row where `ふぁ` / `ふぃ` /
    ///   `ふゅ` / `ふぇ` / `ふぉ` all continue `f`.
    /// - When nothing else starts with that letter, the letter alone would show
    ///   no kana and protect nothing, so the whole output is streamed instead.
    ///   That is what makes `U` show `や` immediately the way `H` shows `あ`,
    ///   while its only branch `UT → ゃ` still costs one Backspace.
    private static func provisionalRomaji(for node: TrieNode, shared: String?) -> String? {
        if let first = shared?.first {
            return String(first)
        }
        guard let output = node.output,
              case let .romaji(own) = output.action,
              let first = own.first
        else {
            return nil
        }
        let sameFirstLetter = subtreeRomajiOutputs(node).filter { $0.hasPrefix(String(first)) }
        return sameFirstLetter.count > 1 ? String(first) : own
    }

    private static func deletionUnits(for provisional: String, at node: TrieNode) -> Int {
        if let output = node.output,
           case let .romaji(own) = output.action,
           own == provisional {
            // Apple Japanese Input has composed the complete output already,
            // so the pre-edit buffer holds kana, not romaji letters.
            return output.kana.count
        }
        return provisional.count
    }

    private static func subtreeRomajiOutputs(_ node: TrieNode) -> [String] {
        var outputs: [String] = []
        if let output = node.output, case let .romaji(value) = output.action {
            outputs.append(value)
        }
        for child in node.children.values {
            outputs.append(contentsOf: subtreeRomajiOutputs(child))
        }
        return outputs
    }

    private static func reachableOutputsAllStart(
        with provisional: String,
        from node: TrieNode
    ) -> Bool {
        guard let output = node.output else {
            // Leaving such a node with an undefined key also has to delete the
            // streamed letter, because there is no output to complete.
            return false
        }
        switch output.action {
        case let .romaji(value):
            if !value.hasPrefix(provisional) { return false }
        case .unicode, .backspace:
            return false
        }
        return node.children.values.allSatisfy {
            reachableOutputsAllStart(with: provisional, from: $0)
        }
    }

    private static func commonPrefix(_ lhs: String, _ rhs: String) -> String {
        String(zip(lhs, rhs).prefix { $0 == $1 }.map(\.0))
    }

    private func processPhysicalPrefix(_ key: PhysicalKey) -> TransitionResult {
        var actions: [SyntheticAction] = []
        var rolledBack = false

        while true {
            if let node = currentNode {
                if let child = node.children[key] {
                    let entered = enterPrefix(child, actions: &actions)
                    return TransitionResult(
                        actions: actions,
                        disposition: .suppress,
                        stateCode: prefixStateCode(
                            rolledBack: rolledBack || entered,
                            isPending: currentNode != nil
                        )
                    )
                }

                rolledBack = completePrefix(at: node, actions: &actions) || rolledBack
                currentNode = nil
                clearEmittedRomaji()
                continue // Reprocess the same physical key from the root.
            }

            guard let child = root.children[key] else {
                return TransitionResult(
                    actions: actions,
                    disposition: actions.isEmpty ? .passThrough : .repostAfterSynthetic,
                    stateCode: actions.isEmpty ? .passthrough
                        : (rolledBack ? .prefixRollback : .passthrough)
                )
            }

            let entered = enterPrefix(child, actions: &actions)
            return TransitionResult(
                actions: actions,
                disposition: .suppress,
                stateCode: prefixStateCode(
                    rolledBack: rolledBack || entered,
                    isPending: currentNode != nil
                )
            )
        }
    }

    private func prefixStateCode(rolledBack: Bool, isPending: Bool) -> TransitionStateCode {
        if rolledBack { return .prefixRollback }
        return isPending ? .pendingPrefix : .emittedTerminal
    }

    /// Move into `node`. Terminal nodes complete the kana immediately; other
    /// nodes extend the streamed prefix. Returns `true` when already emitted
    /// letters had to be deleted.
    @discardableResult
    private func enterPrefix(_ node: TrieNode, actions: inout [SyntheticAction]) -> Bool {
        if node.children.isEmpty {
            let rolledBack = completePrefix(at: node, actions: &actions)
            currentNode = nil
            clearEmittedRomaji()
            return rolledBack
        }

        currentNode = node

        guard let provisional = node.provisionalRomaji else {
            // The node has no romaji to show, so nothing may stay in the
            // pre-edit buffer either.
            return deleteEmittedRomaji(&actions)
        }

        var rolledBack = false
        if !provisional.hasPrefix(emittedRomaji) {
            rolledBack = deleteEmittedRomaji(&actions)
        }
        if provisional.count > emittedRomaji.count {
            actions.append(.romaji(String(provisional.dropFirst(emittedRomaji.count))))
            emittedRomaji = provisional
            emittedDeletionUnits = node.provisionalDeletionUnits
        }
        return rolledBack
    }

    /// Finish the kana pending at `node`. Returns `true` when already emitted
    /// letters had to be deleted.
    private func completePrefix(at node: TrieNode, actions: inout [SyntheticAction]) -> Bool {
        guard let output = node.output else {
            // There is no kana to complete, as after `T` or `Y` alone. What is
            // already on screen stays: Apple Japanese Input owns it, and making
            // a character disappear on its own is exactly what WKR avoids
            // everywhere else, Escape included.
            return false
        }

        switch output.action {
        case let .romaji(value):
            guard value.hasPrefix(emittedRomaji) else {
                let rolledBack = deleteEmittedRomaji(&actions)
                actions.append(output.action)
                return rolledBack
            }
            let remainder = String(value.dropFirst(emittedRomaji.count))
            if !remainder.isEmpty {
                actions.append(.romaji(remainder))
            }
            return false
        case .unicode:
            let rolledBack = deleteEmittedRomaji(&actions)
            actions.append(output.action)
            return rolledBack
        case .backspace:
            return deleteEmittedRomaji(&actions)
        }
    }

    private func deleteEmittedRomaji(_ actions: inout [SyntheticAction]) -> Bool {
        guard !emittedRomaji.isEmpty else { return false }
        actions.append(.backspace(count: emittedDeletionUnits))
        // The Backspaces are counted in display units, but what leaves Apple
        // Japanese Input's raw buffer is every character streamed for them.
        deletedRomajiCharacters += emittedRomaji.count
        clearEmittedRomaji()
        return true
    }

    private func clearEmittedRomaji() {
        emittedRomaji = ""
        emittedDeletionUnits = 0
    }

    private func processBoundaryPrefix() -> TransitionResult {
        guard let node = currentNode else {
            return TransitionResult(disposition: .passThrough, stateCode: .idle)
        }

        var actions: [SyntheticAction] = []
        let rolledBack = completePrefix(at: node, actions: &actions)
        reset()

        if actions.isEmpty {
            return TransitionResult(disposition: .passThrough, stateCode: .reset)
        }
        return TransitionResult(
            actions: actions,
            disposition: .repostAfterSynthetic,
            stateCode: rolledBack ? .prefixRollback : .flushedBoundary
        )
    }

    /// Leave the IME's already visible romaji unfinished so its roman
    /// transliteration shortcut sees exactly what was typed so far. Completing
    /// the node here would append the implicit vowel (`r` -> `ra`) and make
    /// Ctrl+L produce full-width `ra` instead of the displayed `r`.
    private func processRomanTransliteration() -> TransitionResult {
        guard let node = currentNode else {
            return TransitionResult(disposition: .passThrough, stateCode: .idle)
        }

        var actions: [SyntheticAction] = []
        switch mode {
        case .deferredRomaji:
            guard let provisional = node.provisionalRomaji else { break }
            // Deferred mode has not shown the pending key yet. Stream only the
            // provisional that prefix mode would already have displayed; never
            // append the remainder that completes the kana.
            actions.append(.romaji(provisional))
        case let .optimisticRomaji(profile):
            guard let provisional = node.provisionalRomaji else { break }
            guard let output = optimisticProvisional else {
                // Prefix-only nodes such as `T` and `Y` have not emitted a
                // kana yet, so there is nothing to take back. Expose the same
                // provisional romaji that prefix/deferred modes use.
                actions.append(.romaji(provisional))
                break
            }
            guard let count = profile.backspaceCount(for: output.id) else { break }
            // Optimistic mode has already composed the complete kana. Put it
            // back into the same raw provisional state prefix mode exposes so
            // roman transliteration does not inherit the implicit vowel.
            actions.append(.backspace(count: count))
            if case let .romaji(value) = output.action {
                deletedRomajiCharacters += value.count
            }
            actions.append(.romaji(provisional))
        case .prefixRomaji:
            break
        }
        reset()

        return TransitionResult(
            actions: actions,
            disposition: actions.isEmpty ? .passThrough : .repostAfterSynthetic,
            stateCode: .romanTransliteration
        )
    }

    /// Backspace removes exactly the romaji letters this process streamed for
    /// the unfinished kana, so existing text is never touched.
    private func processBackspacePrefix() -> TransitionResult {
        guard currentNode != nil else {
            return TransitionResult(disposition: .passThrough, stateCode: .idle)
        }

        var actions: [SyntheticAction] = []
        _ = deleteEmittedRomaji(&actions)
        reset()
        return TransitionResult(
            actions: actions,
            disposition: .suppress,
            stateCode: .canceledPending
        )
    }

    private func processBackspace() -> TransitionResult {
        guard currentNode != nil else {
            return TransitionResult(disposition: .passThrough, stateCode: .idle)
        }

        switch mode {
        case .deferredRomaji, .prefixRomaji:
            reset()
            return TransitionResult(disposition: .suppress, stateCode: .canceledPending)
        case let .optimisticRomaji(profile):
            guard let provisional = optimisticProvisional,
                  let count = profile.backspaceCount(for: provisional.id)
            else {
                reset()
                return TransitionResult(
                    disposition: .suppress,
                    stateCode: .optimisticReplacementUnavailable
                )
            }
            reset()
            return TransitionResult(
                actions: [.backspace(count: count)],
                disposition: .suppress,
                stateCode: .canceledPending
            )
        }
    }
}
