public enum ControlShortcutPendingAction: Equatable, Sendable {
    case completeKana
    case transliterateRoman
}

public enum ControlShortcutPolicy {
    public static func pendingAction(
        for key: PhysicalKey?,
        isShifted: Bool = false
    ) -> ControlShortcutPendingAction {
        guard !isShifted else { return .completeKana }

        switch key {
        case .l, .semicolon:
            return .transliterateRoman
        default:
            return .completeKana
        }
    }
}
