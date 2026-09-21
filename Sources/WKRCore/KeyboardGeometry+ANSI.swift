import Foundation

extension KeyboardGeometry {
    /// The ANSI (US) board as an Apple Magic Keyboard draws it: a 60% block with
    /// a function row above it and an inverted-T arrow cluster where a full-size
    /// board would start its navigation keys. No numeric keypad, no navigation
    /// cluster, so every cap here is one a laptop keyboard also has.
    ///
    /// The virtual key codes are the same ones the JIS geometry uses wherever
    /// both boards have the key, because a key code names a position on the
    /// board rather than the character printed there — which is why the tally
    /// can be drawn on either without being converted.
    ///
    /// The boards are not the same set of keys, though. JIS carries ¥ (0x5D),
    /// the underscore key (0x5E), 英数 (0x66) and かな (0x68); ANSI has no cap
    /// for any of them, so presses of those four are recorded and then drawn
    /// nowhere here. The caveats say so, because a reader comparing the two tabs
    /// would otherwise read the difference as a change in how they type.
    public static let us: KeyboardGeometry = {
        // A key press is identified by its code *and* its shift state, so a cap
        // that listed only the unshifted code would quietly drop every capital
        // and every shifted symbol out of the picture. Both states are claimed
        // here, and the renderer adds them up into the one number the cap shows.
        func counted(
            _ name: String,
            _ keyCode: UInt16,
            _ primary: String,
            _ secondary: String? = nil,
            x: Double,
            y: Double,
            width: Double = 1,
            height: Double = 1,
            finger: KeyCap.Finger
        ) -> KeyCap {
            KeyCap(
                id: "us-" + name,
                identities: [
                    KeyIdentity(keyCode: keyCode),
                    KeyIdentity(keyCode: keyCode, isShifted: true),
                ],
                x: x,
                y: y,
                width: width,
                height: height,
                legend: KeyCapLegend(primary, secondary),
                finger: finger
            )
        }

        // A modifier keeps its own key code and is drawn with its own number,
        // but it is marked `.modifier` and carries no finger.
        //
        // `.modifier` because these arrive as flags-changed events, which the
        // tap only widens to accept while frequency logging is on, so the number
        // is younger than the ones on the printing keys beside it.
        //
        // No finger because the per-finger table answers "how much is this
        // finger striking", and a modifier is held rather than struck. Folding
        // holds into it would make the figures incomparable to ordinary layout
        // analysis and would put the pinkies at the top of every board. All
        // three geometries follow this rule so the tabs can be read against each
        // other.
        //
        // The `finger` argument is kept in the signature because the call sites
        // read better naming the hand the key belongs to, and because the day
        // this policy is revisited the information is already there.
        func modifier(
            _ name: String,
            _ keyCode: UInt16,
            _ legend: String,
            x: Double,
            y: Double,
            width: Double = 1,
            finger: KeyCap.Finger
        ) -> KeyCap {
            _ = finger
            return KeyCap(
                id: "us-" + name,
                identities: [KeyIdentity(keyCode: keyCode)],
                x: x,
                y: y,
                width: width,
                legend: KeyCapLegend(legend),
                exclusion: .modifier
            )
        }

        // F1..F12 ship as brightness, Mission Control and volume keys, which
        // macOS delivers as system-defined events rather than key events, so
        // `.media` says why the cap is usually cold. The identity is claimed
        // anyway, because the codes are real and the same physical press does
        // arrive as an ordinary key event once the user turns on "use F1, F2,
        // etc. keys as standard function keys" — and because the JIS geometry
        // drawn on the next tab claims them, so withholding them here would make
        // one key countable on one board and not on the other. No finger: they
        // sit outside the touch-typing columns.
        func functionKey(_ name: String, _ keyCode: UInt16, x: Double) -> KeyCap {
            KeyCap(
                id: "us-" + name,
                identities: [
                    KeyIdentity(keyCode: keyCode),
                    KeyIdentity(keyCode: keyCode, isShifted: true),
                ],
                x: x,
                y: 0,
                legend: KeyCapLegend(name.uppercased()),
                exclusion: .media
            )
        }

        var caps: [KeyCap] = []

        // Row 0, the function row, is the one row that does not span the board:
        // esc plus twelve function keys is 13.0u against the 15.0u below it. It
        // is left short rather than padded out, because the only honest way to
        // fill the remaining 2u would be caps this drawing does not have.
        caps.append(counted("esc", 0x35, "esc", x: 0, y: 0, finger: .leftPinky))
        // Out of sequence, like the letters and digits: macOS numbered these by
        // the original board's wiring, not by the label printed on the cap.
        let functionKeys: [UInt16] = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61,
            0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F,
        ]
        for (offset, keyCode) in functionKeys.enumerated() {
            caps.append(functionKey("f\(offset + 1)", keyCode, x: Double(offset + 1)))
        }

