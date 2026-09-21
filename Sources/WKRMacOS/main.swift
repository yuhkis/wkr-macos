import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import UniformTypeIdentifiers
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
    /// The keymap the heatmap is drawn against, for this session.
    ///
    /// Held separately from `configuration.vialKeymapPath` because a `--vil`
    /// argument outranks the user default at parse time. Without this, picking a
    /// keymap from the menu would write the default and then be overruled by the
    /// launch argument every time the report ran.
    private var selectedKeymapPath: String?
    private var engineLease: EngineLease?
    private var peerObserver: NSObjectProtocol?
    private var setupWindow: SetupWindowController?
    private var practiceWindow: PracticeWindowController?
    private var userPaused = false

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationSignalHandler()
        installStatusItem()
        if configuration.action == .practice { openPractice(); return }
        startConversion()
    }

    private func startConversion(requestPermissions: Bool = false) {
        guard configuration.action != .practice else {
            showSetup(reason: "練習専用で起動しています。変換を使うときは一度終了し、通常起動してください。")
            return
        }
        guard eventTapController == nil else { return }
        if let blocker = startupBlocker() {
            AppLog.logger.error("conversion-not-started reason=\(blocker, privacy: .public)")
            showSetup(reason: blocker == "not-a-bundle" ? "アプリの構成を確認してください。" : "別のWKR変換アプリが動いています。先に終了してから開始してください。")
            return
        }
        guard let lease = EngineLease() else {
            showSetup(reason: "別の変換エンジンが使用中、または排他状態を確認できません。")
            return
        }
        engineLease = lease
        let permissions = PermissionController.check(
            requestIfNeeded: requestPermissions || configuration.requestPermissions
        )
        lastPermissionState = permissions
        AppLog.logger.notice("permissions listen=\(permissions.listen, privacy: .public) post=\(permissions.post, privacy: .public)")

        guard permissions.isGranted else {
            AppLog.logger.error("conversion-not-started reason=permissions")
            engineLease = nil
            showSetup(reason: "入力監視: \(permissions.listen ? "許可済み" : "未許可") / アクセシビリティ: \(permissions.post ? "許可済み" : "未許可")。設定画面で WKR macOS Public を許可して、再確認してください。")
            return
        }

        var recorder = KeyFrequencyRecorder(
            enabled: configuration.keyFrequencyEnabled,
            storeURL: KeyFrequencyReportCommand.storeURL(for: configuration),
            retainedDays: configuration.keyFrequencyRetainedDays
        )
        // Before the first count, and only from the resident process: both
        // startup guards are behind us, and neither the report subprocess nor
        // a second instance reaches this line. A tally may not span two rule
        // tables, so if a different one wrote the file it is moved aside now —
        // at the moment the layout changes, rather than at the next midnight.
        if recorder?.rotateIfLayoutChanged() == .failed { recorder = nil }
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
        setupWindow?.close()
        if practiceWindow == nil { NSApp.setActivationPolicy(.accessory) }
        peerObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            if EngineLease.peerIsRunning { self?.terminateFailClosed(reason: "peer-engine") }
        }
        refreshConversionContext()

        AppLog.logger.notice(
            "conversion-started output-mode=\(self.configuration.outputModeName, privacy: .public) english-fallback=\(self.configuration.englishFallbackTrigger.rawValue, privacy: .public) symbol-layer=\(self.configuration.symbolLayerEnabled ? "on" : "off", privacy: .public) key-frequency=\(self.frequencyRecorder != nil ? "on" : "off", privacy: .public)"
        )
    }

    /// Route SIGTERM through `NSApplication.terminate` so the app shuts down the
    /// way every other exit path does.
    ///
    /// `make stop` sends SIGTERM. Its default disposition bypasses
    /// `applicationWillTerminate`, so buffered optional counts and the event tap
    /// need to be handled through the ordinary application teardown.
    ///
    /// `signal(SIGTERM, SIG_IGN)` disarms the default kill; the dispatch source
    /// then observes the same signal and hands it to the main queue, where
    /// `terminate` runs the ordinary teardown, including stopping the event tap,
    /// discarding pending kana and flushing any opt-in frequency counts.
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
        if let peerObserver { NSWorkspace.shared.notificationCenter.removeObserver(peerObserver) }
        eventTapController?.reset(.explicitStop)
        eventTapController?.stop()
        // Written after the tap is down, so the last flush cannot race a
        // keystroke still being counted.
        frequencyRecorder?.flushAndStop()
        engineLease = nil
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
            applicationAllowed: applicationAllowed && !statusMenuIsOpen && !userPaused,
            secureInputEnabled: secureInput
        )

        publishStatus(
            secureInput: secureInput,
            applicationAllowed: applicationAllowed && !userPaused,
            inputSourceMatches: matches
        )

        if lastApplicationAllowed != applicationAllowed {
            lastApplicationAllowed = applicationAllowed
            AppLog.logger.notice("frontmost-application excluded=\(!applicationAllowed, privacy: .public)")
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
            applicationAllowed: applicationAllowed && !userPaused,
            inputSourceMatches: inputSourceMatches,
            statusMenuOpen: statusMenuIsOpen,
            userPaused: userPaused
        )
        guard lastPublishedStatus != status else { return }
        lastPublishedStatus = status
        statusItemController.apply(status)
    }

    /// Creates the menu bar item.
    ///
    /// Installed before the setup screen, so practice and quit remain available
    /// even when conversion is blocked by a peer or missing permissions.
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
        controller.openPracticeRequested = { [weak self] in self?.openPractice() }
        controller.openSetupRequested = { [weak self] in self?.showSetup(reason: "権限を確認し、Apple日本語入力の『ひらがな』で使います。") }
        controller.pauseRequested = { [weak self] in
            guard let self else { return }
            self.userPaused.toggle()
            self.eventTapController?.reset(.explicitStop)
            self.refreshConversionContext()
        }
        controller.pausedProvider = { [weak self] in self?.userPaused ?? false }
        selectedKeymapPath = configuration.vialKeymapPath
        controller.openHeatmapRequested = { [weak self] in
            self?.openKeyFrequencyReport()
        }
        controller.openArchivedHeatmapRequested = { [weak self] in
            self?.chooseArchivedTally()
        }
        controller.chooseKeymapRequested = { [weak self] in
            self?.chooseKeymap()
        }
        controller.clearKeymapRequested = { [weak self] in
            self?.clearKeymap()
        }
        controller.keymapFileNameProvider = { [weak self] in
            self?.selectedKeymapPath.map { ($0 as NSString).lastPathComponent }
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

    /// Asks for a Vial export to draw the heatmap against.
    ///
    /// Uses `begin` rather than `runModal`: a modal session would sit inside
    /// this call while the user browses, and the event tap source is on this
    /// same run loop. `begin` puts the panel up and returns, so nothing here
    /// holds the loop for however long the file browser stays open.
    ///
    /// The app is `LSUIElement`, so it is never the active application and the
    /// panel would open behind whatever is in front. Activating first is what
    /// makes it reachable.
    private func chooseKeymap() {
        precondition(Thread.isMainThread)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "ヒートマップに使う Vial のキーマップ（.vil）を選んでください"
        panel.prompt = "選ぶ"
        if let vil = UTType(filenameExtension: "vil") {
            panel.allowedContentTypes = [vil, .json]
        }
        // `.vil` is JSON, and a system without the type registered would
        // otherwise show nothing selectable.
        panel.allowsOtherFileTypes = true

        NSApp.activate()
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.applyKeymap(path: url.path)
        }
    }

    /// Asks for a tally that was set aside when the layout changed, and draws
    /// it.
    ///
    /// Same shape as `chooseKeymap`, and for the same reasons: `begin` rather
    /// than `runModal` so the run loop the event tap sits on is not held, and
    /// `NSApp.activate()` first because an `LSUIElement` app's panel would
    /// otherwise open behind whatever is in front.
    ///
    /// The panel opens in the archive folder. It lives under Application
    /// Support, which no one reaches by browsing, and putting the user there is
    /// what makes the entry usable at all — while still keeping the directory
    /// off the menu itself.
    private func chooseArchivedTally() {
        precondition(Thread.isMainThread)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "過去の集計ファイルを選んでください"
        panel.prompt = "開く"
        // `allowsOtherFileTypes` is a save-panel setting and does nothing
        // here, so it is not set: the archives this offers are ours and are
        // always `.json`.
        panel.allowedContentTypes = [.json]
        let storeURL = KeyFrequencyReportCommand.storeURL(for: configuration)
        let archiveDirectory = storeURL.map(KeyFrequencyRecorder.archiveDirectory(for:))
        if let storeURL {
            panel.directoryURL = archiveDirectory.flatMap {
                FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
            } ?? storeURL.deletingLastPathComponent()
        }

        NSApp.activate()
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            // Not read here. Opening a file is I/O, this is the run loop the
            // tap is on, and the child draws an unreadable file as a page that
            // says so rather than as an empty picture.
            AppLog.logger.notice("key-frequency-archive opened=true")
            // The page goes in our own archive folder rather than beside
            // whatever was picked. A file chosen from a read-only disk, or from
            // a folder this app may not write to, would otherwise fail at the
            // last step with nowhere to say so — and a picked file named like
            // the live tally would land its report on top of the live one.
            let output = archiveDirectory?
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".html")
                .path
            self.openKeyFrequencyReport(storePathOverride: url.path, reportPathOverride: output)
        }
    }

    /// Goes back to the built-in layout.
    private func clearKeymap() {
        precondition(Thread.isMainThread)
        applyKeymap(path: nil)
    }

    /// Records the choice for this session and for the next launch.
    ///
    /// Writes the same user default the CLI reads, so `make key-frequency-report`
    /// and a later launch of this app agree with what the menu shows. The
    /// session copy is what the report subprocess is actually given, because a
    /// `--vil` launch argument would otherwise keep winning.
    private func applyKeymap(path: String?) {
        precondition(Thread.isMainThread)
        selectedKeymapPath = path
        let defaults = UserDefaults.standard
        if let path {
            defaults.set(path, forKey: AppConfiguration.vialKeymapPathDefaultsKey)
        } else {
            defaults.removeObject(forKey: AppConfiguration.vialKeymapPathDefaultsKey)
        }
        // The path is the user's own file and can name a home directory or a
        // cloud folder, so it is not logged. Whether one is set is enough to
        // tell the two states apart afterwards.
        AppLog.logger.notice("heatmap-keymap selected=\(path != nil, privacy: .public)")
        openKeyFrequencyReport()
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
    private func openKeyFrequencyReport(
        storePathOverride: String? = nil,
        reportPathOverride: String? = nil
    ) {
        precondition(Thread.isMainThread)
        guard let executable = Bundle.main.executableURL else {
            AppLog.logger.error("key-frequency-report launch=failed reason=no-executable")
            return
        }

        var arguments = ["--key-frequency-report", "--open"]
        // An override is a file the user just picked and must be forwarded
        // whatever this process was launched with; without one, the store is
        // forwarded only when this process was given it explicitly, so that the
        // child otherwise resolves the same defaults.
        if let storePath = storePathOverride ?? configuration.keyFrequencyStorePath {
            arguments += ["--key-frequency-store", storePath]
        }
        if let reportPath = reportPathOverride {
            arguments += ["--output", reportPath]
        }
        if let keymapPath = selectedKeymapPath {
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

    private func showSetup(reason: String) {
        if setupWindow == nil {
            let window = SetupWindowController()
            window.retry = { [weak self] in self?.startConversion(requestPermissions: true) }
            window.practice = { [weak self] in self?.openPractice() }
            setupWindow = window
        }
        setupWindow?.show(reason: reason, canStartConversion: configuration.action != .practice)
    }

    private func openPractice() {
        if practiceWindow == nil {
            guard let window = PracticeWindowController() else {
                showSetup(reason: "同梱教材を読み込めません。配布アプリの内容を確認してください。")
                return
            }
            window.onClose = { [weak self] in
                self?.practiceWindow = nil
                if self?.configuration.action == .practice { NSApp.terminate(nil) }
                else { NSApp.setActivationPolicy(.accessory) }
            }
            practiceWindow = window
        }
        practiceWindow?.show()
    }

    private func startupBlocker() -> String? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return "not-a-bundle" }
        if EngineLease.peerIsRunning { return "peer-engine" }
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
    case .keyFrequencyArchive:
        exit(KeyFrequencyReportCommand.runArchive(configuration))
    case .help:
        print("""
        WKR macOS Public — --version / --practice-only / --print-input-source
        Open WKRPublic.app to set up permissions and start conversion.
        --mode prefix|deferred (optimistic requires --allow-unverified-optimistic)
        --key-frequency on|off (default off), --key-frequency-retention all|DAYS
        --key-frequency-report [--open] [--output PATH] [--vil PATH]
        --key-frequency-archive / --key-frequency-reset (stop conversion first)
        --symbol-layer on|off, --english-fallback eisu+eisu|eisu+return|eisu+tab|off
        --exclude-app BUNDLE_ID, --input-source-id ID, --input-mode-id ID
        Input text, key sequences, fine timestamps and research recording are unsupported.
        """)
        exit(EXIT_SUCCESS)
    case .version:
        print(AppVersion.display)
        exit(EXIT_SUCCESS)
    case .run, .practice:
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
