import XCTest
@testable import WKRCore

final class EnglishFallbackJournalTests: XCTestCase {
    /// Feed a key sequence through a prefix-mode transducer while recording it,
    /// exactly as the controller does.
    private func journal(
        typing keys: [PhysicalKey],
        limit: Int = EnglishFallbackJournal.defaultKeyLimit,
        at now: Double = 0
    ) -> EnglishFallbackJournal {
        let engine = WKRTransducer(mode: .prefixRomaji)
        var journal = EnglishFallbackJournal(keyLimit: limit)
        for key in keys {
            let event = WKRInputEvent.physical(key)
            journal.record(event, result: engine.process(event), at: now)
        }
        return journal
    }

    // MARK: - The case the fallback exists for

    func testThingRecordsItsKeysAndTheStreamedRomajiLength() {
        let keys: [PhysicalKey] = [.t, .h, .i, .n, .g]
        let snapshot = journal(typing: keys).snapshot(at: 0)

        XCTAssertEqual(snapshot?.keys, keys)
        // `la` + `yu` + `nn` + `h`, the `layunnh` the connect-back puts on
        // screen for the `thing` the user meant to type.
        XCTAssertEqual(snapshot?.romajiCharacterCount, 7)
    }

    /// The arrows are romaji now, so a mistyped `Y` `J` stays recoverable. It
    /// used to inject Unicode, which stopped the journal for the rest of the
    /// pre-edit and left the connect-back with nothing to replace.
    func testArrowKeysKeepTheJournalUsable() {
        let snapshot = journal(typing: [.y, .j]).snapshot(at: 0)

        XCTAssertEqual(snapshot?.keys, [.y, .j])
        XCTAssertEqual(snapshot?.romajiCharacterCount, 2)  // `z` + `j`
        XCTAssertEqual(
            snapshot.map { String($0.keys.map(\.jisCharacter)) },
            "yj"
        )
    }

    /// A symbol still stops it: the character commits on the spot, so there is
    /// nothing left in the pre-edit for the connect-back to hand back.
    func testSymbolLayerStillStopsTheJournal() {
        XCTAssertNil(journal(typing: [.y, .a]).snapshot(at: 0))
    }

    /// A rollback branch replaces the letter its row streamed, and the
    /// connect-back shows the replacement alone. The journal follows that
    /// instead of giving up, so the keys stay recoverable.
    func testRollbackBranchesStayRecoverable() {
        let cases: [(name: String, keys: [PhysicalKey], count: Int, letters: String)] = [
            // `k` is taken back and `lke` sent, so the screen holds `lke`.
            ("EY", [.e, .y], 3, "ey"),
            ("EYWY", [.e, .y, .w, .y], 6, "eywy"),  // `lke` + `lwa`
            // `や` is one Backspace but two characters, and `lya` replaces both.
            ("UT", [.u, .t], 3, "ut"),
            // The X row keeps `f` for ふぁ and rolls it back for てぃ.
            ("XU", [.x, .u], 4, "xu"),  // `teli`
        ]

        for testCase in cases {
            let snapshot = journal(typing: testCase.keys).snapshot(at: 0)

            XCTAssertEqual(snapshot?.keys, testCase.keys, testCase.name)
            XCTAssertEqual(snapshot?.romajiCharacterCount, testCase.count, testCase.name)
            XCTAssertEqual(
                snapshot.map { String($0.keys.map(\.jisCharacter)) },
                testCase.letters,
                testCase.name
            )
        }
    }

    /// Whatever the branch, the recorded length must equal the romaji actually
    /// left on screen: everything streamed, minus everything taken back.
    func testRecordedLengthMatchesTheRomajiLeftOnScreenForEveryRule() {
        for rule in WKRTransducer.fullRules {
            guard case .romaji = rule.action else { continue }

            let engine = WKRTransducer(mode: .prefixRomaji)
            var journal = EnglishFallbackJournal()
            var onScreen = ""
            for key in rule.input {
                let event = WKRInputEvent.physical(key)
                let result = engine.process(event)
                journal.record(event, result: result, at: 0)
                for action in result.actions {
                    switch action {
                    case let .romaji(value):
                        onScreen += value
                    case .backspace:
                        onScreen.removeLast(result.deletedRomajiCharacters)
                    case .unicode:
                        break
                    }
                }
            }

            XCTAssertEqual(
                journal.snapshot(at: 0)?.romajiCharacterCount,
                onScreen.count,
                rule.id
            )
        }
    }

