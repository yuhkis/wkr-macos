import XCTest
@testable import WKRCore

final class SecureInputLogFieldsTests: XCTestCase {
    func testEnabledNamesALivingHolder() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: 4321, liveness: .alive),
            " holder-pid=4321 holder=alive"
        )
    }

    func testEnabledMarksAHolderThatHasExited() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: 4321, liveness: .gone),
            " holder-pid=4321 holder=gone"
        )
    }

    func testEnabledWithoutAReadablePIDSaysUnknown() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: nil, liveness: .unknown),
            " holder=unknown"
        )
    }

    func testEnabledSuppressesThePIDWhenLivenessIsUnknown() {
        XCTAssertEqual(
            SecureInputLogFields.enabledFields(holderPID: 4321, liveness: .unknown),
            " holder=unknown"
        )
    }

    func testDisabledReportsHeldSecondsToOneDecimal() {
        XCTAssertEqual(
            SecureInputLogFields.disabledFields(heldSeconds: 1491.55, sinceLaunch: false),
            " held-seconds=1491.6"
        )
    }

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
