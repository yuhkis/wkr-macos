import Foundation

public struct VialHoldAction: Equatable, Sendable {
    public let legend: String
    public let identity: KeyIdentity?
    public let exclusion: KeyCapExclusion?

    public init(
        legend: String,
        identity: KeyIdentity?,
        exclusion: KeyCapExclusion?
    ) {
        self.legend = legend
        self.identity = identity
        self.exclusion = exclusion
    }
}

public struct VialKeyAssignment: Equatable, Sendable {
    public let raw: String
    public let legend: KeyCapLegend
    public let identity: KeyIdentity?
    public let exclusion: KeyCapExclusion?
    public let holdAction: VialHoldAction?

    public init(
        raw: String,
        legend: KeyCapLegend,
        identity: KeyIdentity?,
        exclusion: KeyCapExclusion?,
        holdAction: VialHoldAction? = nil
    ) {
        self.raw = raw
        self.legend = legend
        self.identity = identity
        self.exclusion = exclusion
        self.holdAction = holdAction
    }

    public var firmwareShiftSide: FirmwareShiftSide? {
        guard identity?.isShifted == true else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if token.hasPrefix("RSFT(") { return .right }
        if token.hasPrefix("LSFT(") { return .left }
        if token.hasPrefix("0X"),
           let value = UInt32(token.dropFirst(2), radix: 16),
           (0x0100...0x1FFF).contains(value) {
            return (value >> 8) & 0x10 != 0 ? .right : .left
        }
        return .left
    }

    public var isAbsent: Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return token == "-1" || token == "KC_NO" || token == "0X0"
    }
}

public enum FirmwareShiftSide: Equatable, Sendable {
    case left
    case right
}

public enum VialKeymapError: Error, Equatable, LocalizedError {
    case notJSON
    case missingLayout
    case emptyLayout

    public var errorDescription: String? {
        switch self {
        case .notJSON:
            return "Vialの.vilファイルとして読めません。JSON形式ではありません。"
        case .missingLayout:
            return "Vialの.vilファイルに layout がありません。別の形式のファイルの可能性があります。"
        case .emptyLayout:
            return "layout にレイヤーが1つもないため、レイヤー0を読めません。"
        }
    }
}

public struct VialKeymap: Equatable, Sendable {
    public let layers: [[[VialKeyAssignment]]]
    public var baseLayer: [[VialKeyAssignment]] { layers.first ?? [] }
    public let firmwareShiftSides: Set<FirmwareShiftSide>

    public init(
        layers: [[[VialKeyAssignment]]],
        firmwareShiftSides: Set<FirmwareShiftSide> = []
    ) {
        self.layers = layers
        self.firmwareShiftSides = firmwareShiftSides
    }

    public init(
        baseLayer: [[VialKeyAssignment]],
        firmwareShiftSides: Set<FirmwareShiftSide> = []
    ) {
        self.init(layers: [baseLayer], firmwareShiftSides: firmwareShiftSides)
    }

    public static func parse(data: Data) throws -> VialKeymap {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw VialKeymapError.notJSON
        }
        guard let root = object as? [String: Any] else { throw VialKeymapError.notJSON }
        guard let layers = root["layout"] as? [Any] else { throw VialKeymapError.missingLayout }
        guard let base = layers.first else { throw VialKeymapError.emptyLayout }
        guard let rows = base as? [Any] else { throw VialKeymapError.missingLayout }
        guard !rows.isEmpty else { throw VialKeymapError.emptyLayout }

        let decodedLayers: [[[VialKeyAssignment]]] = layers.map { layer in
            guard let layerRows = layer as? [Any] else { return [] }
            return layerRows.map { row in
                guard let entries = row as? [Any] else { return [] }
                return entries.map(VialTokenDecoder.assignment(forEntry:))
            }
        }

        var sides: Set<FirmwareShiftSide> = []
        for layer in decodedLayers {
            for row in layer {
                for assignment in row {
                    if let side = assignment.firmwareShiftSide {
                        sides.insert(side)
                    }
                }
            }
        }

