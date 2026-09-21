import Foundation

// The virtual key codes in this file are Carbon's `kVK_*` values written out as
// literals. WKRCore does not import Carbon, AppKit or Core Graphics, because the
// transducer and the report have to run in tests with no event tap and no window
// server, so the constants this drawing needs are copied rather than linked.
// They are the codes `CGEventField.keyboardEventKeycode` delivers, which is what
// `KeyIdentity` stores.
//
// The legends are the JIS printing as dumped through `UCKeyTranslate` against a
// live JIS keyboard, not the Carbon names, because the two disagree on six keys:
// `kVK_ANSI_Quote` prints `:`, `kVK_ANSI_LeftBracket` prints `@`,
// `kVK_ANSI_RightBracket` prints `[`, `kVK_ANSI_Backslash` prints `]`,
// `kVK_ANSI_Equal` prints `^`, and `kVK_ANSI_Minus` shifts to `=` rather than
// `_`. Reading the names as legends would mislabel most of the right hand, so
// the cap ids below follow the JIS printing too: `bracket-left` is the cap that
// prints `[`, which is `kVK_ANSI_RightBracket`.

/// One 1u printing cap in a staggered row, before it is told where it sits.
///
/// Rows are described as runs so that each row states its tiling once, in one
/// place. A wrong width is invisible in a table of coordinates but shows up
/// immediately as a gap or an overlap in the drawing, and there is only one
/// number per row to get right this way.
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

