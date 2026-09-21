import AppKit

/// A reviewable first-run screen; showing it never starts an event tap.
final class SetupWindowController: NSWindowController {
    var retry: (() -> Void)?
    var practice: (() -> Void)?
    private var retryButton: NSButton?
    private let explanation = NSTextField(wrappingLabelWithString: "")
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 580,height: 390),styleMask: [.titled,.closable],backing: .buffered,defer: false)
        window.title = "WKR macOS Public — 導入と権限"
        super.init(window: window)
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=false
        let title=NSTextField(labelWithString: "わから配列 v2 をはじめる");title.font = .boldSystemFont(ofSize: 22);stack.addArrangedSubview(title)
        stack.addArrangedSubview(explanation)
        for (label,selector) in [("入力監視の設定を開く",#selector(openInput)),("アクセシビリティの設定を開く",#selector(openAccessibility)),("状態を再確認して変換を開始",#selector(retryChosen)),("権限なしでキー位置を練習",#selector(practiceChosen))] {
            let button=NSButton(title: label,target: self,action: selector);stack.addArrangedSubview(button)
            if selector == #selector(retryChosen) { retryButton = button }
        }
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor,constant: 28),stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor,constant: -28),stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor,constant: 24)])
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    func show(reason: String, canStartConversion: Bool) {
        retryButton?.isEnabled = canStartConversion
        explanation.stringValue = reason + "\nApple日本語入力の『ひらがな』を自分で選んでください。配列を自動で切り替えることはありません。"
        NSApp.setActivationPolicy(.regular);showWindow(nil);NSApp.activate()
    }
    @objc private func openInput() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!) }
    @objc private func openAccessibility() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    @objc private func retryChosen() { retry?() }
    @objc private func practiceChosen() { practice?() }
}
