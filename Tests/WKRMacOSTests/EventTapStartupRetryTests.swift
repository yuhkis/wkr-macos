import XCTest
@testable import WKRMacOS

final class EventTapStartupRetryTests: XCTestCase {
    func testSuccessorDoesNotStartWhilePredecessorIsAlive() {
        var wait = EventTapPredecessorWait()
        XCTAssertEqual(wait.next(predecessorAlive: true, elapsed: 0), .wait(after: 0.05))
        XCTAssertEqual(wait.state, .waiting)
        XCTAssertEqual(wait.next(predecessorAlive: true, elapsed: 4), .wait(after: 0.05))
        XCTAssertEqual(wait.state, .waiting)
        XCTAssertEqual(wait.next(predecessorAlive: false, elapsed: 4.1), .startConversion)
        XCTAssertEqual(wait.state, .ready)
    }

    func testPredecessorDeadlineFailsClosedAndDoesNotResumeAutomatically() {
        var wait = EventTapPredecessorWait()
        XCTAssertEqual(wait.next(predecessorAlive: true, elapsed: 4.99), .wait(after: 5 - 4.99))
        XCTAssertEqual(wait.next(predecessorAlive: true, elapsed: 5), .giveUp)
        XCTAssertEqual(wait.state, .timedOut)
        // The visible setup/manual retry remains; the old process disappearing
        // after the deadline must not start the engine behind that guide.
        XCTAssertEqual(wait.next(predecessorAlive: false, elapsed: 6), .giveUp)
        var invalidClock = EventTapPredecessorWait()
        XCTAssertEqual(invalidClock.next(predecessorAlive: true, elapsed: .infinity), .giveUp)
    }

    func testRetryStopsAtDeadlineOrAttemptLimit() {
        let retry = EventTapStartupRetry(waitSeconds: 10)
        XCTAssertEqual(retry.next(afterFailureAt: 0), .relaunch(after: 3))
        XCTAssertEqual(retry.next(afterFailureAt: 8.5), .relaunch(after: 1.5))
        XCTAssertEqual(retry.next(afterFailureAt: 10), .giveUp)
        XCTAssertEqual(retry.next(afterFailureAt: 60), .giveUp)
        XCTAssertEqual(retry.next(afterFailureAt: .infinity), .giveUp)
        XCTAssertEqual(retry.next(afterFailureAt: -.infinity), .giveUp)
        XCTAssertEqual(retry.next(afterFailureAt: 0, attempt: EventTapStartupRetry.maximumAttempts), .giveUp)
        XCTAssertEqual(EventTapStartupRetry(waitSeconds: 0).next(afterFailureAt: 0), .giveUp)
    }

    func testInternalArgumentsAreValidatedAndOnlyReplaceRetryState() {
        let next = EventTapRelaunch(firstFailure: 100, attempt: 3, previousPID: 7)
        XCTAssertEqual(EventTapRelaunch(argument: next.argumentValue), next)
        XCTAssertEqual(
            EventTapRelaunch.arguments(replacingIn: ["wkr", "--mode", "prefix", "--event-tap-relaunch", "100,2,6", "--request-permissions"], with: next),
            ["--mode", "prefix", "--request-permissions", "--event-tap-relaunch", "100,3,7"]
        )
        XCTAssertEqual(
            EventTapRelaunch.arguments(replacingIn: ["wkr", "--event-tap-relaunch=100,2,6"], with: next),
            ["--event-tap-relaunch", "100,3,7"]
        )
        for value in ["", "1,2", "x,2,3", "1,1,3", "1,2,0", "1,2,3,4", "inf,2,3", "-1,2,3", "1e100,2,3", "1,1203,3"] {
            XCTAssertNil(EventTapRelaunch(argument: value))
        }
    }

    func testConfigurationWaitAndInternalArgumentsAreNotResearchSettings() throws {
        let suite = "synthetic-startup-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let args = ["wkr", "--key-frequency-report"]
        let plain = try AppConfiguration.parse(arguments: args, defaults: defaults)
        XCTAssertEqual(plain.eventTapStartupRetry.waitSeconds, 300)
        XCTAssertNil(plain.eventTapRelaunch)
        XCTAssertFalse(plain.keyFrequencyEnabled)
        defaults.set(60, forKey: AppConfiguration.eventTapStartupWaitDefaultsKey)
        XCTAssertEqual(try AppConfiguration.parse(arguments: args, defaults: defaults).eventTapStartupRetry.waitSeconds, 60)
        XCTAssertEqual(try AppConfiguration.parse(arguments: args + ["--event-tap-startup-wait=0"], defaults: defaults).eventTapStartupRetry.waitSeconds, 0)
        for value in ["-1", "3601", "abc"] {
            XCTAssertThrowsError(try AppConfiguration.parse(arguments: args + ["--event-tap-startup-wait", value], defaults: defaults))
        }
        XCTAssertThrowsError(try AppConfiguration.parse(arguments: args + ["--event-tap-startup-wait"], defaults: defaults))
        XCTAssertEqual(try AppConfiguration.parse(arguments: args + ["--event-tap-relaunch", "100,2,6"], defaults: defaults).eventTapRelaunch,
                       EventTapRelaunch(firstFailure: 100, attempt: 2, previousPID: 6))
        XCTAssertNil(try AppConfiguration.parse(arguments: args + ["--event-tap-relaunch", "junk"], defaults: defaults).eventTapRelaunch)
    }

    func testFirstPermissionFailureKeepsSetupAndOnlyTapFailuresRelaunch() {
        XCTAssertTrue(StartupRefusal.permissions.keepsPermissionSetup)
        XCTAssertFalse(StartupRefusal.eventTap.keepsPermissionSetup)
        XCTAssertFalse(StartupRefusal.eventTapTimeout.keepsPermissionSetup)
    }

    func testPermissionPromptsAreNotRepeatedByAutomaticRelaunch() {
        let relaunch = EventTapRelaunch(firstFailure: 100, attempt: 2, previousPID: 6)
        XCTAssertTrue(StartupRefusal.requestsPermissions(configured: true, relaunch: nil))
        XCTAssertFalse(StartupRefusal.requestsPermissions(configured: true, relaunch: relaunch))
        XCTAssertFalse(StartupRefusal.requestsPermissions(configured: false, relaunch: nil))
        XCTAssertTrue(StartupRefusal.requestsPermissions(configured: false, relaunch: relaunch, userRequested: true))
    }

    func testOnlyATimeoutBeforeAnyRealKeyAllowsRecovery() {
        XCTAssertTrue(StartupRefusal.relaunchesAfterTapFailure(reason: "event-tap-disabled-timeout", keyHandled: false))
        XCTAssertFalse(StartupRefusal.relaunchesAfterTapFailure(reason: "event-tap-disabled-timeout", keyHandled: true))
        for reason in ["event-tap-disabled-user-input", "permissions-revoked", "event-source", "peer-engine"] {
            XCTAssertFalse(StartupRefusal.relaunchesAfterTapFailure(reason: reason, keyHandled: false))
            XCTAssertFalse(StartupRefusal.relaunchesAfterTapFailure(reason: reason, keyHandled: true))
        }
        XCTAssertEqual(StartupRefusal.permissions.reason, "permissions")
        XCTAssertEqual(StartupRefusal.permissions.waitEvent, "permissions-check")
        XCTAssertEqual(StartupRefusal.eventTap.reason, "event-tap")
        XCTAssertEqual(StartupRefusal.eventTapTimeout.reason, "event-tap-timeout")
    }
}
