import XCTest
@testable import WKRCore

final class WakaraKeyLegendTests: XCTestCase {
    /// The upstream README's core ten-column diagram, less the three `IME通過`
    /// keys: wkr-layout README.md at `e81658c97b613c0e9d269d58bc960c38093a1b50`
    /// (2026-08-31), read 2026-09-11. That README is newer than the rule pin
    /// `WKRLayout.sourceRevision` (`03cba20`), but only README.md changed in
    /// between, and the pinned README's older 配列図 draws the same 27 names.
    /// The legends are derived from the rules rather than copied from here, so
    /// this is the check that the derivation reads the rules the way upstream
    /// names them. `q` and `a` are swapped here ahead of the upstream ver 2.0
    /// revision of that diagram (trial of the が行 / ぱ行 swap).
    private let upstreamCoreDiagram: [String: String] = [
        "q": "ぱ行", "w": "わ行", "e": "か行", "r": "ら行", "t": "□",
        "y": "■", "u": "や", "i": "ゆ", "o": "よ", "p": "ー",
        "a": "が行", "s": "さ行", "d": "な行", "f": "た行", "g": "は行",
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

    /// A key that begins a rule but has no legend would be the one key the
    /// わから配列 mode silently leaves engraved. The derivation drops a key only
    /// when it lacks a code or, for a prefix, a name, so this catches both.
    func testEveryKeyThatBeginsARuleHasALegend() {
        let firstKeys = Set(WKRLayout.rules.compactMap(\.input.first).map(\.rawValue))
        XCTAssertEqual(Set(WakaraKeyLegends.all.map(\.key)), firstKeys)
    }

    /// `--symbol-layer off` takes the 55 `Y` symbol rules away but leaves the
    /// arrows, so `Y` is still a prefix and the picture must not change.
    func testTurningTheSymbolLayerOffKeepsEveryLegend() {
        XCTAssertEqual(WakaraKeyLegends.derive(from: WKRLayout.rulesWithoutSymbolLayer), WakaraKeyLegends.all)
    }

    func testPassThroughKeysKeepTheirEngraving() {
        let codes = Set(WakaraKeyLegends.all.map(\.keyCode))
        // `,` `.` `/`, which the upstream core diagram (README `e81658c`) marks IME通過.
        XCTAssertTrue(codes.isDisjoint(with: [0x2B, 0x2F, 0x2C]))
    }

    func testKeyCodesAreUnique() {
        let codes = WakaraKeyLegends.all.map(\.keyCode)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    /// The key code table is a literal copy of Carbon's values. Holding it to
    /// both staggered drawings means a transposed pair (G/H, 5/6 — `Events.h`
    /// has both) would put the か行 label on the wrong cap and fail here first.
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

    /// The Corne boards get their codes from the Vial decoder, not from the
    /// staggered drawings, so the table has to agree with that path too.
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

    /// `X` is named ふぁ行, but its `U` `I` `O` give てぃ でゅ でぃ — upstream's
    /// "ふぁ行 / 外来語". A sentence saying the row's vowel keys give ふぁ行 kana
    /// was false for exactly those three, which is why the details list the
    /// rules' output instead of describing it.
    func testTheFaRowDetailShowsItsLoanwordKana() {
        let x = WakaraKeyLegends.all.first { $0.key == "x" }
        XCTAssertEqual(x?.label, "ふぁ行")
        XCTAssertEqual(x?.detail, "子音キー。単打で「ふぁ」、続く母音キーで ふぁ ふぃ ふゅ ふぇ ふぉ てぃ でゅ でぃ")
    }

    /// `Y` opens the symbol layer and is also the 特殊 column after a consonant
    /// key. Both kinds of press are on the ■ cap, so the tooltip names both;
    /// `T` is never a second key after a row and keeps its sentence as written.
    func testPrefixDetailsIncludeTheColumnRoleOnlyWhereItExists() {
        let byKey = Dictionary(uniqueKeysWithValues: WakaraKeyLegends.all.map { ($0.key, $0) })
        XCTAssertEqual(
            byKey["y"]?.detail,
            (WakaraKeyLegends.prefixLegends[.y]?.detail ?? "") + "。子音キーの後では ヶ しぇ ちぇ ゎ ヵ じぇ でぃ てゅ"
        )
        XCTAssertEqual(byKey["t"]?.detail, WakaraKeyLegends.prefixLegends[.t]?.detail)
    }
}
