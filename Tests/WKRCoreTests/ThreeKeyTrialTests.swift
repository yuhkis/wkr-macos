import XCTest
@testable import WKRCore

/// beta.17: three-key rules, only after ゔ (`WJ`) and ヵ (`QE`), and `EP` かい.
/// beta.18 kept them after ゔ alone: `WJJ` finishes the row, `QE` is final at
/// once, and `WU` `WO` went back to ゐ ゑ. ヶ had no rule for that one build;
/// beta.19 made it the two-key `QP`.
final class ThreeKeyTrialTests: XCTestCase {
    private let beta17 = "wkr-layout@03cba20+ga-pa-small-io-yp-y-slash-question-swap-long-question-nm-swap-wp-vi-qw-small-wa-dt-loanwords-p-column-p-ai-words-w-va-ve-p-words-w-vowels-three-key-vu-ep-kai"
    private let beta16 = "wkr-layout@03cba20+ga-pa-small-io-yp-y-slash-question-swap-long-question-nm-swap-wp-vi-qw-small-wa-dt-loanwords-p-column-p-ai-words-w-va-ve-p-words-w-vowels"
    private let modes: [OutputMode] = [.deferredRomaji, .prefixRomaji, .optimisticRomaji(.fullLayoutExperimental)]

    /// The romaji left in the pre-edit. Optimistic mode takes back a composed
    /// kana with one Backspace, so there the last kana's letters go together.
    private func typed(_ keys: [PhysicalKey], mode: OutputMode, rules: [NormalizedRule] = WKRLayout.rules) -> String {
        let engine = WKRTransducer(mode: mode, rules: rules)
        var actions = keys.flatMap { engine.process(.physical($0)).actions }
        actions += engine.process(.boundary(.enter)).actions
        XCTAssertFalse(engine.hasPendingInput)
        var pieces: [String] = []
        for action in actions {
            switch action {
            case let .romaji(value): pieces.append(value)
            case let .unicode(value): pieces.append(value)
            case let .backspace(count):
                if case .optimisticRomaji = mode {
                    pieces.removeLast(count)
                } else {
                    var joined = pieces.joined(); joined.removeLast(count); pieces = [joined]
                }
            }
        }
        return pieces.joined()
    }

