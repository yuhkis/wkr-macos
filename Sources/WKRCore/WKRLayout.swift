public enum WKRLayout {
    public static let sourceRepositoryURL = "https://github.com/yuhkis/wkr-layout"
    /// Base snapshot. Rules marked "ahead of upstream v1.1" below are agreed
    /// layout changes that land in wkr-layout with its next release; re-pin this
    /// revision once that release exists.
    public static let sourceRevision = "a8c102fa6dab6b7d7fdf9678ec9ce2e646facec8"
    public static let sourceImportedOn = "2026-08-11"

    /// Entries that cannot be mapped uniquely to a physical JIS key. They are
    /// retained here as an explicit quarantine instead of being guessed into
    /// the live table.
    public static let quarantinedUpstreamEntries: [String] = [
        "google romantable line 168: duplicate y -> 〒 conflicts with y symbol prefix",
        "google romantable lines 176, 208, 220: embedded control/replacement bytes",
        "google romantable lines 193 and 228: duplicate ■x with different outputs",
        "azooKey lines 251, 252, 272: malformed delimiters or replacement bytes",
        "google romantable lines 210, 211: ■' -> ' and ■\" -> \" are ANSI readings of the keys that JIS labels Shift+7 and Shift+2, which the ■& -> ￡ and ■@ -> ▼ rows (azooKey ’ and ”) already occupy",
    ]

    public static let rules: [NormalizedRule] = makeRules(includingSymbolLayer: true)

    /// The same table without the 55 `Y` symbol rules.
    ///
    /// Every rule in that layer is a Unicode injection, which commits the
    /// moment it is decided and cannot join Apple Japanese Input's pre-edit at
    /// all. Committing without the chance to convert is unwanted often enough
    /// that turning the layer off is a supported choice; see `docs/design.md`
    /// section 5.4.
    ///
    /// Two groups stay. `arrowRules` are romaji, so none of that applies to
    /// them and `Y` keeps working as their prefix. Rules where `Y` is the
    /// *second* key, such as `SY → しぇ` and `EY → ヶ`, are row variants rather
    /// than the symbol layer.
    public static let rulesWithoutSymbolLayer: [NormalizedRule] =
        makeRules(includingSymbolLayer: false)

    /// Prefix mode used to have nothing to show for `Y`, because every rule
    /// under it injected Unicode, and an explicit placeholder letter filled the
    /// gap. The arrows now carry romaji, so the shared prefix of the subtree is
    /// `z` and the ordinary rule computes the provisional like any other root.
    /// Keeping the override would only pin a letter the table already supplies.
    public static let symbolLayerProvisionalRomaji: [PhysicalKey: String] = [:]

    /// JIS bracket keys already produce these characters through Apple Japanese
    /// Input, and going through the IME keeps them in the pre-edit buffer where
    /// Space can still convert them, exactly like `（` and `＜`. Injecting the
    /// character with a Unicode event instead committed it immediately, so
    /// these keys are deliberately left to pass through untouched.
    public static let passThroughKeys: [String] = [
        "[ -> 「", "] -> 」", "Shift+[ -> 『", "Shift+] -> 』",
    ]

    public static let optimisticDeletionProfile = OptimisticDeletionProfile(
        backspacesByRuleID: [
            "e-ka": 1,
            "s-sa": 1,
            "f-ta": 1,
            "d-na": 1,
            "g-ha": 1,
            "v-ma": 1,
            "r-ra": 1,
            "w-wa": 1,
            "q-ga": 1,
            "z-za": 1,
            "c-da": 1,
            "b-ba": 1,
            "a-pa": 1,
            // 「ふぁ」は二つのかな文字として削除する実験値。
            "x-fa": 2,
            "h-a": 1,
            "k-i": 1,
            "j-u": 1,
            "semicolon-e": 1,
            "l-o": 1,
            "u-ya": 1,
            "i-yu": 1,
            "o-yo": 1,
        ]
    )
}

