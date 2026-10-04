import XCTest
@testable import WKRMacOS

final class StartupBoundaryTests: XCTestCase {
    func testV1WaitsForPredecessorBeforeStartingSharedEngine() {
        var wait = EventTapPredecessorWait()
        XCTAssertEqual(wait.next(predecessorAlive: true, elapsed: 0), .wait(after: 0.05))
        XCTAssertEqual(wait.state, .waiting)
        XCTAssertEqual(wait.next(predecessorAlive: false, elapsed: 1), .startConversion)
    }

    func testV1UsesTheSameBoundedRecoveryWithoutEnablingRecording() throws {
        let suite = "synthetic-v1-startup-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = try AppConfiguration.parse(arguments: ["WKRV1", "--event-tap-startup-wait", "0"], defaults: defaults)
        XCTAssertEqual(config.eventTapStartupRetry.next(afterFailureAt: 0), .giveUp)
        XCTAssertFalse(config.keyFrequencyEnabled)
        XCTAssertTrue(StartupRefusal.permissions.keepsPermissionSetup)
        XCTAssertFalse(StartupRefusal.eventTap.keepsPermissionSetup)
        XCTAssertTrue(StartupRefusal.relaunchesAfterTapFailure(reason: "event-tap-disabled-timeout", keyHandled: false))
        XCTAssertFalse(StartupRefusal.relaunchesAfterTapFailure(reason: "event-tap-disabled-timeout", keyHandled: true))
        XCTAssertFalse(StartupRefusal.relaunchesAfterTapFailure(reason: "permissions-revoked", keyHandled: false))
    }
}
