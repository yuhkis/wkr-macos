import AppKit
import WebKit
import XCTest
@testable import WKRMacOS
@testable import WKRPracticeUI

@MainActor
final class PracticeWindowTests: XCTestCase {
    func testBundledPracticeLoadsFromTemporaryDirectory() async throws {
        let (root, bundle) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try XCTUnwrap(PracticeWindowController(bundle: bundle,
            store: PracticeProgressStore(url: root.appendingPathComponent("progress.json"))))
        defer { controller.close() }
        let webView = try XCTUnwrap(controller.window?.contentView?.subviews.compactMap { $0 as? WKWebView }.first)
        let loaded = expectation(description: "The bundled lesson DOM is ready")
        let probe = PracticeNavigationProbe(original: controller, loaded: loaded)
        webView.navigationDelegate = probe
        await fulfillment(of: [loaded], timeout: 12)
        XCTAssertNil(probe.failureCode, "Navigation error code: \(probe.failureCode ?? 0)")
        XCTAssertEqual(probe.lessonCount, 12)
        XCTAssertEqual(controller.loadState, .ready)
        XCTAssertFalse(webView.isHidden)
        controller.webViewWebContentProcessDidTerminate(webView)
        XCTAssertEqual(controller.loadState, .failed)
        XCTAssertTrue(webView.isHidden)
    }
    func testRulePreparationFailureShowsRetryWithoutLoadingUnfilteredPage() throws {
        let (root, bundle) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try XCTUnwrap(PracticeWindowController(bundle: bundle,
            store: PracticeProgressStore(url: root.appendingPathComponent("progress.json")),
            compileRules: { completion in completion(nil, NSError(domain: "synthetic", code: 1)) }))
        defer { controller.close() }
        let content = try XCTUnwrap(controller.window?.contentView)
        let webView = try XCTUnwrap(content.subviews.compactMap { $0 as? WKWebView }.first)
        let status = try XCTUnwrap(content.subviews.compactMap { $0 as? NSStackView }.first)
        let retry = try XCTUnwrap(status.arrangedSubviews.compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(controller.loadState, .failed)
        XCTAssertNil(webView.url)
        XCTAssertTrue(webView.isHidden)
        XCTAssertFalse(status.isHidden)
        XCTAssertFalse(retry.isHidden)
    }
    func testRulePreparationCallbackAfterClosingDoesNotRestartPage() throws {
        let (root, bundle) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var completion: ((WKContentRuleList?, Error?) -> Void)?
        let controller = try XCTUnwrap(PracticeWindowController(bundle: bundle,
            store: PracticeProgressStore(url: root.appendingPathComponent("progress.json")),
            compileRules: { completion = $0 }))
        let webView = try XCTUnwrap(controller.window?.contentView?.subviews.compactMap { $0 as? WKWebView }.first)
        controller.close()
        completion?(nil, NSError(domain: "synthetic", code: 1))
        XCTAssertNil(webView.url)
        XCTAssertNotEqual(controller.loadState, .failed)
    }
    private func makeFixture() throws -> (URL, Bundle) {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("wkr-practice-test-" + UUID().uuidString, isDirectory: true)
        let contents = root.appendingPathComponent("Fixture.app/Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Practice")
        try FileManager.default.copyItem(at: source, to: resources.appendingPathComponent("Practice"))
        let info: [String: Any] = ["CFBundleIdentifier": "example.wkr.practice-test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(UnnormalizedResourceBundle(path: contents.deletingLastPathComponent().path))
        bundle.fixtureResourceURL = resources
        return (root, bundle)
    }

}

@MainActor
private final class PracticeNavigationProbe: NSObject, WKNavigationDelegate {
    let original: PracticeWindowController
    let loaded: XCTestExpectation
    var lessonCount = 0
    var failureCode: Int?
    init(original: PracticeWindowController, loaded: XCTestExpectation) {
        self.original = original
        self.loaded = loaded
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        original.webView(webView, decidePolicyFor: action, decisionHandler: decisionHandler)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        original.webView(webView, didFinish: navigation)
        webView.evaluateJavaScript("document.querySelectorAll('#lessons button').length") { value, error in
            self.lessonCount = value as? Int ?? 0
            self.failureCode = (error as NSError?)?.code
            self.loaded.fulfill()
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        original.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
        failureCode = (error as NSError).code
        loaded.fulfill()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failureCode = (error as NSError).code
        loaded.fulfill()
    }
}

// Bundle.main can preserve /private/tmp while an explicitly opened Bundle
// canonicalizes it to /tmp. Keep the actual launch spelling in this fixture.
private final class UnnormalizedResourceBundle: Bundle, @unchecked Sendable {
    var fixtureResourceURL: URL?
    override var resourceURL: URL? { fixtureResourceURL }
}