private extension WKRLayout {
    static func makeRules(includingSymbolLayer: Bool) -> [NormalizedRule] {
        var result: [NormalizedRule] = []

        for row in kanaRows {
            result.append(
                .init(
                    id: row.rootID,
                    input: [row.key],
                    kana: row.rootKana,
                    romaji: row.rootRomaji
                )
            )
            result.append(contentsOf: row.variants.map { variant in
                makeRule(
                    id: variant.id,
                    input: [row.key, variant.key],
                    kana: variant.kana,
                    delivery: variant.delivery
                )
            })
        }

        result.append(contentsOf: singleRules)
        result.append(contentsOf: smallKanaRules)
        result.append(contentsOf: arrowRules)
        if includingSymbolLayer {
            result.append(contentsOf: symbolRules)
        }
        return result
    }

    enum Delivery {
        case romaji(String)
        case unicode(String)
    }

    struct Variant {
        let id: String
        let key: PhysicalKey
        let kana: String
        let delivery: Delivery

        init(_ id: String, _ key: PhysicalKey, _ kana: String, _ romaji: String) {
            self.id = id
            self.key = key
            self.kana = kana
            self.delivery = .romaji(romaji)
        }

        init(text id: String, _ key: PhysicalKey, _ text: String) {
            self.id = id
            self.key = key
            self.kana = text
            self.delivery = .unicode(text)
        }
    }

    struct KanaRow {
        let rootID: String
        let key: PhysicalKey
        let rootKana: String
        let rootRomaji: String
        let variants: [Variant]
    }

    static func makeRule(
        id: String,
        input: [PhysicalKey],
        kana: String,
        delivery: Delivery
    ) -> NormalizedRule {
        switch delivery {
        case let .romaji(value):
            return .init(id: id, input: input, kana: kana, romaji: value)
        case let .unicode(value):
            return .init(id: id, input: input, text: value)
        }
    }

