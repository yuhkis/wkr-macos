import Foundation


private struct JISRunKey {
    let id: String
    let keyCode: UInt16
    let legend: KeyCapLegend
    let finger: KeyCap.Finger

    init(_ id: String, _ keyCode: UInt16, _ primary: String, _ shifted: String?, _ finger: KeyCap.Finger) {
        self.id = id
        self.keyCode = keyCode
        self.legend = KeyCapLegend(primary, shifted)
        self.finger = finger
    }
}

private func jisRun(_ keys: [JISRunKey], startingAt startX: Double, y: Double) -> [KeyCap] {
    keys.enumerated().map { offset, key in
        KeyCap(
            id: key.id,
            identities: jisBothShiftStates(key.keyCode),
            x: startX + Double(offset),
            y: y,
            legend: key.legend,
            finger: key.finger
        )
    }
}

private func jisBothShiftStates(_ keyCode: UInt16) -> [KeyIdentity] {
    [
        KeyIdentity(keyCode: keyCode, isShifted: false),
        KeyIdentity(keyCode: keyCode, isShifted: true),
    ]
}

private func jisPlain(_ keyCode: UInt16) -> [KeyIdentity] {
    [KeyIdentity(keyCode: keyCode, isShifted: false)]
}

extension KeyboardGeometry {
    public static let jis = KeyboardGeometry(
        model: .jis,
        displayName: KeyboardModel.jis.displayName,
        widthUnits: 15,
        heightUnits: 6,
        caps: jisCaps,
        caveats: jisCaveats
    )

