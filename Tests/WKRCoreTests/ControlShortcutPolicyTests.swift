import XCTest
@testable import WKRCore

final class ControlShortcutPolicyTests: XCTestCase {
    func testRomanTransliterationShortcutsDoNotCompletePendingKana() {
        for key in [PhysicalKey.l, .semicolon] {
            XCTAssertEqual(
                ControlShortcutPolicy.pendingAction(for: key),
                .transliterateRoman,
                key.rawValue
            )
        }
    }

    func testKanaAndUnknownControlShortcutsKeepCompletingPendingKana() {
        for key in [PhysicalKey.a, .colon, .j, .k, .o, .p, .t, .u, .i, .b, nil] {
            XCTAssertEqual(
                ControlShortcutPolicy.pendingAction(for: key),
                .completeKana,
                key?.rawValue ?? "unknown"
            )
        }
    }

    func testShiftedControlShortcutsKeepThePreviousCompletionBehaviour() {
        for key in [PhysicalKey.l, .semicolon] {
            XCTAssertEqual(
                ControlShortcutPolicy.pendingAction(for: key, isShifted: true),
                .completeKana,
                key.rawValue
            )
        }
    }
}
