import XCTest
@testable import WKRCore

final class WakaraKeyLegendTests: XCTestCase {
    private let upstreamCoreDiagram: [String: String] = [
        "q": "が行", "w": "わ行", "e": "か行", "r": "ら行", "t": "□",
        "y": "■", "u": "や", "i": "ゆ", "o": "よ", "p": "ー",
        "a": "ぱ行", "s": "さ行", "d": "な行", "f": "た行", "g": "は行",
        "h": "あ", "j": "う", "k": "い", "l": "お", ";": "え",
        "z": "ざ行", "x": "ふぁ行", "c": "だ行", "v": "ま行", "b": "ば行",
        "n": "ん", "m": "っ",
    ]

    func testLegendsMatchTheUpstreamCoreDiagram() {
        let labels = Dictionary(
            uniqueKeysWithValues: WakaraKeyLegends.all.map { ($0.key, $0.label) }
        )
        XCTAssertEqual(labels, upstreamCoreDiagram)
    }

    func testRolesFollowTheTwoStrokeScheme() {
        let byRole = Dictionary(grouping: WakaraKeyLegends.all, by: \.role)
            .mapValues { Set($0.map(\.key)) }
        XCTAssertEqual(
            byRole[.consonantRow],
            ["q", "w", "e", "r", "a", "s", "d", "f", "g", "z", "x", "c", "v", "b"]
        )
        XCTAssertEqual(byRole[.vowel], ["h", "k", "j", ";", "l", "u", "i", "o"])
        XCTAssertEqual(byRole[.single], ["n", "m", "p"])
        XCTAssertEqual(byRole[.prefix], ["t", "y"])
    }

    func testEveryKeyThatBeginsARuleHasALegend() {
        let firstKeys = Set(WKRLayout.rules.compactMap(\.input.first).map(\.rawValue))
        XCTAssertEqual(Set(WakaraKeyLegends.all.map(\.key)), firstKeys)
    }

    func testTurningTheSymbolLayerOffKeepsEveryLegend() {
        XCTAssertEqual(WakaraKeyLegends.derive(from: WKRLayout.rulesWithoutSymbolLayer), WakaraKeyLegends.all)
    }

    func testPassThroughKeysKeepTheirEngraving() {
        let codes = Set(WakaraKeyLegends.all.map(\.keyCode))
        XCTAssertTrue(codes.isDisjoint(with: [0x2B, 0x2F, 0x2C]))
    }

    func testKeyCodesAreUnique() {
        let codes = WakaraKeyLegends.all.map(\.keyCode)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testKeyCodesLandOnTheSameCapInTheStaggeredDrawings() {
        for geometry in [KeyboardGeometry.jis, .us] {
            for legend in WakaraKeyLegends.all {
                let caps = geometry.caps.filter {
                    $0.identities.contains(KeyIdentity(keyCode: legend.keyCode, isShifted: false))
                }
                XCTAssertEqual(caps.count, 1, "\(geometry.model) \(legend.key)")
                XCTAssertEqual(
                    caps.first?.legend.primary.lowercased(), legend.key,
                    "\(geometry.model) \(legend.key)"
                )
            }
        }
    }

    func testKeyCodesAgreeWithTheVialDecoder() {
        for legend in WakaraKeyLegends.all {
            let token = legend.key == ";" ? "KC_SCOLON" : "KC_" + legend.key.uppercased()
            XCTAssertEqual(
                VialKeymap.decode(token: token).identity,
                KeyIdentity(keyCode: legend.keyCode, isShifted: false),
                token
            )
        }
    }

    func testDetailsNameTheKanaTheKeyProduces() {
        let byKey = Dictionary(uniqueKeysWithValues: WakaraKeyLegends.all.map { ($0.key, $0) })
        XCTAssertEqual(byKey["e"]?.detail, "子音キー。単打で「か」、続く母音キーで か き く け こ きゃ きゅ きょ")
        XCTAssertEqual(byKey["h"]?.detail, "母音キー。単打で「あ」、子音キーの後では段を選ぶ")
        XCTAssertEqual(byKey["n"]?.detail, "単打キー。単打で「ん」")
    }

    func testTheFaRowDetailShowsItsLoanwordKana() {
        let x = WakaraKeyLegends.all.first { $0.key == "x" }
        XCTAssertEqual(x?.label, "ふぁ行")
        XCTAssertEqual(x?.detail, "子音キー。単打で「ふぁ」、続く母音キーで ふぁ ふぃ ふゅ ふぇ ふぉ てぃ でゅ でぃ")
    }

    func testPrefixDetailsIncludeTheColumnRoleOnlyWhereItExists() {
        let byKey = Dictionary(uniqueKeysWithValues: WakaraKeyLegends.all.map { ($0.key, $0) })
        XCTAssertEqual(
            byKey["y"]?.detail,
            (WakaraKeyLegends.prefixLegends[.y]?.detail ?? "") + "。子音キーの後では ヶ しぇ ちぇ ゎ ヵ じぇ でぃ てゅ"
        )
        XCTAssertEqual(byKey["t"]?.detail, WakaraKeyLegends.prefixLegends[.t]?.detail)
    }
}
