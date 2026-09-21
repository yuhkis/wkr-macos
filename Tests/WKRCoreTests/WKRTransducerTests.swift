import XCTest
@testable import WKRCore

final class WKRTransducerTests: XCTestCase {
    func testDeferredCoreSequencesTableDriven() {
        let cases: [(name: String, keys: [PhysicalKey], expectedRomaji: [String])] = [
            ("E", [.e], ["ka"]),
            ("EK", [.e, .k], ["ki"]),
            ("ESK", [.e, .s, .k], ["ka", "shi"]),
            ("WER", [.w, .e, .r], ["wa", "ka", "ra"]),
            ("SU", [.s, .u], ["sha"]),
            ("FO", [.f, .o], ["tyu"]),
            ("QH", [.q, .h], ["la"]),
        ]

        for testCase in cases {
            let engine = WKRTransducer(mode: .deferredRomaji)
            var actual: [String] = []

            for key in testCase.keys {
                actual.append(contentsOf: romaji(in: engine.process(.physical(key)).actions))
            }
            actual.append(contentsOf: romaji(in: engine.process(.boundary(.space)).actions))

            XCTAssertEqual(actual, testCase.expectedRomaji, testCase.name)
        }
    }

    func testSingleKeyRulesTableDriven() {
        let cases: [(PhysicalKey, String)] = [
            (.h, "a"), (.j, "u"), (.k, "i"), (.l, "o"), (.semicolon, "e"),
            (.m, "nn"), (.n, "ltu"), (.y, "-"), (.slash, "?"), (.shiftedSlash, "/"),
        ]

        for (key, expected) in cases {
            let engine = WKRTransducer(mode: .deferredRomaji)
            let first = engine.process(.physical(key))
            let flushed = engine.process(.boundary(.enter))
            XCTAssertEqual(romaji(in: first.actions + flushed.actions), [expected], key.rawValue)
        }
    }

