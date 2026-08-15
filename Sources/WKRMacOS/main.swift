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
    private var lastPermissionState: EventPermissionState?
    private var lastSecureInputState: Bool?
    private var lastInputSourceSnapshot: InputSourceSnapshot?
    private var lastInputSourceMatched: Bool?
    private var lastApplicationAllowed: Bool?
    private var isTerminatingFailClosed = false

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

        guard let controller = EventTapController(
            mode: configuration.outputMode,
            counters: counters,
            englishFallbackTrigger: configuration.englishFallbackTrigger,
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
        refreshConversionContext()

        AppLog.logger.notice(
            "conversion-started output-mode=\(self.configuration.outputModeName, privacy: .public) english-fallback=\(self.configuration.englishFallbackTrigger.rawValue, privacy: .public)"
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        safetyTimer?.invalidate()
        if let applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationObserver)
        }
        eventTapController?.reset(.explicitStop)
        eventTapController?.stop()
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

        eventTapController?.applyContext(
            inputSourceMatches: matches,
            applicationAllowed: applicationAllowed,
            secureInputEnabled: secureInput
        )

        if lastApplicationAllowed != applicationAllowed {
            lastApplicationAllowed = applicationAllowed
            AppLog.logger.notice("frontmost-application id=\(frontmost ?? "none", privacy: .public) excluded=\(!applicationAllowed, privacy: .public)")
        }

        if lastSecureInputState != secureInput {
            lastSecureInputState = secureInput
            AppLog.logger.notice("secure-event-input enabled=\(secureInput, privacy: .public)")
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
    if configuration.printInputSourceOnly {
        guard let snapshot = InputSourceSnapshot.current() else {
            fputs("input-source-unavailable\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("source-id=\(snapshot.sourceID)")
        print("mode-id=\(snapshot.modeID ?? "none")")
        print("localized-name=\(snapshot.localizedName ?? "none")")
        exit(EXIT_SUCCESS)
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
