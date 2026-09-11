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

    func testPayloadCarriesTheWakaraLegendsAndTheirRevision() throws {
        let payload = try Self.payload(of: KeyFrequencyReportRenderer.html(
            store: .empty,
            geometries: [.jis],
            generatedAt: Date(timeIntervalSince1970: 0)
        ))
        let wakara = try XCTUnwrap(payload["wakara"] as? [String: Any])
        XCTAssertEqual(wakara["sourceRevision"] as? String, WKRLayout.sourceRevision)

        let legends = try XCTUnwrap(wakara["legends"] as? [[String: Any]])
        XCTAssertEqual(legends.count, WakaraKeyLegends.all.count)
        let e = try XCTUnwrap(legends.first { $0["key"] as? String == "e" })
        XCTAssertEqual(e["keyCode"] as? Int, 0x0E)
        XCTAssertEqual(e["label"] as? String, "か行")
        XCTAssertEqual(e["role"] as? String, "consonantRow")
    }

    /// The switch is part of the page's own chrome, so a report written by an
    /// older build and one written now differ only in what the payload offers.
    func testPageOffersBothLegendModes() {
        let html = KeyFrequencyReportRenderer.html(
            store: .empty,
            geometries: [.jis],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(html.contains(#"data-legend="print""#))
        XCTAssertTrue(html.contains(#"data-legend="wakara""#))
        XCTAssertTrue(html.contains(#"id="legend-note""#))
    }

    /// Without legends the page must still render, with the わから配列 button
    /// disabled rather than switching to a mode that would relabel nothing.
    func testAnEmptyLegendTableStillProducesAParseablePayload() throws {
        let html = KeyFrequencyReportRenderer.html(
            store: .empty,
            geometries: [.jis],
            generatedAt: Date(timeIntervalSince1970: 0),
            wakaraLegends: []
        )
        let wakara = try XCTUnwrap(try Self.payload(of: html)["wakara"] as? [String: Any])
        XCTAssertEqual((wakara["legends"] as? [Any])?.count, 0)
        // The page, not the payload, keeps the viewer out of an empty mode: the
        // button is disabled and a remembered choice is not restored.
        XCTAssertTrue(html.contains("button.dataset.legend === 'wakara' && !wakaraKeyCount"))
        XCTAssertTrue(html.contains("legend === 'print' || (legend === 'wakara' && wakaraKeyCount)"))
    }

    func testReportStaysDeterministicWithTheLegends() {
        let make = {
            KeyFrequencyReportRenderer.html(
                store: .empty,
                geometries: KeyboardGeometry.allBuiltIn,
                generatedAt: Date(timeIntervalSince1970: 0),
                calendar: Calendar(identifier: .gregorian)
            )
        }
        XCTAssertEqual(make(), make())
    }

    private static func payload(of html: String) throws -> [String: Any] {
        let open = #"<script type="application/json" id="report-data">"#
        let start = try XCTUnwrap(html.range(of: open))
        let end = try XCTUnwrap(html.range(of: "</script>", range: start.upperBound..<html.endIndex))
        let json = String(html[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "<\\/", with: "</")
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }
}