    func testUndefinedNextKeyIsReprocessedAtRoot() {
        let engine = WKRTransducer(mode: .deferredRomaji)
        XCTAssertEqual(engine.process(.physical(.e)).stateCode, .pendingPrefix)

        let result = engine.process(.physical(.digit0))

        XCTAssertEqual(result.actions, [.romaji("ka")])
        XCTAssertEqual(result.disposition, .repostAfterSynthetic)
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testSpaceAndEnterFlushBeforeRepostingBoundary() {
        for boundary in [BoundaryKey.space, .enter] {
            let engine = WKRTransducer(mode: .deferredRomaji)
            _ = engine.process(.physical(.e))

            let result = engine.process(.boundary(boundary))

            XCTAssertEqual(result.actions, [.romaji("ka")])
            XCTAssertEqual(result.disposition, .repostAfterSynthetic)
            XCTAssertEqual(result.stateCode, .flushedBoundary)
        }
    }

    func testBackspaceCancelsDeferredPendingInputWithoutDeletingExistingText() {
        let engine = WKRTransducer(mode: .deferredRomaji)
        _ = engine.process(.physical(.e))

        let result = engine.process(.backspace)

        XCTAssertEqual(result.actions, [])
        XCTAssertEqual(result.disposition, .suppress)
        XCTAssertEqual(result.stateCode, .canceledPending)
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testResetEventsDiscardPendingStateTableDriven() {
        let reasons: [ResetReason] = [.escape, .inputSourceChanged, .applicationChanged]

        for reason in reasons {
            let engine = WKRTransducer(mode: .deferredRomaji)
            _ = engine.process(.physical(.e))

            let reset = engine.process(.reset(reason))
            let rootK = engine.process(.physical(.k))
            let flushedK = engine.process(.boundary(.enter))

            XCTAssertEqual(reset.disposition, .passThrough, "\(reason)")
            XCTAssertEqual(rootK.actions + flushedK.actions, [.romaji("i")], "\(reason)")
        }
    }

    func testSyntheticEventMarkerPreventsReentry() {
        XCTAssertTrue(SyntheticEventTag.matches(userData: SyntheticEventTag.value))
        XCTAssertFalse(SyntheticEventTag.matches(userData: SyntheticEventTag.value + 1))
    }

    func testDisabledModePassesEveryOriginalEventAndClearsPendingState() {
        let engine = WKRTransducer(mode: .deferredRomaji)
        _ = engine.process(.physical(.e))

        let disabledEvents: [WKRInputEvent] = [
            .physical(.k), .boundary(.space), .backspace, .reset(.escape),
        ]
        for event in disabledEvents {
            let result = engine.process(event, isEnabled: false)
            XCTAssertEqual(result.actions, [])
            XCTAssertEqual(result.disposition, .passThrough)
            XCTAssertEqual(result.stateCode, .disabledBypass)
        }
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testOptimisticReplacementUsesExplicitDeletionProfile() {
        let engine = WKRTransducer(
            mode: .optimisticRomaji(.init(backspacesByRuleID: ["e-ka": 1]))
        )

        XCTAssertEqual(engine.process(.physical(.e)).actions, [.romaji("ka")])
        let replacement = engine.process(.physical(.k))

        XCTAssertEqual(replacement.actions, [.backspace(count: 1), .romaji("ki")])
        XCTAssertEqual(replacement.stateCode, .optimisticReplacement)
    }

    func testOptimisticReplacementFailsClosedWithoutDeletionProfile() {
        let engine = WKRTransducer(mode: .optimisticRomaji(.init(backspacesByRuleID: [:])))
        _ = engine.process(.physical(.e))

        let result = engine.process(.physical(.k))

        XCTAssertEqual(result.actions, [])
        XCTAssertEqual(result.disposition, .suppress)
        XCTAssertEqual(result.stateCode, .optimisticReplacementUnavailable)
    }

    func testFullLayoutSnapshotContainsEveryUniqueNormalizedRule() {
        // Pinned so an unintended re-pin fails here first. wkr-layout ver 1.1.
        XCTAssertEqual(WKRLayout.layoutVersion, "2.0.0-beta.1")
        // 217 upstream rules, plus `QW → ゎ` and `QE → ヵ`, which `WP → ゔぃ` and
        // `AP → がい` displaced, plus the special column of the six rows that had
        // none. ゐ and ゑ lost their rules to ゔぁ and ゔぇ and have them back,
        // which changes no count. beta.17 added eight three-key rules, the ゔ row
        // after `WJ` and `QE;` for ヶ; beta.18 dropped `QE;` and added `WJJ`.
        // beta.19 added `QP → ヶ`. beta.24 made `Q` a row key (ぁ alone) with ゎ
        // on `QP`, and dropped `QW` `QE` and ヶ: one in, two out.
        XCTAssertEqual(WKRLayout.rules.count, 233)

        let inputs = WKRLayout.rules.map { rule in
            rule.input.map(\.rawValue).joined(separator: "\u{0}")
        }
        XCTAssertEqual(Set(inputs).count, inputs.count)
        XCTAssertTrue(WKRLayout.quarantinedUpstreamEntries.isEmpty)
        XCTAssertEqual(WKRLayout.passThroughKeys.count, 4)
    }

    /// The JIS bracket keys must reach Apple Japanese Input untouched so that
    /// 「 and 」 stay convertible with Space.
    func testBracketKeysArePassedThroughInEveryMode() {
        let bracketKeys: [PhysicalKey] = [.leftBracket, .rightBracket, .leftBrace, .rightBrace]
        let modes: [OutputMode] = [
            .deferredRomaji, .prefixRomaji, .optimisticRomaji(.fullLayoutExperimental),
        ]

        for mode in modes {
            for key in bracketKeys {
                let engine = WKRTransducer(mode: mode)
                let result = engine.process(.physical(key))

                XCTAssertEqual(result.actions, [], key.rawValue)
                XCTAssertEqual(result.disposition, .passThrough, key.rawValue)
                XCTAssertFalse(engine.hasPendingInput, key.rawValue)
            }
        }
    }

    /// A pending kana still has to be completed before the bracket key reaches
    /// the application.
    func testBracketKeyFlushesPendingKanaFirst() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(engine.process(.physical(.e)).actions, [.romaji("k")])

        let result = engine.process(.physical(.leftBracket))

        XCTAssertEqual(result.actions, [.romaji("a")])
        XCTAssertEqual(result.disposition, .repostAfterSynthetic)
    }

    func testEveryNormalizedRuleEmitsItsDeclaredActionInDeferredMode() {
        for rule in WKRLayout.rules {
            let engine = WKRTransducer(mode: .deferredRomaji)
            var actions: [SyntheticAction] = []

            for key in rule.input {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            actions.append(contentsOf: engine.process(.boundary(.enter)).actions)

            XCTAssertEqual(actions, [rule.action], rule.id)
        }
    }

    func testOptimisticProfileCoversEveryProvisionalRoot() {
        let rules = WKRLayout.rules
        let roots = rules.filter { rule in
            rule.input.count == 1 && rules.contains { candidate in
                candidate.input.count > 1 && candidate.input.first == rule.input.first
            }
        }

        for root in roots {
            guard let continuation = rules.first(where: { candidate in
                candidate.input.count == 2
                    && candidate.input.first == root.input.first
                    && candidate.action != root.action
            }) else {
                continue
            }

            let engine = WKRTransducer(
                mode: .optimisticRomaji(.fullLayoutExperimental)
            )
            _ = engine.process(.physical(root.input[0]))
            let replacement = engine.process(.physical(continuation.input[1]))

            XCTAssertNotEqual(
                replacement.stateCode,
                .optimisticReplacementUnavailable,
                root.id
            )
        }
    }

    func testOptimisticSameOutputContinuationFinalizesWithoutReplacement() {
        let engine = WKRTransducer(
            mode: .optimisticRomaji(.fullLayoutExperimental)
        )

        XCTAssertEqual(engine.process(.physical(.e)).actions, [.romaji("ka")])
        let confirmation = engine.process(.physical(.h))

        XCTAssertEqual(confirmation.actions, [])
        XCTAssertEqual(confirmation.stateCode, .emittedTerminal)
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testRepresentativeUnicodeAndSymbolLayerRules() {
        let cases: [([PhysicalKey], SyntheticAction)] = [
            ([.q, .comma], .unicode("，")),
            ([.p, .a], .unicode("※")),
            ([.p, .shiftedDigit1], .unicode("●")),
            ([.p, .c], .unicode("〇")),
        ]

        for (keys, expected) in cases {
            let engine = WKRTransducer(mode: .deferredRomaji)
            var actions: [SyntheticAction] = []
            for key in keys {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            actions.append(contentsOf: engine.process(.boundary(.enter)).actions)
            XCTAssertEqual(actions, [expected], keys.map(\.rawValue).joined())
        }
    }

    /// The `P` layer rows that were only in the Google table and had no azooKey
    /// counterpart. They are the last upstream symbol rows to be implemented, so
    /// pin both the output and the fact that they cost exactly one Backspace to
    /// take back the provisional `y`.
    func testGoogleOnlySymbolLayerRows() {
        let cases: [([PhysicalKey], String)] = [
            ([.p, .y], "〒"),
            ([.p, .leftBracket], "［"),
            ([.p, .rightBracket], "］"),
            ([.p, .leftBrace], "《"),
            ([.p, .rightBrace], "》"),
        ]

        for (keys, expected) in cases {
            let name = keys.map(\.rawValue).joined(separator: "+")

            let deferred = WKRTransducer(mode: .deferredRomaji)
            var actions: [SyntheticAction] = []
            for key in keys {
                actions.append(contentsOf: deferred.process(.physical(key)).actions)
            }
            actions.append(contentsOf: deferred.process(.boundary(.enter)).actions)
            XCTAssertEqual(actions, [.unicode(expected)], name)

            let prefix = WKRTransducer(mode: .prefixRomaji)
            var prefixActions: [SyntheticAction] = []
            for key in keys {
                prefixActions.append(contentsOf: prefix.process(.physical(key)).actions)
            }
            XCTAssertEqual(
                prefixActions,
                [.romaji("z"), .backspace(count: 1), .unicode(expected)],
                name
            )
        }
    }

    /// 【 】 are reachable from both the original Shift+8 / Shift+9 sequences and
    /// the `P` `I` / `P` `O` rolls added ahead of upstream v1.1.
    func testLenticularBracketsHaveBothBindings() {
        let cases: [(PhysicalKey, PhysicalKey, String)] = [
            (.p, .shiftedDigit8, "【"), (.p, .i, "【"),
            (.p, .shiftedDigit9, "】"), (.p, .o, "】"),
        ]

        for (first, second, expected) in cases {
            let engine = WKRTransducer(mode: .deferredRomaji)
            var actions: [SyntheticAction] = []
            for key in [first, second] {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            actions.append(contentsOf: engine.process(.boundary(.enter)).actions)
            XCTAssertEqual(actions, [.unicode(expected)], "\(first.rawValue)+\(second.rawValue)")
        }
    }

    /// Adding the `P` layer bracket rows must not disturb the bare bracket keys,
    /// which stay with Apple Japanese Input so Space can still convert them.
    func testSymbolLayerBracketsDoNotCaptureBareBracketKeys() {
        for key in [PhysicalKey.leftBracket, .rightBracket, .leftBrace, .rightBrace] {
            let engine = WKRTransducer(mode: .prefixRomaji)
            let result = engine.process(.physical(key))

            XCTAssertEqual(result.actions, [], key.rawValue)
            XCTAssertEqual(result.disposition, .passThrough, key.rawValue)
            XCTAssertFalse(engine.hasPendingInput, key.rawValue)
        }
    }

    // MARK: - Reaching the kana that were out of range

    /// `ヴ` used to be injected, which committed it and took it off the
    /// pre-edit, so nothing could attach to it. As romaji it stays, and the
    /// whole ゔ row follows from the small kana rules already in the table.
    func testTheVuRowIsReachableThroughSmallKana() {
        let cases: [(name: String, keys: [PhysicalKey], romaji: String)] = [
            ("WJ", [.w, .j], "vu"),
            ("WJ QH", [.w, .j, .q, .h], "vula"),      // ゔぁ
            ("WJ QK", [.w, .j, .q, .k], "vuli"),      // ゔぃ
            ("WJ T;", [.w, .j, .q, .semicolon], "vule"),  // ゔぇ
            ("WJ TL", [.w, .j, .q, .l], "vulo"),      // ゔぉ
            ("WJ TU", [.w, .j, .q, .u], "vulya"),     // ゔゃ
            ("WJ QO", [.w, .j, .q, .o], "vulyu"),     // ゔゅ
            ("WJ QI", [.w, .j, .q, .i], "vulyo"),     // ゔょ
        ]

        for testCase in cases {
            let engine = WKRTransducer(mode: .deferredRomaji)
            var actions: [SyntheticAction] = []
            for key in testCase.keys {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            actions.append(contentsOf: engine.process(.boundary(.enter)).actions)

            XCTAssertEqual(concatenatedRomaji(actions), testCase.romaji, testCase.name)
        }
    }

    /// `ヵ` has no hiragana form, so no base kana plus a small kana can build
    /// it. It needs a rule of its own. It was the が row's special column until
    /// that became がい, and now reads like `QW → ゎ`: the small kana prefix,
    /// then the か row key.
    func testSmallKaHasNoRuleAndQIsARowKey() {
        // ヵ had `QE` from beta.15 to beta.23. It comes from conversion now, and
        // `Q` then the か row key is ぁ and か, as after any row key.
        let engine = WKRTransducer(mode: .deferredRomaji)
        var actions: [SyntheticAction] = []
        for key in [PhysicalKey.q, .e] {
            actions.append(contentsOf: engine.process(.physical(key)).actions)
        }
        XCTAssertEqual(actions, [.romaji("la")])
        XCTAssertTrue(engine.hasPendingInput)
        actions.append(contentsOf: engine.process(.boundary(.enter)).actions)
        XCTAssertEqual(actions, [.romaji("la"), .romaji("ka")])
        XCTAssertTrue(WKRLayout.rules.allSatisfy { $0.kana != "ヵ" && $0.kana != "ヶ" })
    }

    /// `KT → ぃ` was the clearest case: it swallowed the `T` of a following
    /// prefix small kana, so `K` `T` `;` produced `ぃえ` instead of `いぇ`.
    /// After the Q/T swap, `ぃ` remains reachable as the prefix form `QK`.
    func testDroppingTheTrailingSmallIUnblocksIe() {
        let engine = WKRTransducer(mode: .deferredRomaji)
        var actions: [SyntheticAction] = []
        for key in [PhysicalKey.k, .q, .semicolon] {
            actions.append(contentsOf: engine.process(.physical(key)).actions)
        }
        actions.append(contentsOf: engine.process(.boundary(.enter)).actions)

        XCTAssertEqual(concatenatedRomaji(actions), "ile")  // い + ぇ
        XCTAssertNil(WKRLayout.rules.first { $0.input == [.k, .q] })
        XCTAssertNotNil(WKRLayout.rules.first { $0.input == [.q, .k] })
    }

    /// All eight trailing small kana are gone. Each swallowed the `T` of a
    /// following prefix small kana, so no base kana could be followed by one.
    func testNoTrailingSmallKanaRemain() {
        // `PQ` is the symbol layer, not a trailing small kana.
        let trailing = WKRLayout.rules.filter {
            $0.input.count == 2 && $0.input[1] == .q && $0.input[0] != .p
        }

        XCTAssertEqual(trailing.map(\.id), [])
    }

    /// Every base kana can now be followed by a prefix small kana, which is
    /// what the trailing forms were blocking.
    func testEveryBaseVowelAcceptsAFollowingSmallKana() {
        let bases: [(PhysicalKey, String)] = [
            (.h, "a"), (.k, "i"), (.j, "u"), (.semicolon, "e"), (.l, "o"),
            (.u, "ya"), (.o, "yu"), (.i, "yo"),
        ]
        let smalls: [(PhysicalKey, String)] = [
            (.h, "la"), (.k, "li"), (.j, "lu"), (.semicolon, "le"), (.l, "lo"),
            (.u, "lya"), (.o, "lyu"), (.i, "lyo"),
        ]

        for (baseKey, baseRomaji) in bases {
            for (smallKey, smallRomaji) in smalls {
                let engine = WKRTransducer(mode: .deferredRomaji)
                var actions: [SyntheticAction] = []
                for key in [baseKey, .q, smallKey] {
                    actions.append(contentsOf: engine.process(.physical(key)).actions)
                }
                actions.append(contentsOf: engine.process(.boundary(.enter)).actions)

                XCTAssertEqual(
                    concatenatedRomaji(actions),
                    baseRomaji + smallRomaji,
                    "\(baseKey.rawValue)+T+\(smallKey.rawValue)"
                )
            }
        }
    }

    /// The provisional a rollback takes back is always raw romaji now, so a
    /// Backspace count and a character count agree everywhere.
    func testNoRuleTakesBackAComposedKana() {
        for rule in WKRTransducer.fullRules {
            let engine = WKRTransducer(mode: .prefixRomaji)
            var result = TransitionResult(disposition: .passThrough, stateCode: .idle)
            for key in rule.input {
                result = engine.process(.physical(key))
            }

            let units = result.actions.reduce(0) { total, action in
                if case let .backspace(count) = action { return total + count }
                return total
            }
            if units > 0 {
                XCTAssertEqual(units, result.deletedRomajiCharacters, rule.id)
            }
        }
    }

    // MARK: - Turning the `P` symbol layer off

    func testDisablingTheSymbolLayerRemovesExactlyThoseRules() {
        let full = Set(WKRLayout.rules.map(\.id))
        let reduced = Set(WKRLayout.rulesWithoutSymbolLayer.map(\.id))

        XCTAssertEqual(full.subtracting(reduced).count, 55)
        XCTAssertTrue(reduced.isSubset(of: full))
        // Everything removed injects Unicode, and nothing that does is left.
        XCTAssertTrue(
            WKRLayout.rules
                .filter { !reduced.contains($0.id) }
                .allSatisfy { rule in
                    guard case .unicode = rule.action else { return false }
                    return rule.input.first == .p
                }
        )
        XCTAssertFalse(
            WKRLayout.rulesWithoutSymbolLayer.contains { rule in
                guard case .unicode = rule.action else { return false }
                return rule.input.first == .p
            }
        )
    }

    func testDisabledSymbolLayerKeepsTheArrowsOnTheYKey() {
        // The arrows are romaji, so none of the reasons for turning the layer
        // off apply to them and `P` stays their prefix.
        let engine = WKRTransducer(
            mode: .prefixRomaji,
            rules: WKRTransducer.rulesWithoutSymbolLayer
        )

        XCTAssertEqual(engine.process(.physical(.p)).actions, [.romaji("z")])
        XCTAssertTrue(engine.hasPendingInput)
        XCTAssertEqual(engine.process(.physical(.j)).actions, [.romaji("j")])
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testDisabledSymbolLayerDropsTheSymbolsUnderY() {
        let engine = WKRTransducer(
            mode: .prefixRomaji,
            rules: WKRTransducer.rulesWithoutSymbolLayer
        )
        _ = engine.process(.physical(.p))

        // `P` `A` was ※. With the layer off there is no such rule, so `A`
        // is reprocessed at the root as が and the streamed `z` stays put.
        let result = engine.process(.physical(.a))

        XCTAssertEqual(result.actions, [.romaji("g")])
    }

    func testDisabledSymbolLayerKeepsRulesWhereYIsTheSecondKey() {
        // `SP → しぇ` and `EP → こと` are row variants, not the symbol layer.
        let cases: [(keys: [PhysicalKey], last: SyntheticAction)] = [
            ([.s, .p], .romaji("he")),
            ([.e, .p], .romaji("oto")),
        ]

        for testCase in cases {
            let engine = WKRTransducer(
                mode: .prefixRomaji,
                rules: WKRTransducer.rulesWithoutSymbolLayer
            )
            var actions: [SyntheticAction] = []
            for key in testCase.keys {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }

            XCTAssertEqual(actions.last, testCase.last, "\(testCase.keys)")
        }
    }

    func testDisabledSymbolLayerLeavesOrdinaryKanaUnchanged() {
        let full = WKRTransducer(mode: .prefixRomaji)
        let reduced = WKRTransducer(
            mode: .prefixRomaji,
            rules: WKRTransducer.rulesWithoutSymbolLayer
        )

        for key in [PhysicalKey.w, .e, .r, .q, .h, .n, .m, .y] {
            XCTAssertEqual(
                full.process(.physical(key)),
                reduced.process(.physical(key)),
                key.rawValue
            )
        }
    }

    func testRowFallbackComposesIndependentNasalGeminateAndLongMark() {
        let rowKeys: [PhysicalKey] = [
            .e, .s, .f, .d, .g, .v, .r, .w, .t, .z, .c, .b, .a, .x,
        ]
        let suffixes: [(PhysicalKey, SyntheticAction)] = [
            (.m, .romaji("nn")),
            (.n, .romaji("ltu")),
            (.y, .romaji("-")),
            (.slash, .romaji("?")),
            (.shiftedSlash, .romaji("/")),
        ]

        for rowKey in rowKeys {
            let rootRule = WKRLayout.rules.first { $0.input == [rowKey] }!
            for (suffixKey, suffixAction) in suffixes {
                let engine = WKRTransducer(mode: .deferredRomaji)
                var actions = engine.process(.physical(rowKey)).actions
                actions.append(contentsOf: engine.process(.physical(suffixKey)).actions)
                actions.append(contentsOf: engine.process(.boundary(.enter)).actions)
                XCTAssertEqual(
                    actions,
                    [rootRule.action, suffixAction],
                    "\(rowKey.rawValue)\(suffixKey.rawValue)"
                )
            }
        }
    }

    // MARK: - prefix-romaji

    func testPrefixModeStreamsSharedRomajiPerKeystroke() {
        let cases: [(name: String, keys: [PhysicalKey], expectedPerKey: [[SyntheticAction]])] = [
            ("E", [.e], [[.romaji("k")]]),
            ("EK", [.e, .k], [[.romaji("k")], [.romaji("i")]]),
            ("SK", [.s, .k], [[.romaji("s")], [.romaji("hi")]]),
            (
                "ESK",
                [.e, .s, .k],
                [[.romaji("k")], [.romaji("a"), .romaji("s")], [.romaji("hi")]]
            ),
            (
                "WER",
                [.w, .e, .r],
                [[.romaji("w")], [.romaji("a"), .romaji("k")], [.romaji("a"), .romaji("r")]]
            ),
            ("FK", [.f, .k], [[.romaji("t")], [.romaji("i")]]),
            ("GJ", [.g, .j], [[.romaji("h")], [.romaji("u")]]),
            ("ZK", [.z, .k], [[.romaji("z")], [.romaji("i")]]),
            ("H", [.h], [[.romaji("a")]]),
            // や・ゆ・よ must appear on the first keystroke like あ・い・う・え・お,
            // so the whole output is streamed and one kana is taken back when
            // the postfix small-kana branch follows.
            ("U", [.u], [[.romaji("ya")]]),
            ("O", [.o], [[.romaji("yu")]]),
            ("I", [.i], [[.romaji("yo")]]),
            // The X row keeps streaming one letter, because ふぁ / ふぃ / ふゅ /
            // ふぇ / ふぉ all continue it.
            ("X", [.x], [[.romaji("f")]]),
            ("XK", [.x, .k], [[.romaji("f")], [.romaji("i")]]),
            ("T", [.q], [[.romaji("l")]]),
            ("QH", [.q, .h], [[.romaji("l")], [.romaji("a")]]),
        ]

        for testCase in cases {
            let engine = WKRTransducer(mode: .prefixRomaji)
            for (index, key) in testCase.keys.enumerated() {
                XCTAssertEqual(
                    engine.process(.physical(key)).actions,
                    testCase.expectedPerKey[index],
                    "\(testCase.name) key \(index)"
                )
            }
        }
    }

    func testPrefixModeCompletesVowelOnBoundaryWithoutChangingKeyCount() {
        for boundary in [BoundaryKey.space, .enter] {
            let engine = WKRTransducer(mode: .prefixRomaji)
            var actions: [SyntheticAction] = []
            for key in [PhysicalKey.w, .e, .r] {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }

            let flushed = engine.process(.boundary(boundary))
            actions.append(contentsOf: flushed.actions)

            XCTAssertEqual(concatenatedRomaji(actions), "wakara")
            XCTAssertEqual(flushed.actions, [.romaji("a")])
            XCTAssertEqual(flushed.disposition, .repostAfterSynthetic)
            XCTAssertEqual(flushed.stateCode, .flushedBoundary)
        }
    }

    func testPrefixModeRomanTransliterationDoesNotCompletePendingKana() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        var actions: [SyntheticAction] = []
        for key in [PhysicalKey.w, .e, .r] {
            actions.append(contentsOf: engine.process(.physical(key)).actions)
        }

        let transliteration = engine.process(.romanTransliteration)

        XCTAssertEqual(concatenatedRomaji(actions), "wakar")
        XCTAssertEqual(transliteration.actions, [])
        XCTAssertEqual(transliteration.disposition, .passThrough)
        XCTAssertEqual(transliteration.stateCode, .romanTransliteration)
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testDeferredModeRomanTransliterationStreamsOnlyTheProvisionalRomaji() {
        let engine = WKRTransducer(mode: .deferredRomaji)
        var actions: [SyntheticAction] = []
        for key in [PhysicalKey.w, .e, .r] {
            actions.append(contentsOf: engine.process(.physical(key)).actions)
        }

        let transliteration = engine.process(.romanTransliteration)
        actions.append(contentsOf: transliteration.actions)

        XCTAssertEqual(concatenatedRomaji(actions), "wakar")
        XCTAssertEqual(transliteration.actions, [.romaji("r")])
        XCTAssertEqual(transliteration.disposition, .repostAfterSynthetic)
        XCTAssertEqual(transliteration.stateCode, .romanTransliteration)
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testOptimisticModeRomanTransliterationRestoresOnlyTheProvisionalRomaji() {
        let engine = WKRTransducer(
            mode: .optimisticRomaji(.fullLayoutExperimental)
        )
        XCTAssertEqual(engine.process(.physical(.e)).actions, [.romaji("ka")])

        let transliteration = engine.process(.romanTransliteration)

        XCTAssertEqual(
            transliteration.actions,
            [.backspace(count: 1), .romaji("k")]
        )
        XCTAssertEqual(transliteration.deletedRomajiCharacters, 2)
        XCTAssertEqual(transliteration.disposition, .repostAfterSynthetic)
        XCTAssertEqual(transliteration.stateCode, .romanTransliteration)
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testOptimisticModeRomanTransliterationExposesAProvisionalOnlyPrefix() {
        let engine = WKRTransducer(
            mode: .optimisticRomaji(.fullLayoutExperimental)
        )
        // `P` is the one bare prefix left; `Q` shows ぁ at once since beta.24.
        XCTAssertEqual(engine.process(.physical(.p)).actions, [])

        let transliteration = engine.process(.romanTransliteration)

        XCTAssertEqual(transliteration.actions, [.romaji("z")])
        XCTAssertEqual(transliteration.deletedRomajiCharacters, 0)
        XCTAssertEqual(transliteration.disposition, .repostAfterSynthetic)
        XCTAssertEqual(transliteration.stateCode, .romanTransliteration)
        XCTAssertFalse(engine.hasPendingInput)
    }

    /// Every romaji rule must reach its declared romaji. Without a rollback the
    /// streamed pieces concatenate to it; with one, everything before the
    /// deletion is discarded and the full romaji is re-sent.
    func testPrefixModeReachesDeclaredRomajiForEveryRule() {
        for rule in WKRTransducer.fullRules {
            guard case let .romaji(expected) = rule.action else { continue }

            let engine = WKRTransducer(mode: .prefixRomaji)
            var actions: [SyntheticAction] = []
            for key in rule.input {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            actions.append(contentsOf: engine.process(.boundary(.enter)).actions)

            XCTAssertEqual(romajiAfterLastDeletion(actions), expected, rule.id)
        }
    }

    /// A rollback deletes what is displayed, which is one Backspace per raw
    /// romaji letter. Dropping the trailing small kana removed the only rules
    /// whose provisional had already composed into a kana, so every remaining
    /// rollback takes back raw letters; the kana case stays covered by the unit
    /// computation and `testNoRuleTakesBackAComposedKana`.
    func testPrefixModeDeletesDisplayedUnitsNotRawLetters() {
        let cases: [(name: String, keys: [PhysicalKey], expected: [SyntheticAction])] = [
            ("XU", [.x, .u], [.romaji("f"), .backspace(count: 1), .romaji("teli")]),
            ("WJ;", [.w, .j, .semicolon], [.romaji("w"), .backspace(count: 1), .romaji("v"), .romaji("e")]),
        ]

        for testCase in cases {
            let engine = WKRTransducer(mode: .prefixRomaji)
            var actions: [SyntheticAction] = []
            for key in testCase.keys {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            XCTAssertEqual(actions, testCase.expected, testCase.name)
        }
    }

    /// The first keystroke has to produce visible feedback for every root,
    /// including the `P` symbol layer, which streams its own letter.
    func testPrefixModeShowsSomethingOnTheFirstKeystroke() {
        var rootKeys: [PhysicalKey] = []
        var seen = Set<PhysicalKey>()
        for rule in WKRTransducer.fullRules where seen.insert(rule.input[0]).inserted {
            rootKeys.append(rule.input[0])
        }

        for key in rootKeys {
            let engine = WKRTransducer(mode: .prefixRomaji)
            let first = engine.process(.physical(key))

            guard engine.hasPendingInput else {
                // Terminal single-key rules already emit their whole output.
                XCTAssertEqual(first.actions.count, 1, key.rawValue)
                continue
            }
            XCTAssertFalse(romaji(in: first.actions).joined().isEmpty, key.rawValue)
        }

        // Kana that a single letter cannot display are streamed in full.
        let wholeOutputRoots: [(PhysicalKey, String)] = [
            (.h, "a"), (.k, "i"), (.j, "u"), (.semicolon, "e"), (.l, "o"),
            (.u, "ya"), (.o, "yu"), (.i, "yo"),
        ]
        for (key, expected) in wholeOutputRoots {
            let engine = WKRTransducer(mode: .prefixRomaji)
            XCTAssertEqual(
                engine.process(.physical(key)).actions,
                [.romaji(expected)],
                key.rawValue
            )
        }

        // `P` streams `z`, the prefix its four arrow rules share.
        let symbolLayer = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(symbolLayer.process(.physical(.p)).actions, [.romaji("z")])
    }

    /// Rollbacks are the price of always showing a letter, so the rules that
    /// pay it stay an explicit, reviewed inventory instead of a surprise.
    func testPrefixModeRollbackInventoryIsExactlyTheDeclaredRules() {
        var expectedRollbacks: Set<String> = [
            // The X row mixes ふ and the て loanword kana, so only ふ keeps the
            // streamed `f`. Their で twins after `C` continue that row's `d`.
            "xp-site", "xu-thi", "xo-thu", "xi-twu",
            // Outputs that cannot continue the letter their row streamed: the
            // full-width punctuation is Unicode, and `ゔ` starts with `v`, not
            // the row's `w`. `ゐ` `ゑ` and `わけ` continue `w` and cost nothing, so
            // the inventory lost the three entries `ゔぁ` `ゔぃ` `ゔぇ` had on `WU`
            // `WO` `WP`. `ゎ` and `ヵ` pay nothing either: `QW` and `QE` let them
            // continue the `l` of the small kana prefix, and every pair on the
            // special column but `XP → して` continues its row's letter.
            "wj-vu",
            // The ゔ row after `WJ`: the Backspace is the one `J` already pays.
            "wjh-va", "wjk-vi", "wjj-vu", "wjsemicolon-ve", "wjl-vo", "wju-vya", "wjo-vyu", "wji-vyo",
            "qcomma-fullwidth-comma", "qperiod-fullwidth-period", "qslash-fullwidth-slash",
        ]
        // The `P` symbol layer streams `z` and every symbol has to take it
        // back before injecting the character. The four arrows continue `z`
        // into their own romaji instead, so they are not in this set.
        expectedRollbacks.formUnion(
            WKRTransducer.fullRules
                .filter { rule in
                    guard rule.input.first == .p else { return false }
                    guard case .unicode = rule.action else { return false }
                    return true
                }
                .map(\.id)
        )

        var actualRollbacks: Set<String> = []
        for rule in WKRTransducer.fullRules {
            let engine = WKRTransducer(mode: .prefixRomaji)
            var actions: [SyntheticAction] = []
            for key in rule.input {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            actions.append(contentsOf: engine.process(.boundary(.enter)).actions)

            let deleted = actions.reduce(0) { total, action in
                if case let .backspace(count) = action { return total + count }
                return total
            }
            if deleted > 0 {
                actualRollbacks.insert(rule.id)
                XCTAssertEqual(deleted, 1, rule.id)
            }
        }

        XCTAssertEqual(actualRollbacks, expectedRollbacks)
    }

    /// Unicode rules cannot share a romaji prefix, so prefix mode deletes
    /// exactly the letters it streamed itself before injecting the character.
    func testPrefixModeRollsBackExactlyItsOwnLettersForUnicodeRules() {
        for rule in WKRTransducer.fullRules {
            guard case let .unicode(expected) = rule.action else { continue }

            let engine = WKRTransducer(mode: .prefixRomaji)
            var actions: [SyntheticAction] = []
            for key in rule.input {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            actions.append(contentsOf: engine.process(.boundary(.enter)).actions)

            let deleted = actions.reduce(0) { total, action in
                if case let .backspace(count) = action { return total + count }
                return total
            }
            XCTAssertEqual(deleted, concatenatedRomaji(actions).count, rule.id)
            XCTAssertEqual(actions.last, .unicode(expected), rule.id)
        }
    }

    func testPrefixModeRepresentativeRollbacks() {
        let cases: [(name: String, keys: [PhysicalKey], expected: [SyntheticAction])] = [
            ("EP", [.e, .p], [.romaji("k"), .romaji("oto")]),
            ("PJ", [.p, .j], [.romaji("z"), .romaji("j")]),
            ("WP", [.w, .p], [.romaji("w"), .romaji("ake")]),
            ("WO", [.w, .o], [.romaji("w"), .romaji("ye")]),
            ("WI", [.w, .i], [.romaji("w"), .romaji("ho")]),
            ("Q,", [.q, .comma], [.romaji("l"), .backspace(count: 1), .unicode("，")]),
            ("P1", [.p, .digit1], [.romaji("z"), .backspace(count: 1), .unicode("○")]),
            ("XH", [.x, .h], [.romaji("f"), .romaji("a")]),
            ("XU", [.x, .u], [.romaji("f"), .backspace(count: 1), .romaji("teli")]),
            // ゔ waits for a third key, so only the shared letter shows.
            ("WJ", [.w, .j], [.romaji("w"), .backspace(count: 1), .romaji("v")]),
            ("WJL", [.w, .j, .l], [.romaji("w"), .backspace(count: 1), .romaji("v"), .romaji("o")]),
            ("WJJ", [.w, .j, .j], [.romaji("w"), .backspace(count: 1), .romaji("v"), .romaji("u")]),
            ("WJR", [.w, .j, .r], [.romaji("w"), .backspace(count: 1), .romaji("v"), .romaji("u"), .romaji("r")]),
            ("AP", [.a, .p], [.romaji("g"), .romaji("ai")]),
            ("QE", [.q, .e], [.romaji("l"), .romaji("a"), .romaji("k")]),
            ("QP", [.q, .p], [.romaji("l"), .romaji("wa")]),
            ("QE;", [.q, .e, .semicolon], [.romaji("l"), .romaji("a"), .romaji("k"), .romaji("e")]),
            ("QES", [.q, .e, .s], [.romaji("l"), .romaji("a"), .romaji("k"), .romaji("a"), .romaji("s")]),
            ("WU", [.w, .u], [.romaji("w"), .romaji("yi")]),
        ]

        for testCase in cases {
            let engine = WKRTransducer(mode: .prefixRomaji)
            var actions: [SyntheticAction] = []
            for key in testCase.keys {
                actions.append(contentsOf: engine.process(.physical(key)).actions)
            }
            XCTAssertEqual(actions, testCase.expected, testCase.name)
        }
    }

    /// Nothing WKR already showed may vanish on its own, so a key that cannot
    /// complete the layer leaves the streamed letter to Apple Japanese Input.
    func testPrefixModeUndefinedNextKeyLeavesUncompletableLetters() {
        // `P` is the bare prefix: `z` is on screen and `R` is not one of its keys.
        let engine = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(engine.process(.physical(.p)).actions, [.romaji("z")])

        let result = engine.process(.physical(.r))

        // Nothing is deleted: the `z` stays, and `R` starts its own kana.
        XCTAssertEqual(result.actions, [.romaji("r")])
        XCTAssertEqual(result.disposition, .suppress)
        XCTAssertTrue(engine.hasPendingInput)

        // `Q` is a row key now, so a key that is not WKR's settles ぁ first.
        let small = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(small.process(.physical(.q)).actions, [.romaji("l")])
        let digit = small.process(.physical(.digit0))
        XCTAssertEqual(digit.actions, [.romaji("a")])
        XCTAssertEqual(digit.disposition, .repostAfterSynthetic)
        XCTAssertFalse(small.hasPendingInput)
    }

    func testPrefixModeBackspaceRemovesOnlyStreamedLetters() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        _ = engine.process(.physical(.e))

        let result = engine.process(.backspace)

        XCTAssertEqual(result.actions, [.backspace(count: 1)])
        XCTAssertEqual(result.disposition, .suppress)
        XCTAssertEqual(result.stateCode, .canceledPending)
        XCTAssertFalse(engine.hasPendingInput)

        let pendingWithoutOutput = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(pendingWithoutOutput.process(.physical(.p)).actions, [.romaji("z")])
        let symbolCancel = pendingWithoutOutput.process(.backspace)
        XCTAssertEqual(symbolCancel.actions, [.backspace(count: 1)])
        XCTAssertEqual(symbolCancel.disposition, .suppress)
    }

    /// Space after `P` must not make the streamed letter disappear. Only an
    /// explicit Backspace cancels it. (`Q` was the other bare prefix until
    /// beta.24; Space after it now settles ぁ, as after any row key.)
    func testPrefixModeBoundaryLeavesPlaceholderInPlace() {
        let small = WKRTransducer(mode: .prefixRomaji)
        _ = small.process(.physical(.q))
        XCTAssertEqual(small.process(.boundary(.space)).actions, [.romaji("a")])
        for key in [PhysicalKey.p] {
            let engine = WKRTransducer(mode: .prefixRomaji)
            XCTAssertFalse(engine.process(.physical(key)).actions.isEmpty, key.rawValue)

            let boundary = engine.process(.boundary(.space))

            XCTAssertEqual(boundary.actions, [], key.rawValue)
            XCTAssertEqual(boundary.disposition, .passThrough, key.rawValue)
            XCTAssertFalse(engine.hasPendingInput, key.rawValue)
        }
    }

    /// Shift+letter switches Apple Japanese Input to the alphabet mode, so the
    /// pending kana must be completed instead of dropped.
    func testPrefixModeUnsupportedShiftCombinationFlushesPendingKana() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(engine.process(.physical(.g)).actions, [.romaji("h")])

        let result = engine.process(.boundary(.other))

        XCTAssertEqual(result.actions, [.romaji("a")])
        XCTAssertEqual(result.disposition, .repostAfterSynthetic)
        XCTAssertFalse(engine.hasPendingInput)
    }

    /// Whatever Apple Japanese Input already shows belongs to the IME, so no
    /// reset reason, Escape included, posts anything.
    func testPrefixModeResetNeverPostsSyntheticEvents() {
        for reason in [
            ResetReason.escape, .applicationChanged, .inputSourceChanged, .secureInput, .mouse,
        ] {
            let engine = WKRTransducer(mode: .prefixRomaji)
            _ = engine.process(.physical(.e))

            let result = engine.process(.reset(reason))

            XCTAssertEqual(result.actions, [], String(describing: reason))
            XCTAssertEqual(result.disposition, .passThrough)
            XCTAssertFalse(engine.hasPendingInput)
        }
    }

    private func concatenatedRomaji(_ actions: [SyntheticAction]) -> String {
        romaji(in: actions).joined()
    }

    /// The romaji that survives in the pre-edit buffer: a rollback always
    /// clears everything prefix mode streamed for the current kana, so only the
    /// pieces after the last Backspace remain.
    private func romajiAfterLastDeletion(_ actions: [SyntheticAction]) -> String {
        var buffer = ""
        for action in actions {
            switch action {
            case let .romaji(value):
                buffer += value
            case .backspace:
                buffer = ""
            case .unicode:
                break
            }
        }
        return buffer
    }

    private func romaji(in actions: [SyntheticAction]) -> [String] {
        actions.compactMap { action in
            guard case let .romaji(value) = action else { return nil }
            return value
        }
    }
}
