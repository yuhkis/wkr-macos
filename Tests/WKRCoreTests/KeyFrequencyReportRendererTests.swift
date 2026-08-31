import XCTest
@testable import WKRCore

final class KeyFrequencyReportRendererTests: XCTestCase {
    func testBoardActionsExposeTapHoldAndExclusionDetailsToAssistiveTechnology() {
        let html = KeyFrequencyReportRenderer.html(
            store: KeyFrequencyStore(schemaVersion: KeyFrequencyStore.currentSchemaVersion, days: []),
            geometries: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(html.contains("role: 'group'"))
        XCTAssertTrue(html.contains("role: 'img'"))
        XCTAssertTrue(html.contains("DATA.exclusionNames[part.exclusion]"))
        XCTAssertTrue(html.contains("+ (claimed > 1 ? '、同じ合計値を共有' : '') + exclusionNote"))
    }
}
