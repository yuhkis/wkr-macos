import XCTest
@testable import WKRCore

final class LongVowelTrialTests: XCTestCase {
    func testRelocatedLongVowelAndMiddleDotAfterPendingKana() {
        for mode in [OutputMode.deferredRomaji, .prefixRomaji] {
            for rules in [WKRLayout.rules, WKRLayout.rulesWithoutSymbolLayer] {
                for (key, expected) in [(PhysicalKey.y, "ka-"), (.slash, "ka?"), (.shiftedSlash, "ka/")] {
                    let engine = WKRTransducer(mode: mode, rules: rules)
                    let results = [engine.process(.physical(.e)), engine.process(.physical(key))]
                    let actual = results.flatMap(\.actions).compactMap { action -> String? in
                        if case .romaji(let value) = action { return value }
                        return nil
                    }.joined()
                    XCTAssertEqual(actual, expected)
                    XCTAssertEqual(results.last?.disposition, .suppress)
                    XCTAssertFalse(engine.hasPendingInput)
                }
            }
        }
    }

    func testSymbolSelectorsRetainTheirPhysicalPositions() {
        for (keys, expected) in [([PhysicalKey.p, .y], "〒"), ([.p, .slash], "／"), ([.q, .slash], "／")] {
            XCTAssertEqual(WKRLayout.rules.first { $0.input == keys }?.kana, expected)
        }
    }

    func testMiddleDotInvalidatesEnglishRewriteAcrossPunctuation() {
        let engine = WKRTransducer(mode: .prefixRomaji)
        var journal = EnglishFallbackJournal()
        for key in [PhysicalKey.e, .k] {
            let event = WKRInputEvent.physical(key)
            journal.record(event, result: engine.process(event), at: 1)
        }
        XCTAssertNotNil(journal.snapshot(at: 1))
        let dot = WKRInputEvent.physical(.shiftedSlash)
        journal.record(dot, result: engine.process(dot), at: 1.1)
        XCTAssertNil(journal.snapshot(at: 1.1))
    }


}

extension LongVowelTrialTests {
    func testQuestionMarkClearsRewriteHistoryAndKeepsPriorLegends() throws {
        for key in [PhysicalKey.slash, .shiftedSlash] {
            let engine = WKRTransducer(mode: .prefixRomaji)
            var journal = EnglishFallbackJournal()
            for input in [PhysicalKey.e, .k, key, .s, .k] {
                let event = WKRInputEvent.physical(input)
                journal.record(event, result: engine.process(event), at: 1)
            }
            XCTAssertNil(journal.snapshot(at: 1))
        }
        XCTAssertEqual(WakaraKeyLegends.all.count, 28)
    }
}


extension LongVowelTrialTests {
    func testBeta11LegendRemainsDistinctAndLongVowelKeepsRewriteHistory() throws {
        let engine = WKRTransducer(mode: .prefixRomaji)
        var journal = EnglishFallbackJournal()
        for key in [PhysicalKey.e, .k, .y] {
            let event = WKRInputEvent.physical(key)
            journal.record(event, result: engine.process(event), at: 1)
        }
        XCTAssertNotNil(journal.snapshot(at: 1))
    }
}