        return VialKeymap(layers: decodedLayers, firmwareShiftSides: sides)
    }

    public static func decode(token: String) -> VialKeyAssignment {
        VialTokenDecoder.decode(token: token, depth: 0)
    }
}

private struct QMKBasicKeycode: Sendable {
    let qmk: UInt16
    let names: [String]
    let macOS: UInt16?
    let legend: String
    let exclusion: KeyCapExclusion?
}

private enum VialTokenDecoder {
    private enum ModMask {
        static let ctrl: UInt8 = 0x01
        static let shift: UInt8 = 0x02
        static let alt: UInt8 = 0x04
        static let gui: UInt8 = 0x08
        static let right: UInt8 = 0x10
        static let uncounted: UInt8 = ctrl | alt | gui
    }

    private static let maximumNesting = 8

    private static func key(
        _ qmk: UInt16,
        _ names: [String],
        _ macOS: UInt16?,
        _ legend: String,
        _ exclusion: KeyCapExclusion? = nil
    ) -> QMKBasicKeycode {
        QMKBasicKeycode(qmk: qmk, names: names, macOS: macOS, legend: legend, exclusion: exclusion)
    }

    private static let table: [QMKBasicKeycode] = [
        key(0x00, ["KC_NO"], nil, ""),
        key(0x01, ["KC_TRANSPARENT", "KC_TRNS"], nil, "▽", .unmappedOnMacOS),

        key(0x04, ["KC_A"], 0x00, "A"),
        key(0x05, ["KC_B"], 0x0B, "B"),
        key(0x06, ["KC_C"], 0x08, "C"),
        key(0x07, ["KC_D"], 0x02, "D"),
        key(0x08, ["KC_E"], 0x0E, "E"),
        key(0x09, ["KC_F"], 0x03, "F"),
        key(0x0A, ["KC_G"], 0x05, "G"),
        key(0x0B, ["KC_H"], 0x04, "H"),
        key(0x0C, ["KC_I"], 0x22, "I"),
        key(0x0D, ["KC_J"], 0x26, "J"),
        key(0x0E, ["KC_K"], 0x28, "K"),
        key(0x0F, ["KC_L"], 0x25, "L"),
        key(0x10, ["KC_M"], 0x2E, "M"),
        key(0x11, ["KC_N"], 0x2D, "N"),
        key(0x12, ["KC_O"], 0x1F, "O"),
        key(0x13, ["KC_P"], 0x23, "P"),
        key(0x14, ["KC_Q"], 0x0C, "Q"),
        key(0x15, ["KC_R"], 0x0F, "R"),
        key(0x16, ["KC_S"], 0x01, "S"),
        key(0x17, ["KC_T"], 0x11, "T"),
        key(0x18, ["KC_U"], 0x20, "U"),
        key(0x19, ["KC_V"], 0x09, "V"),
        key(0x1A, ["KC_W"], 0x0D, "W"),
        key(0x1B, ["KC_X"], 0x07, "X"),
        key(0x1C, ["KC_Y"], 0x10, "Y"),
        key(0x1D, ["KC_Z"], 0x06, "Z"),

        key(0x1E, ["KC_1"], 0x12, "1"),
        key(0x1F, ["KC_2"], 0x13, "2"),
        key(0x20, ["KC_3"], 0x14, "3"),
        key(0x21, ["KC_4"], 0x15, "4"),
        key(0x22, ["KC_5"], 0x17, "5"),
        key(0x23, ["KC_6"], 0x16, "6"),
        key(0x24, ["KC_7"], 0x1A, "7"),
        key(0x25, ["KC_8"], 0x1C, "8"),
        key(0x26, ["KC_9"], 0x19, "9"),
        key(0x27, ["KC_0"], 0x1D, "0"),

        key(0x28, ["KC_ENTER", "KC_ENT"], 0x24, "Enter"),
        key(0x29, ["KC_ESCAPE", "KC_ESC"], 0x35, "Esc"),
        key(0x2A, ["KC_BSPACE", "KC_BSPC", "KC_BACKSPACE"], 0x33, "Bksp"),
        key(0x2B, ["KC_TAB"], 0x30, "Tab"),
        key(0x2C, ["KC_SPACE", "KC_SPC"], 0x31, "Space"),
        key(0x2D, ["KC_MINUS", "KC_MINS"], 0x1B, "-"),
        key(0x2E, ["KC_EQUAL", "KC_EQL"], 0x18, "="),
        key(0x2F, ["KC_LBRACKET", "KC_LBRC", "KC_LEFT_BRACKET"], 0x21, "["),
        key(0x30, ["KC_RBRACKET", "KC_RBRC", "KC_RIGHT_BRACKET"], 0x1E, "]"),
        key(0x31, ["KC_BSLASH", "KC_BSLS", "KC_BACKSLASH"], 0x2A, "\\"),
        key(0x32, ["KC_NONUS_HASH", "KC_NUHS"], 0x2A, "#"),
        key(0x33, ["KC_SCOLON", "KC_SCLN", "KC_SEMICOLON"], 0x29, ";"),
        key(0x34, ["KC_QUOTE", "KC_QUOT", "KC_APOSTROPHE"], 0x27, "'"),
        key(0x35, ["KC_GRAVE", "KC_GRV"], 0x32, "`"),
        key(0x36, ["KC_COMMA", "KC_COMM"], 0x2B, ","),
        key(0x37, ["KC_DOT"], 0x2F, "."),
        key(0x38, ["KC_SLASH", "KC_SLSH"], 0x2C, "/"),
        key(0x39, ["KC_CAPSLOCK", "KC_CAPS", "KC_CAPS_LOCK"], 0x39, "Caps", .modifier),

        key(0x3A, ["KC_F1"], 0x7A, "F1"),
        key(0x3B, ["KC_F2"], 0x78, "F2"),
        key(0x3C, ["KC_F3"], 0x63, "F3"),
        key(0x3D, ["KC_F4"], 0x76, "F4"),
        key(0x3E, ["KC_F5"], 0x60, "F5"),
        key(0x3F, ["KC_F6"], 0x61, "F6"),
        key(0x40, ["KC_F7"], 0x62, "F7"),
        key(0x41, ["KC_F8"], 0x64, "F8"),
        key(0x42, ["KC_F9"], 0x65, "F9"),
        key(0x43, ["KC_F10"], 0x6D, "F10"),
        key(0x44, ["KC_F11"], 0x67, "F11"),
        key(0x45, ["KC_F12"], 0x6F, "F12"),

        key(0x46, ["KC_PSCREEN", "KC_PSCR"], nil, "PrtSc"),
        key(0x47, ["KC_SCROLLLOCK", "KC_SLCK", "KC_SCROLL_LOCK"], nil, "ScrLk"),
        key(0x48, ["KC_PAUSE", "KC_PAUS"], nil, "Pause"),
        key(0x49, ["KC_INSERT", "KC_INS"], nil, "Ins"),

        key(0x4A, ["KC_HOME"], 0x73, "Home"),
        key(0x4B, ["KC_PGUP", "KC_PAGE_UP"], 0x74, "PgUp"),
        key(0x4C, ["KC_DELETE", "KC_DEL"], 0x75, "Del"),
        key(0x4D, ["KC_END"], 0x77, "End"),
        key(0x4E, ["KC_PGDOWN", "KC_PGDN", "KC_PAGE_DOWN"], 0x79, "PgDn"),
        key(0x4F, ["KC_RIGHT", "KC_RGHT"], 0x7C, "→"),
        key(0x50, ["KC_LEFT"], 0x7B, "←"),
        key(0x51, ["KC_DOWN"], 0x7D, "↓"),
        key(0x52, ["KC_UP"], 0x7E, "↑"),

        key(0x58, ["KC_KP_ENTER", "KC_PENT"], 0x4C, "KP Ent"),

        key(0x65, ["KC_APPLICATION", "KC_APP"], nil, "Menu", .unmappedOnMacOS),

        key(0x87, ["KC_RO", "KC_INT1"], 0x5E, "_"),
        key(0x88, ["KC_KANA", "KC_INT2"], nil, "カタカナ"),
        key(0x89, ["KC_JYEN", "KC_INT3"], 0x5D, "¥"),
        key(0x8A, ["KC_HENK", "KC_INT4"], nil, "変換"),
        key(0x8B, ["KC_MHEN", "KC_INT5"], nil, "無変換"),
        key(0x90, ["KC_LANG1"], 0x68, "かな"),
        key(0x91, ["KC_LANG2"], 0x66, "英数"),

        key(0xE0, ["KC_LCTRL", "KC_LCTL", "KC_LEFT_CTRL"], 0x3B, "LCtrl", .modifier),
        key(0xE1, ["KC_LSHIFT", "KC_LSFT", "KC_LEFT_SHIFT"], 0x38, "LShift", .modifier),
        key(0xE2, ["KC_LALT", "KC_LOPT", "KC_LEFT_ALT"], 0x3A, "LAlt", .modifier),
        key(0xE3, ["KC_LGUI", "KC_LCMD", "KC_LEFT_GUI"], 0x37, "LGui", .modifier),
        key(0xE4, ["KC_RCTRL", "KC_RCTL", "KC_RIGHT_CTRL"], 0x3E, "RCtrl", .modifier),
        key(0xE5, ["KC_RSHIFT", "KC_RSFT", "KC_RIGHT_SHIFT"], 0x3C, "RShift", .modifier),
        key(0xE6, ["KC_RALT", "KC_ROPT", "KC_RIGHT_ALT"], 0x3D, "RAlt", .modifier),
        key(0xE7, ["KC_RGUI", "KC_RCMD", "KC_RIGHT_GUI"], 0x36, "RGui", .modifier),

        key(0xA8, ["KC_MUTE", "KC_AUDIO_MUTE"], nil, "Mute", .media),
        key(0xA9, ["KC_VOLU", "KC_AUDIO_VOL_UP"], nil, "Vol+", .media),
        key(0xAA, ["KC_VOLD", "KC_AUDIO_VOL_DOWN"], nil, "Vol-", .media),
        key(0xAB, ["KC_MNXT", "KC_MEDIA_NEXT_TRACK"], nil, "Next", .media),
        key(0xAC, ["KC_MPRV", "KC_MEDIA_PREV_TRACK"], nil, "Prev", .media),
        key(0xAD, ["KC_MSTP", "KC_MEDIA_STOP"], nil, "Stop", .media),
        key(0xAE, ["KC_MPLY", "KC_MEDIA_PLAY_PAUSE"], nil, "Play", .media),
        key(0xAF, ["KC_MSEL", "KC_MEDIA_SELECT"], nil, "Media", .media),

        key(0xF0, ["KC_MS_U", "KC_MS_UP"], nil, "Ms↑", .mouse),
        key(0xF1, ["KC_MS_D", "KC_MS_DOWN"], nil, "Ms↓", .mouse),
        key(0xF2, ["KC_MS_L", "KC_MS_LEFT"], nil, "Ms←", .mouse),
        key(0xF3, ["KC_MS_R", "KC_MS_RIGHT"], nil, "Ms→", .mouse),
        key(0xF4, ["KC_BTN1", "KC_MS_BTN1"], nil, "Btn1", .mouse),
        key(0xF5, ["KC_BTN2", "KC_MS_BTN2"], nil, "Btn2", .mouse),
        key(0xF6, ["KC_BTN3", "KC_MS_BTN3"], nil, "Btn3", .mouse),
        key(0xF9, ["KC_WH_U", "KC_MS_WH_UP"], nil, "Wh↑", .mouse),
        key(0xFA, ["KC_WH_D", "KC_MS_WH_DOWN"], nil, "Wh↓", .mouse),
        key(0xFB, ["KC_WH_L", "KC_MS_WH_LEFT"], nil, "Wh←", .mouse),
        key(0xFC, ["KC_WH_R", "KC_MS_WH_RIGHT"], nil, "Wh→", .mouse),
    ]

