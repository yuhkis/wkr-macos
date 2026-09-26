import XCTest
@testable import WKRCore

/// beta.14: the だ row and the `X` row carry the で and て loanword kana on the
/// same keys, and the special column changes the kana after every row.
/// beta.15 gave the slots that held unwritten kana to common sequences, and
/// beta.16 gathered every sequence on the special column.
final class LoanwordColumnsTrialTests: XCTestCase {
    private let beta13 = "wkr-layout@03cba20+ga-pa-small-io-yp-y-slash-question-swap-long-question-nm-swap-wp-vi-qw-small-wa"
    private let rows: [PhysicalKey] = [.e, .s, .f, .d, .g, .v, .r, .w, .a, .z, .c, .b, .t, .x]

    private func actions(typing keys: [PhysicalKey], mode: OutputMode) -> [SyntheticAction] {
        let engine = WKRTransducer(mode: mode)
        var actions = keys.flatMap { engine.process(.physical($0)).actions }
        actions += engine.process(.boundary(.enter)).actions
        XCTAssertFalse(engine.hasPendingInput)
        return actions
    }

    private func onScreen(_ actions: [SyntheticAction]) -> String {
        var buffer = ""
        for action in actions {
            switch action {
            case let .romaji(value): buffer += value
            case let .unicode(value): buffer += value
            case let .backspace(count): buffer.removeLast(count)
            }
        }
        return buffer
    }

    private func rule(_ keys: [PhysicalKey]) -> NormalizedRule? {
        WKRLayout.rules.first { $0.input == keys }
    }

