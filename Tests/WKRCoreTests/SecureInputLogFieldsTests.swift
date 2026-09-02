import XCTest
@testable import WKRCore

final class SecureInputLogFieldsTests: XCTestCase {
    func testEnabledNamesALivingHolder() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: 62279, liveness: .alive),
            " holder-pid=62279 holder=alive"
        )
    }

    /// The case that cost a login session on 2026-09-02: the count outlived its
    /// holder, so quitting applications and re-locking the screen were both
    /// hopeless. The log has to make that distinguishable at a glance.
    func testEnabledMarksAHolderThatHasExited() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: 62279, liveness: .gone),
            " holder-pid=62279 holder=gone"
        )
    }

    func testEnabledWithoutAReadablePIDSaysUnknown() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: nil, liveness: .unknown),
            " holder=unknown"
        )
    }

    /// A PID that cannot be classified is worth no more than no PID at all:
    /// reporting a number beside `holder=unknown` would invite acting on it.
    func testEnabledSuppressesThePIDWhenLivenessIsUnknown() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: 62279, liveness: .unknown),
            " holder=unknown"
        )
    }

    func testDisabledReportsHeldSecondsToOneDecimal() {
        XCTAssertEqual(
            SecureInputLogFields.disabledFields(heldSeconds: 1491.55, sinceLaunch: false),
            " held-seconds=1491.6"
        )
    }

    /// The benign case. A password field measured 0.4 s on this machine, and it
    /// has to stay readable next to the four-digit pathological one.
    func testDisabledKeepsSubSecondEpisodesLegible() {
        XCTAssertEqual(
            SecureInputLogFields.disabledFields(heldSeconds: 0.38, sinceLaunch: false),
            " held-seconds=0.4"
        )
    }

    func testDisabledMarksADurationThatIsOnlyALowerBound() {
        XCTAssertEqual(
            SecureInputLogFields.disabledFields(heldSeconds: 12.0, sinceLaunch: true),
            " held-seconds=12.0 since=launch"
        )
    }

    /// Launching into an already-open gate is the normal case, and it must not
    /// invent a duration it never measured.
    func testDisabledOmitsDurationWhenTheRisingEdgeWasNeverSeen() {
        XCTAssertEqual(
            SecureInputLogFields.disabledFields(heldSeconds: nil, sinceLaunch: false),
            ""
        )
        XCTAssertEqual(
            SecureInputLogFields.disabledFields(heldSeconds: nil, sinceLaunch: true),
            ""
        )
    }

    /// Every field is a number or a fixed keyword. Nothing here can carry a
    /// keystroke, a process name, or a path — see `AGENTS.md` on what may be
    /// logged.
    func testEveryProducedFieldIsNumbersAndKeywordsOnly() {
        let produced = SecureInputHolderLiveness.allCases.map {
            SecureInputLogFields.enabledFields(holderPID: 4321, liveness: $0)
        } + [
            SecureInputLogFields.disabledFields(heldSeconds: 3.25, sinceLaunch: true),
            SecureInputLogFields.disabledFields(heldSeconds: 3.25, sinceLaunch: false),
        ]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-=. ")
        for field in produced {
            XCTAssertTrue(
                field.unicodeScalars.allSatisfy(allowed.contains),
                "unexpected characters in \(field)"
            )
        }
    }
}
