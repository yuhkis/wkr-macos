/// Decides whether a Control shortcut should complete WKR's pending kana before
/// Apple Japanese Input sees it.
///
/// Kana transliteration needs the implicit remainder (`r` -> `ra`) so Ctrl+J/K
/// can operate on a complete kana. Roman transliteration must keep the already
/// displayed `r` as-is; adding `a` changes what Ctrl+L/; is supposed to return.
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
        // These are the two shortcuts reported for the active key settings.
        // Do not union shortcuts from Apple's other presets: the same Control
        // key can mean a different operation under a different preset.
        case .l, .semicolon:
            return .transliterateRoman
        default:
            // Preserve the existing fail-closed behaviour for every shortcut
            // whose Apple Japanese Input meaning is unknown or keymap-dependent.
            return .completeKana
        }
    }
}
