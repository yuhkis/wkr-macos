import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import UniformTypeIdentifiers
import WKRCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration: AppConfiguration
    private var engineLease: EngineLease?
    private let counters = EventCounters()
    private var eventTapController: EventTapController?
    private var inputSourceMonitor: InputSourceMonitor?
    private var safetyTimer: Timer?
    private var applicationObserver: NSObjectProtocol?
    private var terminationSignalSource: DispatchSourceSignal?
    private var lastPermissionState: EventPermissionState?
    private var lastSecureInputState: Bool?
    private var secureInputSince: DispatchTime?
    private var secureInputHeldSinceLaunch = false
    private var lastInputSourceSnapshot: InputSourceSnapshot?
    private var lastInputSourceMatched: Bool?
    private var lastApplicationAllowed: Bool?
    private var isTerminatingFailClosed = false
    private var frequencyRecorder: KeyFrequencyRecorder?
    private var statusItemController: StatusItemController?
    private var statusMenuIsOpen = false
    private var lastPublishedStatus: ConversionStatus?
    private var selectedKeymapPath: String?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let blocker = startupBlocker() {
            AppLog.logger.error("conversion-not-started reason=\(blocker, privacy: .public)")
            NSApplication.shared.terminate(nil)
            return
        }

        guard !EngineLease.peerIsRunning, let lease = EngineLease() else {
            AppLog.logger.error("conversion-not-started reason=another-engine")
            NSApplication.shared.terminate(nil)
            return
        }
        engineLease = lease

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
            matches = snapshot.sourceID == configuration.inputSourceID
                && snapshot.modeID == configuration.inputModeID
        } else {
            matches = false
        }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let applicationAllowed = configuration.excludedApplications.isEmpty
            || !(frontmost.map(configuration.excludedApplications.contains) ?? false)

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
            AppLog.logger.notice("application-context excluded=\(!applicationAllowed, privacy: .public)")
        }

        if lastSecureInputState != secureInput {
            let stateWasUnknown = lastSecureInputState == nil
            lastSecureInputState = secureInput
            logSecureInputChange(to: secureInput, stateWasUnknown: stateWasUnknown)
        }

        if snapshot != lastInputSourceSnapshot || matches != lastInputSourceMatched {
            lastInputSourceSnapshot = snapshot
            lastInputSourceMatched = matches
            guard snapshot != nil else {
                AppLog.logger.error("input-source-unavailable matches-target=false")
                return
            }
            AppLog.logger.notice("input-source matches-target=\(matches, privacy: .public)")
        }
    }

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
        selectedKeymapPath = configuration.vialKeymapPath
        controller.openHeatmapRequested = { [weak self] in
            self?.openKeyFrequencyReport()
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
            self.refreshConversionContext()
        }
        statusItemController = controller
        AppLog.logger.notice(
            "status-item created=true glyph=\(controller.usesSymbols ? "symbol" : "title", privacy: .public)"
        )
    }

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
        panel.allowsOtherFileTypes = true

        NSApp.activate()
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.applyKeymap(path: url.path)
        }
    }

    private func clearKeymap() {
        precondition(Thread.isMainThread)
        applyKeymap(path: nil)
    }

    private func applyKeymap(path: String?) {
        precondition(Thread.isMainThread)
        selectedKeymapPath = path
        let defaults = UserDefaults.standard
        if let path {
            defaults.set(path, forKey: AppConfiguration.vialKeymapPathDefaultsKey)
        } else {
            defaults.removeObject(forKey: AppConfiguration.vialKeymapPathDefaultsKey)
        }
        AppLog.logger.notice("heatmap-keymap selected=\(path != nil, privacy: .public)")
        openKeyFrequencyReport()
    }

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
        if let keymapPath = selectedKeymapPath {
            arguments += ["--vil", keymapPath]
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        do {
            try process.run()
            AppLog.logger.notice("key-frequency-report launch=ok")
        } catch {
            AppLog.logger.error("key-frequency-report launch=failed reason=spawn")
        }
    }

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
    case .version:
        print("WKR macOS v1 archive 0.7.0-archive.1 / layout 1.1.0")
        exit(EXIT_SUCCESS)
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