        // The code tables below are written in the order the caps are drawn, not
        // in code order, and the codes genuinely run out of sequence: `5` is
        // 0x17 while `6` is 0x16, `=` is 0x18 just before `9` is 0x19, and `G`
        // is 0x05 while `H` is 0x04. The letter block also skips 0x0A, which is
        // the ISO section key an ANSI board does not carry, so `B` is 0x0B.
        // None of this is a transcription slip; sorting it would break it.
        let numberRow: [(name: String, code: UInt16, primary: String, secondary: String?, finger: KeyCap.Finger)] = [
            ("grave", 0x32, "`", "~", .leftPinky),
            ("1", 0x12, "1", "!", .leftPinky),
            ("2", 0x13, "2", "@", .leftRing),
            ("3", 0x14, "3", "#", .leftMiddle),
            ("4", 0x15, "4", "$", .leftIndex),
            ("5", 0x17, "5", "%", .leftIndex),
            ("6", 0x16, "6", "^", .rightIndex),
            ("7", 0x1A, "7", "&", .rightIndex),
            ("8", 0x1C, "8", "*", .rightMiddle),
            ("9", 0x19, "9", "(", .rightRing),
            ("0", 0x1D, "0", ")", .rightPinky),
            ("minus", 0x1B, "-", "_", .rightPinky),
            ("equal", 0x18, "=", "+", .rightPinky),
        ]
        for (index, key) in numberRow.enumerated() {
            caps.append(
                counted(key.name, key.code, key.primary, key.secondary, x: Double(index), y: 1, finger: key.finger)
            )
        }
        caps.append(counted("delete", 0x33, "⌫", x: 13, y: 1, width: 2, finger: .rightPinky))

        let upperRow: [(name: String, code: UInt16, primary: String, secondary: String?, finger: KeyCap.Finger)] = [
            ("q", 0x0C, "Q", nil, .leftPinky),
            ("w", 0x0D, "W", nil, .leftRing),
            ("e", 0x0E, "E", nil, .leftMiddle),
            ("r", 0x0F, "R", nil, .leftIndex),
            ("t", 0x11, "T", nil, .leftIndex),
            ("y", 0x10, "Y", nil, .rightIndex),
            ("u", 0x20, "U", nil, .rightIndex),
            ("i", 0x22, "I", nil, .rightMiddle),
            ("o", 0x1F, "O", nil, .rightRing),
            ("p", 0x23, "P", nil, .rightPinky),
            ("left-bracket", 0x21, "[", "{", .rightPinky),
            ("right-bracket", 0x1E, "]", "}", .rightPinky),
        ]
        caps.append(counted("tab", 0x30, "⇥", x: 0, y: 2, width: 1.5, finger: .leftPinky))
        for (index, key) in upperRow.enumerated() {
            caps.append(
                counted(key.name, key.code, key.primary, key.secondary, x: 1.5 + Double(index), y: 2, finger: key.finger)
            )
        }
        caps.append(counted("backslash", 0x2A, "\\", "|", x: 13.5, y: 2, width: 1.5, finger: .rightPinky))

        let homeRow: [(name: String, code: UInt16, primary: String, secondary: String?, finger: KeyCap.Finger)] = [
            ("a", 0x00, "A", nil, .leftPinky),
            ("s", 0x01, "S", nil, .leftRing),
            ("d", 0x02, "D", nil, .leftMiddle),
            ("f", 0x03, "F", nil, .leftIndex),
            ("g", 0x05, "G", nil, .leftIndex),
            ("h", 0x04, "H", nil, .rightIndex),
            ("j", 0x26, "J", nil, .rightIndex),
            ("k", 0x28, "K", nil, .rightMiddle),
            ("l", 0x25, "L", nil, .rightRing),
            ("semicolon", 0x29, ";", ":", .rightPinky),
            ("quote", 0x27, "'", "\"", .rightPinky),
        ]
        // Caps Lock is a modifier here for the same reason Shift is: macOS
        // reports it through flags-changed, not as a key event.
        caps.append(modifier("caps-lock", 0x39, "⇪", x: 0, y: 3, width: 1.75, finger: .leftPinky))
        for (index, key) in homeRow.enumerated() {
            caps.append(
                counted(key.name, key.code, key.primary, key.secondary, x: 1.75 + Double(index), y: 3, finger: key.finger)
            )
        }
        caps.append(counted("return", 0x24, "↩", x: 12.75, y: 3, width: 2.25, finger: .rightPinky))

        let lowerRow: [(name: String, code: UInt16, primary: String, secondary: String?, finger: KeyCap.Finger)] = [
            ("z", 0x06, "Z", nil, .leftPinky),
            ("x", 0x07, "X", nil, .leftRing),
            ("c", 0x08, "C", nil, .leftMiddle),
            ("v", 0x09, "V", nil, .leftIndex),
            ("b", 0x0B, "B", nil, .leftIndex),
            ("n", 0x2D, "N", nil, .rightIndex),
            ("m", 0x2E, "M", nil, .rightIndex),
            ("comma", 0x2B, ",", "<", .rightMiddle),
            ("period", 0x2F, ".", ">", .rightRing),
            ("slash", 0x2C, "/", "?", .rightPinky),
        ]
        caps.append(modifier("left-shift", 0x38, "⇧", x: 0, y: 4, width: 2.25, finger: .leftPinky))
        for (index, key) in lowerRow.enumerated() {
            caps.append(
                counted(key.name, key.code, key.primary, key.secondary, x: 2.25 + Double(index), y: 4, finger: key.finger)
            )
        }
        caps.append(modifier("right-shift", 0x3C, "⇧", x: 12.25, y: 4, width: 2.75, finger: .rightPinky))

