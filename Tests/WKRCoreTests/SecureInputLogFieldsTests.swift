import XCTest
@testable import WKRCore

// PID and durations below are synthetic fixtures, not live diagnostics.
final class SecureInputLogFieldsTests: XCTestCase {
    func testEnabledNamesALivingHolder() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: 4242, liveness: .alive),
            " holder-pid=4242 holder=alive"
        )
    }

    /// A departed holder remains distinct from a living or unreadable holder.
    func testEnabledMarksAHolderThatHasExited() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: 4242, liveness: .gone),
            " holder-pid=4242 holder=gone"
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
            SecureInputLogFields.enabledFields(holderPID: 4242, liveness: .unknown),
            " holder=unknown"
        )
    }

    func testDisabledReportsHeldSecondsToOneDecimal() {
        XCTAssertEqual(
            SecureInputLogFields.disabledFields(heldSeconds: 1491.55, sinceLaunch: false),
            " held-seconds=1491.6"
        )
    }

    /// The benign case. A synthetic short episode must remain readable; it
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