    private static let jisCaps: [KeyCap] = {
        var caps: [KeyCap] = []

        caps.append(
            KeyCap(
                id: "escape",
                identities: jisBothShiftStates(0x35),
                x: 0,
                y: 0,
                legend: KeyCapLegend("esc"),
                finger: .leftPinky
            )
        )

        let functionKeys: [(name: String, keyCode: UInt16)] = [
            ("F1", 0x7A), ("F2", 0x78), ("F3", 0x63), ("F4", 0x76),
            ("F5", 0x60), ("F6", 0x61), ("F7", 0x62), ("F8", 0x64),
            ("F9", 0x65), ("F10", 0x6D), ("F11", 0x67), ("F12", 0x6F),
        ]
        caps.append(
            contentsOf: functionKeys.enumerated().map { offset, key in
                KeyCap(
                    id: key.name.lowercased(),
                    identities: jisBothShiftStates(key.keyCode),
                    x: 1 + Double(offset),
                    y: 0,
                    legend: KeyCapLegend(key.name),
                    exclusion: .media
                )
            }
        )

        caps.append(
            contentsOf: jisRun(
                [
                    JISRunKey("digit-1", 0x12, "1", "!", .leftPinky),
                    JISRunKey("digit-2", 0x13, "2", "\"", .leftRing),
                    JISRunKey("digit-3", 0x14, "3", "#", .leftMiddle),
                    JISRunKey("digit-4", 0x15, "4", "$", .leftIndex),
                    JISRunKey("digit-5", 0x17, "5", "%", .leftIndex),
                    JISRunKey("digit-6", 0x16, "6", "&", .rightIndex),
                    JISRunKey("digit-7", 0x1A, "7", "'", .rightIndex),
                    JISRunKey("digit-8", 0x1C, "8", "(", .rightMiddle),
                    JISRunKey("digit-9", 0x19, "9", ")", .rightRing),
                    JISRunKey("digit-0", 0x1D, "0", nil, .rightPinky),
                    JISRunKey("minus", 0x1B, "-", "=", .rightPinky),
                    JISRunKey("caret", 0x18, "^", "~", .rightPinky),
                    JISRunKey("yen", 0x5D, "\u{00A5}", "|", .rightPinky),
                ],
                startingAt: 0,
                y: 1
            )
        )
        caps.append(
            KeyCap(
                id: "delete",
                identities: jisBothShiftStates(0x33),
                x: 13,
                y: 1,
                legend: KeyCapLegend("delete"),
                finger: .rightPinky
            )
        )

        caps.append(
            KeyCap(
                id: "tab",
                identities: jisBothShiftStates(0x30),
                x: 0,
                y: 2,
                width: 1.5,
                legend: KeyCapLegend("tab"),
                finger: .leftPinky
            )
        )
        caps.append(
            contentsOf: jisRun(
                [
                    JISRunKey("q", 0x0C, "Q", nil, .leftPinky),
                    JISRunKey("w", 0x0D, "W", nil, .leftRing),
                    JISRunKey("e", 0x0E, "E", nil, .leftMiddle),
                    JISRunKey("r", 0x0F, "R", nil, .leftIndex),
                    JISRunKey("t", 0x11, "T", nil, .leftIndex),
                    JISRunKey("y", 0x10, "Y", nil, .rightIndex),
                    JISRunKey("u", 0x20, "U", nil, .rightIndex),
                    JISRunKey("i", 0x22, "I", nil, .rightMiddle),
                    JISRunKey("o", 0x1F, "O", nil, .rightRing),
                    JISRunKey("p", 0x23, "P", nil, .rightPinky),
                    JISRunKey("at", 0x21, "@", "`", .rightPinky),
                    JISRunKey("bracket-left", 0x1E, "[", "{", .rightPinky),
                ],
                startingAt: 1.5,
                y: 2
            )
        )

        caps.append(
            KeyCap(
                id: "return-upper",
                identities: jisBothShiftStates(0x24),
                x: 13.5,
                y: 2,
                width: 1.5,
                legend: KeyCapLegend("return"),
                finger: .rightPinky
            )
        )
        caps.append(
            KeyCap(
                id: "return-lower",
                x: 13.75,
                y: 3,
                width: 1.25,
                legend: KeyCapLegend("")
            )
        )

        caps.append(
            KeyCap(
                id: "caps-lock",
                identities: jisPlain(0x39),
                x: 0,
                y: 3,
                width: 1.75,
                legend: KeyCapLegend("caps lock"),
                exclusion: .modifier
            )
        )
        caps.append(
            contentsOf: jisRun(
                [
                    JISRunKey("a", 0x00, "A", nil, .leftPinky),
                    JISRunKey("s", 0x01, "S", nil, .leftRing),
                    JISRunKey("d", 0x02, "D", nil, .leftMiddle),
                    JISRunKey("f", 0x03, "F", nil, .leftIndex),
                    JISRunKey("g", 0x05, "G", nil, .leftIndex),
                    JISRunKey("h", 0x04, "H", nil, .rightIndex),
                    JISRunKey("j", 0x26, "J", nil, .rightIndex),
                    JISRunKey("k", 0x28, "K", nil, .rightMiddle),
                    JISRunKey("l", 0x25, "L", nil, .rightRing),
                    JISRunKey("semicolon", 0x29, ";", "+", .rightPinky),
                    JISRunKey("colon", 0x27, ":", "*", .rightPinky),
                    JISRunKey("bracket-right", 0x2A, "]", "}", .rightPinky),
                ],
                startingAt: 1.75,
                y: 3
            )
        )

        caps.append(
            KeyCap(
                id: "shift-left",
                identities: jisPlain(0x38),
                x: 0,
                y: 4,
                width: 2.25,
                legend: KeyCapLegend("shift"),
                exclusion: .modifier
            )
        )
        caps.append(
            contentsOf: jisRun(
                [
                    JISRunKey("z", 0x06, "Z", nil, .leftPinky),
                    JISRunKey("x", 0x07, "X", nil, .leftRing),
                    JISRunKey("c", 0x08, "C", nil, .leftMiddle),
                    JISRunKey("v", 0x09, "V", nil, .leftIndex),
                    JISRunKey("b", 0x0B, "B", nil, .leftIndex),
                    JISRunKey("n", 0x2D, "N", nil, .rightIndex),
                    JISRunKey("m", 0x2E, "M", nil, .rightIndex),
                    JISRunKey("comma", 0x2B, ",", "<", .rightMiddle),
                    JISRunKey("period", 0x2F, ".", ">", .rightRing),
                    JISRunKey("slash", 0x2C, "/", "?", .rightPinky),
                    JISRunKey("underscore", 0x5E, "_", nil, .rightPinky),
                ],
                startingAt: 2.25,
                y: 4
            )
        )
        caps.append(
            KeyCap(
                id: "shift-right",
                identities: jisPlain(0x3C),
                x: 13.25,
                y: 4,
                width: 1.75,
                legend: KeyCapLegend("shift"),
                exclusion: .modifier
            )
        )

        let bottomModifiers: [(id: String, keyCode: UInt16, legend: String, x: Double, width: Double)] = [
            ("fn", 0x3F, "fn", 0.0, 1.0),
            ("control", 0x3B, "control", 1.0, 1.0),
            ("option-left", 0x3A, "option", 2.0, 1.0),
            ("command-left", 0x37, "command", 3.0, 1.25),
            ("command-right", 0x36, "command", 9.75, 1.25),
            ("option-right", 0x3D, "option", 11.0, 1.0),
        ]
        caps.append(
            contentsOf: bottomModifiers.map { key in
                KeyCap(
                    id: key.id,
                    identities: jisPlain(key.keyCode),
                    x: key.x,
                    y: 5,
                    width: key.width,
                    legend: KeyCapLegend(key.legend),
                    exclusion: .modifier
                )
            }
        )

        caps.append(
            KeyCap(
                id: "eisu",
                identities: jisBothShiftStates(0x66),
                x: 4.25,
                y: 5,
                width: 1.25,
                legend: KeyCapLegend("英数"),
                finger: .leftThumb
            )
        )
        caps.append(
            KeyCap(
                id: "space",
                identities: jisBothShiftStates(0x31),
                x: 5.5,
                y: 5,
                width: 3,
                legend: KeyCapLegend("space"),
                finger: .rightThumb
            )
        )
        caps.append(
            KeyCap(
                id: "kana",
                identities: jisBothShiftStates(0x68),
                x: 8.5,
                y: 5,
                width: 1.25,
                legend: KeyCapLegend("かな"),
                finger: .rightThumb
            )
        )

        let arrows: [(id: String, keyCode: UInt16, legend: String, x: Double, y: Double, height: Double)] = [
            ("arrow-left", 0x7B, "←", 12.0, 5.0, 1.0),
            ("arrow-up", 0x7E, "↑", 13.0, 5.0, 0.5),
            ("arrow-down", 0x7D, "↓", 13.0, 5.5, 0.5),
            ("arrow-right", 0x7C, "→", 14.0, 5.0, 1.0),
        ]
        caps.append(
            contentsOf: arrows.map { key in
                KeyCap(
                    id: key.id,
                    identities: jisBothShiftStates(key.keyCode),
                    x: key.x,
                    y: key.y,
                    height: key.height,
                    legend: KeyCapLegend(key.legend)
                )
            }
        )

        return caps
    }()

    private static let jisCaveats: [String] = [
        "ファンクションキーとメディアキーは system-defined イベントとして届くため、event tap では数えられません。",
        "「F1、F2 などのキーを標準のファンクションキーとして使用」が有効なときだけ、F1〜F12 は通常のキーイベントとして数えられます。",
        "修飾キーは flags-changed イベントで数えます。頻度ログが有効なときだけ event tap が受け取ります。",
        "Command / Control / Option を伴う打鍵は変換対象外としてバイパスするため、頻度にも数えていません。",
        "return は逆L字の1つのキーです。打鍵数は上側の枠にまとめ、下側の枠には数を出しません。",
        "Shift の有無は別に数えます。JIS では Shift+0 が 0、Shift+_ が _ のように刻印が変わらないキーでも、2通りの打鍵として集計します。",
        "指ごとの集計は「その指が叩いた回数」です。修飾キーは押しっぱなしにするもので叩く回数とは性質が違うため、指の集計には入れていません（キーごとの数値には出ます）。",
    ]
}