        // The bottom row's modifiers add up to 11.5u and the arrow cluster needs
        // 3u, so something has to give up half a unit. The cluster is set flush
        // against the right edge and the slack is left as a visible 0.5u seam
        // after the right Option, rather than hidden by widening a modifier: the
        // reader can measure these caps against their own keyboard, and a cap
        // drawn wider than it is would be the kind of error nobody catches.
        // There is no right Control cap (0x3E) — the cluster owns that end.
        caps.append(modifier("fn", 0x3F, "fn", x: 0, y: 5, finger: .leftPinky))
        caps.append(modifier("left-control", 0x3B, "⌃", x: 1, y: 5, finger: .leftPinky))
        caps.append(modifier("left-option", 0x3A, "⌥", x: 2, y: 5, finger: .leftThumb))
        caps.append(modifier("left-command", 0x37, "⌘", x: 3, y: 5, width: 1.25, finger: .leftThumb))
        // The space bar is filed under the right thumb because that is the
        // convention the typing tutors teach. It is a 5u bar either thumb can
        // reach, so no single answer is right, and the summary is easier to read
        // when the largest key in the tally sits in one place every run.
        caps.append(counted("space", 0x31, "Space", x: 4.25, y: 5, width: 5.5, finger: .rightThumb))
        caps.append(modifier("right-command", 0x36, "⌘", x: 9.75, y: 5, width: 1.25, finger: .rightThumb))
        caps.append(modifier("right-option", 0x3D, "⌥", x: 11, y: 5, finger: .rightThumb))

        // Up and down split one 1u column into halves, so the cluster reads as
        // the inverted T it is on the board. All four are filed under the right
        // pinky: they sit outside every home-row column, and the pinky is the
        // finger whose column they extend.
        caps.append(counted("left-arrow", 0x7B, "←", x: 12, y: 5, finger: .rightPinky))
        caps.append(counted("up-arrow", 0x7E, "↑", x: 13, y: 5, height: 0.5, finger: .rightPinky))
        caps.append(counted("down-arrow", 0x7D, "↓", x: 13, y: 5.5, height: 0.5, finger: .rightPinky))
        caps.append(counted("right-arrow", 0x7C, "→", x: 14, y: 5, finger: .rightPinky))

        // Every row from the number row down tiles to exactly 15.0u, which is
        // the width the renderer sizes its viewBox from:
        //   row 1   13 × 1u + 2.00u                         = 15.0
        //   row 2   1.50u + 12 × 1u + 1.50u                 = 15.0
        //   row 3   1.75u + 11 × 1u + 2.25u                 = 15.0
        //   row 4   2.25u + 10 × 1u + 2.75u                 = 15.0
        //   row 5   11.50u of modifiers + 0.50u seam + 3u   = 15.0
        // The function row stops at 13.0u, as noted where it is built. Height is
        // six rows of 1u; the half-height arrows share row 5 and add nothing.
        return KeyboardGeometry(
            model: .us,
            displayName: KeyboardModel.us.displayName,
            widthUnits: 15,
            heightUnits: 6,
            caps: caps,
            caveats: [
                "⇧ ⌃ ⌥ ⌘ ⇪ fn の単独押下は flags-changed イベントとして届く。打鍵頻度の記録が有効な間だけ event tap がこれを受け取るため、記録を有効にする前の分は数に含まれない。",
                "F1〜F12 は既定では輝度・音量などのシステムキーとして届く。system-defined イベントのため event tap からは見えない。「F1、F2 などのキーを標準のファンクションキーとして使用」が有効なときだけ通常のキーイベントとして数えられる。",
                "ANSI配列には 英数 / かな キーがない。macOS では Control+Space か Karabiner の再割り当てで切り替えるのが普通で、Control を伴う打鍵は計数対象外のため、この2キーの数はこの図には出ない。JIS の図には両方あり、Cornix の図にはレイヤー0へ置いている分だけが出る。",
                "JIS にあって ANSI に無いキー（¥、_、英数、かな）の打鍵は、記録はされていてもこの図には描かれない。JIS のタブと見比べるときは、その差を打ち方の違いと読み違えないこと。",
                "指ごとの集計は「その指が叩いた回数」です。修飾キーは押しっぱなしにするもので叩く回数とは性質が違うため、指の集計には入れていません（キーごとの数値には出ます）。",
            ]
        )
    }()
}
