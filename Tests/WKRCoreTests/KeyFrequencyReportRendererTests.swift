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

    /// Days carry the table they were counted under, and the payload carries a
    /// legend table for each one the page may meet, so a day counted under an
    /// earlier layout is not relabelled with today's names.
    func testPayloadNamesTheTableEachDayWasCountedUnder() throws {
        let store = KeyFrequencyStore(days: [
            .init(date: "2026-09-11", entries: [.init(keyCode: 0x0C, isShifted: false, count: 5)], layouts: ["old"]),
            .init(date: "2026-09-12", entries: [.init(keyCode: 0x0C, isShifted: false, count: 5)], layouts: ["old", "new"]),
        ])
        let oldLegends = [WakaraKeyLegend(keyCode: 0x0C, key: "q", label: "が行", role: .consonantRow, detail: "")]
        let html = KeyFrequencyReportRenderer.html(
            store: store,
            geometries: [.jis],
            generatedAt: Date(timeIntervalSince1970: 0),
            layoutIdentifier: "new",
            historicalLegends: ["old": oldLegends]
        )
        let payload = try Self.payload(of: html)
        let wakara = try XCTUnwrap(payload["wakara"] as? [String: Any])
        XCTAssertEqual(wakara["layout"] as? String, "new")
        XCTAssertEqual(wakara["legacyLayout"] as? String, KeyFrequencyStore.layoutBeforeMarking)
        let tables = try XCTUnwrap(wakara["legendsByLayout"] as? [String: [[String: Any]]])
        XCTAssertEqual(Set(tables.keys), ["old", "new"])
        XCTAssertEqual(tables["old"]?.first?["label"] as? String, "が行")
        XCTAssertEqual(tables["new"]?.count, WakaraKeyLegends.all.count)

        let days = try XCTUnwrap((payload["store"] as? [String: Any])?["days"] as? [[String: Any]])
        XCTAssertEqual(days.map { $0["layouts"] as? [String] }, [["old"], ["old", "new"]])

        // The window that starts where the newest table did, and the note that
        // flags the day both tables wrote.
        XCTAssertTrue(html.contains(#"data-period="since""#))
        XCTAssertTrue(html.contains("は配列の切替日で、前後の打鍵が混ざります"))
    }

    /// By default the payload names the live table, plus the ver 1.1 core it
    /// replaced, so days counted before the が行 / ぱ行 swap keep their names.
    func testPayloadDefaultsToTheLiveTableAndTheOneItReplaced() throws {
        let wakara = try XCTUnwrap(try Self.payload(of: KeyFrequencyReportRenderer.html(
            store: .empty, geometries: [.jis], generatedAt: Date(timeIntervalSince1970: 0)
        ))["wakara"] as? [String: Any])
        XCTAssertEqual(wakara["layout"] as? String, "wkr-layout@03cba20+ga-pa-swap")
        let tables = try XCTUnwrap(wakara["legendsByLayout"] as? [String: [[String: Any]]])
        XCTAssertEqual(Set(tables.keys), ["wkr-layout@03cba20+ga-pa-swap", "wkr-layout@03cba20"])
        XCTAssertEqual(tables["wkr-layout@03cba20"]?.first { $0["key"] as? String == "q" }?["label"] as? String, "が行")
        XCTAssertEqual(tables["wkr-layout@03cba20"]?.first { $0["key"] as? String == "a" }?["label"] as? String, "ぱ行")
        XCTAssertEqual(tables["wkr-layout@03cba20+ga-pa-swap"]?.first { $0["key"] as? String == "a" }?["label"] as? String, "が行")
    }

    /// More than one tally can exist once a layout change has archived the
    /// earlier one, so a saved or forwarded page has to say which it is drawn
    /// from. The name only: the directory above it carries a home folder and
    /// often an account name.
    func testHeaderNamesTheTallyItWasDrawnFrom() {
        let html = KeyFrequencyReportRenderer.html(
            store: .empty,
            geometries: [.jis],
            generatedAt: Date(timeIntervalSince1970: 0),
            sourceFileName: "key-frequency-2026-08-28_2026-09-12.json"
        )
        XCTAssertTrue(html.contains("<dt>集計ファイル</dt>"))
        XCTAssertTrue(html.contains("key-frequency-2026-08-28_2026-09-12.json"))

        // Nothing is added when there is nothing to name, so a page rendered
        // without one is the page it always was.
        let unnamed = KeyFrequencyReportRenderer.html(
            store: .empty,
            geometries: [.jis],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertFalse(unnamed.contains("集計ファイル"))
    }

    /// A file name reaches the page as text, not as markup.
    func testTheTallyNameIsEscaped() {
        let html = KeyFrequencyReportRenderer.html(
            store: .empty,
            geometries: [.jis],
            generatedAt: Date(timeIntervalSince1970: 0),
            sourceFileName: "<script>x</script>.json"
        )
        XCTAssertFalse(html.contains("<script>x</script>.json"))
        XCTAssertTrue(html.contains("&lt;script&gt;x&lt;/script&gt;.json"))
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
