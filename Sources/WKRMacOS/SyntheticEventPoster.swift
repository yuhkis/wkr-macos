import Carbon.HIToolbox
import CoreGraphics
import WKRCore

final class SyntheticEventPoster {
    private let source: CGEventSource

    init?() {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        self.source = source
    }

    @discardableResult
    func post(_ actions: [SyntheticAction], through proxy: CGEventTapProxy) -> Bool {
        guard let events = makeEvents(for: actions) else { return false }
        for event in events {
            event.tapPostEvent(proxy)
        }
        return true
    }

    /// Post without a tap proxy, for work that finishes on the main run loop
    /// rather than inside the callback. The English fallback runs here because
    /// it waits for a burst of `英数` presses to end, which is a timer rather
    /// than a keystroke. Our own tap sees these events too, and skips them by
    /// the same marker.
    @discardableResult
    func post(_ actions: [SyntheticAction]) -> Bool {
        guard let events = makeEvents(for: actions) else { return false }
        for event in events {
            event.post(tap: .cgSessionEventTap)
        }
        return true
    }

    /// Build the complete batch before posting any part of it. This prevents a
    /// malformed action from producing a partial synthetic sequence.
    private func makeEvents(for actions: [SyntheticAction]) -> [CGEvent]? {
        var events: [CGEvent] = []
        for action in actions {
            switch action {
            case let .romaji(value):
                for character in value {
                    guard let keyCode = Self.keyCodes[character],
                          let pair = makeKeyPair(keyCode)
                    else { return nil }
                    events.append(contentsOf: pair)
                }
            case let .unicode(value):
                guard let pair = makeUnicodePair(value) else { return nil }
                events.append(contentsOf: pair)
            case let .backspace(count):
                guard count >= 0 else { return nil }
                for _ in 0..<count {
                    guard let pair = makeKeyPair(CGKeyCode(kVK_Delete)) else { return nil }
                    events.append(contentsOf: pair)
                }
            }
        }
        return events
    }

    private func makeUnicodePair(_ value: String) -> [CGEvent]? {
        let utf16 = Array(value.utf16)
        guard !utf16.isEmpty,
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0,
                  keyDown: false
              )
        else {
            return nil
        }

        utf16.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        keyDown.flags = []
        keyUp.flags = []
        mark(keyDown)
        mark(keyUp)
        return [keyDown, keyUp]
    }

    private func makeKeyPair(_ keyCode: CGKeyCode) -> [CGEvent]? {
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        ) else {
            return nil
        }

        keyDown.flags = []
        keyUp.flags = []
        mark(keyDown)
        mark(keyUp)
        return [keyDown, keyUp]
    }

    private func mark(_ event: CGEvent) {
        event.setIntegerValueField(
            .eventSourceUserData,
            value: SyntheticEventTag.value
        )
    }

    private static let keyCodes: [Character: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A),
        "b": CGKeyCode(kVK_ANSI_B),
        "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D),
        "e": CGKeyCode(kVK_ANSI_E),
        "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G),
        "h": CGKeyCode(kVK_ANSI_H),
        "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J),
        "k": CGKeyCode(kVK_ANSI_K),
        "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M),
        "n": CGKeyCode(kVK_ANSI_N),
        "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P),
        "q": CGKeyCode(kVK_ANSI_Q),
        "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S),
        "t": CGKeyCode(kVK_ANSI_T),
        "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V),
        "w": CGKeyCode(kVK_ANSI_W),
        "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y),
        "z": CGKeyCode(kVK_ANSI_Z),
        "-": CGKeyCode(kVK_ANSI_Minus),
    ]
}
