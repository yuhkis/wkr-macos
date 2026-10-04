import XCTest
@testable import WKRCore

final class IOTrialTests: XCTestCase {
    func testEveryKanaRowMovesItsIAndOColumnsTogether() {
        let rows: [(PhysicalKey, String, String)] = [
            (.e, "きょ", "きゅ"), (.s, "しょ", "しゅ"), (.d, "ちょ", "ちゅ"),
            (.f, "にょ", "にゅ"), (.g, "ひょ", "ひゅ"), (.v, "みょ", "みゅ"),
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
            ([.m], "nn"), ([.u], "ltu"), ([.e, .m], "kann"), ([.e, .u], "kaltu"), ([.n], "ye"), ([.e, .n], "kye"),
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

    func testPIsTheYaColumnAndThePublishedTableHasNoSymbolLayer() {
        for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
            XCTAssertEqual(rules.first { $0.input == [.y] }?.action, .romaji("-"))
            XCTAssertEqual(rules.first { $0.input == [.p] }?.kana, "や")
            XCTAssertEqual(rules.first { $0.input == [.s, .p] }?.kana, "しゃ")
            XCTAssertEqual(rules.first { $0.input == [.s, .n] }?.kana, "しぇ")
            XCTAssertFalse(rules.contains { $0.input.first == .p && $0.input.count > 1 })
            XCTAssertTrue(rules.allSatisfy { if case .romaji = $0.action { return true }; return false })
        }
    }
}