    func testTheVuRowAfterWJInEveryMode() {
        let cases: [([PhysicalKey], String)] = [
            ([.w, .j, .h], "va"), ([.w, .j, .k], "vi"), ([.w, .j, .semicolon], "ve"), ([.w, .j, .l], "vo"),
            ([.w, .j, .u], "vya"), ([.w, .j, .o], "vyu"), ([.w, .j, .i], "vyo"),
            // The row's own う column, finished on the spot, and what follows it.
            ([.w, .j, .j], "vu"), ([.w, .j, .j, .r], "vura"), ([.w, .j, .j, .h], "vua"),
            ([.w, .j, .j, .j], "vuu"), ([.w, .j, .j, .w, .j, .j], "vuvu"),
            // ゔ alone, and ゔ before anything that is not a column key.
            ([.w, .j], "vu"), ([.w, .j, .r], "vura"), ([.w, .j, .m], "vunn"), ([.w, .j, .y], "vu-"),
            // The old way still works: the small kana prefix is not a column key.
            ([.w, .j, .q, .l], "vulo"),
            // The two-key ゔぁ ゔぃ ゔぇ are gone: the row under `WJ` is the one way in.
            ([.w, .u], "wyi"), ([.w, .o], "wye"), ([.w, .p], "wake"),
            // わ then う still needs its あ spelled out, as か then う does.
            ([.w, .h, .j], "wau"),
        ]
        for mode in modes {
            for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
                for (keys, expected) in cases {
                    XCTAssertEqual(typed(keys, mode: mode, rules: rules), expected, "\(keys) \(mode)")
                }
            }
        }
    }

    /// beta.24: `Q` is the key of the small kana row. Alone it is ぁ, a row key
    /// after it completes that ぁ, `QP` is ゎ, and ヵ ヶ have no rule.
    func testQIsARowKeyAndSmallKaKeComeFromConversion() {
        let cases: [([PhysicalKey], String)] = [
            ([.q], "la"), ([.q, .h], "la"), ([.q, .k], "li"), ([.q, .u], "lya"), ([.q, .p], "lwa"),
            ([.q, .w, .e], "lawaka"), ([.q, .e], "laka"), ([.q, .s], "lasa"),
            ([.q, .m], "lann"), ([.q, .n], "laltu"), ([.q, .y], "la-"), ([.q, .q], "lala"),
            // もーつぁると: つ, ぁ, る with no vowel key for the ぁ.
            ([.f, .j, .q, .r, .j], "tularu"),
            // くゎ, and ぁ before an arrow needs its vowel spelled out like any row.
            ([.e, .j, .q, .p], "kulwa"), ([.q, .h, .p, .l], "lazl"),
        ]
        for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
            XCTAssertTrue(rules.allSatisfy { $0.kana != "ヶ" && $0.kana != "ヵ" })
            XCTAssertEqual(rules.filter { $0.kana == "ゎ" }.map(\.input), [[.q, .p]])
            XCTAssertEqual(Set(rules.filter { $0.kana == "ぁ" }.map(\.input)), [[.q], [.q, .h]])
        }
        // `lwa` continues the row's `l`, so prefix mode takes nothing back.
        let engine = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(engine.process(.physical(.q)).actions, [.romaji("l")])
        XCTAssertEqual(engine.process(.physical(.p)).actions, [.romaji("wa")])
        XCTAssertFalse(engine.hasPendingInput)
        for mode in modes {
            for (keys, expected) in cases {
                XCTAssertEqual(typed(keys, mode: mode), expected, "\(keys) \(mode)")
            }
        }
    }

    /// The narrow case the rules are kept to: a third key is looked at only
    /// after ゔ, which no vowel follows in Japanese. Every other rule is one or
    /// two keys, so き then あ is still two kana. The eight are one row: the
    /// five vowels and や ゆ よ, on the keys every row has them on.
    func testThreeKeyRulesExistOnlyAfterVu() {
        let long = WKRLayout.rules.filter { $0.input.count > 2 }
        XCTAssertEqual(long.count, 8)
        XCTAssertTrue(long.allSatisfy { $0.input.count == 3 })
        XCTAssertEqual(Set(long.map { Array($0.input.prefix(2)) }), [[.w, .j]])
        XCTAssertEqual(Set(long.map { $0.input[2] }), [.h, .k, .j, .semicolon, .l, .u, .o, .i])
        XCTAssertEqual(long.map(\.kana), ["ゔぁ", "ゔぃ", "ゔ", "ゔぇ", "ゔぉ", "ゔゃ", "ゔゅ", "ゔょ"])
        XCTAssertEqual(typed([.e, .k, .h], mode: .prefixRomaji), "kia")
        XCTAssertEqual(typed([.w, .k, .h], mode: .prefixRomaji), "wia")
    }

    /// What it costs in prefix mode: after `WJ` the shared `v` stands in until
    /// the next key. `WJJ` finishes ゔ at that key; ヵ no longer waits at all.
    /// Nothing on screen is ever taken back twice.
    func testPrefixModeShowsTheSharedLetterWhileItWaits() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(engine.process(.physical(.w)).actions, [.romaji("w")])
        XCTAssertEqual(engine.process(.physical(.j)).actions, [.backspace(count: 1), .romaji("v")])
        XCTAssertTrue(engine.hasPendingInput)
        XCTAssertEqual(engine.process(.physical(.l)).actions, [.romaji("o")])
        XCTAssertFalse(engine.hasPendingInput)

        let vu = WKRTransducer(mode: .prefixRomaji)
        _ = vu.process(.physical(.w))
        _ = vu.process(.physical(.j))
        XCTAssertEqual(vu.process(.physical(.j)).actions, [.romaji("u")])
        XCTAssertFalse(vu.hasPendingInput)

        let small = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(small.process(.physical(.q)).actions, [.romaji("l")])
        XCTAssertEqual(small.process(.physical(.e)).actions, [.romaji("a"), .romaji("k")])
        XCTAssertTrue(small.hasPendingInput)
        XCTAssertEqual(small.process(.physical(.semicolon)).actions, [.romaji("e")])
    }



    /// A digit is passed through. The following QP uses the same current
    /// delivery sequence as it would at the start of input. This assertion
    /// covers WKR's output events, not the input method's composition behavior.
    func testADigitBeforeQPChangesNothingWKRSends() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        let digit = engine.process(.physical(.digit2))
        XCTAssertEqual(digit.actions, [])
        XCTAssertEqual(digit.disposition, .passThrough)
        XCTAssertFalse(engine.hasPendingInput)
        XCTAssertEqual(engine.process(.physical(.q)).actions, [.romaji("l")])
        XCTAssertEqual(engine.process(.physical(.p)).actions, [.romaji("wa")])
        XCTAssertFalse(engine.hasPendingInput)
    }

    /// Legacy identifiers retain their prefix labels independently of the
    /// current Q row and symbol labels.



}
