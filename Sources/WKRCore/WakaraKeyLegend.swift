import Foundation

/// What one key means in わから配列, for the heatmap's わから配列 legend mode.
///
/// The heatmap normally prints what is engraved on each cap, which answers
/// "which key" but not "which part of the layout". Under わから配列 the `E` key
/// is the か行 key, and a reader looking for how hard the vowel keys are worked
/// wants to see あ い う え お rather than H K J ; L. This is the name the key
/// would carry in the upstream README's core ten-column diagram.
///
/// Keyed by macOS virtual key code rather than by cap, because that is what the
/// transducer keys on: whatever physical position sends `kVK_ANSI_E`, whether a
/// MacBook's E key or a Corne position a `.vil` assigned `KC_E` to, is the か行
/// key. One table therefore relabels every board and every layer.
public struct WakaraKeyLegend: Equatable, Sendable, Codable {
    /// How the key takes part in the two-stroke scheme.
    public enum Role: String, Equatable, Sendable, Codable, CaseIterable {
        /// Selects a consonant row, and alone produces that row's あ-column
        /// kana. The fourteen left-hand keys.
        case consonantRow
        /// Alone produces a kana; after a consonant key it selects the column.
        case vowel
        /// Produces a kana alone and does nothing else (`ん` `っ` `ー`).
        case single
        /// Produces nothing alone and opens a layer for the next key.
        case prefix
    }

    public let keyCode: UInt16
    /// `PhysicalKey.rawValue`, so the entry says which key it came from without
    /// the reader having to decode the key code.
    public let key: String
    /// What the cap shows in the わから配列 mode: `か行`, `あ`, `□`.
    public let label: String
    public let role: Role
    /// One sentence for the tooltip.
    public let detail: String

    public init(keyCode: UInt16, key: String, label: String, role: Role, detail: String) {
        self.keyCode = keyCode
        self.key = key
        self.label = label
        self.role = role
        self.detail = detail
    }
}

public enum WakaraKeyLegends {
    /// Every key that begins a rule in the live table, in `PhysicalKey` order.
    public static let all: [WakaraKeyLegend] = derive(from: WKRLayout.rules)

    /// Legends for rule tables this build no longer runs, keyed by the
    /// `WKRLayout.layoutIdentifier` they were derived from, so that days a
    /// tally counted under an earlier table are labelled the way that table
    /// named its keys. Empty until the core columns change for the first time;
    /// each change adds the table it retired.
    public static let historical: [String: [WakaraKeyLegend]] = [:]