    private static let byName: [String: QMKBasicKeycode] = {
        var map: [String: QMKBasicKeycode] = [:]
        for entry in table {
            for name in entry.names where map[name] == nil {
                map[name] = entry
            }
        }
        return map
    }()

    private static let byCode: [UInt16: QMKBasicKeycode] = {
        var map: [UInt16: QMKBasicKeycode] = [:]
        for entry in table where map[entry.qmk] == nil {
            map[entry.qmk] = entry
        }
        return map
    }()

    private static let modifierMasks: [String: UInt8] = [
        "LCTL": ModMask.ctrl,
        "LSFT": ModMask.shift,
        "LALT": ModMask.alt,
        "LOPT": ModMask.alt,
        "LGUI": ModMask.gui,
        "LCMD": ModMask.gui,
        "LWIN": ModMask.gui,
        "RCTL": ModMask.right | ModMask.ctrl,
        "RSFT": ModMask.right | ModMask.shift,
        "RALT": ModMask.right | ModMask.alt,
        "ROPT": ModMask.right | ModMask.alt,
        "RGUI": ModMask.right | ModMask.gui,
        "RCMD": ModMask.right | ModMask.gui,
        "RWIN": ModMask.right | ModMask.gui,
        "C_S": ModMask.ctrl | ModMask.shift,
        "LCA": ModMask.ctrl | ModMask.alt,
        "LCG": ModMask.ctrl | ModMask.gui,
        "LSA": ModMask.shift | ModMask.alt,
        "LAG": ModMask.alt | ModMask.gui,
        "LSG": ModMask.shift | ModMask.gui,
        "SGUI": ModMask.shift | ModMask.gui,
        "LCAG": ModMask.ctrl | ModMask.alt | ModMask.gui,
        "MEH": ModMask.ctrl | ModMask.shift | ModMask.alt,
        "HYPR": ModMask.ctrl | ModMask.shift | ModMask.alt | ModMask.gui,
    ]

