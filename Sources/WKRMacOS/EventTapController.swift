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
    /// Per-key press counts, or `nil` when frequency logging is off. When it is
    /// off nothing here changes at all: the event mask, the callback path and
    /// the work done per keystroke stay exactly what they were before the
    /// feature existed.
    private let frequencyRecorder: KeyFrequencyRecorder?
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
    /// Stops a Unicode injection that a pre-edit would swallow. The English
    /// fallback does not go through this: its own Backspace removes the whole
    /// pre-edit first, which is why that injection arrives.
    private var unicodeInjectionGate = UnicodeInjectionGate()
    /// `英数` is an ordinary key rather than a modifier, so the chord is read
    /// from its own key state.
    private var eisuIsHeld = false
    /// Presses in the current `英数` burst. The connect-back needs a different
    /// number of them per application, so the fallback waits for the burst to
    /// end instead of counting to a fixed total.
    private var eisuBurstPresses = 0
    private var eisuBurstSettle: DispatchWorkItem?

    init?(
        mode: OutputMode,
        counters: EventCounters,
        englishFallbackTrigger: EnglishFallbackTrigger = .default,
        symbolLayerEnabled: Bool = true,
        frequencyRecorder: KeyFrequencyRecorder? = nil,
        requestContextRefresh: @escaping ContextRefreshHandler,
        fatalErrorHandler: @escaping FatalErrorHandler
    ) {
        guard let poster = SyntheticEventPoster() else { return nil }
        self.transducer = WKRTransducer(
            mode: mode,
            rules: symbolLayerEnabled
                ? WKRTransducer.fullRules
                : WKRTransducer.rulesWithoutSymbolLayer
        )
        self.poster = poster
        self.counters = counters
        self.frequencyRecorder = frequencyRecorder
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
        case .disabled, .eisuBurst: return nil
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

    /// `isConverting` without the input source test.
    ///
    /// `かな` and `英数` are the two keys that change the input source, so one
    /// of them is always pressed while the source does not yet match. Gating
    /// their count on the source would make `かな` structurally uncountable and
    /// leave a hole in the picture at the one key this layout leans on hardest.
    /// Widening the gate for exactly these two is safe because a mode switch
    /// carries nothing about what was typed: every other safety condition, and
    /// in particular Secure Event Input, still has to hold.
    private var isRecordingSafe: Bool {
        permissionsGranted
            && contextIsCurrent
            && applicationAllowed
            && !secureInputEnabled
            && tapOperational
            && eventTap != nil
    }

    func start(permissionsGranted: Bool) -> Bool {
        guard permissionsGranted else { return false }
        self.permissionsGranted = true

        var types: [CGEventType] = [
            .keyDown, .keyUp,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        if frequencyRecorder != nil {
            // Modifiers are not key events, so a heatmap cannot show Shift,
            // Control or a Corne's thumb-mounted Command keys without this.
            // It is observe-only — the flags-changed branch always returns the
            // event unmodified — and it is added only when the user asked for
            // counts, so the default event mask is unchanged.
            types.append(.flagsChanged)
        }
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
        unicodeInjectionGate.clear()
        eisuIsHeld = false
        cancelEisuBurst()
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

        if contextChanged, !isConverting {
            frequencyRecorder?.forgetModifierState()
        }

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
        // Flags-changed events only reach the recorder while the gate is open,
        // so a modifier released while it is shut is never seen to come up. The
        // baseline is dropped here instead, or the next press of that modifier
        // would read as "already down" and go uncounted.
        frequencyRecorder?.forgetModifierState()
    }

    func setPermissionsGranted(_ granted: Bool) {
        if permissionsGranted, !granted {
            invalidateContext(.tapDisabled)
        }
        permissionsGranted = granted
    }

    func reset(_ reason: ResetReason) {
        // Every reason either ends the pre-edit or means WKR can no longer
        // account for it, including `英数` and `かな`, which commit it.
        unicodeInjectionGate.clear()
        if reason != .inputSourceChanged {
            // `英数` arrives as an input source change and is the key the chord
            // is built on, so only that reason leaves the journal in place.
            englishFallbackJournal.clear()
            eisuIsHeld = false
            cancelEisuBurst()
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

        if type == .flagsChanged {
            // Observe only. A modifier never resets the pending kana, because
            // pressing Shift on the way to a shifted key must not throw away
            // the romaji already streamed for the key before it.
            if isConverting, let frequencyRecorder {
                frequencyRecorder.recordFlagsChanged(
                    keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
                    flags: event.flags
                )
            }
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
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if keyCode == CGKeyCode(kVK_JIS_Kana) || keyCode == CGKeyCode(kVK_JIS_Eisu) {
            if isRecordingSafe, let frequencyRecorder {
                frequencyRecorder.recordKeyDown(
                    keyCode: keyCode,
                    flags: event.flags,
                    isAutorepeat: isAutorepeat
                )
            }
            if keyCode == CGKeyCode(kVK_JIS_Eisu) {
                eisuIsHeld = true
                if !isAutorepeat, englishFallbackTrigger == .eisuBurst {
                    // Holding the key down is not a burst, so repeats are left
                    // out of the count.
                    extendEisuBurst()
                }
            } else {
                // `かな` starts a new pre-edit, so nothing from before it can
                // still be on screen to replace.
                englishFallbackJournal.clear()
                cancelEisuBurst()
            }
            invalidateContext(.inputSourceChanged)
            counters.bypassed()
            DispatchQueue.main.async { [weak self] in
                self?.requestContextRefresh()
            }
            return Unmanaged.passUnretained(event)
        }

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
            if isConverting,
               event.flags.contains(.maskControl),
               event.flags.intersection(Self.focusMovingModifierFlags).isEmpty {
                // The first Control shortcut has already reconciled WKR's
                // pending state and cleared the fallback journal. Repeats must
                // keep the conservative Unicode-gate count: a generic reset
                // would claim the IME pre-edit is empty while it can remain
                // marked after kana/roman transliteration.
                counters.bypassed()
                return Unmanaged.passUnretained(event)
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

        // Counted here, once the conversion gate has been proved open and
        // autorepeat has already returned above, so the tally covers exactly
        // the keys WKR itself is responsible for interpreting. The recorder
        // drops anything carrying Command, Control or Option on its own; this
        // point is chosen so that Escape, Backspace, the cursor keys and the
        // boundary keys are all counted too, because they are real presses the
        // user made while typing Japanese.
        if let frequencyRecorder {
            frequencyRecorder.recordKeyDown(
                keyCode: keyCode,
                flags: event.flags,
                isAutorepeat: isAutorepeat
            )
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
            // Apple Japanese Input keeps its conversion shortcuts on Control.
            // Kana conversion needs a pending kana completed: `W` `E` `R` then
            // Ctrl+K has to reach ワカラ, not ワカr. Roman transliteration is
            // different: Ctrl+L / Ctrl+; must see the streamed `r` itself, not
            // an invented trailing `a`.
            //
            // Command and Option keep failing closed. Those shortcuts can move
            // the focus, and synthetic romaji would then land somewhere else.
            if event.flags.contains(.maskControl),
               event.flags.intersection(Self.focusMovingModifierFlags).isEmpty {
                let key = Self.physicalKey(for: keyCode, shifted: false)
                switch ControlShortcutPolicy.pendingAction(
                    for: key,
                    isShifted: event.flags.contains(.maskShift)
                ) {
                case .completeKana:
                    if transducer.hasPendingInput {
                        AppLog.logger.notice("pending-flushed reason=control-shortcut")
                    }
                    // Even with no transducer prefix left, Apple Japanese
                    // Input can still have the completed kana as marked text.
                    // Treating the shortcut as a boundary keeps the Unicode
                    // gate conservatively closed instead of clearing it via a
                    // generic modified-key reset.
                    return applyBoundaryFlush(through: proxy, to: event, keyCode: keyCode)
                case .transliterateRoman:
                    if transducer.hasPendingInput {
                        AppLog.logger.notice("pending-released reason=roman-transliteration")
                    }
                    return applyRomanTransliteration(
                        through: proxy,
                        to: event,
                        keyCode: keyCode
                    )
                }
            }
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

        let decision = unicodeInjectionGate.decide(inputEvent, transducer.process(inputEvent))
        if decision.droppedUnicode {
            // Notice level because the user pressed two keys and gets nothing.
            // Without this line there is no way to tell it apart from a symbol
            // that was injected and then swallowed by the application.
            AppLog.logger.notice("unicode-injection-skipped reason=pre-edit-open")
        }
        englishFallbackJournal.record(inputEvent, result: decision.result, at: Self.now())

        AppLog.logger.debug("state=\(decision.result.stateCode.rawValue, privacy: .public)")
        return apply(decision.result, through: proxy, to: event, keyCode: keyCode)
    }

    /// Complete the kana already half shown, then let the original key reach
    /// the application. Used where the key is not WKR's to interpret but the
    /// streamed romaji would otherwise be left behind.
    private func applyBoundaryFlush(
        through proxy: CGEventTapProxy,
        to event: CGEvent,
        keyCode: CGKeyCode
    ) -> Unmanaged<CGEvent>? {
        let inputEvent = WKRInputEvent.boundary(.other)
        let decision = unicodeInjectionGate.decide(inputEvent, transducer.process(inputEvent))
        englishFallbackJournal.record(inputEvent, result: decision.result, at: Self.now())
        return apply(decision.result, through: proxy, to: event, keyCode: keyCode)
    }

    /// Let a roman-transliteration shortcut operate on exactly the provisional
    /// romaji already visible, without completing the pending kana.
    private func applyRomanTransliteration(
        through proxy: CGEventTapProxy,
        to event: CGEvent,
        keyCode: CGKeyCode
    ) -> Unmanaged<CGEvent>? {
        let inputEvent = WKRInputEvent.romanTransliteration
        let decision = unicodeInjectionGate.decide(inputEvent, transducer.process(inputEvent))
        englishFallbackJournal.record(inputEvent, result: decision.result, at: Self.now())
        return apply(decision.result, through: proxy, to: event, keyCode: keyCode)
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

    /// Count one `英数` press and restart the settle timer. The fallback runs
    /// when the burst ends, so the user can tap `英数` as many times as the
    /// application needs to reach the alphabet.
    private func extendEisuBurst() {
        eisuBurstPresses += 1
        eisuBurstSettle?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            self?.finishEisuBurst()
        }
        eisuBurstSettle = settle
        // The tap callback already runs on the main run loop, so the burst
        // state needs no locking.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + EnglishFallbackTrigger.burstSettleSeconds,
            execute: settle
        )
    }

    private func cancelEisuBurst() {
        eisuBurstSettle?.cancel()
        eisuBurstSettle = nil
        eisuBurstPresses = 0
    }

    private func finishEisuBurst() {
        let presses = eisuBurstPresses
        cancelEisuBurst()
        // One press is an ordinary switch to English and must not touch text.
        guard presses >= EnglishFallbackTrigger.minimumBurstPresses else { return }
        performEnglishFallback(through: nil)
    }

    /// Replace the romaji Apple Japanese Input connected back with the letters
    /// the user actually pressed. Returns how many synthetic actions were sent.
    ///
    /// The user decides when to run this: they press `英数` until the alphabet
    /// is on screen, and only then complete the chord. WKR never guesses how
    /// many presses that took. What it does know is the text now on screen,
    /// because it streamed exactly those romaji characters itself.
    @discardableResult
    private func performEnglishFallback(through proxy: CGEventTapProxy?) -> Int {
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

        let posted = proxy.map { poster.post(actions, through: $0) } ?? poster.post(actions)
        guard posted else {
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
        cancelEisuBurst()
        suppressedKeyUps.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.fatalErrorHandler(reason)
        }
    }

    /// Modifiers whose shortcuts can move the focus before a synthetic event
    /// arrives, so a pending kana is discarded rather than flushed.
    private static let focusMovingModifierFlags: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskAlphaShift, .maskSecondaryFn,
    ]

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
