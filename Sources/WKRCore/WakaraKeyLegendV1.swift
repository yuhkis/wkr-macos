#if WKR_V1
// Frozen public v1 rules; the runtime conversion engine is shared with v2.
import Foundation

public struct WakaraKeyLegend: Equatable, Sendable, Codable {
    public enum Role: String, Equatable, Sendable, Codable, CaseIterable {
        case consonantRow
        case vowel
        case single
        case prefix
    }

    public let keyCode: UInt16
    public let key: String
    public let label: String
    public let role: Role
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
    public static let historical: [String: [WakaraKeyLegend]] = [:]
    public static let all: [WakaraKeyLegend] = derive(from: WKRLayout.rules)

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

        func outputs(where matches: (NormalizedRule) -> Bool) -> String {
            rowRules.filter(matches).map(\.kana).joined(separator: " ")
        }

        return PhysicalKey.allCases.compactMap { key -> WakaraKeyLegend? in
            guard let keyCode = unshiftedKeyCodes[key] else { return nil }
            if let kana = singleKana[key] {
                if rows.contains(key) {
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

    static let prefixLegends: [PhysicalKey: (label: String, detail: String)] = [
        .t: ("□", "小書きの前置キー。続くキーで ぁ ゃ などの小書きを入力する"),
        .y: ("■", "記号・特殊文字の前置キー。続くキーで記号や ← などを入力する"),
    ]

    static let unshiftedKeyCodes: [PhysicalKey: UInt16] = [
        .a: 0x00, .s: 0x01, .d: 0x02, .f: 0x03, .h: 0x04, .g: 0x05,
        .z: 0x06, .x: 0x07, .c: 0x08, .v: 0x09, .b: 0x0B, .q: 0x0C,
        .w: 0x0D, .e: 0x0E, .r: 0x0F, .y: 0x10, .t: 0x11, .o: 0x1F,
        .u: 0x20, .i: 0x22, .p: 0x23, .l: 0x25, .j: 0x26, .k: 0x28,
        .n: 0x2D, .m: 0x2E, .semicolon: 0x29, .comma: 0x2B,
        .period: 0x2F, .slash: 0x2C,
    ]
}

#endif
