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
        // `EY` is `ヶ`, which is injected as a Unicode string and commits on the
        // spot instead of joining the romaji the connect-back can return.
        XCTAssertNil(journal(typing: [.e, .y]).snapshot(at: 0))
    }

    func testRollbackBranchStopsTheJournal() {
        // `HT` is the trailing small `ぁ`: it deletes the `a` already shown, and
        // a backspace count is in display units rather than romaji characters.
        XCTAssertNil(journal(typing: [.h, .t]).snapshot(at: 0))
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
        var journal = self.journal(typing: [.h, .t])
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

    func testTheDefaultTriggerIsTheEisuReturnChord() {
        XCTAssertEqual(EnglishFallbackTrigger.default, .eisuReturn)
        XCTAssertEqual(EnglishFallbackTrigger.default.rawValue, "eisu+return")
    }

    func testAnUnknownTriggerNameIsRejected() {
        XCTAssertNil(EnglishFallbackTrigger(rawValue: "eisu+escape"))
    }
}
