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
            ("FI", [.f, .i], ["tyu"]),
            ("HT", [.h, .t], ["la"]),
            ("TH", [.t, .h], ["la"]),
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
            (.n, "nn"), (.m, "ltu"), (.p, "-"),
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
        XCTAssertEqual(WKRLayout.sourceRevision, "a8c102fa6dab6b7d7fdf9678ec9ce2e646facec8")
        XCTAssertEqual(WKRLayout.rules.count, 222)

        let inputs = WKRLayout.rules.map { rule in
            rule.input.map(\.rawValue).joined(separator: "\u{0}")
        }
        XCTAssertEqual(Set(inputs).count, inputs.count)
        XCTAssertFalse(WKRLayout.quarantinedUpstreamEntries.isEmpty)
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
            ([.e, .y], .unicode("ヶ")),
            ([.w, .j], .unicode("ヴ")),
            ([.w, .u], .unicode("ゐ")),
            ([.t, .comma], .unicode("，")),
            ([.y, .j], .unicode("↓")),
            ([.y, .shiftedDigit1], .unicode("●")),
            ([.y, .c], .unicode("〇")),
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

    /// The `Y` layer rows that were only in the Google table and had no azooKey
    /// counterpart. They are the last upstream symbol rows to be implemented, so
    /// pin both the output and the fact that they cost exactly one Backspace to
    /// take back the provisional `y`.
    func testGoogleOnlySymbolLayerRows() {
        let cases: [([PhysicalKey], String)] = [
            ([.y, .y], "〒"),
            ([.y, .leftBracket], "［"),
            ([.y, .rightBracket], "］"),
            ([.y, .leftBrace], "《"),
            ([.y, .rightBrace], "》"),
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
                [.romaji("y"), .backspace(count: 1), .unicode(expected)],
                name
            )
        }
    }

    /// 【 】 are reachable from both the original Shift+8 / Shift+9 sequences and
    /// the `Y` `I` / `Y` `O` rolls added ahead of upstream v1.1.
    func testLenticularBracketsHaveBothBindings() {
        let cases: [(PhysicalKey, PhysicalKey, String)] = [
            (.y, .shiftedDigit8, "【"), (.y, .i, "【"),
            (.y, .shiftedDigit9, "】"), (.y, .o, "】"),
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

    /// Adding the `Y` layer bracket rows must not disturb the bare bracket keys,
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

    // MARK: - Turning the `Y` symbol layer off

    func testDisablingTheSymbolLayerRemovesExactlyThoseRules() {
        let full = Set(WKRLayout.rules.map(\.id))
        let reduced = Set(WKRLayout.rulesWithoutSymbolLayer.map(\.id))

        XCTAssertEqual(full.subtracting(reduced).count, 59)
        XCTAssertTrue(reduced.isSubset(of: full))
        // Nothing left in the table starts with `Y`.
        XCTAssertTrue(
            WKRLayout.rulesWithoutSymbolLayer.allSatisfy { $0.input.first != .y }
        )
    }

    func testDisabledSymbolLayerLetsTheYKeyPassThrough() {
        let engine = WKRTransducer(
            mode: .prefixRomaji,
            rules: WKRTransducer.rulesWithoutSymbolLayer
        )
        let result = engine.process(.physical(.y))

        XCTAssertEqual(result.actions, [])
        XCTAssertEqual(result.disposition, .passThrough)
        XCTAssertFalse(engine.hasPendingInput)
    }

    func testDisabledSymbolLayerKeepsRulesWhereYIsTheSecondKey() {
        // `SY → しぇ` and `EY → ヶ` are row variants, not the symbol layer.
        let cases: [(keys: [PhysicalKey], last: SyntheticAction)] = [
            ([.s, .y], .romaji("he")),
            ([.e, .y], .unicode("ヶ")),
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

        for key in [PhysicalKey.w, .e, .r, .t, .h, .n, .m, .p] {
            XCTAssertEqual(
                full.process(.physical(key)),
                reduced.process(.physical(key)),
                key.rawValue
            )
        }
    }

    func testRowFallbackComposesIndependentNasalGeminateAndLongMark() {
        let rowKeys: [PhysicalKey] = [
            .e, .s, .f, .d, .g, .v, .r, .w, .q, .z, .c, .b, .a, .x,
        ]
        let suffixes: [(PhysicalKey, SyntheticAction)] = [
            (.n, .romaji("nn")),
            (.m, .romaji("ltu")),
            (.p, .romaji("-")),
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
            ("HT", [.h, .t], [[.romaji("a")], [.backspace(count: 1), .romaji("la")]]),
            // や・ゆ・よ must appear on the first keystroke like あ・い・う・え・お,
            // so the whole output is streamed and one kana is taken back when
            // the postfix small-kana branch follows.
            ("U", [.u], [[.romaji("ya")]]),
            ("I", [.i], [[.romaji("yu")]]),
            ("O", [.o], [[.romaji("yo")]]),
            ("UT", [.u, .t], [[.romaji("ya")], [.backspace(count: 1), .romaji("lya")]]),
            // The X row keeps streaming one letter, because ふぁ / ふぃ / ふゅ /
            // ふぇ / ふぉ all continue it.
            ("X", [.x], [[.romaji("f")]]),
            ("XK", [.x, .k], [[.romaji("f")], [.romaji("i")]]),
            ("T", [.t], [[.romaji("l")]]),
            ("TH", [.t, .h], [[.romaji("l")], [.romaji("a")]]),
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

    /// A rollback must delete exactly what is displayed: one Backspace per raw
    /// romaji letter, or one per kana once the output has composed.
    func testPrefixModeDeletesDisplayedUnitsNotRawLetters() {
        let cases: [(name: String, keys: [PhysicalKey], expected: [SyntheticAction])] = [
            // `や` is one composed kana even though it took two letters.
            ("UT", [.u, .t], [.romaji("ya"), .backspace(count: 1), .romaji("lya")]),
            ("IT", [.i, .t], [.romaji("yu"), .backspace(count: 1), .romaji("lyu")]),
            ("OT", [.o, .t], [.romaji("yo"), .backspace(count: 1), .romaji("lyo")]),
            // `f` is still a raw letter in the pre-edit buffer.
            ("XU", [.x, .u], [.romaji("f"), .backspace(count: 1), .romaji("teli")]),
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
    /// including the `Y` symbol layer, which streams its own letter.
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
            (.u, "ya"), (.i, "yu"), (.o, "yo"),
        ]
        for (key, expected) in wholeOutputRoots {
            let engine = WKRTransducer(mode: .prefixRomaji)
            XCTAssertEqual(
                engine.process(.physical(key)).actions,
                [.romaji(expected)],
                key.rawValue
            )
        }

        let symbolLayer = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(symbolLayer.process(.physical(.y)).actions, [.romaji("y")])
    }

    /// Rollbacks are the price of always showing a letter, so the rules that
    /// pay it stay an explicit, reviewed inventory instead of a surprise.
    func testPrefixModeRollbackInventoryIsExactlyTheDeclaredRules() {
        var expectedRollbacks: Set<String> = [
            // Postfix small kana replace the vowel that was already shown.
            "ht-small-a", "kt-small-i", "jt-small-u", "semicolont-small-e",
            "lt-small-o", "ut-small-ya", "it-small-yu", "ot-small-yo",
            // The X row mixes ふ, て and で, so only ふ keeps the streamed `f`.
            "xy-tyu", "xu-thi", "xi-dhu", "xo-dhi",
            // Unicode outputs have no romaji to continue.
            "ey-small-ke", "wj-vu", "wu-archaic-wi", "wi-archaic-we", "wy-small-wa",
            "tcomma-fullwidth-comma", "tperiod-fullwidth-period", "tslash-fullwidth-slash",
        ]
        // The whole `Y` layer streams a placeholder letter that every symbol
        // has to take back before injecting the character.
        expectedRollbacks.formUnion(
            WKRTransducer.fullRules.filter { $0.input.first == .y }.map(\.id)
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
            ("EY", [.e, .y], [.romaji("k"), .backspace(count: 1), .unicode("ヶ")]),
            ("T,", [.t, .comma], [.romaji("l"), .backspace(count: 1), .unicode("，")]),
            ("Y1", [.y, .digit1], [.romaji("y"), .backspace(count: 1), .unicode("○")]),
            ("XH", [.x, .h], [.romaji("f"), .romaji("a")]),
            ("XU", [.x, .u], [.romaji("f"), .backspace(count: 1), .romaji("teli")]),
            ("WJ", [.w, .j], [.romaji("w"), .backspace(count: 1), .unicode("ヴ")]),
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
        let engine = WKRTransducer(mode: .prefixRomaji)
        XCTAssertEqual(engine.process(.physical(.t)).actions, [.romaji("l")])

        let result = engine.process(.physical(.digit0))

        XCTAssertEqual(result.actions, [])
        XCTAssertEqual(result.disposition, .passThrough)
        XCTAssertFalse(engine.hasPendingInput)
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
        XCTAssertEqual(pendingWithoutOutput.process(.physical(.y)).actions, [.romaji("y")])
        let symbolCancel = pendingWithoutOutput.process(.backspace)
        XCTAssertEqual(symbolCancel.actions, [.backspace(count: 1)])
        XCTAssertEqual(symbolCancel.disposition, .suppress)
    }

    /// Space after `Y` or `T` must not make the streamed letter disappear.
    /// Only an explicit Backspace cancels it.
    func testPrefixModeBoundaryLeavesPlaceholderInPlace() {
        for key in [PhysicalKey.y, .t] {
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
