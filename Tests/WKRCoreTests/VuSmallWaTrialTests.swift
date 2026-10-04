import XCTest
@testable import WKRCore

final class VuSmallWaTrialTests: XCTestCase {

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
            XCTAssertEqual(rules.filter { $0.kana == "ゎ" }.map(\.input), [[.q, .w]])
            XCTAssertEqual(rules.first { $0.input == [.w, .o] }?.action, .romaji("wye"))
            XCTAssertEqual(rules.first { $0.input == [.w, .p] }?.action, .romaji("wyi"))
            XCTAssertEqual(rules.filter { $0.kana == "ゔぇ" }.map(\.input), [[.w, .j, .semicolon]])
            XCTAssertEqual(rules.first { $0.input == [.q, .w] }?.action, .romaji("lwa"))
            XCTAssertEqual(rules.first { $0.input == [.q, .p] }?.action, .romaji("lya"))
            // The row itself is untouched: ゔ stays where `wu` would have been.
            XCTAssertEqual(rules.first { $0.input == [.w, .j] }?.action, .romaji("vu"))
            XCTAssertEqual(rules.first { $0.input == [.c, .p] }?.kana, "でぃ")
        }
    }

    func testBothRulesLeaveTheirOwnSpellingInBothCommonModes() {
        let cases: [([PhysicalKey], String)] = [
            ([.w, .j, .k], "vi"), ([.w, .j, .semicolon], "ve"), ([.w, .p], "wyi"), ([.q, .w], "lwa"),
            ([.w, .u], "waltu"), ([.w, .o], "wye"),
            // The one place ゎ is written: the historical くゎ and ぐゎ.
            ([.e, .j, .q, .w], "kulwa"), ([.a, .j, .q, .w], "gulwa"),
            // The rest of the ゔ family still comes from the small kana prefix.
            ([.w, .j, .q, .h], "vula"), ([.w, .j, .q, .semicolon], "vule"),
            // `W` alone is still わ, so ゎ does not need a vowel first.
            ([.w, .q, .w], "walwa"),
            // QW has its small ゎ binding; QE falls back to ぁ and か.
            ([.q, .w], "lwa"), ([.q, .e], "laka"), ([.q, .m], "lann"), ([.q, .u], "laltu"), ([.q, .n], "laye"), ([.q, .y], "la-"),
        ]
        for mode in [OutputMode.deferredRomaji, .prefixRomaji] {
            for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
                for (keys, expected) in cases {
                    XCTAssertEqual(onScreen(actions(typing: keys, mode: mode, rules: rules)), expected)
                }
            }
        }
    }

    /// WJ replaces w with v; QW, WP and WO continue their streamed prefixes.
    func testPrefixModeTakesBackTheRowLetterForVuAndNothingForSmallWa() {
        XCTAssertEqual(
            actions(typing: [.w, .j, .semicolon], mode: .prefixRomaji),
            [.romaji("w"), .backspace(count: 1), .romaji("v"), .romaji("e")]
        )
        XCTAssertEqual(
            actions(typing: [.w, .p], mode: .prefixRomaji),
            [.romaji("w"), .romaji("yi")]
        )
        XCTAssertEqual(
            actions(typing: [.w, .o], mode: .prefixRomaji),
            [.romaji("w"), .romaji("ye")]
        )
        XCTAssertEqual(
            actions(typing: [.q, .w], mode: .prefixRomaji),
            [.romaji("l"), .romaji("wa")]
        )
    }

    func testOptimisticModeReplacesTheProvisionalWa() {
        let mode = OutputMode.optimisticRomaji(.fullLayoutExperimental)
        XCTAssertEqual(
            actions(typing: [.w, .p], mode: mode),
            [.romaji("wa"), .backspace(count: 1), .romaji("wyi")]
        )
        XCTAssertEqual(actions(typing: [.q, .w], mode: mode), [.romaji("la"), .backspace(count: 1), .romaji("lwa")])
    }



}
