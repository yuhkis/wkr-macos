import Carbon.HIToolbox
import CoreFoundation
import CoreGraphics
import WKRCore

final class EventTapController {
    typealias ContextRefreshHandler = () -> Void
    typealias FatalErrorHandler = (String) -> Void

    private let transducer: WKRTransducer
    private let poster: SyntheticEventPoster
    private let counters: EventCounters
    private let requestContextRefresh: ContextRefreshHandler
    private let fatalErrorHandler: FatalErrorHandler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var inputSourceMatches = false
    private var applicationAllowed = false
    private var secureInputEnabled = true
    private var permissionsGranted = false
    private var contextIsCurrent = false
    private var tapOperational = false
    private var suppressedKeyUps: Set<CGKeyCode> = []
    private let englishFallbackTrigger: EnglishFallbackTrigger
    /// Physical keys and streamed romaji length for the current pre-edit, so
    /// the `英数` connect-back can be replaced with what the user pressed.
    private var englishFallbackJournal = EnglishFallbackJournal()
    /// `英数` is an ordinary key rather than a modifier, so the chord is read
    /// from its own key state.
    private var eisuIsHeld = false

    init?(
        mode: OutputMode,
        counters: EventCounters,
        englishFallbackTrigger: EnglishFallbackTrigger = .default,
        requestContextRefresh: @escaping ContextRefreshHandler,
        fatalErrorHandler: @escaping FatalErrorHandler
    ) {
        guard let poster = SyntheticEventPoster() else { return nil }
        self.transducer = WKRTransducer(mode: mode)
        self.poster = poster
        self.counters = counters
        self.englishFallbackTrigger = englishFallbackTrigger
        self.requestContextRefresh = requestContextRefresh
        self.fatalErrorHandler = fatalErrorHandler
    }

    /// Coarse clock for the journal's lifetime. A wall-clock jump can only
    /// expire the journal early, which fails closed, and reading it is cheap
    /// enough for the event tap callback.
    private static func now() -> Double {
        CFAbsoluteTimeGetCurrent()
    }

    private var englishFallbackChordKey: CGKeyCode? {
        switch englishFallbackTrigger {
        case .disabled: return nil
        case .eisuReturn: return CGKeyCode(kVK_Return)
        case .eisuTab: return CGKeyCode(kVK_Tab)
        }
    }

    var isConverting: Bool {
        permissionsGranted
            && contextIsCurrent
            && inputSourceMatches
            && applicationAllowed
            && !secureInputEnabled
            && tapOperational
            && eventTap != nil
    }

