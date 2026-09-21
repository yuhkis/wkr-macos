import XCTest
@testable import WKRCore

final class UnicodeInjectionGateTests: XCTestCase {
    /// Drive a prefix-mode transducer through the gate exactly as the
    /// controller does, and return what would have been posted for each key.
    private func post(
        _ events: [WKRInputEvent],
        engine: WKRTransducer = WKRTransducer(mode: .prefixRomaji)
    ) -> [UnicodeInjectionGate.Decision] {
        var gate = UnicodeInjectionGate()
        return events.map { event in
            gate.decide(event, engine.process(event))
        }
    }

    private func keys(_ keys: [PhysicalKey]) -> [WKRInputEvent] {
        keys.map(WKRInputEvent.physical)
    }

    private func containsUnicode(_ decision: UnicodeInjectionGate.Decision) -> Bool {
        decision.result.actions.contains { action in
            guard case .unicode = action else { return false }
            return true
        }
    }

    // MARK: - The case the gate exists for

    func testSymbolIsInjectedWhenNothingIsPending() {
        // `Y` `A` is ※ at the start of an empty pre-edit: the provisional
        // `z` is the only thing on screen, and the same batch deletes it, so
        // the injection is allowed by this gate.
        let decisions = post(keys([.p, .a]))

        XCTAssertFalse(decisions[1].droppedUnicode)
        XCTAssertEqual(
            decisions[1].result.actions,
            [.backspace(count: 1), .unicode("※")]
        )
    }

    func testSymbolIsDroppedWhileAPreEditIsOpen() {
        // `W` `E` `R` `H` leaves `わから` uncommitted, and Apple Japanese Input
        // discards the injection in that state. Sending it anyway loses the
        // keystroke with nothing on screen to show for it. The `H` is there
        // because `P` straight after a row key is that row's special column
        // (`RP` is りぇ), so a bare kana before the symbol prefix takes its
        // vowel explicitly, in every row.
        let decisions = post(keys([.w, .e, .r, .h, .p, .a]))

        XCTAssertTrue(decisions[5].droppedUnicode)
        // The provisional `z` is still removed, so the sequence leaves the
        // pre-edit exactly as it was rather than a stray letter in it.
        XCTAssertEqual(decisions[5].result.actions, [.backspace(count: 1)])
    }

    func testTheDroppedInjectionKeepsTheRestOfTheResultIntact() {
        let decisions = post(keys([.w, .e, .r, .h, .p, .a]))
        let original = WKRTransducer(mode: .prefixRomaji)
        for event in keys([.w, .e, .r, .h, .p]) { _ = original.process(event) }
        let ungated = original.process(.physical(.a))

        XCTAssertEqual(decisions[5].result.disposition, ungated.disposition)
        XCTAssertEqual(decisions[5].result.stateCode, ungated.stateCode)
    }

    // MARK: - Every Unicode rule, not only the `Y` layer

    func testUnicodeRulesOutsideTheSymbolLayerAreGatedToo() {
        // `T` `,` is `，` and `T` `/` is `／`, the punctuation left on this
        // path now that `ヴ` reaches the pre-edit as `vu`.
        let comma = post(keys([.w, .e, .r, .q, .comma]))
        let slash = post(keys([.w, .e, .r, .q, .slash]))

        XCTAssertTrue(comma[4].droppedUnicode)
        XCTAssertTrue(slash[4].droppedUnicode)
    }

    // MARK: - What reopens the gate