    /// Read the legends off the rules instead of writing a second copy of the
    /// layout.
    ///
    /// `AGENTS.md` gives the layout table one owner, and a hand-written list of
    /// labels here would drift from `WKRLayout` the first time a row changed. The
    /// shape of the rules already says what each key is: a key with a one-key
    /// rule that other rules continue from is a consonant row, one whose one-key
    /// rule is also the second key of a row is a vowel, and one with no one-key
    /// rule at all is a prefix. Only the prefixes have no kana to be named
    /// after, so they alone take their names from `prefixLegends`.
    ///
    /// A key that begins no rule — `,` `.` `/`, the digits, the brackets — is
    /// left out: WKR passes it through to Apple Japanese Input, and its engraving
    /// is already the truthful legend.
    ///
    /// The tooltip sentences list kana read off the same rules rather than
    /// describing them. A description has to be true of every row, and one is
    /// not: `X` is ふぁ行, but `XU` `XI` `XO` give てぃ でゅ でぃ.
    static func derive(from rules: [NormalizedRule]) -> [WakaraKeyLegend] {
        var singleKana: [PhysicalKey: String] = [:]
        var continued: Set<PhysicalKey> = []
        for rule in rules {
            guard let first = rule.input.first else { continue }
            if rule.input.count == 1 {
                singleKana[first] = rule.kana
            } else {
                continued.insert(first)
            }
        }
        let rows = Set(singleKana.keys).intersection(continued)
        let rowRules = rules.filter { $0.input.count == 2 && rows.contains($0.input[0]) }
        let columns = Set(rowRules.map { $0.input[1] })

        // What the matching two-stroke row rules produce, in table order.
        func outputs(where matches: (NormalizedRule) -> Bool) -> String {
            rowRules.filter(matches).map(\.kana).joined(separator: " ")
        }

        return PhysicalKey.allCases.compactMap { key -> WakaraKeyLegend? in
            // A first key without a code would drop out of every board silently.
            // The tests fail on it rather than letting the picture lose a key.
            guard let keyCode = unshiftedKeyCodes[key] else { return nil }
            if let kana = singleKana[key] {
                if rows.contains(key) {
                    // Vowel keys only: what the row gives after `Y` is the
                    // ■ key's to describe, since those presses land on its cap.
                    let row = outputs { $0.input[0] == key && singleKana[$0.input[1]] != nil }
                    return WakaraKeyLegend(
                        keyCode: keyCode,
                        key: key.rawValue,
                        label: kana + "行",
                        role: .consonantRow,
                        detail: "子音キー。単打で「\(kana)」、続く母音キーで \(row)"
                    )
                }
                if columns.contains(key) {
                    return WakaraKeyLegend(
                        keyCode: keyCode,
                        key: key.rawValue,
                        label: kana,
                        role: .vowel,
                        detail: "母音キー。単打で「\(kana)」、子音キーの後では段を選ぶ"
                    )
                }
                return WakaraKeyLegend(
                    keyCode: keyCode,
                    key: key.rawValue,
                    label: kana,
                    role: .single,
                    detail: "単打キー。単打で「\(kana)」"
                )
            }
            if continued.contains(key), let prefix = prefixLegends[key] {
                // `Y` is also the 特殊 column after a consonant key (`SY → しぇ`,
                // `EY → ヶ`). Those presses are in the same cap's count, so a
                // tooltip that called them all symbol input would misread it —
                // most of all with the symbol layer off, when they are most of
                // what `Y` still does.
                let column = outputs { $0.input[1] == key }
                return WakaraKeyLegend(
                    keyCode: keyCode,
                    key: key.rawValue,
                    label: prefix.label,
                    role: .prefix,
                    detail: prefix.detail + (column.isEmpty ? "" : "。子音キーの後では \(column)")
                )
            }
            return nil
        }
    }

    /// Names for the keys that only open a layer. They produce nothing alone,
    /// so nothing in the rules can name them; these are the upstream README's
    /// own glyphs, `□` for the small-kana prefix and `■` for the symbol prefix.
    static let prefixLegends: [PhysicalKey: (label: String, detail: String)] = [
        .t: ("□", "小書きの前置キー。続くキーで ぁ ゃ などの小書きを入力する"),
        .y: ("■", "記号・特殊文字の前置キー。続くキーで記号や ← などを入力する"),
    ]

    /// The macOS virtual key code of each unshifted key in the core ten columns.
    ///
    /// Carbon's `kVK_ANSI_*` values written out as literals, for the same reason
    /// `KeyboardGeometry+JIS.swift` gives: WKRCore links neither Carbon nor
    /// Core Graphics. `EventTapController` resolves the same codes the other
    /// way, from the live event to a `PhysicalKey`; the tests hold this table to
    /// the JIS and US drawings and to the Vial decoder so that the three agree
    /// on which cap each code is.
    static let unshiftedKeyCodes: [PhysicalKey: UInt16] = [
        .a: 0x00, .s: 0x01, .d: 0x02, .f: 0x03, .h: 0x04, .g: 0x05,
        .z: 0x06, .x: 0x07, .c: 0x08, .v: 0x09, .b: 0x0B, .q: 0x0C,
        .w: 0x0D, .e: 0x0E, .r: 0x0F, .y: 0x10, .t: 0x11, .o: 0x1F,
        .u: 0x20, .i: 0x22, .p: 0x23, .l: 0x25, .j: 0x26, .k: 0x28,
        .n: 0x2D, .m: 0x2E, .semicolon: 0x29, .comma: 0x2B,
        .period: 0x2F, .slash: 0x2C,
    ]
}
