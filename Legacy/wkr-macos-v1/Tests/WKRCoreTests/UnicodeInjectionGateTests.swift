import XCTest
@testable import WKRCore

final class UnicodeInjectionGateTests: XCTestCase {
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


    func testSymbolIsInjectedWhenNothingIsPending() {
        let decisions = post(keys([.y, .a]))

        XCTAssertFalse(decisions[1].droppedUnicode)
        XCTAssertEqual(
            decisions[1].result.actions,
            [.backspace(count: 1), .unicode("※")]
        )
    }

    func testSymbolIsDroppedWhileAPreEditIsOpen() {
        let decisions = post(keys([.w, .e, .r, .y, .a]))

        XCTAssertTrue(decisions[4].droppedUnicode)
        XCTAssertEqual(decisions[4].result.actions, [.backspace(count: 1)])
    }

    func testTheDroppedInjectionKeepsTheRestOfTheResultIntact() {
        let decisions = post(keys([.w, .e, .r, .y, .a]))
        let original = WKRTransducer(mode: .prefixRomaji)
        for event in keys([.w, .e, .r, .y]) { _ = original.process(event) }
        let ungated = original.process(.physical(.a))

        XCTAssertEqual(decisions[4].result.disposition, ungated.disposition)
        XCTAssertEqual(decisions[4].result.stateCode, ungated.stateCode)
    }


    func testUnicodeRulesOutsideTheSymbolLayerAreGatedToo() {
        let comma = post(keys([.w, .e, .r, .t, .comma]))
        let slash = post(keys([.w, .e, .r, .t, .slash]))

        XCTAssertTrue(comma[4].droppedUnicode)
        XCTAssertTrue(slash[4].droppedUnicode)
    }


    func testReturnCommitsSoTheNextSymbolIsInjected() {
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.enter)] + keys([.y, .a])
        )

        XCTAssertFalse(decisions.last!.droppedUnicode)
        XCTAssertTrue(containsUnicode(decisions.last!))
    }

    func testSpaceDoesNotReopenTheGate() {
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.space)] + keys([.y, .a])
        )

        XCTAssertTrue(decisions.last!.droppedUnicode)
    }

    func testPunctuationDoesNotReopenTheGate() {
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.punctuation)] + keys([.y, .a])
        )

        XCTAssertTrue(decisions.last!.droppedUnicode)
    }

    func testKanaTransliterationBoundaryDoesNotReopenTheGateAfterATerminalRule() {
        let decisions = post(
            keys([.e, .k]) + [.boundary(.other)] + keys([.y, .a])
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

        let symbol = keys([.y, .a]).map { gate.decide($0, engine.process($0)) }
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
        let symbol = keys([.y, .a]).map { gate.decide($0, engine.process($0)) }
        XCTAssertTrue(symbol.last!.droppedUnicode)
    }

    func testAnInjectedSymbolLeavesThePreEditEmptyForTheNextOne() {
        let decisions = post(keys([.y, .a, .y, .c]))

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
        let decisions = keys([.y, .a]).map { gate.decide($0, engine.process($0)) }
        XCTAssertFalse(decisions[1].droppedUnicode)
    }


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
