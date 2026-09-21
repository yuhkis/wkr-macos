import XCTest
@testable import WKRCore

final class PublicLayoutTests: XCTestCase {
    func testCompiledRulesEqualCanonicalJSON() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let object=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Resources/Layout/layout-v2.json"))) as! [String:Any]
        let expected=object["rules"] as! [[String:Any]]
        XCTAssertEqual(expected.count,WKRLayout.rules.count)
        for (rule,item) in zip(WKRLayout.rules,expected) {
            XCTAssertEqual(rule.id,item["id"] as? String)
            XCTAssertEqual(rule.input.map(\.rawValue),item["keys"] as? [String])
            XCTAssertEqual(rule.kana,item["output"] as? String)
            switch rule.action {
            case let .romaji(value): XCTAssertEqual(value,item["romaji"] as? String)
            case let .unicode(value): XCTAssertEqual(value,item["output"] as? String)
            case .backspace: XCTFail("layout cannot contain an action history")
            }
        }
    }
    func testPauseDisplayCannotClaimConversion() {
        XCTAssertEqual(ConversionStatus.resolve(gateOpen:false,secureInputEnabled:false,applicationAllowed:false,inputSourceMatches:true,statusMenuOpen:false,userPaused:true),.paused)
    }
    func testProgressRejectsOutOfBoundsValuesAndUnknownLessons() throws {
        for lessons in [["vowels":["completed":-1,"bestAccuracy":50]], ["vowels":["completed":1,"bestAccuracy":101]], ["unknown":["completed":1,"bestAccuracy":50]]] {
            let data=try JSONSerialization.data(withJSONObject:["schemaVersion":1,"layoutVersion":WKRLayout.layoutVersion,"lessons":lessons])
            XCTAssertNil(PracticeProgress.validated(data))
        }
    }
}