    static let kanaRows: [KanaRow] = [
        .init(rootID: "e-ka", key: .e, rootKana: "か", rootRomaji: "ka", variants: [
            .init("eh-ka", .h, "か", "ka"),
            .init("ek-ki", .k, "き", "ki"),
            .init("ej-ku", .j, "く", "ku"),
            .init("esemicolon-ke", .semicolon, "け", "ke"),
            .init("el-ko", .l, "こ", "ko"),
            .init("eu-kya", .u, "きゃ", "kya"),
            .init("ei-kyu", .i, "きゅ", "kyu"),
            .init("eo-kyo", .o, "きょ", "kyo"),
            // `lke` was measured against Apple Japanese Input's own romaji
            // table on 2026-08-16: the rule exists and produces U+30F6, the
            // character this row declares. Romaji keeps it inside the pre-edit,
            // where the symbol layer's Unicode injection cannot go.
            .init("ey-small-ke", .y, "ヶ", "lke"),
        ]),
        .init(rootID: "s-sa", key: .s, rootKana: "さ", rootRomaji: "sa", variants: [
            .init("sh-sa", .h, "さ", "sa"),
            .init("sk-shi", .k, "し", "shi"),
            .init("sj-su", .j, "す", "su"),
            .init("ssemicolon-se", .semicolon, "せ", "se"),
            .init("sl-so", .l, "そ", "so"),
            .init("su-sha", .u, "しゃ", "sha"),
            .init("si-shu", .i, "しゅ", "shu"),
            .init("so-sho", .o, "しょ", "sho"),
            .init("sy-she", .y, "しぇ", "she"),
        ]),
        // 行内の全ローマ字が同じ1文字目を共有するように、Apple日本語入力が
        // 受理する訓令式綴りを選ぶ。prefix-romajiが1キー目から `t` を出せる。
        .init(rootID: "f-ta", key: .f, rootKana: "た", rootRomaji: "ta", variants: [
            .init("fh-ta", .h, "た", "ta"),
            .init("fk-chi", .k, "ち", "ti"),
            .init("fj-tsu", .j, "つ", "tu"),
            .init("fsemicolon-te", .semicolon, "て", "te"),
            .init("fl-to", .l, "と", "to"),
            .init("fu-cha", .u, "ちゃ", "tya"),
            .init("fi-chu", .i, "ちゅ", "tyu"),
            .init("fo-cho", .o, "ちょ", "tyo"),
            .init("fy-che", .y, "ちぇ", "tye"),
        ]),
        .init(rootID: "d-na", key: .d, rootKana: "な", rootRomaji: "na", variants: [
            .init("dh-na", .h, "な", "na"),
            .init("dk-ni", .k, "に", "ni"),
            .init("dj-nu", .j, "ぬ", "nu"),
            .init("dsemicolon-ne", .semicolon, "ね", "ne"),
            .init("dl-no", .l, "の", "no"),
            .init("du-nya", .u, "にゃ", "nya"),
            .init("di-nyu", .i, "にゅ", "nyu"),
            .init("do-nyo", .o, "にょ", "nyo"),
        ]),
        .init(rootID: "g-ha", key: .g, rootKana: "は", rootRomaji: "ha", variants: [
            .init("gh-ha", .h, "は", "ha"),
            .init("gk-hi", .k, "ひ", "hi"),
            .init("gj-fu", .j, "ふ", "hu"),
            .init("gsemicolon-he", .semicolon, "へ", "he"),
            .init("gl-ho", .l, "ほ", "ho"),
            .init("gu-hya", .u, "ひゃ", "hya"),
            .init("gi-hyu", .i, "ひゅ", "hyu"),
            .init("go-hyo", .o, "ひょ", "hyo"),
        ]),
        .init(rootID: "v-ma", key: .v, rootKana: "ま", rootRomaji: "ma", variants: [
            .init("vh-ma", .h, "ま", "ma"),
            .init("vk-mi", .k, "み", "mi"),
            .init("vj-mu", .j, "む", "mu"),
            .init("vsemicolon-me", .semicolon, "め", "me"),
            .init("vl-mo", .l, "も", "mo"),
            .init("vu-mya", .u, "みゃ", "mya"),
            .init("vi-myu", .i, "みゅ", "myu"),
            .init("vo-myo", .o, "みょ", "myo"),
        ]),
        .init(rootID: "r-ra", key: .r, rootKana: "ら", rootRomaji: "ra", variants: [
            .init("rh-ra", .h, "ら", "ra"),
            .init("rk-ri", .k, "り", "ri"),
            .init("rj-ru", .j, "る", "ru"),
            .init("rsemicolon-re", .semicolon, "れ", "re"),
            .init("rl-ro", .l, "ろ", "ro"),
            .init("ru-rya", .u, "りゃ", "rya"),
            .init("ri-ryu", .i, "りゅ", "ryu"),
            .init("ro-ryo", .o, "りょ", "ryo"),
        ]),
        .init(rootID: "w-wa", key: .w, rootKana: "わ", rootRomaji: "wa", variants: [
            .init("wh-wa", .h, "わ", "wa"),
            .init("wk-wi", .k, "うぃ", "wi"),
            // Was ヴ (U+30F4) as a Unicode injection. Apple Japanese Input has
            // no hiragana-mode spelling for the katakana form: every `v` rule in
            // its table produces ゔ (U+3094), because ゔ exists while ヵ and ヶ
            // have no hiragana form and so are spelled directly. Injecting ヴ
            // committed it and took it out of the pre-edit, which is why ゔぁ,
            // ゔぃ, ゔぇ, ゔぉ and the ゔゃ row could not be built at all: there
            // was nothing left on screen for a small kana to attach to. `vu`
            // keeps it in the pre-edit, so those eight follow from the existing
            // small kana rules, and Space still reaches ヴ.
            .init("wj-vu", .j, "ゔ", "vu"),
            .init("wsemicolon-we", .semicolon, "うぇ", "we"),
            .init("wl-wo", .l, "を", "wo"),
            .init("wu-archaic-wi", .u, "ゐ", "wyi"),
            .init("wi-archaic-we", .i, "ゑ", "wye"),
            .init("wo-who", .o, "うぉ", "who"),
            .init("wy-small-wa", .y, "ゎ", "lwa"),
        ]),
        .init(rootID: "q-ga", key: .q, rootKana: "が", rootRomaji: "ga", variants: [
            .init("qh-ga", .h, "が", "ga"),
            .init("qk-gi", .k, "ぎ", "gi"),
            .init("qj-gu", .j, "ぐ", "gu"),
            .init("qsemicolon-ge", .semicolon, "げ", "ge"),
            .init("ql-go", .l, "ご", "go"),
            .init("qu-gya", .u, "ぎゃ", "gya"),
            .init("qi-gyu", .i, "ぎゅ", "gyu"),
            .init("qo-gyo", .o, "ぎょ", "gyo"),
            // `ヵ` had no key at all while `ヶ` sat on `EY`, and neither can be
            // built from a base kana because they have no hiragana form. This
            // row's `Y` slot was free. Added ahead of upstream wkr-layout v1.1.
            .init("qy-small-ka", .y, "ヵ", "lka"),
        ]),
        .init(rootID: "z-za", key: .z, rootKana: "ざ", rootRomaji: "za", variants: [
            .init("zh-za", .h, "ざ", "za"),
            .init("zk-ji", .k, "じ", "zi"),
            .init("zj-zu", .j, "ず", "zu"),
            .init("zsemicolon-ze", .semicolon, "ぜ", "ze"),
            .init("zl-zo", .l, "ぞ", "zo"),
            .init("zu-ja", .u, "じゃ", "zya"),
            .init("zi-ju", .i, "じゅ", "zyu"),
            .init("zo-jo", .o, "じょ", "zyo"),
            .init("zy-je", .y, "じぇ", "zye"),
        ]),
        .init(rootID: "c-da", key: .c, rootKana: "だ", rootRomaji: "da", variants: [
            .init("ch-da", .h, "だ", "da"),
            .init("ck-di", .k, "ぢ", "di"),
            .init("cj-du", .j, "づ", "du"),
            .init("csemicolon-de", .semicolon, "で", "de"),
            .init("cl-do", .l, "ど", "do"),
            .init("cu-dya", .u, "ぢゃ", "dya"),
            .init("ci-dyu", .i, "ぢゅ", "dyu"),
            .init("co-dyo", .o, "ぢょ", "dyo"),
            .init("cy-dhi", .y, "でぃ", "deli"),
        ]),
        .init(rootID: "b-ba", key: .b, rootKana: "ば", rootRomaji: "ba", variants: [
            .init("bh-ba", .h, "ば", "ba"),
            .init("bk-bi", .k, "び", "bi"),
            .init("bj-bu", .j, "ぶ", "bu"),
            .init("bsemicolon-be", .semicolon, "べ", "be"),
            .init("bl-bo", .l, "ぼ", "bo"),
            .init("bu-bya", .u, "びゃ", "bya"),
            .init("bi-byu", .i, "びゅ", "byu"),
            .init("bo-byo", .o, "びょ", "byo"),
        ]),
        .init(rootID: "a-pa", key: .a, rootKana: "ぱ", rootRomaji: "pa", variants: [
            .init("ah-pa", .h, "ぱ", "pa"),
            .init("ak-pi", .k, "ぴ", "pi"),
            .init("aj-pu", .j, "ぷ", "pu"),
            .init("asemicolon-pe", .semicolon, "ぺ", "pe"),
            .init("al-po", .l, "ぽ", "po"),
            .init("au-pya", .u, "ぴゃ", "pya"),
            .init("ai-pyu", .i, "ぴゅ", "pyu"),
            .init("ao-pyo", .o, "ぴょ", "pyo"),
        ]),
        // `ふぁ` 系はApple日本語入力が受理する短い綴りを使い、合成キーイベント数
        // を減らす。`て` / `で` 系の小書き部分は他の小書きと同じ `l` に揃える。
        .init(rootID: "x-fa", key: .x, rootKana: "ふぁ", rootRomaji: "fa", variants: [
            .init("xh-fa", .h, "ふぁ", "fa"),
            .init("xk-fi", .k, "ふぃ", "fi"),
            .init("xj-fyu", .j, "ふゅ", "fyu"),
            .init("xsemicolon-fe", .semicolon, "ふぇ", "fe"),
            .init("xl-fo", .l, "ふぉ", "fo"),
            .init("xy-tyu", .y, "てゅ", "telyu"),
            .init("xu-thi", .u, "てぃ", "teli"),
            .init("xi-dhu", .i, "でゅ", "delyu"),
            .init("xo-dhi", .o, "でぃ", "deli"),
        ]),
    ]

