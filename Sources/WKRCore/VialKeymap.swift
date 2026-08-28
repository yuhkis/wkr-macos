import Foundation

/// One key of a Vial keymap, reduced to what a heatmap can use.
///
/// A `.vil` export describes the firmware's intent, which is not the same thing
/// as what macOS receives. The two line up only for plain keycodes: a layer hold
/// never leaves the board, a media key arrives as a system-defined event rather
/// than a key event, and anything carrying Command, Control or Option is
/// deliberately not counted. `identity` is therefore absent far more often than
/// a keymap reader would expect, and `exclusion` is what lets the picture say
/// why instead of drawing a cold cap that reads as "never pressed".
public struct VialKeyAssignment: Equatable, Sendable {
    /// The token exactly as the file wrote it, kept so a cap the decoder did not
    /// understand can still be reported as the text the user can search Vial for.
    public let raw: String
    public let legend: KeyCapLegend
    public let identity: KeyIdentity?
    public let exclusion: KeyCapExclusion?

    public init(
        raw: String,
        legend: KeyCapLegend,
        identity: KeyIdentity?,
        exclusion: KeyCapExclusion?
    ) {
        self.raw = raw
        self.legend = legend
        self.identity = identity
        self.exclusion = exclusion
    }

    /// Which Shift the firmware itself holds down when this key is tapped, or
    /// `nil` for a key the user shifts by hand.
    ///
    /// Only the wrap forms produce a shifted identity from a bare tap —
    /// `LSFT(…)`, `RSFT(…)` and their QK_MODS hex encodings; every other
    /// shift-carrying token either taps unshifted (`LSFT_T`) or is a shortcut
    /// with no identity at all. The side matters because macOS reports left and
    /// right Shift as different key codes in flags-changed events, which is the
    /// one honest way to tell a firmware-held Shift apart from a finger on the
    /// physical Shift key: put the wraps on the side the physical key is not.
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
        // A shifted identity always comes from one of the forms above; QMK's
        // default side for a bare shift wrap is the left hand.
        return .left
    }

    /// True where the matrix has no key at that position (`-1`) or the firmware
    /// sends nothing from it (`KC_NO`).
    ///
    /// Both still occupy a slot in their row. A Corne's rows are ragged and the
    /// geometry is addressed by column index, so dropping the hole would slide
    /// every key after it one column left.
    public var isAbsent: Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // `0X0` is here because a numeric entry is rewritten as hex before it is
        // decoded, so a `0` in the layout array — which is `KC_NO` written as a
        // number — arrives as the string `0x0` and would otherwise read as a
        // real key.
        return token == "-1" || token == "KC_NO" || token == "0X0"
    }
}

/// The hand whose Shift a wrap key presses. See
/// `VialKeyAssignment.firmwareShiftSide`.
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

/// Layer 0 of a Vial `.vil` export, decoded into cap labels and countable
/// identities.
///
/// Only layer 0 is read. The tally the picture is filled from holds macOS
/// virtual key codes and nothing else, so it cannot say which firmware layer was
/// active when a code arrived — macOS sees the tap action and never the layer.
/// Decoding the higher layers would produce labels that no number can honestly
/// be attached to.
public struct VialKeymap: Equatable, Sendable {
    /// Layer 0 only, in the file's own row/column order.
    public let baseLayer: [[VialKeyAssignment]]
    /// Sides whose Shift some key on ANY layer holds down when tapped.
    ///
    /// The picture only draws layer 0, but the counts it explains come from
    /// every layer the user actually typed on: a symbol layer full of
    /// `LSFT(…)` keys presses left Shift on each use, whether or not layer 0
    /// carries a single wrap. A Shift-reading note derived from layer 0 alone
    /// would therefore vanish exactly when the keymap moves its wraps out of
    /// sight, which is the opposite of what the note is for.
    public let firmwareShiftSides: Set<FirmwareShiftSide>

    public init(
        baseLayer: [[VialKeyAssignment]],
        firmwareShiftSides: Set<FirmwareShiftSide> = []
    ) {
        self.baseLayer = baseLayer
        self.firmwareShiftSides = firmwareShiftSides
    }