    func testRecordedRomajiLengthMatchesWhatTheTransducerStreamed() {
        let cases: [(name: String, keys: [PhysicalKey], expected: Int)] = [
            ("THING", [.t, .h, .i, .n, .g], 7),  // l a  yu  nn  h
            ("WER", [.w, .e, .r], 5),            // w a  k a  r, shown as `わかr`
            ("EK", [.e, .k], 2),                 // k i
            ("H", [.h], 1),                      // a
        ]

        for testCase in cases {
            let snapshot = journal(typing: testCase.keys).snapshot(at: 0)
            XCTAssertEqual(snapshot?.romajiCharacterCount, testCase.expected, testCase.name)
        }
    }

    func testCountEqualsTheRomajiActuallyEmitted() {
        // Guard against the count drifting from the transducer: recompute it
        // from the actions instead of hard-coding a second table.
        let keys: [PhysicalKey] = [.w, .e, .r, .t, .h, .i, .n, .g]
        let engine = WKRTransducer(mode: .prefixRomaji)
        var journal = EnglishFallbackJournal()
        var emitted = 0

        for key in keys {
            let event = WKRInputEvent.physical(key)
            let result = engine.process(event)
            for case let .romaji(value) in result.actions {
                emitted += value.count
            }
            journal.record(event, result: result, at: 0)
        }

        XCTAssertEqual(journal.snapshot(at: 0)?.romajiCharacterCount, emitted)
    }

    // MARK: - Surviving the `英数` key

    func testInputSourceChangeKeepsTheJournal() {
        var journal = self.journal(typing: [.t, .h, .i, .n, .g])
        journal.record(
            .reset(.inputSourceChanged),
            result: TransitionResult(disposition: .passThrough, stateCode: .reset),
            at: 0
        )

        XCTAssertEqual(journal.snapshot(at: 0)?.keys.count, 5)
    }

    func testEveryOtherResetReasonClearsTheJournal() {
        let reasons: [ResetReason] = [
            .escape, .applicationChanged, .mouse, .cursorMovement,
            .modifiedKey, .tapDisabled, .secureInput, .explicitStop,
        ]

        for reason in reasons {
            var journal = self.journal(typing: [.t, .h, .i, .n, .g])
            journal.record(
                .reset(reason),
                result: TransitionResult(disposition: .passThrough, stateCode: .reset),
                at: 0
            )
            XCTAssertNil(journal.snapshot(at: 0), String(describing: reason))
        }
    }

    // MARK: - Fail closed

    func testBoundaryKeysClearTheJournal() {
        for boundary in [BoundaryKey.space, .enter, .tab, .punctuation, .other] {
            var journal = self.journal(typing: [.e, .k])
            journal.record(
                .boundary(boundary),
                result: TransitionResult(disposition: .passThrough, stateCode: .idle),
                at: 0
            )
            XCTAssertNil(journal.snapshot(at: 0), String(describing: boundary))
        }
    }

    func testBackspaceClearsTheJournal() {
        var journal = self.journal(typing: [.e, .k])
        journal.record(
            .backspace,
            result: TransitionResult(disposition: .suppress, stateCode: .canceledPending),
            at: 0
        )

        XCTAssertNil(journal.snapshot(at: 0))
    }

    func testUnicodeOutputStopsTheJournal() {
        // `WJ` is `ヴ`, injected as a Unicode string, so it commits on the spot
        // instead of joining the romaji the connect-back can return.
        XCTAssertNil(journal(typing: [.w, .j]).snapshot(at: 0))
    }

    func testAnUnexplainedBackspaceStopsTheJournal() {
        // Without a character figure from the transducer, a backspace count is
        // in display units and cannot be reconciled with the romaji on screen.
        var journal = self.journal(typing: [.e])
        journal.record(
            .physical(.k),
            result: TransitionResult(
                actions: [.backspace(count: 1), .romaji("ki")],
                disposition: .suppress,
                stateCode: .optimisticReplacement
            ),
            at: 0
        )

        XCTAssertNil(journal.snapshot(at: 0))
    }

    func testABackspaceLongerThanTheRecordStopsTheJournal() {
        var journal = self.journal(typing: [.e])  // one character, `k`
        journal.record(
            .physical(.k),
            result: TransitionResult(
                actions: [.backspace(count: 1)],
                disposition: .suppress,
                stateCode: .prefixRollback,
                deletedRomajiCharacters: 5
            ),
            at: 0
        )

        XCTAssertNil(journal.snapshot(at: 0))
    }

    func testPassThroughKeyStopsTheJournal() {
        // A key with no rule reaches Apple Japanese Input itself, so the
        // streamed romaji is no longer the whole pre-edit.
        var journal = self.journal(typing: [.e])
        journal.record(
            .physical(.k),
            result: TransitionResult(disposition: .passThrough, stateCode: .passthrough),
            at: 0
        )

        XCTAssertNil(journal.snapshot(at: 0))
    }

