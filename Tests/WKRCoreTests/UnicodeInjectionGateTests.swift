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
        // `Y` `J` at the start of an empty pre-edit: the provisional `y` is the
        // only thing on screen, and the same batch deletes it, so the
        // injection lands. This is what was measured working on 2026-08-16.
        let decisions = post(keys([.y, .j]))

        XCTAssertFalse(decisions[1].droppedUnicode)
        XCTAssertEqual(
            decisions[1].result.actions,
            [.backspace(count: 1), .unicode("↓")]
        )
    }

    func testSymbolIsDroppedWhileAPreEditIsOpen() {
        // `W` `E` `R` leaves `わから` uncommitted, and Apple Japanese Input
        // discards the injection in that state. Sending it anyway loses the
        // keystroke with nothing on screen to show for it.
        let decisions = post(keys([.w, .e, .r, .y, .j]))

        XCTAssertTrue(decisions[4].droppedUnicode)
        // The provisional `y` is still removed, so the sequence leaves the
        // pre-edit exactly as it was rather than a stray letter in it.
        XCTAssertEqual(decisions[4].result.actions, [.backspace(count: 1)])
    }

    func testTheDroppedInjectionKeepsTheRestOfTheResultIntact() {
        let decisions = post(keys([.w, .e, .r, .y, .j]))
        let original = WKRTransducer(mode: .prefixRomaji)
        for event in keys([.w, .e, .r, .y]) { _ = original.process(event) }
        let ungated = original.process(.physical(.j))

        XCTAssertEqual(decisions[4].result.disposition, ungated.disposition)
        XCTAssertEqual(decisions[4].result.stateCode, ungated.stateCode)
    }

    // MARK: - Every Unicode rule, not only the `Y` layer

    func testUnicodeRulesOutsideTheSymbolLayerAreGatedToo() {
        // `T` `,` is `，`, and `E` `Y` is `ヶ`. Both take the same path.
        let comma = post(keys([.w, .e, .r, .t, .comma]))
        let smallKe = post(keys([.w, .e, .r, .e, .y]))

        XCTAssertTrue(comma[4].droppedUnicode)
        XCTAssertTrue(smallKe[4].droppedUnicode)
    }

    // MARK: - What reopens the gate

    func testReturnCommitsSoTheNextSymbolIsInjected() {
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.enter)] + keys([.y, .j])
        )

        XCTAssertFalse(decisions.last!.droppedUnicode)
        XCTAssertTrue(containsUnicode(decisions.last!))
    }

    func testSpaceDoesNotReopenTheGate() {
        // Space converts without committing, so the pre-edit is still there.
        // Treating it as a commit would send an injection that cannot arrive.
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.space)] + keys([.y, .j])
        )

        XCTAssertTrue(decisions.last!.droppedUnicode)
    }

    func testPunctuationDoesNotReopenTheGate() {
        // Whether punctuation commits the pre-edit is unmeasured, and guessing
        // that it does costs a lost keystroke.
        let decisions = post(
            keys([.w, .e, .r]) + [.boundary(.punctuation)] + keys([.y, .j])
        )

        XCTAssertTrue(decisions.last!.droppedUnicode)
    }

    func testAnInjectedSymbolLeavesThePreEditEmptyForTheNextOne() {
        // The injection commits on the spot, so two symbols in a row both work.
        let decisions = post(keys([.y, .j, .y, .k]))

        XCTAssertFalse(decisions[1].droppedUnicode)
        XCTAssertFalse(decisions[3].droppedUnicode)
        XCTAssertEqual(
            decisions[3].result.actions,
            [.backspace(count: 1), .unicode("↑")]
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
        let decisions = keys([.y, .j]).map { gate.decide($0, engine.process($0)) }
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