    static let singleRules: [NormalizedRule] = [
        .init(id: "h-a", input: [.h], kana: "あ", romaji: "a"),
        .init(id: "k-i", input: [.k], kana: "い", romaji: "i"),
        .init(id: "j-u", input: [.j], kana: "う", romaji: "u"),
        .init(id: "semicolon-e", input: [.semicolon], kana: "え", romaji: "e"),
        .init(id: "l-o", input: [.l], kana: "お", romaji: "o"),
        .init(id: "u-ya", input: [.u], kana: "や", romaji: "ya"),
        .init(id: "i-yu", input: [.i], kana: "ゆ", romaji: "yu"),
        .init(id: "o-yo", input: [.o], kana: "よ", romaji: "yo"),
        .init(id: "n-n", input: [.n], kana: "ん", romaji: "nn"),
        .init(id: "m-small-tsu", input: [.m], kana: "っ", romaji: "ltu"),
        .init(id: "p-long", input: [.p], kana: "ー", romaji: "-"),
    ]

    // 後置小書きは `K` `T` を持たない。`KT → ぃ` があると `K` の後の `T` がその規則に
    // 吸われ、`K` `T` `;` が `いぇ` ではなく `ぃえ` になる。`ぃ` は前置形 `TK` で入力する。
    // 残る7件の後置小書きにも同じ衝突があり、上流での判断は docs/layout-coverage.md にある。
    //
    // 小書きは `x` ではなく `l` で送る。2026-08-12の実機確認で、Apple日本語入力は
    // 単発の `xya` は受理するが、`xyaxyuxyo` のように連続すると先頭の `x` を確定
    // 文字として切り離し、`xやx湯ょ` になった。`lyalyulyo` は連続でも正しく
    // `ゃゅょ` になる。
    static let smallKanaRules: [NormalizedRule] = [
        .init(id: "th-small-a", input: [.t, .h], kana: "ぁ", romaji: "la"),
        .init(id: "tk-small-i", input: [.t, .k], kana: "ぃ", romaji: "li"),
        .init(id: "tj-small-u", input: [.t, .j], kana: "ぅ", romaji: "lu"),
        .init(id: "tsemicolon-small-e", input: [.t, .semicolon], kana: "ぇ", romaji: "le"),
        .init(id: "tl-small-o", input: [.t, .l], kana: "ぉ", romaji: "lo"),
        .init(id: "tu-small-ya", input: [.t, .u], kana: "ゃ", romaji: "lya"),
        .init(id: "ti-small-yu", input: [.t, .i], kana: "ゅ", romaji: "lyu"),
        .init(id: "to-small-yo", input: [.t, .o], kana: "ょ", romaji: "lyo"),
        .init(id: "ht-small-a", input: [.h, .t], kana: "ぁ", romaji: "la"),
        .init(id: "jt-small-u", input: [.j, .t], kana: "ぅ", romaji: "lu"),
        .init(id: "semicolont-small-e", input: [.semicolon, .t], kana: "ぇ", romaji: "le"),
        .init(id: "lt-small-o", input: [.l, .t], kana: "ぉ", romaji: "lo"),
        .init(id: "ut-small-ya", input: [.u, .t], kana: "ゃ", romaji: "lya"),
        .init(id: "it-small-yu", input: [.i, .t], kana: "ゅ", romaji: "lyu"),
        .init(id: "ot-small-yo", input: [.o, .t], kana: "ょ", romaji: "lyo"),
        .init(id: "tcomma-fullwidth-comma", input: [.t, .comma], text: "，"),
        .init(id: "tperiod-fullwidth-period", input: [.t, .period], text: "．"),
        .init(id: "tslash-fullwidth-slash", input: [.t, .slash], text: "／"),
    ]

