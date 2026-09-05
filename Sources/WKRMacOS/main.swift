import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import WKRCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration: AppConfiguration
    private let counters = EventCounters()
    private var eventTapController: EventTapController?
    private var inputSourceMonitor: InputSourceMonitor?
    private var safetyTimer: Timer?
    private var applicationObserver: NSObjectProtocol?
    /// Held for the process's lifetime: a cancelled or deallocated signal
    /// source stops delivering, and the whole point of this one is to still be
    /// there at the very end.
    private var terminationSignalSource: DispatchSourceSignal?
    private var lastPermissionState: EventPermissionState?
    private var lastSecureInputState: Bool?
    /// When the current Secure Event Input episode began, on a clock that stops
    /// while the machine sleeps. Wall time would count an overnight sleep as
    /// hours of a closed gate and make every morning look like the pathological
    /// case; what matters is how long the user could have been typing into it.
    private var secureInputSince: DispatchTime?
    /// `true` when Secure Event Input was already on at the first observation,
    /// which makes the reported duration a lower bound rather than a measurement.
    private var secureInputHeldSinceLaunch = false
    private var lastInputSourceSnapshot: InputSourceSnapshot?
    private var lastInputSourceMatched: Bool?
    private var lastApplicationAllowed: Bool?
    private var isTerminatingFailClosed = false
    private var frequencyRecorder: KeyFrequencyRecorder?
    private var statusItemController: StatusItemController?
    /// True while this app's own status menu is tracking. The gate is shut for
    /// the duration so converted romaji cannot land in the menu's type-select.
    private var statusMenuIsOpen = false
    private var lastPublishedStatus: ConversionStatus?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let blocker = startupBlocker() {
            AppLog.logger.error("conversion-not-started reason=\(blocker, privacy: .public)")
            NSApplication.shared.terminate(nil)
            return
        }

        let permissions = PermissionController.check(
            requestIfNeeded: configuration.requestPermissions
        )
        lastPermissionState = permissions
        AppLog.logger.notice("permissions listen=\(permissions.listen, privacy: .public) post=\(permissions.post, privacy: .public)")

        guard permissions.isGranted else {
            AppLog.logger.error("conversion-not-started reason=permissions")
            NSApplication.shared.terminate(nil)
            return
        }

        let recorder = KeyFrequencyRecorder(
            enabled: configuration.keyFrequencyEnabled,
            storeURL: KeyFrequencyReportCommand.storeURL(for: configuration),
            retainedDays: configuration.keyFrequencyRetainedDays
        )
        frequencyRecorder = recorder
        recorder?.startFlushing()

        guard let controller = EventTapController(
            mode: configuration.outputMode,
            counters: counters,
            englishFallbackTrigger: configuration.englishFallbackTrigger,
            symbolLayerEnabled: configuration.symbolLayerEnabled,
            frequencyRecorder: recorder,
            requestContextRefresh: { [weak self] in
                self?.refreshConversionContext()
            },
            fatalErrorHandler: { [weak self] reason in
                self?.terminateFailClosed(reason: reason)
            }
        ) else {
            AppLog.logger.error("conversion-not-started reason=event-source")
            NSApplication.shared.terminate(nil)
            return
        }

        guard controller.start(permissionsGranted: permissions.isGranted) else {
            AppLog.logger.error("conversion-not-started reason=event-tap")
            NSApplication.shared.terminate(nil)
            return
        }
        eventTapController = controller

        let monitor = InputSourceMonitor { [weak self] snapshot in
            self?.refreshConversionContext(snapshot: snapshot)
        }
        inputSourceMonitor = monitor
        monitor.start()

        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.eventTapController?.invalidateContext(.applicationChanged)
            DispatchQueue.main.async { [weak self] in
                self?.refreshConversionContext()
            }
        }

        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.pollSafetyContextOnMainThread()
        }
        safetyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        installTerminationSignalHandler()
        installStatusItem()
        refreshConversionContext()

        AppLog.logger.notice(
            "conversion-started output-mode=\(self.configuration.outputModeName, privacy: .public) english-fallback=\(self.configuration.englishFallbackTrigger.rawValue, privacy: .public) symbol-layer=\(self.configuration.symbolLayerEnabled ? "on" : "off", privacy: .public) key-frequency=\(self.configuration.keyFrequencyEnabled ? "on" : "off", privacy: .public)"
        )
    }

    /// Route SIGTERM through `NSApplication.terminate` so the app shuts down the
    /// way every other exit path does.
    ///
    /// `make stop` sends SIGTERM, and AppKit installs no handler for it: the
    /// default disposition kills the process outright, so
    /// `applicationWillTerminate` never runs. Nothing depended on that until the
    /// key frequency tally arrived, which holds up to two minutes of counts in
    /// memory between flushes — 2026-08-28 a `make stop` was measured dropping
    /// the counts typed since the previous flush, with no final
    /// `key-frequency flush=ok` and no `summary` line in the log to show for it.
    ///
    /// `signal(SIGTERM, SIG_IGN)` disarms the default kill; the dispatch source
    /// then observes the same signal and hands it to the main queue, where
    /// `terminate` runs the ordinary teardown. Everything else the app does on
    /// the way out — dropping the event tap, discarding pending kana — was
    /// already being skipped too, so this is not only about the tally.
    private func installTerminationSignalHandler() {
        precondition(Thread.isMainThread)
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            AppLog.logger.notice("termination-signal received=SIGTERM action=terminate")
            NSApplication.shared.terminate(nil)
        }
        source.resume()
        terminationSignalSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        safetyTimer?.invalidate()
        if let applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationObserver)
        }
        eventTapController?.reset(.explicitStop)
        eventTapController?.stop()
        // Written after the tap is down, so the last flush cannot race a
        // keystroke still being counted.
        frequencyRecorder?.flushAndStop()
        counters.logSummary()
    }

    private func pollSafetyContextOnMainThread() {
        precondition(Thread.isMainThread)
        let permissions = PermissionController.current()
        if lastPermissionState != permissions {
            lastPermissionState = permissions
            AppLog.logger.notice("permissions listen=\(permissions.listen, privacy: .public) post=\(permissions.post, privacy: .public)")
        }

        eventTapController?.setPermissionsGranted(permissions.isGranted)
        guard permissions.isGranted else {
            terminateFailClosed(reason: "permissions-revoked")
            return
        }

        // Both TIS and Secure Event Input are queried only on the main thread.
        // Polling also reconciles notification lag and per-application sources.
        refreshConversionContext()
    }

    private func refreshConversionContext(
        snapshot suppliedSnapshot: InputSourceSnapshot? = nil
    ) {
        precondition(Thread.isMainThread)
        guard !isTerminatingFailClosed else { return }

        let secureInput = IsSecureEventInputEnabled()
        let snapshot = suppliedSnapshot ?? InputSourceSnapshot.current()
        let matches: Bool
        if let snapshot {
            // The parser refuses to launch without both IDs, so these are always
            // present. Comparing the optionals directly keeps a hypothetical nil
            // a fail-closed mismatch rather than a crash in a resident process.
            matches = snapshot.sourceID == configuration.inputSourceID
                && snapshot.modeID == configuration.inputModeID
        } else {
            matches = false
        }

        // A virtual machine or remote desktop forwards keystrokes to a guest
        // that runs its own input method, so converting them here would send
        // WKR romaji into that guest. Only a positively identified excluded
        // bundle closes this gate: when the frontmost application cannot be
        // identified, the input-source gate above still applies, and refusing
        // there would disable conversion for unidentifiable reasons.
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let applicationAllowed = configuration.excludedApplications.isEmpty
            || !(frontmost.map(configuration.excludedApplications.contains) ?? false)

        // Our own menu shuts the gate while it tracks: an open NSMenu takes
        // key input, and converted romaji would land in its type-select.
        // Narrowing an existing input at the call site can only close the gate
        // further, which is why this is done here rather than by adding an
        // eighth condition to `isConverting`.
        eventTapController?.applyContext(
            inputSourceMatches: matches,
            applicationAllowed: applicationAllowed && !statusMenuIsOpen,
            secureInputEnabled: secureInput
        )

        publishStatus(
            secureInput: secureInput,
            applicationAllowed: applicationAllowed,
            inputSourceMatches: matches
        )

        if lastApplicationAllowed != applicationAllowed {
            lastApplicationAllowed = applicationAllowed
            AppLog.logger.notice("frontmost-application id=\(frontmost ?? "none", privacy: .public) excluded=\(!applicationAllowed, privacy: .public)")
        }

        if lastSecureInputState != secureInput {
            let stateWasUnknown = lastSecureInputState == nil
            lastSecureInputState = secureInput
            logSecureInputChange(to: secureInput, stateWasUnknown: stateWasUnknown)
        }

        if snapshot != lastInputSourceSnapshot || matches != lastInputSourceMatched {
            lastInputSourceSnapshot = snapshot
            lastInputSourceMatched = matches
            guard let snapshot else {
                AppLog.logger.error("input-source-unavailable matches-target=false")
                return
            }
            AppLog.logger.notice("input-source id=\(snapshot.sourceID, privacy: .public) mode-id=\(snapshot.modeID ?? "none", privacy: .public) name=\(snapshot.localizedName ?? "none", privacy: .public) matches-target=\(matches, privacy: .public)")
        }
    }

    /// Works out what the menu bar should show and hands it to the status item.
    ///
    /// Takes the three reasons as arguments rather than reading them back from
    /// the controller. `invalidateContext` clears `inputSourceMatches` and
    /// `applicationAllowed` together with `contextIsCurrent` on every app switch
    /// and every かな / 英数 press, so a read-back would show a *wrong* reason —
    /// "除外アプリが前面" for an application that is not excluded — many times an
    /// hour. The values passed here are the ones just measured, and were just
    /// handed to `applyContext`, so they agree with the gate by construction.
    ///
    /// The gate itself arrives as `isConverting`, untouched. This function never
    /// re-derives it.
    private func publishStatus(
        secureInput: Bool,
        applicationAllowed: Bool,
        inputSourceMatches: Bool
    ) {
        precondition(Thread.isMainThread)
        guard let statusItemController else { return }
        let status = ConversionStatus.resolve(
            gateOpen: eventTapController?.isConverting ?? false,
            secureInputEnabled: secureInput,
            applicationAllowed: applicationAllowed,
            inputSourceMatches: inputSourceMatches,
            statusMenuOpen: statusMenuIsOpen
        )
        guard lastPublishedStatus != status else { return }
        lastPublishedStatus = status
        statusItemController.apply(status)
    }

    /// Creates the menu bar item.
    ///
    /// Placed after every startup refusal so a process that is about to die
    /// never flashes an icon, and before the first `refreshConversionContext()`
    /// so the first thing drawn is a real measurement rather than a guess.
    ///
    /// A failure here is logged and otherwise ignored. The indicator is worth
    /// strictly less than conversion, and refusing to start over a missing
    /// status item would trade the whole app for its status line.
    private func installStatusItem() {
        precondition(Thread.isMainThread)
        let controller = StatusItemController()
        guard controller.isUsable else {
            AppLog.logger.error("status-item created=false reason=no-button")
            controller.removeFromStatusBar()
            return
        }
        controller.menuContentProvider = { [weak self] in
            self?.currentMenuContent() ?? ConversionMenuContent(status: .stopping)
        }
        controller.openHeatmapRequested = { [weak self] in
            self?.openKeyFrequencyReport()
        }
        controller.menuOpenStateChanged = { [weak self] isOpen in
            guard let self else { return }
            self.statusMenuIsOpen = isOpen
            AppLog.logger.notice("status-menu open=\(isOpen, privacy: .public)")
            // Apply the narrowed gate now rather than waiting up to 0.10 s for
            // the next tick, so the first keystroke after the menu opens is
            // already covered.
            self.refreshConversionContext()
        }
        statusItemController = controller
        AppLog.logger.notice(
            "status-item created=true glyph=\(controller.usesSymbols ? "symbol" : "title", privacy: .public)"
        )
    }

    /// Renders and opens the key-frequency heatmap.
    ///
    /// Runs as a **separate process**, never in this one. Rendering reads the
    /// whole store, builds the HTML for every keyboard and layer, and writes a
    /// file; doing that here would block the main run loop, which is where the
    /// event tap source lives, and a long enough stall means
    /// `tapDisabledByTimeout` and a fail-closed exit. The resident process must
    /// survive looking at a report.
    ///
    /// The child is this same binary with `--key-frequency-report`, which exits
    /// before `NSApplication` is ever created — so it neither asks for Input
    /// Monitoring nor trips the duplicate-instance guard, which only runs on the
    /// `.run` path. Launching the executable directly rather than through
    /// `open` matters: Launch Services would otherwise just activate the
    /// already-running instance instead of starting the one-shot.
    ///
    /// The store and keymap paths are forwarded when this process was given
    /// them explicitly. When they were not, the child resolves the same user
    /// defaults this process did, so the menu and `make key-frequency-report`
    /// produce the same report.
    private func openKeyFrequencyReport() {
        precondition(Thread.isMainThread)
        guard let executable = Bundle.main.executableURL else {
            AppLog.logger.error("key-frequency-report launch=failed reason=no-executable")
            return
        }

        var arguments = ["--key-frequency-report", "--open"]
        if let storePath = configuration.keyFrequencyStorePath {
            arguments += ["--key-frequency-store", storePath]
        }
        if let keymapPath = configuration.vialKeymapPath {
            arguments += ["--vil", keymapPath]
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        do {
            // Returns as soon as the child is spawned; nothing here waits on it.
            try process.run()
            AppLog.logger.notice("key-frequency-report launch=ok")
        } catch {
            // A report that will not open is not a reason to stop converting.
            AppLog.logger.error("key-frequency-report launch=failed reason=spawn")
        }
    }

    /// Gathers what the menu shows, at the moment it opens.
    ///
    /// The holder is re-queried here rather than reused from the rising edge.
    /// Orphaning produces no falling edge — `IsSecureEventInputEnabled()` simply
    /// stays true — so a liveness captured when the gate closed can still read
    /// `alive` long after the holder exited. That is precisely the case where
    /// the remedy differs, so it has to be fresh. One query per menu open is
    /// well clear of the 10 Hz path this must never touch.
    private func currentMenuContent() -> ConversionMenuContent {
        precondition(Thread.isMainThread)
        let status = lastPublishedStatus ?? .stopping
        guard status == .secureInput else {
            return ConversionMenuContent(
                status: status,
                inputSourceName: lastInputSourceSnapshot?.localizedName
            )
        }
        let holder = SecureInputHolder.current()
        let heldSeconds = secureInputSince.map { start in
            Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds)
                / Double(NSEC_PER_SEC)
        }
        return ConversionMenuContent(
            status: status,
            inputSourceName: lastInputSourceSnapshot?.localizedName,
            secureInput: SecureInputDetail(
                holderPID: holder.pid,
                liveness: holder.liveness,
                heldSeconds: heldSeconds,
                heldSinceLaunch: secureInputHeldSinceLaunch
            )
        )
    }

    /// Records one Secure Event Input transition.
    ///
    /// The two edges carry different things because a later investigation needs
    /// different things from them. The rising edge names the holder, which is
    /// what decides the response and cannot be recovered afterwards — by the
    /// time anyone reads the log the holder may be gone. The falling edge
    /// carries the duration, which is what separates a password field from a
    /// leak; deriving it by hand from two timestamps is what made the first two
    /// investigations slow.
    private func logSecureInputChange(to enabled: Bool, stateWasUnknown: Bool) {
        precondition(Thread.isMainThread)

        guard enabled else {
            let heldSeconds = secureInputSince.map { start in
                Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds)
                    / Double(NSEC_PER_SEC)
            }
            let fields = SecureInputLogFields.disabledFields(
                heldSeconds: heldSeconds,
                sinceLaunch: secureInputHeldSinceLaunch
            )
            secureInputSince = nil
            secureInputHeldSinceLaunch = false
            AppLog.logger.notice("secure-event-input enabled=false\(fields, privacy: .public)")
            return
        }

        let holder = SecureInputHolder.current()
        secureInputSince = .now()
        secureInputHeldSinceLaunch = stateWasUnknown
        let fields = SecureInputLogFields.enabledFields(
            holderPID: holder.pid,
            liveness: holder.liveness
        )
        AppLog.logger.notice("secure-event-input enabled=true\(fields, privacy: .public)")
    }

    private func terminateFailClosed(reason: String) {
        precondition(Thread.isMainThread)
        guard !isTerminatingFailClosed else { return }
        isTerminatingFailClosed = true
        AppLog.logger.error("conversion-stopped reason=\(reason, privacy: .public) action=terminate")
        eventTapController?.invalidateContext(.tapDisabled)
        eventTapController?.stop()
        NSApplication.shared.terminate(nil)
    }

    /// `nil` when it is safe to start, otherwise the reason to log. Both cases
    /// refuse to start: without a bundle identifier there is neither an identity
    /// to deduplicate against nor a stable TCC identity to hold the permissions.
    private func startupBlocker() -> String? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return "not-a-bundle" }
        let isOnlyInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .allSatisfy { $0.processIdentifier == getpid() || $0.isTerminated }
        return isOnlyInstance ? nil : "duplicate-instance"
    }
}

do {
    let configuration = try AppConfiguration.parse(arguments: CommandLine.arguments)
    switch configuration.action {
    case .printInputSource:
        guard let snapshot = InputSourceSnapshot.current() else {
            fputs("input-source-unavailable\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("source-id=\(snapshot.sourceID)")
        print("mode-id=\(snapshot.modeID ?? "none")")
        print("localized-name=\(snapshot.localizedName ?? "none")")
        exit(EXIT_SUCCESS)
    case .keyFrequencyReport:
        exit(KeyFrequencyReportCommand.runReport(configuration))
    case .keyFrequencyReset:
        exit(KeyFrequencyReportCommand.runReset(configuration))
    case .run:
        break
    }

    let application = NSApplication.shared
    let delegate = AppDelegate(configuration: configuration)
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()
} catch {
    fputs("configuration-error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
