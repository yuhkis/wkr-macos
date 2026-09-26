import AppKit
import WKRCore
import WKRPracticeUI

// This executable never links the event-tap target or starts a converter.
final class PracticeAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PracticeWindowController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let window = PracticeWindowController() else {
            let alert = NSAlert(); alert.messageText = "同梱教材を読み込めません"
            alert.informativeText = "配布アプリを展開し直してください。"; alert.runModal()
            NSApp.terminate(nil); return
        }
        window.onClose = { NSApp.terminate(nil) }
        controller = window; window.show()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
if CommandLine.arguments.count > 1 {
    guard CommandLine.arguments == [CommandLine.arguments[0], "--version"] else {
        fputs("Unsupported option in the practice app.\n", stderr); exit(1)
    }
    print("わから v2 練習帳 " + PracticeMetadata.version + " / 配列 " + WKRLayout.layoutVersion)
    exit(0)
}
let application = NSApplication.shared
let delegate = PracticeAppDelegate()
application.setActivationPolicy(.regular); application.delegate = delegate
let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
appMenu.addItem(withTitle: "練習帳を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = appMenu; menu.addItem(item); application.mainMenu = menu
application.run()