    /// The four arrows, which Apple Japanese Input's own romaji table already
    /// carries (`RomajiRule_Default.txt`, verified 2026-08-16: they are the
    /// only four rules in it whose output is not kana).
    ///
    /// They sit apart from `symbolRules` because romaji makes them ordinary:
    /// they join the pre-edit, convert with Space, come back from the `英数`
    /// connect-back, and work in the middle of a sentence. None of that is true
    /// of the symbol layer, so turning that layer off leaves these in place.
    /// They also give the `Y` node a shared romaji prefix of `z`, which is what
    /// prefix mode now streams for it.
    static let arrowRules: [NormalizedRule] = [
        .init(id: "yh-left", input: [.y, .h], kana: "←", romaji: "zh"),
        .init(id: "yj-down", input: [.y, .j], kana: "↓", romaji: "zj"),
        .init(id: "yk-up", input: [.y, .k], kana: "↑", romaji: "zk"),
        .init(id: "yl-right", input: [.y, .l], kana: "→", romaji: "zl"),
    ]

    static let symbolRules: [NormalizedRule] = [
        .init(id: "y1-open-circle", input: [.y, .digit1], text: "○"),
        .init(id: "y-shift1-filled-circle", input: [.y, .shiftedDigit1], text: "●"),
        .init(id: "y2-open-down-triangle", input: [.y, .digit2], text: "▽"),
        .init(id: "y-shift2-filled-down-triangle", input: [.y, .shiftedDigit2], text: "▼"),
        .init(id: "y3-open-up-triangle", input: [.y, .digit3], text: "△"),
        .init(id: "y-shift3-filled-up-triangle", input: [.y, .shiftedDigit3], text: "▲"),
        .init(id: "y4-open-square", input: [.y, .digit4], text: "□"),
        .init(id: "y-shift4-filled-square", input: [.y, .shiftedDigit4], text: "■"),
        .init(id: "y5-open-diamond", input: [.y, .digit5], text: "◇"),
        .init(id: "y-shift5-filled-diamond", input: [.y, .shiftedDigit5], text: "◆"),
        .init(id: "y6-open-star", input: [.y, .digit6], text: "☆"),
        .init(id: "y-shift6-filled-star", input: [.y, .shiftedDigit6], text: "★"),
        .init(id: "y7-double-circle", input: [.y, .digit7], text: "◎"),
        .init(id: "y-shift7-pound", input: [.y, .shiftedDigit7], text: "￡"),
        .init(id: "y8-cent", input: [.y, .digit8], text: "￠"),
        .init(id: "y-shift8-bracket-open", input: [.y, .shiftedDigit8], text: "【"),
        .init(id: "y9-male", input: [.y, .digit9], text: "♂"),
        .init(id: "y-shift9-bracket-close", input: [.y, .shiftedDigit9], text: "】"),
        .init(id: "y0-female", input: [.y, .digit0], text: "♀"),
        .init(id: "y-underscore-therefore", input: [.y, .jisUnderscore], text: "∴"),
        .init(id: "y-equals-approximately", input: [.y, .shiftedMinus], text: "≒"),
        .init(id: "y-plus-plus-minus", input: [.y, .shiftedSemicolon], text: "±"),
        .init(id: "y-yen-fullwidth-backslash", input: [.y, .jisYen], text: "＼"),
        .init(id: "y-bar-parallel", input: [.y, .shiftedJisYen], text: "∥"),
        .init(id: "y-backtick-acute", input: [.y, .shiftedAt], text: "´"),
        .init(id: "y-tilde-diaeresis", input: [.y, .shiftedCaret], text: "¨"),
        .init(id: "yq-dakuten", input: [.y, .q], text: "゛"),
        .init(id: "yp-wave-dash", input: [.y, .p], text: "～"),
        .init(id: "y-colon-handakuten", input: [.y, .colon], text: "゜"),
        .init(id: "yn-prime", input: [.y, .n], text: "′"),
        .init(id: "ym-double-prime", input: [.y, .m], text: "″"),
        .init(id: "y-semicolon-fullwidth", input: [.y, .semicolon], text: "；"),
        .init(id: "y-comma-fullwidth", input: [.y, .comma], text: "，"),
        .init(id: "y-less-equal", input: [.y, .shiftedComma], text: "≦"),
        .init(id: "y-period-fullwidth", input: [.y, .period], text: "．"),
        .init(id: "y-greater-equal", input: [.y, .shiftedPeriod], text: "≧"),
        .init(id: "y-slash-fullwidth", input: [.y, .slash], text: "／"),
        .init(id: "ye-iteration", input: [.y, .e], text: "々"),
        .init(id: "yt-shime", input: [.y, .t], text: "〆"),
        .init(id: "ys-katakana-repeat", input: [.y, .s], text: "ヽ"),
        .init(id: "yd-hiragana-repeat", input: [.y, .d], text: "ゝ"),
        .init(id: "yf-ditto", input: [.y, .f], text: "〃"),
        .init(id: "yg-hyphen", input: [.y, .g], text: "‐"),
        .init(id: "yc-ideographic-zero", input: [.y, .c], text: "〇"),
        .init(id: "yx-multiply", input: [.y, .x], text: "×"),
        .init(id: "ya-reference-mark", input: [.y, .a], text: "※"),
        .init(id: "yb-degree", input: [.y, .b], text: "°"),
        .init(id: "yw-literal-w", input: [.y, .w], text: "w"),
        // Google romantable line 197. `■x` appears twice upstream (lines 193 and
        // 228) with `〒` and `×`; azooKey keeps only `×`, so `〒` is taken from
        // the unambiguous `■y` row instead.
        .init(id: "yy-postal-mark", input: [.y, .y], text: "〒"),
        // Google romantable lines 198-201. azooKey has no counterpart, but the
        // JIS bracket keys map one-to-one so the reading is unambiguous. These
        // are the `Y` layer; the bare bracket keys still pass through to Apple
        // Japanese Input untouched (see `passThroughKeys`).
        .init(id: "y-leftbracket-fullwidth", input: [.y, .leftBracket], text: "［"),
        .init(id: "y-rightbracket-fullwidth", input: [.y, .rightBracket], text: "］"),
        .init(id: "y-leftbrace-double-angle", input: [.y, .leftBrace], text: "《"),
        .init(id: "y-rightbrace-double-angle", input: [.y, .rightBrace], text: "》"),
        // Added ahead of upstream wkr-layout v1.1. 【 】 are frequent in Japanese
        // writing but sat on Shift+8 / Shift+9, which costs a layer hold on
        // keyboards without a number row. `I` and `O` were unused in the `Y`
        // layer and roll outward from `Y` (index → middle → ring), matching the
        // open/close order. The Shift+8 / Shift+9 sequences stay valid.
        .init(id: "yi-lenticular-open", input: [.y, .i], text: "【"),
        .init(id: "yo-lenticular-close", input: [.y, .o], text: "】"),
    ]
}
