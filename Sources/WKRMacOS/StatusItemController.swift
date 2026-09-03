import AppKit
import WKRCore

/// The menu bar item.
///
/// Plumbing only: every string and every decision about what to say lives in
/// `ConversionStatusText`, in the target the tests can import. This file owns
/// the AppKit objects and nothing else.
///
/// It is display-only. Nothing here participates in the conversion gate, and a
/// failure to create the item or draw a symbol never stops the app — losing the
/// indicator is worth strictly less than losing conversion.
final class StatusItemController: NSObject, NSMenuDelegate {
    /// What the menu should show, gathered when it opens. The app delegate
    /// supplies this; sampling on open rather than on the timer is what keeps
    /// the holder's liveness fresh, since an orphaned count produces no edge.
    var menuContentProvider: (() -> ConversionMenuContent)?
    /// Called with `true` while the menu tracks and `false` when it stops, so
    /// the gate can be shut for the duration.
    var menuOpenStateChanged: ((Bool) -> Void)?
    /// Called when the user asks for the heatmap. Must return immediately: the
    /// event tap source is on this run loop.
    var openHeatmapRequested: (() -> Void)?

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let titleItem = NSMenuItem()
    private let detailItems: [NSMenuItem]
    private let remedyItem = NSMenuItem()
    private var images: [ConversionStatus: NSImage] = [:]
    private var lastApplied: ConversionStatus?

    /// True when every symbol resolved and the item is drawn as an icon; false
    /// when it fell back to text. Logged once at startup so a missing icon can
    /// be told apart from a hidden one.
    private(set) var usesSymbols = false

    /// False when the status bar gave us no button, which would leave an item
    /// that exists but can be neither seen nor clicked. The caller drops the
    /// controller in that case; it is not worth keeping an invisible one alive.
    private(set) var isUsable = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Two detail lines is the most any state needs (holder + elapsed).
        detailItems = [NSMenuItem(), NSMenuItem()]
        super.init()

        guard statusItem.button != nil else { return }
        isUsable = true

        // Never `.removalAllowed`: a stray Command-drag would persist
        // isVisible = false and silently delete the only surface this app has.
        statusItem.isVisible = true

        var resolvedAll = true
        for status in ConversionStatus.allCases {
            let name = ConversionStatusText.symbolName(status)
            guard let image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: ConversionStatusText.statusTitle(status)
            ) else {
                resolvedAll = false
                continue
            }
            image.isTemplate = true
            images[status] = image
        }
        usesSymbols = resolvedAll

        menu.autoenablesItems = false
        menu.delegate = self

        for item in [titleItem] + detailItems + [remedyItem] {
            item.isEnabled = false
            item.target = nil
            item.action = nil
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let heatmap = NSMenuItem(
            title: ConversionStatusText.openHeatmapTitle,
            action: #selector(openHeatmapChosen),
            keyEquivalent: ""
        )
        heatmap.target = self
        heatmap.isEnabled = true
        menu.addItem(heatmap)

        let quit = NSMenuItem(
            title: ConversionStatusText.quitTitle,
            action: #selector(quitChosen),
            keyEquivalent: ""
        )
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)

        statusItem.menu = menu
        apply(.stopping)
    }

    func removeFromStatusBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Draws `status`, doing nothing when it has not changed.
    ///
    /// Called from the 0.10 s safety timer, which shares the main run loop with
    /// the event tap source, so the steady state must touch no AppKit at all.
    func apply(_ status: ConversionStatus) {
        guard lastApplied != status else { return }
        lastApplied = status

        let title = ConversionStatusText.statusTitle(status)
        if let button = statusItem.button {
            if let image = images[status] {
                button.image = image
                button.title = ""
            } else {
                // An item with neither image nor title is invisible. Text is a
                // worse icon than a symbol and a far better one than nothing.
                button.image = nil
                button.title = ConversionStatusText.fallbackGlyph(status)
            }
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }
        titleItem.title = title
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        let content = menuContentProvider?() ?? ConversionMenuContent(status: lastApplied ?? .stopping)
        titleItem.title = ConversionStatusText.statusTitle(content.status)

        let details = ConversionStatusText.detailLines(content)
        for (index, item) in detailItems.enumerated() {
            if index < details.count {
                item.title = details[index]
                item.isHidden = false
            } else {
                item.title = ""
                item.isHidden = true
            }
        }

        if let remedy = ConversionStatusText.remedyLine(content) {
            remedyItem.title = remedy
            remedyItem.isHidden = false
        } else {
            remedyItem.title = ""
            remedyItem.isHidden = true
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpenStateChanged?(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpenStateChanged?(false)
    }

    @objc private func openHeatmapChosen() {
        // Hop off the menu's own call so this returns before any work starts.
        // The tap source shares this run loop.
        DispatchQueue.main.async { [weak self] in
            self?.openHeatmapRequested?()
        }
    }

    @objc private func quitChosen() {
        // Return immediately. The event tap source is on this run loop, and the
        // normal shutdown path (flush, summary) runs from applicationWillTerminate.
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
