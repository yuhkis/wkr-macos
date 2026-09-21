import AppKit
import WKRCore

final class StatusItemController: NSObject, NSMenuDelegate {
    var menuContentProvider: (() -> ConversionMenuContent)?
    var menuOpenStateChanged: ((Bool) -> Void)?
    var openHeatmapRequested: (() -> Void)?
    var chooseKeymapRequested: (() -> Void)?
    var clearKeymapRequested: (() -> Void)?
    var keymapFileNameProvider: (() -> String?)?

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let titleItem = NSMenuItem()
    private let detailItems: [NSMenuItem]
    private let remedyItem = NSMenuItem()
    private let keymapItem = NSMenuItem()
    private let clearKeymapItem = NSMenuItem()
    private var images: [ConversionStatus: NSImage] = [:]
    private var lastApplied: ConversionStatus?

    private(set) var usesSymbols = false

    private(set) var isUsable = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        detailItems = [NSMenuItem(), NSMenuItem()]
        super.init()

        guard statusItem.button != nil else { return }
        isUsable = true

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
        let version = NSMenuItem(title: "v1保存版 0.7.0-archive.1 / 配列 1.1.0", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())

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

        keymapItem.isEnabled = false
        keymapItem.target = nil
        keymapItem.action = nil
        menu.addItem(keymapItem)

        let choose = NSMenuItem(
            title: ConversionStatusText.chooseKeymapTitle,
            action: #selector(chooseKeymapChosen),
            keyEquivalent: ""
        )
        choose.target = self
        choose.isEnabled = true
        menu.addItem(choose)

        clearKeymapItem.title = ConversionStatusText.clearKeymapTitle
        clearKeymapItem.action = #selector(clearKeymapChosen)
        clearKeymapItem.target = self
        clearKeymapItem.isEnabled = true
        menu.addItem(clearKeymapItem)

        menu.addItem(.separator())

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

    func apply(_ status: ConversionStatus) {
        guard lastApplied != status else { return }
        lastApplied = status

        let title = ConversionStatusText.statusTitle(status)
        if let button = statusItem.button {
            if let image = images[status] {
                button.image = image
                button.title = ""
            } else {
                button.image = nil
                button.title = ConversionStatusText.fallbackGlyph(status)
            }
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }
        titleItem.title = title
    }


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

        let keymapFileName = keymapFileNameProvider?()
        keymapItem.title = ConversionStatusText.keymapLine(fileName: keymapFileName)
        clearKeymapItem.isHidden = keymapFileName == nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpenStateChanged?(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpenStateChanged?(false)
    }

    @objc private func openHeatmapChosen() {
        DispatchQueue.main.async { [weak self] in
            self?.openHeatmapRequested?()
        }
    }

    @objc private func chooseKeymapChosen() {
        DispatchQueue.main.async { [weak self] in
            self?.chooseKeymapRequested?()
        }
    }

    @objc private func clearKeymapChosen() {
        DispatchQueue.main.async { [weak self] in
            self?.clearKeymapRequested?()
        }
    }

    @objc private func quitChosen() {
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