    func testReturnCommitsSoTheNextSymbolIsInjected() {
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.enter)] + keys([.p, .a])
        )

        XCTAssertFalse(decisions.last!.droppedUnicode)
        XCTAssertTrue(containsUnicode(decisions.last!))
    }

    func testSpaceDoesNotReopenTheGate() {
        // Space converts without committing, so the pre-edit is still there.
        // Treating it as a commit would send an injection that cannot arrive.
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.space)] + keys([.p, .a])
        )

        XCTAssertTrue(decisions.last!.droppedUnicode)
    }

    func testPunctuationDoesNotReopenTheGate() {
        // Whether punctuation commits the pre-edit is unmeasured, and guessing
        // that it does costs a lost keystroke.
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.punctuation)] + keys([.p, .a])
        )

        XCTAssertTrue(decisions.last!.droppedUnicode)
    }

    func testKanaTransliterationBoundaryDoesNotReopenTheGateAfterATerminalRule() {
        // `E K` has completed its transducer rule, but the kana is still
        // marked text in Apple Japanese Input. Ctrl+J/K follows this `.other`
        // boundary path even though the transducer has no pending prefix.
        let decisions = post(
            keys([.e, .k]) + [.boundary(.other)] + keys([.p, .a])
        )

        XCTAssertTrue(decisions.last!.droppedUnicode)
    }

    func testRomanTransliterationKeepsThePreEditClosedToUnicode() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        var gate = UnicodeInjectionGate()
        for event in keys([.w, .e, .r]) {
            _ = gate.decide(event, engine.process(event))
        }

        let event = WKRInputEvent.romanTransliteration
        let transliteration = gate.decide(event, engine.process(event))

        XCTAssertEqual(transliteration.result.actions, [])
        XCTAssertFalse(gate.preEditIsEmpty)

        let symbol = keys([.p, .a]).map { gate.decide($0, engine.process($0)) }
        XCTAssertTrue(symbol.last!.droppedUnicode)
    }

    func testDeferredRomanTransliterationKeepsThePreEditClosedToUnicode() {
        let engine = WKRTransducer(mode: .deferredRomaji)
        var gate = UnicodeInjectionGate()
        for event in keys([.w, .e, .r]) {
            _ = gate.decide(event, engine.process(event))
        }

        let event = WKRInputEvent.romanTransliteration
        let transliteration = gate.decide(event, engine.process(event))

        XCTAssertEqual(transliteration.result.actions, [.romaji("r")])
        XCTAssertFalse(gate.preEditIsEmpty)
    }

    func testOptimisticRomanTransliterationKeepsTheRestoredPrefixInThePreEdit() {
        let engine = WKRTransducer(
            mode: .optimisticRomaji(.fullLayoutExperimental)
        )
        var gate = UnicodeInjectionGate()
        let physical = WKRInputEvent.physical(.e)
        _ = gate.decide(physical, engine.process(physical))

        let event = WKRInputEvent.romanTransliteration
        let transliteration = gate.decide(event, engine.process(event))

        XCTAssertEqual(
            transliteration.result.actions,
            [.backspace(count: 1), .romaji("k")]
        )
        XCTAssertFalse(gate.preEditIsEmpty)
    }

    func testRomanTransliterationKeepsTheGateClosedWithoutTransducerPendingInput() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        var gate = UnicodeInjectionGate()
        for event in keys([.e, .k]) {
            _ = gate.decide(event, engine.process(event))
        }
        XCTAssertFalse(engine.hasPendingInput)
        XCTAssertFalse(gate.preEditIsEmpty)

        let event = WKRInputEvent.romanTransliteration
        _ = gate.decide(event, engine.process(event))

        XCTAssertFalse(gate.preEditIsEmpty)
        let symbol = keys([.p, .a]).map { gate.decide($0, engine.process($0)) }
        XCTAssertTrue(symbol.last!.droppedUnicode)
    }

    func testAnInjectedSymbolLeavesThePreEditEmptyForTheNextOne() {
        // The injection commits on the spot, so two symbols in a row both work.
        let decisions = post(keys([.p, .a, .p, .c]))

        XCTAssertFalse(decisions[1].droppedUnicode)
        XCTAssertFalse(decisions[3].droppedUnicode)
        XCTAssertEqual(
            decisions[3].result.actions,
            [.backspace(count: 1), .unicode("〇")]
        )
    }

    func testClearReopensTheGate() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        var gate = UnicodeInjectionGate()
        for event in keys([.w, .e, .r]) {
            _ = gate.decide(event, engine.process(event))
        }
        XCTAssertFalse(gate.preEditIsEmpty)

        gate.clear()
        engine.reset()

        XCTAssertTrue(gate.preEditIsEmpty)
        let decisions = keys([.p, .a]).map { gate.decide($0, engine.process($0)) }
        XCTAssertFalse(decisions[1].droppedUnicode)
    }

    // MARK: - Ordinary kana are untouched

    func testRomajiOutputIsNeverAltered() {
        let events = keys([.w, .e, .r]) + [.boundary(.enter)]
        let gated = post(events)
        let plain = WKRTransducer(mode: .prefixRomaji)

        for (index, event) in events.enumerated() {
            XCTAssertEqual(gated[index].result, plain.process(event))
            XCTAssertFalse(gated[index].droppedUnicode)
        }
    }
}