    func start(permissionsGranted: Bool) -> Bool {
        guard permissionsGranted else { return false }
        self.permissionsGranted = true

        let types: [CGEventType] = [
            .keyDown, .keyUp,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return controller.handle(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapOperational = true
        return true
    }

    func stop() {
        transducer.reset()
        englishFallbackJournal.clear()
        eisuIsHeld = false
        tapOperational = false
        contextIsCurrent = false
        permissionsGranted = false
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        suppressedKeyUps.removeAll()
    }

    func applyContext(
        inputSourceMatches: Bool,
        applicationAllowed: Bool,
        secureInputEnabled: Bool
    ) {
        let contextChanged = !contextIsCurrent
            || self.inputSourceMatches != inputSourceMatches
            || self.applicationAllowed != applicationAllowed
            || self.secureInputEnabled != secureInputEnabled

        self.inputSourceMatches = inputSourceMatches
        self.applicationAllowed = applicationAllowed
        self.secureInputEnabled = secureInputEnabled
        contextIsCurrent = true

        if contextChanged, !applicationAllowed {
            reset(.applicationChanged)
            suppressedKeyUps.removeAll()
        } else if contextChanged, !inputSourceMatches {
            reset(.inputSourceChanged)
            suppressedKeyUps.removeAll()
        } else if contextChanged, secureInputEnabled {
            reset(.secureInput)
            suppressedKeyUps.removeAll()
        }
    }

    func invalidateContext(_ reason: ResetReason) {
        contextIsCurrent = false
        inputSourceMatches = false
        applicationAllowed = false
        reset(reason)
        suppressedKeyUps.removeAll()
    }

    func setPermissionsGranted(_ granted: Bool) {
        if permissionsGranted, !granted {
            invalidateContext(.tapDisabled)
        }
        permissionsGranted = granted
    }

    func reset(_ reason: ResetReason) {
        if reason != .inputSourceChanged {
            // `英数` arrives as an input source change and is the key the chord
            // is built on, so only that reason leaves the journal in place.
            englishFallbackJournal.clear()
            eisuIsHeld = false
        }
        if transducer.reset() {
            counters.reset()
            // Logged at notice level because a discarded pending kana is the
            // only way streamed romaji can be left behind in the pre-edit
            // buffer, and the reason is what identifies the cause.
            AppLog.logger.notice("state=reset reason=\(String(describing: reason), privacy: .public)")
        }
    }

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if SyntheticEventTag.matches(
            userData: event.getIntegerValueField(.eventSourceUserData)
        ) {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let reason = type == .tapDisabledByUserInput ? "user-input" : "timeout"
            failClosed(reason: "event-tap-disabled-\(reason)")
            AppLog.logger.error("event-tap-disabled type=\(type.rawValue, privacy: .public) action=terminate")
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            reset(.mouse)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            return handleKeyUp(event: event, keyCode: keyCode)
        }
        return handleKeyDown(proxy: proxy, event: event, keyCode: keyCode)
    }

    private func handleKeyUp(event: CGEvent, keyCode: CGKeyCode) -> Unmanaged<CGEvent>? {
        if keyCode == CGKeyCode(kVK_JIS_Eisu) {
            eisuIsHeld = false
        }
        if suppressedKeyUps.remove(keyCode) != nil {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(
        proxy: CGEventTapProxy,
        event: CGEvent,
        keyCode: CGKeyCode
    ) -> Unmanaged<CGEvent>? {
        if keyCode == CGKeyCode(kVK_JIS_Kana) || keyCode == CGKeyCode(kVK_JIS_Eisu) {
            if keyCode == CGKeyCode(kVK_JIS_Eisu) {
                eisuIsHeld = true
            } else {
                // `かな` starts a new pre-edit, so nothing from before it can
                // still be on screen to replace.
                englishFallbackJournal.clear()
            }
            invalidateContext(.inputSourceChanged)
            counters.bypassed()
            DispatchQueue.main.async { [weak self] in
                self?.requestContextRefresh()
            }
            return Unmanaged.passUnretained(event)
        }

        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Modifiers are checked here so that Command+Return and Shift+Return
        // keep reaching the application even while `英数` happens to be down.
        let hasOtherModifiers = !event.flags.intersection(Self.disallowedModifierFlags).isEmpty
            || event.flags.contains(.maskShift)
        if eisuIsHeld, !hasOtherModifiers, let chordKey = englishFallbackChordKey,
           keyCode == chordKey {
            // Consume the key whether or not the replacement runs. Held under
            // `英数` this is never an ordinary Return, and letting it through
            // would send the message in a chat client.
            let actionCount = isAutorepeat ? 0 : performEnglishFallback(through: proxy)
            counters.transformed(actions: actionCount)
            suppressedKeyUps.insert(keyCode)
            return nil
        }

        if isAutorepeat {
            if suppressedKeyUps.contains(keyCode) {
                return nil
            }
            reset(.modifiedKey)
            counters.bypassed()
            return Unmanaged.passUnretained(event)
        }

        guard isConverting else {
            transducer.reset()
            counters.bypassed()
            return Unmanaged.passUnretained(event)
        }

        // Escape is checked before the modifier filter so that its reset is
        // always attributed to Escape itself. Apple Japanese Input decides what
        // happens to the pre-edit buffer; WKR only drops its own state.
        if keyCode == CGKeyCode(kVK_Escape) {
            reset(.escape)
            counters.bypassed()
            return Unmanaged.passUnretained(event)
        }

        if !event.flags.intersection(Self.disallowedModifierFlags).isEmpty {
            reset(.modifiedKey)
            counters.bypassed()
            return Unmanaged.passUnretained(event)
        }

        if Self.cursorKeyCodes.contains(keyCode) {
            reset(.cursorMovement)
            counters.bypassed()
            return Unmanaged.passUnretained(event)
        }

        let inputEvent: WKRInputEvent
        let isShifted = event.flags.contains(.maskShift)
        if keyCode == CGKeyCode(kVK_Delete) {
            inputEvent = .backspace
        } else if let key = Self.physicalKey(for: keyCode, shifted: isShifted) {
            inputEvent = .physical(key)
        } else if keyCode == CGKeyCode(kVK_Return) || keyCode == CGKeyCode(kVK_ANSI_KeypadEnter) {
            // Shift+Return is a line break in many apps, so it has to flush the
            // pending kana exactly like a plain Return before passing through.
            inputEvent = .boundary(.enter)
        } else if isShifted, Self.punctuationKeyCodes.contains(keyCode) {
            // Shifted punctuation such as `？` on Shift+/ ends a word just like
            // `、` and `。`, so it flushes the pending kana instead of dropping
            // it as an unsupported Shift combination.
            inputEvent = .boundary(.punctuation)
        } else if isShifted {
            // Shift+letter switches Apple Japanese Input to the alphabet mode,
            // so it ends the current kana. Flushing keeps `G Shift+O` as
            // `はO`; discarding the pending state left the streamed `h` behind
            // and produced `hO`.
            inputEvent = .boundary(.other)
        } else if keyCode == CGKeyCode(kVK_Space) {
            inputEvent = .boundary(.space)
        } else if keyCode == CGKeyCode(kVK_Tab) {
            inputEvent = .boundary(.tab)
        } else if Self.punctuationKeyCodes.contains(keyCode) {
            inputEvent = .boundary(.punctuation)
        } else {
            inputEvent = .boundary(.other)
        }

        let result = transducer.process(inputEvent)
        englishFallbackJournal.record(inputEvent, result: result, at: Self.now())

        AppLog.logger.debug("state=\(result.stateCode.rawValue, privacy: .public)")
        return apply(result, through: proxy, to: event, keyCode: keyCode)
    }

    private func apply(
        _ result: TransitionResult,
        through proxy: CGEventTapProxy,
        to original: CGEvent,
        keyCode: CGKeyCode
    ) -> Unmanaged<CGEvent>? {
        guard poster.post(result.actions, through: proxy) else {
            AppLog.logger.error("synthetic-post-failed kind=event-creation action=terminate")
            counters.bypassed()
            failClosed(reason: "synthetic-event-creation")
            return Unmanaged.passUnretained(original)
        }

        switch result.disposition {
        case .passThrough:
            counters.bypassed()
            return Unmanaged.passUnretained(original)
        case .suppress:
            suppressedKeyUps.insert(keyCode)
            counters.transformed(actions: result.actions.count)
            return nil
        case .repostAfterSynthetic:
            // Events inserted with CGEventTapPostEvent enter before the event
            // returned by this callback, so the unmodified boundary/undefined
            // key can pass directly and its original keyUp remains paired.
            counters.transformed(actions: result.actions.count)
            return Unmanaged.passUnretained(original)
        }
    }

    /// Replace the romaji Apple Japanese Input connected back with the letters
    /// the user actually pressed. Returns how many synthetic actions were sent.
    ///
    /// The user decides when to run this: they press `英数` until the alphabet
    /// is on screen, and only then complete the chord. WKR never guesses how
    /// many presses that took. What it does know is the text now on screen,
    /// because it streamed exactly those romaji characters itself.
    private func performEnglishFallback(through proxy: CGEventTapProxy) -> Int {
        guard permissionsGranted, tapOperational, applicationAllowed, !secureInputEnabled else {
            englishFallbackJournal.clear()
            AppLog.logger.notice("english-fallback state=blocked")
            return 0
        }
        guard let snapshot = englishFallbackJournal.snapshot(at: Self.now()) else {
            AppLog.logger.notice("english-fallback state=unavailable")
            return 0
        }

        let actions: [SyntheticAction] = [
            .backspace(count: snapshot.romajiCharacterCount),
            .unicode(String(snapshot.keys.map(\.jisCharacter))),
        ]
        // Whatever happens next, this pre-edit has been consumed.
        englishFallbackJournal.clear()

        guard poster.post(actions, through: proxy) else {
            AppLog.logger.error("synthetic-post-failed kind=english-fallback action=terminate")
            failClosed(reason: "english-fallback-post")
            return 0
        }
        AppLog.logger.notice(
            "english-fallback state=replaced keys=\(snapshot.keys.count, privacy: .public)"
        )
        return actions.count
    }

    private func failClosed(reason: String) {
        tapOperational = false
        permissionsGranted = false
        contextIsCurrent = false
        inputSourceMatches = false
        transducer.reset()
        englishFallbackJournal.clear()
        eisuIsHeld = false
        suppressedKeyUps.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.fatalErrorHandler(reason)
        }
    }

    private static let disallowedModifierFlags: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskAlphaShift,
        .maskSecondaryFn,
    ]

    private static let cursorKeyCodes: Set<CGKeyCode> = [
        CGKeyCode(kVK_LeftArrow), CGKeyCode(kVK_RightArrow),
        CGKeyCode(kVK_UpArrow), CGKeyCode(kVK_DownArrow),
        CGKeyCode(kVK_Home), CGKeyCode(kVK_End),
        CGKeyCode(kVK_PageUp), CGKeyCode(kVK_PageDown),
        CGKeyCode(kVK_ForwardDelete),
    ]

    private static let punctuationKeyCodes: Set<CGKeyCode> = [
        CGKeyCode(kVK_ANSI_Comma), CGKeyCode(kVK_ANSI_Period),
        CGKeyCode(kVK_ANSI_Slash), CGKeyCode(kVK_ANSI_Quote),
        CGKeyCode(kVK_ANSI_LeftBracket), CGKeyCode(kVK_ANSI_RightBracket),
        CGKeyCode(kVK_ANSI_Backslash), CGKeyCode(kVK_ANSI_Grave),
        CGKeyCode(kVK_ANSI_Minus), CGKeyCode(kVK_ANSI_Equal),
        CGKeyCode(kVK_JIS_Yen), CGKeyCode(kVK_JIS_Underscore),
    ]

    private static func physicalKey(
        for keyCode: CGKeyCode,
        shifted: Bool
    ) -> PhysicalKey? {
        if shifted {
            return shiftedPhysicalKeys[keyCode]
        }
        return unshiftedPhysicalKeys[keyCode]
    }

    private static let unshiftedPhysicalKeys: [CGKeyCode: PhysicalKey] = [
        CGKeyCode(kVK_ANSI_A): .a,
        CGKeyCode(kVK_ANSI_B): .b,
        CGKeyCode(kVK_ANSI_C): .c,
        CGKeyCode(kVK_ANSI_D): .d,
        CGKeyCode(kVK_ANSI_E): .e,
        CGKeyCode(kVK_ANSI_F): .f,
        CGKeyCode(kVK_ANSI_G): .g,
        CGKeyCode(kVK_ANSI_H): .h,
        CGKeyCode(kVK_ANSI_I): .i,
        CGKeyCode(kVK_ANSI_J): .j,
        CGKeyCode(kVK_ANSI_K): .k,
        CGKeyCode(kVK_ANSI_L): .l,
        CGKeyCode(kVK_ANSI_M): .m,
        CGKeyCode(kVK_ANSI_N): .n,
        CGKeyCode(kVK_ANSI_O): .o,
        CGKeyCode(kVK_ANSI_P): .p,
        CGKeyCode(kVK_ANSI_Q): .q,
        CGKeyCode(kVK_ANSI_R): .r,
        CGKeyCode(kVK_ANSI_S): .s,
        CGKeyCode(kVK_ANSI_T): .t,
        CGKeyCode(kVK_ANSI_U): .u,
        CGKeyCode(kVK_ANSI_V): .v,
        CGKeyCode(kVK_ANSI_W): .w,
        CGKeyCode(kVK_ANSI_X): .x,
        CGKeyCode(kVK_ANSI_Y): .y,
        CGKeyCode(kVK_ANSI_Z): .z,
        CGKeyCode(kVK_ANSI_Semicolon): .semicolon,
        CGKeyCode(kVK_ANSI_Comma): .comma,
        CGKeyCode(kVK_ANSI_Period): .period,
        CGKeyCode(kVK_ANSI_Slash): .slash,
        // On a JIS keyboard these ANSI-position constants correspond to
        // the printed :, [, and ] keys respectively.
        CGKeyCode(kVK_ANSI_Quote): .colon,
        CGKeyCode(kVK_ANSI_RightBracket): .leftBracket,
        CGKeyCode(kVK_ANSI_Backslash): .rightBracket,
        CGKeyCode(kVK_ANSI_1): .digit1,
        CGKeyCode(kVK_ANSI_2): .digit2,
        CGKeyCode(kVK_ANSI_3): .digit3,
        CGKeyCode(kVK_ANSI_4): .digit4,
        CGKeyCode(kVK_ANSI_5): .digit5,
        CGKeyCode(kVK_ANSI_6): .digit6,
        CGKeyCode(kVK_ANSI_7): .digit7,
        CGKeyCode(kVK_ANSI_8): .digit8,
        CGKeyCode(kVK_ANSI_9): .digit9,
        CGKeyCode(kVK_ANSI_0): .digit0,
        CGKeyCode(kVK_JIS_Yen): .jisYen,
    ]

    private static let shiftedPhysicalKeys: [CGKeyCode: PhysicalKey] = [
        CGKeyCode(kVK_ANSI_1): .shiftedDigit1,
        CGKeyCode(kVK_ANSI_2): .shiftedDigit2,
        CGKeyCode(kVK_ANSI_3): .shiftedDigit3,
        CGKeyCode(kVK_ANSI_4): .shiftedDigit4,
        CGKeyCode(kVK_ANSI_5): .shiftedDigit5,
        CGKeyCode(kVK_ANSI_6): .shiftedDigit6,
        CGKeyCode(kVK_ANSI_7): .shiftedDigit7,
        CGKeyCode(kVK_ANSI_8): .shiftedDigit8,
        CGKeyCode(kVK_ANSI_9): .shiftedDigit9,
        CGKeyCode(kVK_JIS_Underscore): .jisUnderscore,
        CGKeyCode(kVK_ANSI_Minus): .shiftedMinus,
        CGKeyCode(kVK_ANSI_Semicolon): .shiftedSemicolon,
        CGKeyCode(kVK_JIS_Yen): .shiftedJisYen,
        // JIS @/` and ^/~ positions.
        CGKeyCode(kVK_ANSI_LeftBracket): .shiftedAt,
        CGKeyCode(kVK_ANSI_Equal): .shiftedCaret,
        CGKeyCode(kVK_ANSI_Comma): .shiftedComma,
        CGKeyCode(kVK_ANSI_Period): .shiftedPeriod,
        CGKeyCode(kVK_ANSI_RightBracket): .leftBrace,
        CGKeyCode(kVK_ANSI_Backslash): .rightBrace,
    ]
}
