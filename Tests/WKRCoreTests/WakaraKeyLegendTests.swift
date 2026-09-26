import XCTest
@testable import WKRCore

final class WakaraKeyLegendTests: XCTestCase {
    func testV2RolesAgreeWithCanonicalRoots() {
        let expected = ["q":"ぁ行","w":"わ行","e":"か行","r":"ら行","t":"ぱ行","y":"ー","u":"や","i":"よ","o":"ゆ","p":"■","a":"が行","s":"さ行","d":"な行","f":"た行","g":"は行","h":"あ","j":"う","k":"い","l":"お",";":"え","z":"ざ行","x":"ふぁ行","c":"だ行","v":"ま行","b":"ば行","n":"ん","m":"っ","/":"？"]
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: WakaraKeyLegends.all.map { ($0.key,$0.label) }), expected)
        XCTAssertEqual(Set(WakaraKeyLegends.all.map(\.keyCode)).count, expected.count)
        for legend in WakaraKeyLegends.all {
            XCTAssertTrue(WKRLayout.rules.contains { $0.input.first?.rawValue == legend.key })
        }
    }
    func testCurrentLegendsRoundTripWithoutPrivateHistory() throws {
        let data=try JSONEncoder().encode(WakaraKeyLegends.all)
        XCTAssertEqual(try JSONDecoder().decode([WakaraKeyLegend].self,from:data),WakaraKeyLegends.all)
        XCTAssertTrue(WakaraKeyLegends.historical.isEmpty)
    }
}