    private static let layerSwitchNames: Set<String> = ["MO", "TG", "TT", "TO", "DF", "OSL"]


    static func assignment(forEntry value: Any) -> VialKeyAssignment {
        if let token = value as? String {
            return decode(token: token, depth: 0)
        }
        if let number = value as? Int, number >= 0 {
            return decode(token: "0x" + String(number, radix: 16), depth: 0)
        }
        return absent
    }

    static func decode(token: String, depth: Int) -> VialKeyAssignment {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard depth <= maximumNesting else { return verbatim(token, trimmed) }
        let upper = trimmed.uppercased()

        if upper == "-1" { return absent }

        if upper.hasPrefix("0X") {
            guard let value = UInt32(upper.dropFirst(2), radix: 16) else {
                return verbatim(token, trimmed)
            }
            return decode(packed: value, token: token, trimmed: trimmed, depth: depth)
        }

        if let (name, argument) = splitWrapper(trimmed) {
            return decode(
                wrapper: name.uppercased(),
                argument: argument,
                token: token,
                trimmed: trimmed,
                depth: depth
            )
        }

        if let basic = byName[upper] {
            return assignment(token: token, basic: basic)
        }

        return verbatim(token, trimmed)
    }


    private static func decode(
        wrapper name: String,
        argument: String,
        token: String,
        trimmed: String,
        depth: Int
    ) -> VialKeyAssignment {
        if name.hasSuffix("_T"), let mods = modifierMasks[String(name.dropLast(2))] {
            let inner = decode(token: argument, depth: depth + 1)
            return applyModTap(mods, to: inner, token: token)
        }

        if let mods = modifierMasks[name] {
            let inner = decode(token: argument, depth: depth + 1)
            return applyModifiers(mods, to: inner, token: token)
        }

        if name.hasPrefix("LT") {
            let suffix = name.dropFirst(2)
            if suffix.isEmpty {
                let parts = argument.split(separator: ",", maxSplits: 1)
                if parts.count == 2, let layer = layerNumber(String(parts[0])) {
                    let inner = decode(token: String(parts[1]), depth: depth + 1)
                    return applyLayerTap(layer: layer, to: inner, token: token)
                }
            } else if let layer = layerNumber(String(suffix)) {
                let inner = decode(token: argument, depth: depth + 1)
                return applyLayerTap(layer: layer, to: inner, token: token)
            }
        }

        if layerSwitchNames.contains(name), let layer = layerNumber(argument) {
            return VialKeyAssignment(
                raw: token,
                legend: KeyCapLegend("\(name) \(layer)"),
                identity: nil,
                exclusion: .layerHold
            )
        }

        return verbatim(token, trimmed)
    }