    public static func parse(data: Data) throws -> VialKeymap {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            // The underlying parse error names a byte offset, which is of no use
            // to someone who picked the wrong file in an open panel.
            throw VialKeymapError.notJSON
        }
        guard let root = object as? [String: Any] else { throw VialKeymapError.notJSON }
        guard let layers = root["layout"] as? [Any] else { throw VialKeymapError.missingLayout }
        guard let base = layers.first else { throw VialKeymapError.emptyLayout }
        guard let rows = base as? [Any] else { throw VialKeymapError.missingLayout }
        guard !rows.isEmpty else { throw VialKeymapError.emptyLayout }

        // Every layer is decoded for the Shift-side scan even though only
        // layer 0 is kept for drawing. The decoder is total, so a foreign or
        // half-edited layer cannot make this throw.
        var sides: Set<FirmwareShiftSide> = []
        for layer in layers {
            guard let layerRows = layer as? [Any] else { continue }
            for row in layerRows {
                guard let entries = row as? [Any] else { continue }
                for entry in entries {
                    if let side = VialTokenDecoder.assignment(forEntry: entry).firmwareShiftSide {
                        sides.insert(side)
                    }
                }
            }
        }

        return VialKeymap(
            baseLayer: rows.map { row in
                // A row that is not an array is the only shape this can meet that
                // has no column count to preserve, so it becomes an empty row
                // rather than aborting a file whose other rows are readable.
                guard let entries = row as? [Any] else { return [] }
                return entries.map(VialTokenDecoder.assignment(forEntry:))
            },
            firmwareShiftSides: sides
        )
    }

    /// Total by construction: an unrecognised token becomes its own legend, and
    /// nothing here traps or throws. A keymap the user exported from a fork with
    /// keycodes this build has never heard of must still draw.
    public static func decode(token: String) -> VialKeyAssignment {
        VialTokenDecoder.decode(token: token, depth: 0)
    }
}

/// One entry of the QMK basic keycode table.
///
/// `qmk` is the HID usage id the firmware stores, `macOS` the virtual key code
/// the host reports for that usage. They are unrelated numbers — HID puts the
/// letters in alphabetical order and macOS does not — so both are written out.
private struct QMKBasicKeycode: Sendable {
    let qmk: UInt16
    let names: [String]
    let macOS: UInt16?
    let legend: String
    let exclusion: KeyCapExclusion?
}

private enum VialTokenDecoder {
    /// QMK packs the applied modifiers into five bits. The low four name the
    /// modifier and `right` swaps the whole set to the right-hand side, which is
    /// why a right-hand combination is one bit rather than four more.
    private enum ModMask {
        static let ctrl: UInt8 = 0x01
        static let shift: UInt8 = 0x02
        static let alt: UInt8 = 0x04
        static let gui: UInt8 = 0x08
        static let right: UInt8 = 0x10
        /// The three the recorder never counts an event under. `docs/design.md`
        /// section 9 has the reasoning; the short version is that a shortcut is
        /// a command, not a keystroke, and counting it would inflate the letter
        /// it happens to be built on.
        static let uncounted: UInt8 = ctrl | alt | gui
    }

    /// A token nests at most a modifier around a mod-tap around a keycode in
    /// anything Vial writes. The limit exists so a hand-edited or hostile file
    /// cannot recurse the decoder off the stack.
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

