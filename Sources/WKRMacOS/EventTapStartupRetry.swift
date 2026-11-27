import Foundation

/// A bounded series of fresh processes for startup failures. This is not a
/// retry of a disabled tap in the same process, and carries no input history.
struct EventTapStartupRetry: Equatable {
    static let defaultWaitSeconds = 300
    static let maximumWaitSeconds = 3600
    static let maximumAttempts = 1202
    static let interval: TimeInterval = 3
    let waitSeconds: Int

    enum Next: Equatable {
        case relaunch(after: TimeInterval)
        case giveUp
    }

    func next(afterFailureAt elapsed: TimeInterval, attempt: Int = 1) -> Next {
        guard elapsed.isFinite, attempt < Self.maximumAttempts else { return .giveUp }
        let remaining = TimeInterval(waitSeconds) - max(0, elapsed)
        guard remaining > 0 else { return .giveUp }
        return .relaunch(after: min(Self.interval, remaining))
    }
}

/// Internal, temporary launch arguments. The retry state is never saved to a
/// file or UserDefaults. A successor waits for its predecessor to release the
/// engine lease before it checks for another converter.
struct EventTapRelaunch: Equatable {
    static let argument = "--event-tap-relaunch"
    let firstFailure: TimeInterval
    let attempt: Int
    let previousPID: pid_t

    let runtimeRecovery: Bool

    init(firstFailure: TimeInterval, attempt: Int, previousPID: pid_t, runtimeRecovery: Bool = false) {
        self.runtimeRecovery = runtimeRecovery
        self.firstFailure = firstFailure
        self.attempt = attempt
        self.previousPID = previousPID
    }

    init?(argument: String) {
        let fields = argument.split(separator: ",", omittingEmptySubsequences: false)
        let runtime = fields.count == 4 && fields.last == "runtime"
        guard fields.count == 3 || runtime,
              let firstFailure = TimeInterval(fields[0]), firstFailure.isFinite,
              firstFailure >= 0, firstFailure < TimeInterval(Int.max),
              let attempt = Int(fields[1]), (2...EventTapStartupRetry.maximumAttempts).contains(attempt),
              let pid = pid_t(fields[2]), pid > 0
        else { return nil }
        self.init(firstFailure: firstFailure, attempt: attempt, previousPID: pid, runtimeRecovery: runtime)
    }

    var argumentValue: String {
        "\(Int(firstFailure)),\(attempt),\(previousPID)" + (runtimeRecovery ? ",runtime" : "")
    }

    static func arguments(replacingIn arguments: [String], with relaunch: EventTapRelaunch) -> [String] {
        var result: [String] = []
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            if token == argument { index += 2; continue }
            if token.hasPrefix(argument + "=") { index += 1; continue }
            result.append(token)
            index += 1
        }
        return result + [argument, relaunch.argumentValue]
    }
}

enum StartupRefusal: Equatable {
    case permissions
    case eventTap
    case eventTapTimeout
    case runtimeTimeout

    /// Initial permission setup remains visible while this process rechecks.
    /// Only tap failures launch a successor process.
    var keepsPermissionSetup: Bool { self == .permissions }

    var reason: String {
        switch self {
        case .permissions: return "permissions"
        case .eventTap: return "event-tap"
        case .eventTapTimeout: return "event-tap-timeout"
        case .runtimeTimeout: return "runtime-tap-timeout"
        }
    }

    var waitEvent: String {
        switch self {
        case .permissions: return "permissions-check"
        case .eventTap: return "event-tap-start"
        case .eventTapTimeout: return "event-tap-timeout"
        case .runtimeTimeout: return "runtime-tap-timeout"
        }
    }

    static func requestsPermissions(configured: Bool, relaunch: EventTapRelaunch?, userRequested: Bool = false) -> Bool {
        userRequested || (configured && relaunch == nil)
    }

    static let tapTimeoutReason = "event-tap-disabled-timeout"

    static func afterTapFailure(reason: String, keyHandled: Bool, paused: Bool,
                                recovering: Bool, activeSeconds: TimeInterval) -> Self? {
        guard reason == tapTimeoutReason, !paused else { return nil }
        if recovering && activeSeconds < 60 { return nil }
        return keyHandled ? .runtimeTimeout : .eventTapTimeout
    }

    func successor(previous: EventTapRelaunch?, now: TimeInterval, pid: pid_t) -> EventTapRelaunch {
        // A new incident after sustained operation has its own retry budget.
        let chain = self == .runtimeTimeout ? nil : previous
        return EventTapRelaunch(firstFailure: min(chain?.firstFailure ?? now, now),
                                attempt: (chain?.attempt ?? 1) + 1, previousPID: pid,
                                runtimeRecovery: self == .runtimeTimeout || chain?.runtimeRecovery == true)
    }
}

/// A successor must finish AppKit launch before waiting for its predecessor:
/// Launch Services may deliver the predecessor's open completion only then.
/// This policy is polled by a timer, without blocking the main run loop.
struct EventTapPredecessorWait: Equatable {
    static let interval: TimeInterval = 0.05
    static let defaultTimeout: TimeInterval = 5
    let timeout: TimeInterval
    private(set) var state = State.waiting

    enum State: Equatable { case waiting, ready, timedOut }
    enum Next: Equatable {
        case wait(after: TimeInterval)
        case startConversion
        case giveUp
    }

    init(timeout: TimeInterval = Self.defaultTimeout) { self.timeout = timeout }

    mutating func next(predecessorAlive: Bool, elapsed: TimeInterval) -> Next {
        guard state != .timedOut else { return .giveUp }
        if state == .ready { return .startConversion }
        guard !predecessorAlive else {
            guard elapsed.isFinite, timeout.isFinite, elapsed < timeout else {
                state = .timedOut
                return .giveUp
            }
            return .wait(after: min(Self.interval, timeout - max(0, elapsed)))
        }
        state = .ready
        return .startConversion
    }
}