/// Both shift states of a printing key.
///
/// The recorder files `2` and `"` as two separate identities, so a cap that can
/// produce both has to claim both or half of its presses would land on no cap at
/// all. That includes the two JIS keys whose shifted legend is the same
/// character as the unshifted one, `0` and `_`: the press still arrives with the
/// shift flag set and is still tallied apart, even though the cap has no second
/// character to print.
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
    /// The Apple JIS board as it ships on the MacBook and the Magic Keyboard:
    /// six rows, 15 units wide.
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

        // Escape is countable even though it is also one of the events that
        // discards pending conversion state: the tap receives a real key event
        // for it, and how often the user reaches for it is exactly the sort of
        // thing this report exists to show.
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

        // The function row is not in ascending code order and never has been;
        // F5 is 0x60 while F1 is 0x7A. Reading them off in order would relabel
        // the whole row, so each one is paired with its code here.
        let functionKeys: [(name: String, keyCode: UInt16)] = [
            ("F1", 0x7A), ("F2", 0x78), ("F3", 0x63), ("F4", 0x76),
            ("F5", 0x60), ("F6", 0x61), ("F7", 0x62), ("F8", 0x64),
            ("F9", 0x65), ("F10", 0x6D), ("F11", 0x67), ("F12", 0x6F),
        ]
        caps.append(
            contentsOf: functionKeys.enumerated().map { offset, key in
                KeyCap(
                    id: key.name.lowercased(),
                    // Shift+F-key is an ordinary application shortcut, so the
                    // cap claims both states like every other printing key.
                    identities: jisBothShiftStates(key.keyCode),
                    x: 1 + Double(offset),
                    y: 0,
                    legend: KeyCapLegend(key.name),
                    // These carry their identities because the codes are real
                    // and do arrive as key events once the user turns on "use
                    // F1, F2, etc. keys as standard function keys". With that
                    // off, which is the default, the same physical press leaves
                    // the keyboard as a system-defined brightness or volume
                    // event that the tap never sees, so a cold cap here means
                    // "not visible" far more often than "not pressed".
                    exclusion: .media
                )
            }
        )

        // Rows 2, 3 and 4 tile to exactly 15u, which is what squares off the
        // right edge: 1.5 + 12 + 1.5 (tab, letters, return upper), 1.75 + 12 +
        // 1.25 (control, letters, return lower) and 2.25 + 11 + 1.75 (shift,
        // letters, shift). The function row stops at 13u and the number row at
        // 14u because a JIS board genuinely is short there: it has no key left
        // of `1`, and `¥` occupies the unit that would otherwise widen
        // `delete`. Leaving those two rows short is the honest drawing;
        // stretching a cap to hide it would misstate a key's size.
        caps.append(
            contentsOf: jisRun(
                [
                    JISRunKey("digit-1", 0x12, "1", "!", .leftPinky),
                    JISRunKey("digit-2", 0x13, "2", "\"", .leftRing),
                    JISRunKey("digit-3", 0x14, "3", "#", .leftMiddle),
                    JISRunKey("digit-4", 0x15, "4", "$", .leftIndex),
                    // 5 is 0x17 and 6 is 0x16. The pair is transposed in
                    // Events.h, and they are also the two keys the hands split
                    // at, so getting them backwards would move the boundary
                    // between the index fingers as well as the labels.
                    JISRunKey("digit-5", 0x17, "5", "%", .leftIndex),
                    JISRunKey("digit-6", 0x16, "6", "&", .rightIndex),
                    JISRunKey("digit-7", 0x1A, "7", "'", .rightIndex),
                    JISRunKey("digit-8", 0x1C, "8", "(", .rightMiddle),
                    JISRunKey("digit-9", 0x19, "9", ")", .rightRing),
                    // Shift+0 on JIS is `0` again, so there is no second legend
                    // to print. The cap still claims both shift states above.
                    JISRunKey("digit-0", 0x1D, "0", nil, .rightPinky),
                    JISRunKey("minus", 0x1B, "-", "=", .rightPinky),
                    JISRunKey("caret", 0x18, "^", "~", .rightPinky),
                    // Written as an escape because U+00A5 and a backslash are
                    // the classic pair to confuse in a fixed-width font, and
                    // this cap is precisely where the confusion starts.
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
            // Tab carries its shifted identity because Shift+Tab is a distinct
            // key in this codebase: it is one of the English fallback chords,
            // and back-tab is a different action from tab in every app anyway.
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

        // The JIS return is one inverted-L key drawn as two caps. Only the
        // upper one carries the identity: `KeyCap` allows an identity to appear
        // on several caps and leaves the renderer to mark them as a shared
        // total, but here the two halves are literally the same key, and a
        // reader who saw the same number printed twice would read it as two
        // presses. The lower half is therefore blank and identity-less, and
        // takes no `exclusion` because it is not an uncountable key — it is the
        // rest of a counted one.
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

        // Apple prints caps lock here and control at the bottom left, so that
        // is what is drawn. Swapping them to suit a common remap would make the
        // picture disagree with the board the reader is looking at, and a
        // heatmap whose caps are not where the user's fingers found them is
        // worse than one that is missing a key. Like every other modifier it
        // carries no finger: it is held rather than struck, so filing it under
        // the left pinky would inflate that finger's share with presses the
        // user does not experience as keystrokes.
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
                    // G is 0x05 and H is 0x04. Events.h really does list the
                    // home row out of alphabetical order, and taking the codes
                    // in order would swap the two keys the index fingers meet
                    // on — the most-pressed pair on the board.
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
                    // B is 0x0B, not 0x0A: 0x0A is the ISO section key, which
                    // sits left of Z on an ISO board and does not exist on this
                    // one.
                    JISRunKey("b", 0x0B, "B", nil, .leftIndex),
                    JISRunKey("n", 0x2D, "N", nil, .rightIndex),
                    JISRunKey("m", 0x2E, "M", nil, .rightIndex),
                    JISRunKey("comma", 0x2B, ",", "<", .rightMiddle),
                    JISRunKey("period", 0x2F, ".", ">", .rightRing),
                    JISRunKey("slash", 0x2C, "/", "?", .rightPinky),
                    // Both shift states of the JIS underscore key produce `_`,
                    // so like `0` it has one legend and two identities.
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

        // Apple's own bottom row, tiled to the same 15u as the three rows above
        // it: 1 + 1 + 1 + 1.25 + 1.25 + 3 + 1.25 + 1.25 + 1 + 3 for the arrow
        // cluster. The space bar carries the slack, which is where a real board
        // puts it too.
        //
        // None of these modifiers carries a finger. They sit outside the
        // touch-typing columns, and every one of them is a hold rather than a
        // stroke, so filing them under a finger would inflate that finger's
        // share of the typing with presses the user does not experience as
        // keystrokes.
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

        // 英数 and かな are the two caps this picture is really for. The English
        // fallback fires on a 英数 burst, so how hard that cap is worked is the
        // one number here that predicts how often the fallback runs; かな is its
        // counterpart on the way back. Unlike the modifiers flanking them they
        // arrive as ordinary key events, which is why they are countable
        // without the flags-changed path — and why they are drawn full size and
        // in the middle rather than tucked in beside the command keys.
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
        // A cap holds one finger, and the space bar is the one key most people
        // strike with either thumb. It goes to the right thumb because on this
        // board the left thumb is the 英数 thumb: the fallback trigger lives
        // there, so crediting space to the left as well would bury the number
        // that matters.
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

        // Left and right arrows are full height and the vertical pair is
        // stacked half-height in one column, which is the shape Apple ships and
        // also the shape that keeps the row exactly three units wide here.
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
                    // Shift+arrow is how text is selected, so these arrive
                    // shifted often enough that dropping that half would visibly
                    // cool the cluster.
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