    /// The one table both token paths read.
    ///
    /// `legend` is what Vial prints, which is the ANSI name of the keycode, and
    /// `macOS` is what the host actually receives. On a JIS host those two
    /// disagree on the symbol keys: `KC_RBRACKET` is drawn `]` here because that
    /// is the cap the user is looking at in Vial, while the identity is
    /// `kVK_ANSI_RightBracket`, which JIS prints as `[`. Reconciling them would
    /// mean picking one to lie about; the label follows the picture and the
    /// identity follows the event, and `KeyboardGeometry` is where the JIS
    /// legends live.
    private static let table: [QMKBasicKeycode] = [
        // Absent and pass-through. Layer 0 should hold neither, but a keymap in
        // the middle of being edited does.
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

        // HID counts the digit row 1..9 then 0; macOS interleaves 6 and 5 and
        // puts 0 at the far end, so this row in particular cannot be generated.
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
        // macOS folds the non-US hash usage onto the same virtual key code as
        // backslash, so both caps share one count. The geometry marks caps that
        // share a total rather than splitting it.
        key(0x32, ["KC_NONUS_HASH", "KC_NUHS"], 0x2A, "#"),
        key(0x33, ["KC_SCOLON", "KC_SCLN", "KC_SEMICOLON"], 0x29, ";"),
        key(0x34, ["KC_QUOTE", "KC_QUOT", "KC_APOSTROPHE"], 0x27, "'"),
        key(0x35, ["KC_GRAVE", "KC_GRV"], 0x32, "`"),
        key(0x36, ["KC_COMMA", "KC_COMM"], 0x2B, ","),
        key(0x37, ["KC_DOT"], 0x2F, "."),
        key(0x38, ["KC_SLASH", "KC_SLSH"], 0x2C, "/"),
        key(0x39, ["KC_CAPSLOCK", "KC_CAPS", "KC_CAPS_LOCK"], 0x39, "Caps", .modifier),

        // The function row is scattered across the macOS code space (F5 is 0x60
        // and F1 is 0x7A), which is the other place a generated table would go
        // wrong.
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

        // Apple keyboards have no Print Screen, Scroll Lock, Pause or Insert, and
        // the codes macOS reports for a PC keyboard's versions were not measured
        // here. They are named so the cap reads properly, and left without an
        // identity rather than pointed at a key code this build cannot vouch for.
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

        // The one keypad key a split board plausibly carries, on a thumb. The
        // rest of the keypad is not on any board this draws and falls through to
        // a verbatim legend.
        key(0x58, ["KC_KP_ENTER", "KC_PENT"], 0x4C, "KP Ent"),

        key(0x65, ["KC_APPLICATION", "KC_APP"], nil, "Menu", .unmappedOnMacOS),

        // JIS keys. `KC_RO` and `KC_JYEN` reach macOS as their own virtual key
        // codes; the Windows-side 変換 / 無変換 / カタカナひらがな keys do not,
        // which is why the roadmap treats them as pass-through boundary keys.
        key(0x87, ["KC_RO", "KC_INT1"], 0x5E, "_"),
        key(0x88, ["KC_KANA", "KC_INT2"], nil, "カタカナ"),
        key(0x89, ["KC_JYEN", "KC_INT3"], 0x5D, "¥"),
        key(0x8A, ["KC_HENK", "KC_INT4"], nil, "変換"),
        key(0x8B, ["KC_MHEN", "KC_INT5"], nil, "無変換"),
        key(0x90, ["KC_LANG1"], 0x68, "かな"),
        key(0x91, ["KC_LANG2"], 0x66, "英数"),

        // Modifiers keep their identity. They reach macOS as flags-changed
        // events rather than key events, which the recorder does widen the tap
        // for, so the count is real; `.modifier` records that it only exists
        // while frequency logging is on.
        key(0xE0, ["KC_LCTRL", "KC_LCTL", "KC_LEFT_CTRL"], 0x3B, "LCtrl", .modifier),
        key(0xE1, ["KC_LSHIFT", "KC_LSFT", "KC_LEFT_SHIFT"], 0x38, "LShift", .modifier),
        key(0xE2, ["KC_LALT", "KC_LOPT", "KC_LEFT_ALT"], 0x3A, "LAlt", .modifier),
        key(0xE3, ["KC_LGUI", "KC_LCMD", "KC_LEFT_GUI"], 0x37, "LGui", .modifier),
        key(0xE4, ["KC_RCTRL", "KC_RCTL", "KC_RIGHT_CTRL"], 0x3E, "RCtrl", .modifier),
        key(0xE5, ["KC_RSHIFT", "KC_RSFT", "KC_RIGHT_SHIFT"], 0x3C, "RShift", .modifier),
        key(0xE6, ["KC_RALT", "KC_ROPT", "KC_RIGHT_ALT"], 0x3D, "RAlt", .modifier),
        key(0xE7, ["KC_RGUI", "KC_RCMD", "KC_RIGHT_GUI"], 0x36, "RGui", .modifier),

        // Media and system keys are delivered as system-defined events, so the
        // key event tap never sees them however often they are pressed.
        key(0xA8, ["KC_MUTE", "KC_AUDIO_MUTE"], nil, "Mute", .media),
        key(0xA9, ["KC_VOLU", "KC_AUDIO_VOL_UP"], nil, "Vol+", .media),
        key(0xAA, ["KC_VOLD", "KC_AUDIO_VOL_DOWN"], nil, "Vol-", .media),
        key(0xAB, ["KC_MNXT", "KC_MEDIA_NEXT_TRACK"], nil, "Next", .media),
        key(0xAC, ["KC_MPRV", "KC_MEDIA_PREV_TRACK"], nil, "Prev", .media),
        key(0xAD, ["KC_MSTP", "KC_MEDIA_STOP"], nil, "Stop", .media),
        key(0xAE, ["KC_MPLY", "KC_MEDIA_PLAY_PAUSE"], nil, "Play", .media),
        key(0xAF, ["KC_MSEL", "KC_MEDIA_SELECT"], nil, "Media", .media),

        // Emulated pointer keys arrive as mouse events, for the same reason.
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

    /// Aliases share a `qmk` value, so the first spelling in each row wins and
    /// the hex path always draws the canonical name's legend.
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

    // MARK: - Entry points

    static func assignment(forEntry value: Any) -> VialKeyAssignment {
        if let token = value as? String {
            return decode(token: token, depth: 0)
        }
        if let number = value as? Int, number >= 0 {
            // Some exports store the packed keycode as a number instead of a
            // token. Rendering it back to `0x…` sends it down the one hex path
            // rather than giving the numeric case its own decoder to drift from.
            return decode(token: "0x" + String(number, radix: 16), depth: 0)
        }
        // `-1` and anything unreadable both mean "draw nothing here". The slot is
        // kept either way so the columns after it do not shift.
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

        // `USER07`, `MACRO03`, `M0`, `QK_KB_1` and every keycode a fork invented
        // land here. Drawing the token is the only honest label: guessing at what
        // a macro types would attach counts to a key it never pressed.
        return verbatim(token, trimmed)
    }

    // MARK: - Token shapes

    private static func decode(
        wrapper name: String,
        argument: String,
        token: String,
        trimmed: String,
        depth: Int
    ) -> VialKeyAssignment {
        // A mod-tap is a modifier name with `_T` welded on, and it must be tested
        // before the plain modifier so `LSFT_T` never reads as an unknown name.
        if name.hasSuffix("_T"), let mods = modifierMasks[String(name.dropLast(2))] {
            let inner = decode(token: argument, depth: depth + 1)
            return applyModTap(mods, to: inner, token: token)
        }

        if let mods = modifierMasks[name] {
            let inner = decode(token: argument, depth: depth + 1)
            return applyModifiers(mods, to: inner, token: token)
        }

        // Vial writes the layer into the name (`LT1(KC_SPACE)`); QMK source
        // writes it as an argument (`LT(1, KC_SPACE)`). Both appear in files
        // people hand-edit, so both are accepted.
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
            // Nothing about these ever reaches the host: the board changes its
            // own layer and sends no report at all.
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
            // QK_MODS. Worked example: 0xc04 is mods 0x0C (Alt+Gui) over basic
            // 0x04 (KC_A), which is ⌘⌥A: a shortcut, not a keystroke, and so it
            // carries no identity of its own.
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
            // Tap dances, combos, encoder actions and everything Vial added since
            // this table was written. Drawn as the hex it is.
            return verbatim(token, trimmed)
        }
    }