    private static func decode(
        packed value: UInt32,
        token: String,
        trimmed: String,
        depth: Int
    ) -> VialKeyAssignment {
        switch value {
        case 0x0000...0x00FF:
            guard let basic = byCode[UInt16(value)] else { return verbatim(token, trimmed) }
            return assignment(token: token, basic: basic)

        case 0x0100...0x1FFF:
            guard let basic = byCode[UInt16(value & 0xFF)] else { return verbatim(token, trimmed) }
            let mods = UInt8((value >> 8) & 0x1F)
            return applyModifiers(mods, to: assignment(token: token, basic: basic), token: token)

        case 0x2000...0x3FFF:
            guard let basic = byCode[UInt16(value & 0xFF)] else { return verbatim(token, trimmed) }
            let mods = UInt8((value >> 8) & 0x1F)
            return applyModTap(mods, to: assignment(token: token, basic: basic), token: token)

        case 0x4000...0x4FFF:
            guard let basic = byCode[UInt16(value & 0xFF)] else { return verbatim(token, trimmed) }
            let layer = Int((value >> 8) & 0x0F)
            return applyLayerTap(layer: layer, to: assignment(token: token, basic: basic), token: token)

        default:
            return verbatim(token, trimmed)
        }
    }


    private static func applyModifiers(
        _ mods: UInt8,
        to inner: VialKeyAssignment,
        token: String
    ) -> VialKeyAssignment {
        let legend = KeyCapLegend(inner.legend.primary, modifierLabel(mods))
        guard let identity = inner.identity else {
            return VialKeyAssignment(
                raw: token,
                legend: legend,
                identity: nil,
                exclusion: inner.exclusion,
                holdAction: inner.holdAction
            )
        }
        guard (mods & ModMask.uncounted) == 0 else {
            return VialKeyAssignment(
                raw: token,
                legend: legend,
                identity: nil,
                exclusion: .shortcut,
                holdAction: inner.holdAction
            )
        }
        let isShifted = identity.isShifted || (mods & ModMask.shift) != 0
        return VialKeyAssignment(
            raw: token,
            legend: legend,
            identity: KeyIdentity(keyCode: identity.keyCode, isShifted: isShifted),
            exclusion: inner.exclusion,
            holdAction: inner.holdAction
        )
    }

