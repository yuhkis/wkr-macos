import XCTest
@testable import WKRCore

/// beta.13: the わ row gained ゔぃ, and ゎ moved under the small
/// kana prefix as `QW`. ゔぃ was on the special column until beta.16 put the
/// わ row's columns in vowel order, where it was `WO` and `WP` gave ゔぇ.
/// Since beta.18 it is `WJK`, in the ゔ row; `WO` is ゑ again and `WP` わけ.
final class VuSmallWaTrialTests: XCTestCase {
    private let beta12 = "wkr-layout@03cba20+ga-pa-small-io-yp-y-slash-question-swap-long-question-nm-swap"

    private func actions(
        typing keys: [PhysicalKey],
        mode: OutputMode,
        rules: [NormalizedRule] = WKRLayout.rules
    ) -> [SyntheticAction] {
        let engine = WKRTransducer(mode: mode, rules: rules)
        var actions = keys.flatMap { engine.process(.physical($0)).actions }
        actions += engine.process(.boundary(.enter)).actions
        XCTAssertFalse(engine.hasPendingInput)
        return actions
    }

    /// What is left in the pre-edit: every letter sent, minus what was taken
    /// back. Every rollback in these cases removes raw romaji, one letter per
    /// Backspace.
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

    func testEachKanaHasExactlyOneRuleWithAndWithoutTheSymbolLayer() {
        for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
            // Three keys, as part of the ゔ row; the two-key trial slot is ゑ again.
            XCTAssertEqual(rules.filter { $0.kana == "ゔぃ" }.map(\.input), [[.w, .j, .k]])
            XCTAssertEqual(rules.filter { $0.kana == "ゎ" }.map(\.input), [[.q, .p]])
            XCTAssertEqual(rules.first { $0.input == [.w, .o] }?.action, .romaji("wye"))
            XCTAssertEqual(rules.first { $0.input == [.w, .p] }?.action, .romaji("wake"))
            XCTAssertEqual(rules.filter { $0.kana == "ゔぇ" }.map(\.input), [[.w, .j, .semicolon]])
            XCTAssertEqual(rules.first { $0.input == [.q, .p] }?.action, .romaji("lwa"))
            XCTAssertNil(rules.first { $0.input == [.q, .w] })
            // The row itself is untouched: ゔ stays where `wu` would have been.
            XCTAssertEqual(rules.first { $0.input == [.w, .j] }?.action, .romaji("vu"))
            XCTAssertEqual(rules.first { $0.input == [.c, .u] }?.kana, "でぃ")
        }
    }

    func testBothRulesLeaveTheirOwnSpellingInBothCommonModes() {
        let cases: [([PhysicalKey], String)] = [
            ([.w, .j, .k], "vi"), ([.w, .j, .semicolon], "ve"), ([.w, .p], "wake"), ([.q, .p], "lwa"),
            ([.w, .u], "wyi"), ([.w, .o], "wye"),
            // The one place ゎ is written: the historical くゎ and ぐゎ.
            ([.e, .j, .q, .p], "kulwa"), ([.a, .j, .q, .p], "gulwa"),
            // The rest of the ゔ family still comes from the small kana prefix.
            ([.w, .j, .q, .h], "vula"), ([.w, .j, .q, .semicolon], "vule"),
            // `W` alone is still わ, so ゎ does not need a vowel first.
            ([.w, .q, .p], "walwa"),
            // `Q` then a row key is ぁ and that row's kana, as after any row key.
            ([.q, .w], "lawa"), ([.q, .e], "laka"), ([.q, .m], "lann"), ([.q, .n], "laltu"), ([.q, .y], "la-"),
        ]
        for mode in [OutputMode.deferredRomaji, .prefixRomaji] {
            for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
                for (keys, expected) in cases {
                    XCTAssertEqual(onScreen(actions(typing: keys, mode: mode, rules: rules)), expected)
                }
            }
        }
    }

    /// `v` cannot continue the row's `w`, so `WJ` pays the one Backspace `lwa`
    /// paid on `WP` in ver 1.1. `lwa` continues the prefix's `l` and pays
    /// nothing, and neither do `wyi`, `wye` and `wake`, which continue the `w`.
    func testPrefixModeTakesBackTheRowLetterForVuAndNothingForSmallWa() {
        XCTAssertEqual(
            actions(typing: [.w, .j, .semicolon], mode: .prefixRomaji),
            [.romaji("w"), .backspace(count: 1), .romaji("v"), .romaji("e")]
        )
        XCTAssertEqual(
            actions(typing: [.w, .p], mode: .prefixRomaji),
            [.romaji("w"), .romaji("ake")]
        )
        XCTAssertEqual(
            actions(typing: [.w, .o], mode: .prefixRomaji),
            [.romaji("w"), .romaji("ye")]
        )
        XCTAssertEqual(
            actions(typing: [.q, .p], mode: .prefixRomaji),
            [.romaji("l"), .romaji("wa")]
        )
    }

    func testOptimisticModeReplacesTheProvisionalWa() {
        let mode = OutputMode.optimisticRomaji(.fullLayoutExperimental)
        XCTAssertEqual(
            actions(typing: [.w, .p], mode: mode),
            [.romaji("wa"), .backspace(count: 1), .romaji("wake")]
        )
        XCTAssertEqual(actions(typing: [.q, .p], mode: mode), [.romaji("la"), .backspace(count: 1), .romaji("lwa")])
    }

    /// The identifier moved, so the days beta.12 counted are set aside and keep
    /// the tooltip they were counted under: ゎ after a consonant key, not ゔぃ.

}