    /// The rule the layout is read by: after a consonant key, `U` `I` `O` and
    /// `P` always give a kana of their own. No row leaves one of them to mean
    /// the bare kana followed by や よ ゆ or by the symbol prefix.
    func testEveryConsonantRowChangesTheKanaOnAllFourColumns() {
        for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
            for row in rows {
                let root = rules.first { $0.input == [row] }?.kana
                XCTAssertNotNil(root, row.rawValue)
                for column in [PhysicalKey.u, .i, .o, .p] {
                    let kana = rules.first { $0.input == [row, column] }?.kana
                    XCTAssertNotNil(kana, "\(row.rawValue)+\(column.rawValue)")
                    XCTAssertNotEqual(kana, root, "\(row.rawValue)+\(column.rawValue)")
                }
            }
        }
    }

    func testTheDaRowAndTheXRowAreTwinsOnTheSameKeys() {
        let twins: [(PhysicalKey, String, String, String, String)] = [
            (.u, "でぃ", "deli", "てぃ", "teli"), (.o, "でゅ", "delyu", "てゅ", "telyu"),
            (.i, "どぅ", "dolu", "とぅ", "tolu"),
            // Neither row has a ぇ kana for the special column, so it gives the
            // commonest sequence of each family: で then す, and し then て.
            (.p, "です", "desu", "して", "site"),
        ]
        for (key, voiced, voicedRomaji, plain, plainRomaji) in twins {
            XCTAssertEqual(rule([.c, key])?.kana, voiced)
            XCTAssertEqual(rule([.c, key])?.action, .romaji(voicedRomaji))
            XCTAssertEqual(rule([.x, key])?.kana, plain)
            XCTAssertEqual(rule([.x, key])?.action, .romaji(plainRomaji))
        }
        // でぃ used to be on `XI` as well as `CP`. Each kana has one home now.
        for kana in ["でぃ", "てぃ", "でゅ", "てゅ", "どぅ", "とぅ"] {
            XCTAssertEqual(WKRLayout.rules.filter { $0.kana == kana }.count, 1, kana)
        }
        // The ふぁ row itself is untouched.
        XCTAssertEqual(rule([.x])?.kana, "ふぁ")
        XCTAssertEqual(rule([.x, .j])?.kana, "ふゅ")
    }

    /// Rows with a ぇ loanword kana keep it on the special column; the others
    /// give a common pair of kana that begins with the row's own. Until
    /// beta.17 that was the row's あい wherever nothing stood out; beta.18
    /// tries the pair that looks most useful for each row.
    func testRowsWithoutALoanwordKanaGiveACommonPair() {
        let cases: [(PhysicalKey, String, String)] = [
            (.d, "ので", "node"), (.g, "はい", "hai"), (.v, "ます", "masu"),
            (.r, "れる", "reru"), (.b, "ぶん", "bunn"), (.t, "ぷろ", "puro"), (.a, "がい", "gai"),
            (.c, "です", "desu"), (.e, "こと", "koto"), (.w, "わけ", "wake"),
        ]
        // Every pair begins with its row's kana and is exactly two kana units.
        for (row, kana, _) in cases {
            let rowKana = Set(WKRLayout.rules.filter { $0.input.first == row && $0.input.count <= 2 && $0.kana.count == 1 }.map(\.kana))
            XCTAssertEqual(kana.count, 2, kana)
            XCTAssertTrue(rowKana.contains(String(kana.prefix(1))), kana)
        }
        for (row, kana) in [(PhysicalKey.s, "しぇ"), (.f, "ちぇ"), (.z, "じぇ"), (.x, "して")] {
            XCTAssertEqual(rule([row, .p])?.kana, kana)
        }
        for mode in [OutputMode.deferredRomaji, .prefixRomaji] {
            for (row, kana, romaji) in cases {
                XCTAssertEqual(rule([row, .p])?.kana, kana)
                let sent = actions(typing: [row, .p], mode: mode)
                XCTAssertEqual(onScreen(sent), romaji)
                // They spell with the row's own letter, so nothing is taken back.
                XCTAssertFalse(sent.contains { if case .backspace = $0 { return true }; return false }, kana)
            }
        }
    }

    /// `C` streams `d` and all four loanword kana continue it; `X` streams `f`
    /// for ふぁ, so its four て kana pay the one Backspace they always paid.
    func testPrefixModeCostsAreUnchanged() {
        for key in [PhysicalKey.u, .i, .o, .p] {
            let voiced = actions(typing: [.c, key], mode: .prefixRomaji)
            XCTAssertEqual(voiced.first, .romaji("d"))
            XCTAssertFalse(voiced.contains { if case .backspace = $0 { return true }; return false })
            let plain = actions(typing: [.x, key], mode: .prefixRomaji)
            XCTAssertEqual(Array(plain.prefix(2)), [.romaji("f"), .backspace(count: 1)])
        }
    }

    func testDisplacedSequencesStayTypable() {
        let cases: [([PhysicalKey], String)] = [
            // ぢゃ ぢゅ ぢょ: the base kana and a prefixed small kana.
            ([.c, .k, .q, .u], "dilya"), ([.c, .k, .q, .o], "dilyu"), ([.c, .k, .q, .i], "dilyo"),
            // A bare あ-column kana before the symbol prefix or before や よ ゆ
            // takes its vowel explicitly, in every row alike.
            ([.d, .h, .p, .l], "nazl"), ([.c, .h, .i], "dayo"), ([.v, .h, .p, .l], "mazl"),
            // ー っ ん are not columns, so the bare kana still takes them directly.
            ([.d, .y], "na-"), ([.c, .n], "dann"),
            // The sequences a slot now gives can still be spelled out, and まい,
            // which ます displaced, is the vowel spelled out like かい.
            ([.d, .h, .k], "nai"), ([.c, .semicolon, .s, .j], "desu"), ([.s, .k, .f, .semicolon], "shite"),
            ([.v, .h, .k], "mai"), ([.e, .h, .k], "kai"), ([.v, .s, .j], "masu"),
            // でょ てょ and the six ぇ kana are the base kana and a prefixed small kana.
            ([.c, .semicolon, .q, .i], "delyo"), ([.d, .k, .q, .semicolon], "nile"),
        ]
        for mode in [OutputMode.deferredRomaji, .prefixRomaji] {
            for (keys, expected) in cases {
                XCTAssertEqual(onScreen(actions(typing: keys, mode: mode)), expected)
            }
        }
    }

    /// Days counted under beta.13 keep the three tooltips they were counted
    /// under: だ行 with ぢゃ, ふぁ行 with てぃ でゅ でぃ, and ■ without the new kana.


    /// Legacy beta.14 identifiers preserve the old role labels. The current
    /// table names sequences from the canonical rules without rewriting them.

}