    private static func applyModTap(
        _ mods: UInt8,
        to inner: VialKeyAssignment,
        token: String
    ) -> VialKeyAssignment {
        let legend = KeyCapLegend(inner.legend.primary, modifierLabel(mods) + "_T")
        let holdIdentity = modifierIdentity(mods)
        let holdAction = VialHoldAction(
            legend: modifierHoldLegend(mods),
            identity: holdIdentity,
            exclusion: holdIdentity == nil ? .compoundModifierHold : .modifier
        )
        guard let identity = inner.identity else {
            return VialKeyAssignment(
                raw: token,
                legend: legend,
                identity: nil,
                exclusion: inner.exclusion,
                holdAction: holdAction
            )
        }
        return VialKeyAssignment(
            raw: token,
            legend: legend,
            identity: KeyIdentity(keyCode: identity.keyCode, isShifted: false),
            exclusion: inner.exclusion,
            holdAction: holdAction
        )
    }

    private static func applyLayerTap(
        layer: Int,
        to inner: VialKeyAssignment,
        token: String
    ) -> VialKeyAssignment {
        VialKeyAssignment(
            raw: token,
            legend: KeyCapLegend(inner.legend.primary, "LT \(layer)"),
            identity: inner.identity,
            exclusion: inner.exclusion,
            holdAction: VialHoldAction(
                legend: "Layer \(layer)",
                identity: nil,
                exclusion: .layerHold
            )
        )
    }