    func testExceedingTheKeyLimitStopsTheJournal() {
        XCTAssertNotNil(journal(typing: [.e, .k, .e], limit: 3).snapshot(at: 0))
        XCTAssertNil(journal(typing: [.e, .k, .e, .k], limit: 3).snapshot(at: 0))
    }

    func testTheLimitStaysWithinTheMeasuredPreEditLength() {
        // Every rule consumes at least one key, so the limit also bounds the
        // kana in the pre-edit. 2026-08-14 measured that a pre-edit of about
        // twelve kana does not commit any part of itself on its own.
        XCTAssertLessThanOrEqual(EnglishFallbackJournal.defaultKeyLimit, 12)
    }

    func testAnInvalidatedJournalStaysClosedUntilABoundary() {
        var journal = self.journal(typing: [.w, .j])
        let event = WKRInputEvent.physical(.e)
        let engine = WKRTransducer(mode: .prefixRomaji)
        journal.record(event, result: engine.process(event), at: 0)

        XCTAssertNil(journal.snapshot(at: 0))

        journal.record(
            .boundary(.enter),
            result: TransitionResult(disposition: .passThrough, stateCode: .idle),
            at: 0
        )
        let reopened = WKRTransducer(mode: .prefixRomaji)
        let reopenedEvent = WKRInputEvent.physical(.h)
        journal.record(reopenedEvent, result: reopened.process(reopenedEvent), at: 0)

        XCTAssertEqual(journal.snapshot(at: 0)?.keys, [.h])
    }

    func testTheJournalExpires() {
        let journal = self.journal(typing: [.e, .k], at: 100)

        XCTAssertNotNil(journal.snapshot(at: 100 + 29))
        XCTAssertNil(journal.snapshot(at: 100 + 30))
    }

    func testAnEmptyJournalOffersNothing() {
        XCTAssertNil(EnglishFallbackJournal().snapshot(at: 0))
    }

    // MARK: - Physical key to character

    func testKeysCarryTheirPrintedCharacter() {
        let cases: [(PhysicalKey, Character)] = [
            (.t, "t"), (.g, "g"), (.semicolon, ";"), (.digit1, "1"),
            // JIS shifted positions, which differ from ANSI.
            (.shiftedDigit2, "\""), (.shiftedDigit6, "&"), (.shiftedDigit7, "'"),
            (.shiftedDigit8, "("), (.shiftedDigit9, ")"),
            (.leftBrace, "{"), (.rightBrace, "}"), (.jisUnderscore, "_"),
            (.shiftedAt, "`"), (.shiftedCaret, "~"),
        ]

        for (key, expected) in cases {
            XCTAssertEqual(key.jisCharacter, expected, key.rawValue)
        }
    }

    func testEveryPhysicalKeyHasAJISCharacter() {
        for key in PhysicalKey.allCases {
            XCTAssertNotEqual(key.jisCharacter, "\u{FFFD}", key.rawValue)
        }
    }

    func testThingReadsBackAsThing() {
        let snapshot = journal(typing: [.t, .h, .i, .n, .g]).snapshot(at: 0)
        let letters = snapshot.map { String($0.keys.map(\.jisCharacter)) }

        XCTAssertEqual(letters, "thing")
    }

    // MARK: - Trigger

    func testTriggerNamesRoundTrip() {
        for trigger in EnglishFallbackTrigger.allCases {
            XCTAssertEqual(EnglishFallbackTrigger(rawValue: trigger.rawValue), trigger)
        }
    }

    func testTheDefaultTriggerIsTheEisuBurst() {
        // Holding `英数` while reaching for Return proved to be an awkward hand
        // movement: the key was usually already released by the time Return
        // was pressed, so the chord never fired.
        XCTAssertEqual(EnglishFallbackTrigger.default, .eisuBurst)
        XCTAssertEqual(EnglishFallbackTrigger.default.rawValue, "eisu+eisu")
    }

    func testABurstNeedsAtLeastTwoPresses() {
        // One press is an ordinary switch to English and must never replace
        // text.
        XCTAssertGreaterThanOrEqual(EnglishFallbackTrigger.minimumBurstPresses, 2)
        XCTAssertGreaterThan(EnglishFallbackTrigger.burstSettleSeconds, 0)
    }

    func testAnUnknownTriggerNameIsRejected() {
        XCTAssertNil(EnglishFallbackTrigger(rawValue: "eisu+escape"))
    }
}
