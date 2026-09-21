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
    case romanTransliteration
    case backspace
    case reset(ResetReason)
}

public enum SyntheticAction: Equatable, Sendable {
    case romaji(String)
    case unicode(String)
    case backspace(count: Int)
}

public enum OriginalEventDisposition: Equatable, Sendable {
    case suppress
    case passThrough
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
    case prefixRollback
}

public struct TransitionResult: Equatable, Sendable {
    public let actions: [SyntheticAction]
    public let disposition: OriginalEventDisposition
    public let stateCode: TransitionStateCode
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

    public static let fullLayoutExperimental = WKRLayout.optimisticDeletionProfile
}

public enum OutputMode: Equatable, Sendable {
    case deferredRomaji
    case optimisticRomaji(OptimisticDeletionProfile)
    case prefixRomaji
}

public enum SyntheticEventTag {
    public static let value: Int64 = 0x574B_5250_304D_4143 // "WKRP0MAC"

    public static func matches(userData: Int64) -> Bool {
        userData == value
    }
}

private final class TrieNode {
    var children: [PhysicalKey: TrieNode] = [:]
    var output: NormalizedRule?
    var sharedRomajiPrefix: String?
    var provisionalRomaji: String?
    var provisionalDeletionUnits = 0
    var provisionalMayRollBack = false
}

public final class WKRTransducer {
    public static let fullRules: [NormalizedRule] = WKRLayout.rules
    public static let rulesWithoutSymbolLayer: [NormalizedRule] =
        WKRLayout.rulesWithoutSymbolLayer

    private let root = TrieNode()
    private let mode: OutputMode
    private var currentNode: TrieNode?
    private var optimisticProvisional: NormalizedRule?
    private var emittedRomaji = ""
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

        for (key, provisional) in symbolLayerProvisionalRomaji {
            guard let node = root.children[key], node.provisionalRomaji == nil else { continue }
            node.provisionalRomaji = provisional
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

    private func completePrefix(at node: TrieNode, actions: inout [SyntheticAction]) -> Bool {
        guard let output = node.output else {
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

    private func processRomanTransliteration() -> TransitionResult {
        guard let node = currentNode else {
            return TransitionResult(disposition: .passThrough, stateCode: .idle)
        }

        var actions: [SyntheticAction] = []
        switch mode {
        case .deferredRomaji:
            guard let provisional = node.provisionalRomaji else { break }
            actions.append(.romaji(provisional))
        case let .optimisticRomaji(profile):
            guard let provisional = node.provisionalRomaji else { break }
            guard let output = optimisticProvisional else {
                actions.append(.romaji(provisional))
                break
            }
            guard let count = profile.backspaceCount(for: output.id) else { break }
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