    private static func modifierLabel(_ mods: UInt8) -> String {
        let isRight = (mods & ModMask.right) != 0
        let applied = mods & 0x0F
        guard applied != 0 else { return isRight ? "R" : "" }

        if applied.nonzeroBitCount == 1 {
            let name: String
            switch applied {
            case ModMask.ctrl: name = "Ctl"
            case ModMask.shift: name = "Sft"
            case ModMask.alt: name = "Alt"
            default: name = "Gui"
            }
            return (isRight ? "R" : "L") + name
        }

        var label = isRight ? "R" : ""
        if applied & ModMask.gui != 0 { label += "⌘" }
        if applied & ModMask.ctrl != 0 { label += "⌃" }
        if applied & ModMask.alt != 0 { label += "⌥" }
        if applied & ModMask.shift != 0 { label += "⇧" }
        return label
    }

    private static func modifierHoldLegend(_ mods: UInt8) -> String {
        let isRight = (mods & ModMask.right) != 0
        let applied = mods & 0x0F
        guard applied.nonzeroBitCount == 1 else { return modifierLabel(mods) }
        switch applied {
        case ModMask.ctrl: return isRight ? "RCtrl" : "LCtrl"
        case ModMask.shift: return isRight ? "RShift" : "LShift"
        case ModMask.alt: return isRight ? "RAlt" : "LAlt"
        default: return isRight ? "RGui" : "LGui"
        }
    }

    private static func modifierIdentity(_ mods: UInt8) -> KeyIdentity? {
        let isRight = (mods & ModMask.right) != 0
        let applied = mods & 0x0F
        guard applied.nonzeroBitCount == 1 else { return nil }
        let keyCode: UInt16
        switch applied {
        case ModMask.ctrl: keyCode = isRight ? 0x3E : 0x3B
        case ModMask.shift: keyCode = isRight ? 0x3C : 0x38
        case ModMask.alt: keyCode = isRight ? 0x3D : 0x3A
        default: keyCode = isRight ? 0x36 : 0x37
        }
        return KeyIdentity(keyCode: keyCode)
    }


    private static let absent = VialKeyAssignment(
        raw: "-1",
        legend: KeyCapLegend(""),
        identity: nil,
        exclusion: nil
    )

    private static func assignment(token: String, basic: QMKBasicKeycode) -> VialKeyAssignment {
        VialKeyAssignment(
            raw: token,
            legend: KeyCapLegend(basic.legend),
            identity: basic.macOS.map { KeyIdentity(keyCode: $0) },
            exclusion: basic.exclusion
        )
    }

    private static func verbatim(_ token: String, _ trimmed: String) -> VialKeyAssignment {
        VialKeyAssignment(
            raw: token,
            legend: KeyCapLegend(trimmed),
            identity: nil,
            exclusion: .unmappedOnMacOS
        )
    }

    private static func splitWrapper(_ token: String) -> (name: String, argument: String)? {
        guard token.hasSuffix(")"), let open = token.firstIndex(of: "(") else { return nil }
        let argumentStart = token.index(after: open)
        let argumentEnd = token.index(before: token.endIndex)
        guard argumentStart <= argumentEnd else { return nil }
        return (String(token[token.startIndex..<open]), String(token[argumentStart..<argumentEnd]))
    }

    private static func layerNumber(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }
}
