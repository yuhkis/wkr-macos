import XCTest
@testable import WKRCore

final class IOTrialTests: XCTestCase {
    func testEveryKanaRowMovesItsIAndOColumnsTogether() {
        let rows: [(PhysicalKey, String, String)] = [
            (.e, "きょ", "きゅ"), (.s, "しょ", "しゅ"), (.f, "ちょ", "ちゅ"),
            (.d, "にょ", "にゅ"), (.g, "ひょ", "ひゅ"), (.v, "みょ", "みゅ"),
            (.r, "りょ", "りゅ"), (.w, "うぉ", "ゑ"), (.a, "ぎょ", "ぎゅ"),
            (.z, "じょ", "じゅ"), (.c, "どぅ", "でゅ"), (.b, "びょ", "びゅ"),
            (.t, "ぴょ", "ぴゅ"), (.x, "とぅ", "てゅ"),
        ]
        for (root, iKana, oKana) in rows {
            XCTAssertEqual(WKRLayout.rules.first { $0.input == [root, .i] }?.kana, iKana, root.rawValue)
            XCTAssertEqual(WKRLayout.rules.first { $0.input == [root, .o] }?.kana, oKana, root.rawValue)
        }
    }

    func testSingleSmallAndContractedKanaInBothCommonModes() {
        let cases: [([PhysicalKey], String)] = [
            ([.m], "nn"), ([.n], "ltu"), ([.e, .m], "kann"), ([.e, .n], "kaltu"),
            ([.i], "yo"), ([.o], "yu"), ([.e, .i], "kyo"), ([.e, .o], "kyu"),
            ([.q, .i], "lyo"), ([.q, .o], "lyu"), ([.i, .o], "yoyu"),
        ]
        for mode in [OutputMode.deferredRomaji, .prefixRomaji] {
            for (keys, expected) in cases {
                let engine = WKRTransducer(mode: mode)
                var actions = keys.flatMap { engine.process(.physical($0)).actions }
                actions += engine.process(.boundary(.enter)).actions
                let romaji = actions.compactMap { action -> String? in
                    if case .romaji(let text) = action { return text }
                    return nil
                }.joined()
                XCTAssertEqual(romaji, expected)
                XCTAssertFalse(engine.hasPendingInput)
            }
        }
    }

    func testSymbolSelectorsStayWhilePrefixAndLongVowelMove() {
        for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
            XCTAssertEqual(rules.first { $0.input == [.y] }?.action, .romaji("-"))
            XCTAssertEqual(rules.first { $0.input == [.p, .j] }?.action, .romaji("zj"))
            XCTAssertEqual(rules.first { $0.input == [.s, .p] }?.kana, "しぇ")
        }
        XCTAssertEqual(WKRLayout.rules.first { $0.input == [.p, .i] }?.kana, "【")
        XCTAssertEqual(WKRLayout.rules.first { $0.input == [.p, .o] }?.kana, "】")
        XCTAssertEqual(WKRLayout.rules.first { $0.input == [.p, .y] }?.kana, "〒")
        XCTAssertEqual(WKRLayout.rules.first { $0.input == [.p, .p] }?.kana, "～")
        XCTAssertEqual(WKRLayout.rules.first { $0.input == [.p, .n] }?.kana, "′")
        XCTAssertEqual(WKRLayout.rules.first { $0.input == [.p, .m] }?.kana, "″")
    }


}