    // MARK: - Composition rules

    /// `LSFT(KC_ENTER)` holds Shift down and presses Return, so the host sees a
    /// shifted Return and the shift state is part of the identity.
    ///
    /// Any of Command, Control or Option drops the identity altogether. Keeping
    /// the inner key code looks harmless and is not: the recorder never counts
    /// an event carrying those flags, so the only presses filed under that code
    /// came from the *plain* key somewhere else on the board, and the cap would
    /// display a number it did not earn. During development a cap wrapped in
    /// one of these modifiers showed the whole board's total for its inner key
    /// until this returned nil.
    private static func applyModifiers(
        _ mods: UInt8,
        to inner: VialKeyAssignment,
        token: String
    ) -> VialKeyAssignment {
        let legend = KeyCapLegend(inner.legend.primary, modifierLabel(mods))
        guard let identity = inner.identity else {
            // A modified media or mouse key still never reaches the key event
            // tap, so the inner reason is the true one.
            return VialKeyAssignment(
                raw: token,
                legend: legend,
                identity: nil,
                exclusion: inner.exclusion
            )
        }
        guard (mods & ModMask.uncounted) == 0 else {
            return VialKeyAssignment(
                raw: token,
                legend: legend,
                identity: nil,
                exclusion: .shortcut
            )
        }
        let isShifted = identity.isShifted || (mods & ModMask.shift) != 0
        return VialKeyAssignment(
            raw: token,
            legend: legend,
            identity: KeyIdentity(keyCode: identity.keyCode, isShifted: isShifted),
            exclusion: inner.exclusion
        )
    }

