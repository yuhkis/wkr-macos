import XCTest
@testable import WKRCore

final class LoanwordColumnsTrialTests: XCTestCase {
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

    /// Every row has P/I/O variants. N adds the ぇ column except on the W row.
    func testEveryConsonantRowChangesTheKanaOnAllFourColumns() {
        for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
            for row in rows {
                let root = rules.first { $0.input == [row] }?.kana
                XCTAssertNotNil(root, row.rawValue)
                for column in [PhysicalKey.p, .i, .o] {
                    let kana = rules.first { $0.input == [row, column] }?.kana
                    XCTAssertNotNil(kana, "\(row.rawValue)+\(column.rawValue)")
                    XCTAssertNotEqual(kana, root, "\(row.rawValue)+\(column.rawValue)")
                }
                if row == .w {
                    XCTAssertNil(rules.first { $0.input == [row, .n] })
                } else {
                    let ye = rules.first { $0.input == [row, .n] }?.kana
                    XCTAssertNotNil(ye, row.rawValue)
                    XCTAssertTrue(ye?.hasSuffix("ぇ") == true, row.rawValue)
                }
            }
        }
    }

    func testTheDaRowAndTheXRowAreTwinsOnTheSameKeys() {
        let twins: [(PhysicalKey, String, String, String, String)] = [
            (.p, "でぃ", "deli", "てぃ", "teli"), (.o, "でゅ", "delyu", "てゅ", "telyu"),
            (.i, "どぅ", "dolu", "とぅ", "tolu"),
            // N is the ぇ column, with each row's available kana.
            (.n, "ぢぇ", "dye", "ふぇ", "fe"),
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

    /// The P column gives kana, not the old two-kana shortcuts. N gives ぇ.
    func testRowsHaveYaAndYeKanaRatherThanShortcuts() {
        let cases: [(PhysicalKey, String, String)] = [
            (.d, "ちゃ", "tya"), (.f, "にゃ", "nya"), (.g, "ひゃ", "hya"), (.v, "みゃ", "mya"),
            (.r, "りゃ", "rya"), (.b, "びゃ", "bya"), (.t, "ぴゃ", "pya"), (.a, "ぎゃ", "gya"),
            (.c, "でぃ", "deli"), (.e, "きゃ", "kya"), (.w, "ゐ", "wyi"), (.x, "てぃ", "teli"),
            (.s, "しゃ", "sha"), (.z, "じゃ", "zya"),
        ]
        for (row, kana) in [(PhysicalKey.s, "しぇ"), (.d, "ちぇ"), (.f, "にぇ"), (.z, "じぇ"), (.x, "ふぇ")] {
            XCTAssertEqual(rule([row, .n])?.kana, kana)
        }
        for mode in [OutputMode.deferredRomaji, .prefixRomaji] {
            for (row, kana, romaji) in cases {
                XCTAssertEqual(rule([row, .p])?.kana, kana)
                XCTAssertEqual(onScreen(actions(typing: [row, .p], mode: mode)), romaji)
            }
        }
        XCTAssertNil(rule([.w, .n]))
        XCTAssertTrue(WKRLayout.rules.allSatisfy { !["こと", "ので", "はい", "ます", "れる", "わけ", "がい", "ぶん", "ぷろ", "です", "して"].contains($0.kana) })
    }

    /// C keeps its d prefix. X rolls back f for P/I/O, but N keeps f for ふぇ.
    func testPrefixModeCostsAreUnchanged() {
        for key in [PhysicalKey.p, .i, .o] {
            let voiced = actions(typing: [.c, key], mode: .prefixRomaji)
            XCTAssertEqual(voiced.first, .romaji("d"))
            XCTAssertFalse(voiced.contains { if case .backspace = $0 { return true }; return false })
            let plain = actions(typing: [.x, key], mode: .prefixRomaji)
            XCTAssertEqual(Array(plain.prefix(2)), [.romaji("f"), .backspace(count: 1)])
        }
        XCTAssertEqual(actions(typing: [.x, .n], mode: .prefixRomaji), [.romaji("f"), .romaji("e")])
        XCTAssertEqual(actions(typing: [.c, .n], mode: .prefixRomaji), [.romaji("d"), .romaji("ye")])
    }

    func testDisplacedSequencesStayTypable() {
        let cases: [([PhysicalKey], String)] = [
            // ぢゃ ぢゅ ぢょ: the base kana and a prefixed small kana.
            ([.c, .k, .q, .p], "dilya"), ([.c, .k, .q, .o], "dilyu"), ([.c, .k, .q, .i], "dilyo"),
            // A bare あ-column kana before independent や よ ゆ needs H.
            ([.f, .h, .p, .l], "nayao"), ([.c, .h, .i], "dayo"), ([.v, .h, .p, .l], "mayao"),
            // ー っ ん are not columns, so the bare kana still takes them directly.
            ([.f, .y], "na-"), ([.c, .m], "dann"), ([.c, .u], "daltu"),
            // Words formerly covered by shortcuts remain explicit kana sequences.
            ([.f, .h, .k], "nai"), ([.c, .semicolon, .s, .j], "desu"), ([.s, .k, .d, .semicolon], "shite"),
            ([.v, .h, .k], "mai"), ([.e, .h, .k], "kai"), ([.v, .s, .j], "masu"),
            // でょ てょ and the six ぇ kana are the base kana and a prefixed small kana.
            ([.c, .semicolon, .q, .i], "delyo"), ([.f, .k, .q, .semicolon], "nile"),
        ]
        for mode in [OutputMode.deferredRomaji, .prefixRomaji] {
            for (keys, expected) in cases {
                XCTAssertEqual(onScreen(actions(typing: keys, mode: mode)), expected)
            }
        }
    }


}
