import AppKit
import WebKit
import WKRCore

public final class PracticeWindowController: NSWindowController, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    enum LoadState: Equatable { case loading, ready, failed }
    public typealias ContentRuleCompiler = (@escaping (WKContentRuleList?, Error?) -> Void) -> Void

    private let webView: WKWebView
    private let pageURL: URL
    private let resourceDirectoryURL: URL
    private let store: PracticeProgressStore
    private let compileRules: ContentRuleCompiler
    private let statusMessage = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton(title: "再読み込み", target: nil, action: nil)
    private let statusView = NSStackView()
    private let ioQueue = DispatchQueue(label: "wkr.public.practice-storage")
    private var rulesReady = false
    private var loadGeneration = 0
    private var loadTimeout: DispatchWorkItem?
    private var activeNavigation: WKNavigation?
    private var closed = false
    private(set) var loadState: LoadState = .loading
    public var onClose: (() -> Void)?

    public init?(bundle: Bundle = .main, store: PracticeProgressStore = PracticeProgressStore(),
          compileRules: ContentRuleCompiler? = nil) {
        guard let base = bundle.resourceURL?.appendingPathComponent("Practice", isDirectory: true),
              FileManager.default.fileExists(atPath: base.appendingPathComponent("index.html").path) else { return nil }
        // Use the same canonical spelling for both the document and read grant.
        // Bundle.main may preserve /private/tmp while standardizedFileURL uses /tmp.
        resourceDirectoryURL = base.resolvingSymlinksInPath().standardizedFileURL
        pageURL = resourceDirectoryURL.appendingPathComponent("index.html")
        self.store = store
        self.compileRules = compileRules ?? Self.compileOfflineRules
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 840), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "わから v2 練習帳 — \("練習 " + PracticeMetadata.version + " / 配列 " + WKRLayout.layoutVersion)"
        window.minSize = NSSize(width: 520, height: 560)
        let content = NSView()
        window.contentView = content
        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        config.userContentController.add(self, name: "wkrProgress")
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(webView)
        statusView.orientation = .vertical
        statusView.alignment = .centerX
        statusView.spacing = 16
        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusMessage.alignment = .center
        statusMessage.preferredMaxLayoutWidth = 420
        statusView.addArrangedSubview(statusMessage)
        statusView.addArrangedSubview(retryButton)
        retryButton.target = self
        retryButton.action = #selector(retryLoad)
        content.addSubview(statusView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            statusView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            statusView.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -48),
        ])
        window.center()
        loadPractice()
    }
    required public init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    public func show() {
        Self.configureEditingMenu()
        NSApp.setActivationPolicy(.regular); showWindow(nil)
        window?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    private static func configureEditingMenu() {
        // WKWebView forwards standard editing shortcuts through the menu's responder chain.
        let menu = NSApp.mainMenu ?? NSMenu()
        if menu.items.isEmpty {
            let appItem = NSMenuItem(), appMenu = NSMenu()
            appMenu.addItem(withTitle: "アプリを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            appItem.submenu = appMenu; menu.addItem(appItem)
        }
        if menu.items.contains(where: { $0.identifier?.rawValue == "wkr.practice.edit" }) { return }
        let item = NSMenuItem(title: "編集", action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("wkr.practice.edit")
        let edit = NSMenu(title: "編集")
        for (title, action, key) in [("取り消す", "undo:", "z"), ("切り取る", "cut:", "x"),
                                     ("コピー", "copy:", "c"), ("ペースト", "paste:", "v"),
                                     ("すべてを選択", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        item.submenu = edit; menu.addItem(item); NSApp.mainMenu = menu
    }
    public func windowWillClose(_ notification: Notification) {
        closed = true
        loadGeneration += 1
        loadTimeout?.cancel()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wkrProgress")
        webView.stopLoading()
        onClose?()
    }
    private static func compileOfflineRules(_ completion: @escaping (WKContentRuleList?, Error?) -> Void) {
        // CSP also denies connections; no unfiltered fallback is loaded on failure.
        let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "wkr-public-offline", encodedContentRuleList: rules, completionHandler: completion)
    }
    @objc private func retryLoad() { loadPractice() }
    private func loadPractice() {
        guard !closed else { return }
        loadGeneration += 1
        let generation = loadGeneration
        activeNavigation = nil
        webView.stopLoading()
        loadTimeout?.cancel()
        loadState = .loading
        webView.isHidden = true
        statusView.isHidden = false
        retryButton.isHidden = true
        statusMessage.stringValue = "練習を読み込んでいます…"
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.loadGeneration == generation, self.loadState == .loading else { return }
            self.showFailure("読み込みに時間がかかっています。もう一度お試しください。")
        }
        loadTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        if rulesReady { loadPage(); return }
        compileRules { [weak self] list, error in
            guard let self, !self.closed, self.loadGeneration == generation, self.loadState == .loading else { return }
            guard let list, error == nil else {
                self.showFailure("練習の準備を完了できませんでした。もう一度お試しください。")
                return
            }
            self.webView.configuration.userContentController.add(list)
            self.rulesReady = true
            self.loadPage()
        }
    }
    private func loadPage() {
        activeNavigation = webView.loadFileURL(pageURL, allowingReadAccessTo: resourceDirectoryURL)
        if activeNavigation == nil { showFailure("同梱の練習を読み込めませんでした。もう一度お試しください。") }
    }
    private func showFailure(_ message: String) {
        guard !closed else { return }
        loadState = .failed
        activeNavigation = nil
        loadTimeout?.cancel()
        webView.stopLoading()
        webView.isHidden = true
        statusView.isHidden = false
        retryButton.isHidden = false
        statusMessage.stringValue = message
    }
    private func isPracticeDocument(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL == pageURL
    }
    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.targetFrame?.isMainFrame == true && isPracticeDocument(action.request.url) ? .allow : .cancel)
    }
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !closed, loadState == .loading, let navigation, navigation === activeNavigation else { return }
        loadTimeout?.cancel()
        loadState = .ready
        statusView.isHidden = true
        webView.isHidden = false
    }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation)
    }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation)
    }
    private func navigationFailed(_ navigation: WKNavigation?) {
        guard let navigation, navigation === activeNavigation else { return }
        showFailure("同梱の練習を読み込めませんでした。もう一度お試しください。")
    }
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showFailure("練習の表示が停止しました。再読み込みして続けてください。")
    }
    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, isPracticeDocument(message.frameInfo.request.url),
              let body = message.body as? [String: Any], let action = body["action"] as? String,
              ["load","save","delete"].contains(action) else { return }
        var incoming: PracticeProgress?
        if action == "save" {
            guard let object = body["progress"], JSONSerialization.isValidJSONObject(object),
                  let bytes = try? JSONSerialization.data(withJSONObject: object),
                  let value = PracticeProgress.validated(bytes) else { return }
            incoming = value
        }
        // Disk I/O is off the event tap's run loop. No input text is bridged.
        ioQueue.async { [weak self] in
            guard let self else { return }
            var payload: [String: Any]
            do {
                switch action {
                case "save": try self.store.save(incoming!)
                case "delete": try self.store.delete()
                default: break
                }
                let loaded = try self.store.load()
                let data = try JSONEncoder().encode(loaded ?? .empty)
                payload = ["enabled": loaded != nil, "progress": try JSONSerialization.jsonObject(with: data)]
            } catch { payload = ["error": true] }
            guard let bytes = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: bytes, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in self?.webView.evaluateJavaScript("window.wkrReceiveProgress(\(json))", completionHandler: nil) }
        }
    }
}
