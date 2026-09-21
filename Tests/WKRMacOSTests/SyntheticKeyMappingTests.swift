import XCTest
import Carbon.HIToolbox
import WKRCore
@testable import WKRMacOS

final class SyntheticKeyMappingTests: XCTestCase {
    func testEveryRomajiRuleCanBePostedIncludingRelocatedPunctuation() {
        for rule in WKRLayout.rules {
            if case .romaji(let value) = rule.action {
                for character in value {
                    XCTAssertNotNil(SyntheticEventPoster.keyCodes[character], rule.id)
                }
            }
        }
        XCTAssertEqual(SyntheticEventPoster.keyCodes["/"], UInt16(kVK_ANSI_Slash))
        XCTAssertEqual(SyntheticEventPoster.keyCodes["-"], UInt16(kVK_ANSI_Minus))
    }
}

extension SyntheticKeyMappingTests {
    func testQuestionMarkUsesShiftAndMiddleDotDoesNot() throws {
        let poster = try XCTUnwrap(SyntheticEventPoster())
        let events = try XCTUnwrap(poster.makeEvents(for: [.romaji("?/")]))
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map { $0.flags.contains(.maskShift) }, [true, true, false, false])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_Slash) })
        XCTAssertEqual(EventTapController.physicalKey(for: UInt16(kVK_ANSI_Slash), shifted: true), .shiftedSlash)
        XCTAssertEqual(EventTapController.physicalKey(for: UInt16(kVK_ANSI_Slash), shifted: false), .slash)
        XCTAssertNil(EventTapController.physicalKey(for: UInt16(kVK_ANSI_Y), shifted: true))
    }
}