    /// `LSFT_T(KC_ENTER)` is the opposite case and the one this file exists to
    /// get right: the modifier applies to the *hold*, and a tap sends a bare
    /// Return with no flags at all. So the identity is unshifted and nothing is
    /// excluded — this cap is counted like any other letter. Confusing it with
    /// `LSFT(KC_ENTER)` would move every home-row-mod tap out of the tally.
    private static func applyModTap(
        _ mods: UInt8,
        to inner: VialKeyAssignment,
        token: String
    ) -> VialKeyAssignment {
        let legend = KeyCapLegend(inner.legend.primary, modifierLabel(mods) + "_T")
        guard let identity = inner.identity else {
            return VialKeyAssignment(
                raw: token,
                legend: legend,
                identity: nil,
                exclusion: inner.exclusion
            )
        }
        return VialKeyAssignment(
            raw: token,
            legend: legend,
            identity: KeyIdentity(keyCode: identity.keyCode, isShifted: false),
            exclusion: nil
        )
    }

    /// The hold switches layers inside the firmware and the host learns nothing
    /// about it, so the tap action carries the identity and `.layerHold` records
    /// that the other half of this key is invisible from here.
    private static func applyLayerTap(
        layer: Int,
        to inner: VialKeyAssignment,
        token: String
    ) -> VialKeyAssignment {
        VialKeyAssignment(
            raw: token,
            legend: KeyCapLegend(inner.legend.primary, "LT \(layer)"),
            identity: inner.identity,
            // With a tap action the host can see, `.layerHold` is the whole
            // story: only the hold is invisible. With no identity the tap is
            // unreachable too, and the inner key's own reason is the more useful
            // one to show — `LT1(KC_MUTE)` is not seen because it is a media
            // key, and saying "layer hold" would send the reader looking for a
            // layer that is not the problem.
            exclusion: inner.identity == nil ? (inner.exclusion ?? .layerHold) : .layerHold
        )
    }

    // MARK: - Labels

    /// A single modifier is named the way Vial's own editor names it, so the
    /// drawing and the app the user is comparing it against read alike. Two or
    /// more would not fit, so they collapse to glyphs, always in the order
    /// ⌘ ⌃ ⌥ ⇧ — the order itself does not matter as long as it is fixed, or two
    /// caps carrying the same chord would draw differently.
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

        // Glyphs cannot say which hand, so the side is spelled out in front of
        // them when it is the right one.
        var label = isRight ? "R" : ""
        if applied & ModMask.gui != 0 { label += "⌘" }
        if applied & ModMask.ctrl != 0 { label += "⌃" }
        if applied & ModMask.alt != 0 { label += "⌥" }
        if applied & ModMask.shift != 0 { label += "⇧" }
        return label
    }

    // MARK: - Small pieces

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
        // `raw` keeps the bytes; the legend drops surrounding whitespace, which
        // would otherwise push the label off centre in the drawing.
        //
        // An unresolved token is marked rather than left blank. A cap with no
        // number and no reason reads as "never pressed", and that is a
        // different claim from "this key cannot be seen from here" — which is
        // what a custom firmware keycode actually is.
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
