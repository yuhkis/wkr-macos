import XCTest
@testable import WKRCore

final class EnglishFallbackJournalTests: XCTestCase {
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


    func testThingRecordsItsKeysAndTheStreamedRomajiLength() {
        let keys: [PhysicalKey] = [.t, .h, .i, .n, .g]
        let snapshot = journal(typing: keys).snapshot(at: 0)

        XCTAssertEqual(snapshot?.keys, keys)
        XCTAssertEqual(snapshot?.romajiCharacterCount, 7)
    }

    func testArrowKeysKeepTheJournalUsable() {
        let snapshot = journal(typing: [.y, .j]).snapshot(at: 0)

        XCTAssertEqual(snapshot?.keys, [.y, .j])
        XCTAssertEqual(snapshot?.romajiCharacterCount, 2)  // `z` + `j`
        XCTAssertEqual(
            snapshot.map { String($0.keys.map(\.jisCharacter)) },
            "yj"
        )
    }

    func testSymbolLayerStillStopsTheJournal() {
        XCTAssertNil(journal(typing: [.y, .a]).snapshot(at: 0))
    }

    func testRollbackBranchesStayRecoverable() {
        let cases: [(name: String, keys: [PhysicalKey], count: Int, letters: String)] = [
            ("EY", [.e, .y], 3, "ey"),
            ("EYWY", [.e, .y, .w, .y], 6, "eywy"),  // `lke` + `lwa`
            ("QY", [.q, .y], 3, "qy"),  // `g` taken back, `lka` sent
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

    func testRomanTransliterationClearsTheJournal() {
        var journal = self.journal(typing: [.e, .k])
        journal.record(
            .romanTransliteration,
            result: TransitionResult(
                disposition: .passThrough,
                stateCode: .romanTransliteration
            ),
            at: 0
        )

        XCTAssertNil(journal.snapshot(at: 0))
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
        XCTAssertNil(journal(typing: [.t, .comma]).snapshot(at: 0))
    }

    func testAnUnexplainedBackspaceStopsTheJournal() {
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
        XCTAssertLessThanOrEqual(EnglishFallbackJournal.defaultKeyLimit, 12)
    }

    func testAnInvalidatedJournalStaysClosedUntilABoundary() {
        var journal = self.journal(typing: [.t, .comma])
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


    func testKeysCarryTheirPrintedCharacter() {
        let cases: [(PhysicalKey, Character)] = [
            (.t, "t"), (.g, "g"), (.semicolon, ";"), (.digit1, "1"),
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


    func testTriggerNamesRoundTrip() {
        for trigger in EnglishFallbackTrigger.allCases {
            XCTAssertEqual(EnglishFallbackTrigger(rawValue: trigger.rawValue), trigger)
        }
    }

    func testTheDefaultTriggerIsTheEisuBurst() {
        XCTAssertEqual(EnglishFallbackTrigger.default, .eisuBurst)
        XCTAssertEqual(EnglishFallbackTrigger.default.rawValue, "eisu+eisu")
    }

    func testABurstNeedsAtLeastTwoPresses() {
        XCTAssertGreaterThanOrEqual(EnglishFallbackTrigger.minimumBurstPresses, 2)
        XCTAssertGreaterThan(EnglishFallbackTrigger.burstSettleSeconds, 0)
    }

    func testAnUnknownTriggerNameIsRejected() {
        XCTAssertNil(EnglishFallbackTrigger(rawValue: "eisu+escape"))
    }
}
