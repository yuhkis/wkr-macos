import Foundation

/// The key-frequency report, as one HTML file with nothing outside it.
///
/// A single self-contained file is the deliverable because the tally is the most
/// personal thing wkr-macos keeps: the user has to be able to mail it, archive it
/// or delete it without wondering what else travelled with it. Nothing emitted
/// here names an external resource — no font, no script, no stylesheet, no image —
/// so opening the report performs no network request and cannot leak the counts by
/// fetching anything, which is the same rule `AGENTS.md` puts on the running app.
///
/// Swift encodes; the inline JavaScript draws. That split is deliberate rather
/// than lazy. The period selector has to recompute the colour scale, the ranking
/// and the per-finger totals for four windows across three keyboards, and
/// re-deriving them in the page is both far smaller than emitting twelve
/// pre-drawn boards and the only way the file keeps answering questions after the
/// day it was written.
public enum KeyFrequencyReportRenderer {
    /// A complete, standalone HTML document. No network references of any kind.
    public static func html(
        store: KeyFrequencyStore,
        geometries: [KeyboardGeometry],
        generatedAt: Date,
        calendar: Calendar = .current
    ) -> String {
        let payload = Payload(
            generatedAt: isoTimestamp(generatedAt, calendar: calendar),
            windows: Payload.Windows(
                recent7: window(endingOn: generatedAt, days: 7, calendar: calendar),
                recent30: window(endingOn: generatedAt, days: 30, calendar: calendar)
            ),
            fingerOrder: KeyCap.Finger.allCases.map(\.rawValue),
            fingerNames: Dictionary(
                uniqueKeysWithValues: KeyCap.Finger.allCases.map { ($0.rawValue, $0.displayName) }
            ),
            exclusionNames: exclusionReasons,
            store: store,
            geometries: geometries
        )

        // A JSON string may legitimately contain `</`, and the HTML parser ends a
        // script element at the first `</` it sees regardless of what the script
        // means. `\/` is a valid JSON escape for `/`, so rewriting every `</`
        // survives the round trip through `JSON.parse` unchanged while leaving no
        // sequence that could close the tag early.
        let blob = encode(payload, pretty: false)
            .replacingOccurrences(of: "</", with: "<\\/")

        return document(
            timestamp: displayTimestamp(generatedAt, calendar: calendar),
            isoTimestamp: payload.generatedAt,
            payload: blob
        )
    }

    /// The same data as JSON, for anyone who would rather plot it themselves.
    public static func json(store: KeyFrequencyStore) -> String {
        encode(store, pretty: true)
    }
}

// MARK: - Payload

extension KeyFrequencyReportRenderer {
    /// Everything the page needs, in one object.
    ///
    /// The Japanese names for fingers and exclusion reasons are carried in the
    /// payload rather than written into the JavaScript so that the enums stay the
    /// only place those strings are defined. A finger renamed in
    /// `KeyboardGeometry.swift` reaches the report without anyone touching this
    /// file.
    private struct Payload: Encodable {
        struct Windows: Encodable {
            let recent7: [String]
            let recent30: [String]
        }

        let generatedAt: String
        let windows: Windows
        let fingerOrder: [String]
        let fingerNames: [String: String]
        let exclusionNames: [String: String]
        let store: KeyFrequencyStore
        let geometries: [KeyboardGeometry]
    }

    /// Why each excluded cap carries no number, in the words the tooltip shows.
    ///
    /// The switch below is exhaustive on purpose: a new exclusion reason stops
    /// this file compiling until someone has written the sentence that explains it
    /// to the reader, which is the only mechanism that keeps the picture honest as
    /// the geometries grow. The array is the one part that has to be maintained by
    /// hand, because `KeyCapExclusion` is not `CaseIterable` and the synthesis can
    /// only happen in its own file; a case missing from it falls back to the raw
    /// value in the tooltip rather than disappearing.
    private static let exclusionReasons: [String: String] = {
        let all: [KeyCapExclusion] = [
            .modifier, .layerHold, .encoder, .media, .mouse, .shortcut, .unmappedOnMacOS,
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.rawValue, reason(for: $0)) })
    }()

    private static func reason(for exclusion: KeyCapExclusion) -> String {
        switch exclusion {
        case .modifier:
            return "修飾キー。押下は flags-changed イベントとして届くため、頻度記録を有効にしている間だけ数えられる。"
        case .layerHold:
            return "レイヤーキーの長押し。キーボードのファームウェア内で完結し、macOS には届かない。数えているのはタップ側の動作だけ。"
        case .encoder:
            return "ロータリーエンコーダ。押下も回転も system-defined イベントとして届くため、キーイベントの tap からは見えない。"
        case .media:
            return "メディア／システムキー。エンコーダと同じ理由で、キーイベントとしては届かない。"
        case .mouse:
            return "キーボードが送るマウスボタン。マウスイベントとして届くため数えていない。"
        case .shortcut:
            return "Command / Control / Option を伴う操作だけを持つキー。これらのイベントは意図的に数えていない。"
        case .unmappedOnMacOS:
            return "macOS に対応する仮想キーコードが無いか、キーマップからは送出内容を決められないキー。キーイベントの中に、このキーを名指しするものが無い。"
        }
    }
}

// MARK: - Encoding and formatting

extension KeyFrequencyReportRenderer {
    private static func encode<Value: Encodable>(_ value: Value, pretty: Bool) -> String {
        let encoder = JSONEncoder()
        // Sorted keys so that two runs over the same tally produce byte-identical
        // reports, which is what makes a saved report diffable against a later
        // one. Slashes stay unescaped because the `</` rewrite above is the only
        // escaping this document actually needs, and `\/` everywhere would make
        // the standalone JSON unpleasant to read.
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        guard
            let data = try? encoder.encode(value),
            let text = String(data: data, encoding: .utf8)
        else {
            // The payload is integers and short strings, so there is no value
            // `JSONEncoder` can refuse; an empty object keeps the page parseable
            // and visibly empty rather than trapping while writing a report.
            return "{}"
        }
        return text
    }

    /// The `days` calendar days ending on `end`, oldest first.
    ///
    /// `KeyFrequencyTally.days(endingOn:count:)` answers the same question but
    /// against `Calendar.current`, and a report rendered for a different time zone
    /// than the tally was filed in would then disagree with its own day strings.
    /// The window is anchored on the generation moment rather than the newest
    /// recorded day, because 直近7日 means the last seven days of the user's life,
    /// not the last seven days they happened to type.
    private static func window(endingOn end: Date, days: Int, calendar: Calendar) -> [String] {
        (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end)
                .map { KeyFrequencyDay(date: $0, calendar: calendar).rawValue }
        }
    }

    /// A fixed pattern rather than a localised date style: the timestamp is read
    /// on the same page as the day strings from the tally, which are always
    /// `YYYY-MM-DD`, and a locale that reorders the fields would make the two look
    /// like different calendars.
    private static func displayTimestamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func isoTimestamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Document

extension KeyFrequencyReportRenderer {
    private static func document(
        timestamp: String,
        isoTimestamp: String,
        payload: String
    ) -> String {
        #"""
        <!doctype html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>わから配列 打鍵頻度</title>
        <style>
        \#(styleSheet)
        </style>
        </head>
        <body>
        <main>
        <header class="head">
          <h1>わから配列 打鍵頻度</h1>
          <dl class="facts">
            <div><dt>作成</dt><dd><time datetime="\#(escaped(isoTimestamp))">\#(escaped(timestamp))</time></dd></div>
            <div><dt>総打鍵数</dt><dd id="fact-total">—</dd></div>
            <div><dt>記録期間</dt><dd id="fact-range">—</dd></div>
          </dl>
          <p class="empty" id="empty-note" hidden>まだ記録がありません。</p>
          <noscript><p class="empty">この報告書の作図には JavaScript を使っています。</p></noscript>
        </header>

        <section class="controls" aria-label="集計期間">
          <div class="segmented" id="period" role="group" aria-label="集計期間の選択">
            <button type="button" data-period="all">全期間</button>
            <button type="button" data-period="w7">直近7日</button>
            <button type="button" data-period="w30">直近30日</button>
            <button type="button" data-period="day">単日</button>
          </div>
          <label class="daypick" id="daypick-label" hidden>対象日 <select id="daypick"></select></label>
          <p class="period-note" id="period-note"></p>
        </section>

        <div class="tabs" id="tabs" role="tablist" aria-label="キーボード"></div>

        <section class="panel" role="tabpanel" id="panel">
          <div class="board-wrap" id="board-wrap">
            <div class="board-scroll" id="board"></div>
            <div class="tip" id="tip" hidden></div>
          </div>

          <div class="scale">
            <div class="scale-head">
              <span>色の目盛</span>
              <span class="scale-hint">面積ではなく順位が読めるよう、最大値に対する平方根で色を割り当てている</span>
            </div>
            <div id="scale"></div>
            <div class="scale-ticks" id="scale-ticks"></div>
            <div class="scale-keys">
              <span class="key-swatch zero"></span>期間内に打鍵なし
              <span class="key-swatch excl"></span>数えられない
              <span class="key-swatch noted"></span>注記あり（数値は有効）
              <span class="key-swatch shared"></span>数値を共有
            </div>
          </div>

          <div class="caveats" id="caveats" hidden></div>

          <div class="tables">
            <section>
              <h2>上位25キー</h2>
              <div class="table-scroll">
                <table id="ranking">
                  <thead><tr><th>順位</th><th>キー</th><th class="num">打鍵数</th><th class="num">割合</th><th class="bar-head"><span class="sr">相対量</span></th></tr></thead>
                  <tbody></tbody>
                </table>
              </div>
            </section>
            <section>
              <h2>指別の合計</h2>
              <div class="table-scroll">
                <table id="fingers">
                  <thead><tr><th>指</th><th class="num">打鍵数</th><th class="num">割合</th></tr></thead>
                  <tbody></tbody>
                </table>
              </div>
              <p class="table-note" id="finger-note"></p>
            </section>
          </div>
        </section>
        </main>

        <script type="application/json" id="report-data">\#(payload)</script>
        <script>
        \#(script)
        </script>
        </body>
        </html>
        """#
    }
}

// MARK: - Stylesheet

extension KeyFrequencyReportRenderer {
    private static let styleSheet = #"""
/* The complete light palette lives on bare :root so that a viewer whose system
   is set to "no preference" still gets every colour. The dark block below
   redefines only the tokens that actually change, and nothing anywhere gets its
   sole definition inside a media query. */
:root {
  color-scheme: light dark;

  --bg: #f7f5f1;
  --surface: #fffdfa;
  --fg: #1d1b18;
  --fg-muted: #6b6459;
  --fg-faint: #948c80;
  --rule: #e0dad0;
  --rule-strong: #c8bfb1;
  --accent: #a8412a;
  --accent-soft: #e8ded2;

  --cap-stroke: #cdc5b7;
  --cap-excluded: #fbf9f6;

  /* The heat ramp, as space-separated sRGB triples. They are tokens rather than
     literals in the script because the drawing has to follow the viewer's theme,
     and reading them back out of the stylesheet is the only way one ramp
     definition serves both. Stop 0 doubles as the "pressed nothing" fill, so a
     cold cap is by construction the coldest colour on the scale. */
  --ramp-0: 238 233 225;
  --ramp-1: 250 224 178;
  --ramp-2: 243 184 105;
  --ramp-3: 223 121 62;
  --ramp-4: 155 45 33;

  /* Cap text is chosen against the cap's own fill, not the page, so these two do
     not change with the theme. */
  --ink-dark: 33 27 21;
  --ink-light: 251 247 241;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16171a;
    --surface: #1d1f23;
    --fg: #e9e5de;
    --fg-muted: #9b948a;
    --fg-faint: #746d64;
    --rule: #303338;
    --rule-strong: #464a50;
    --accent: #e08a5c;
    --accent-soft: #35302b;

    --cap-stroke: #3a3e44;
    --cap-excluded: #1a1c1f;

    --ramp-0: 40 42 46;
    --ramp-1: 74 51 40;
    --ramp-2: 130 76 41;
    --ramp-3: 196 112 49;
    --ramp-4: 246 179 97;
  }
}

*, *::before, *::after { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", "Hiragino Sans",
    "Hiragino Kaku Gothic ProN", "Yu Gothic Medium", Meiryo, sans-serif;
  font-size: 14px;
  line-height: 1.65;
}

main { max-width: 1180px; margin: 0 auto; padding: 34px 20px 96px; }

h1 { margin: 0 0 14px; font-size: 21px; font-weight: 600; letter-spacing: .04em; }
h2 { margin: 0 0 8px; font-size: 13px; font-weight: 600; letter-spacing: .06em; color: var(--fg-muted); }

.sr {
  position: absolute; width: 1px; height: 1px;
  overflow: hidden; clip-path: inset(50%); white-space: nowrap;
}

.head { border-bottom: 1px solid var(--rule); padding-bottom: 18px; }

.facts { display: flex; flex-wrap: wrap; gap: 4px 32px; margin: 0; }
.facts div { display: flex; align-items: baseline; gap: 10px; }
.facts dt { font-size: 12px; color: var(--fg-muted); letter-spacing: .06em; }
.facts dd { margin: 0; font-variant-numeric: tabular-nums; }

.empty { margin: 14px 0 0; color: var(--accent); font-size: 13px; }

.controls {
  display: flex; flex-wrap: wrap; align-items: center; gap: 12px 18px;
  padding: 16px 0 14px; border-bottom: 1px solid var(--rule);
}

.segmented { display: inline-flex; border: 1px solid var(--rule-strong); border-radius: 6px; overflow: hidden; }
.segmented button {
  appearance: none; border: 0; border-left: 1px solid var(--rule-strong);
  background: var(--surface); color: var(--fg-muted);
  font: inherit; font-size: 13px; padding: 5px 14px; cursor: pointer;
}
.segmented button:first-child { border-left: 0; }
.segmented button:hover:not(:disabled) { color: var(--fg); }
.segmented button.on { background: var(--accent-soft); color: var(--fg); font-weight: 600; }
.segmented button:disabled { cursor: default; color: var(--fg-faint); }

.daypick { font-size: 13px; color: var(--fg-muted); }
.daypick select {
  font: inherit; font-size: 13px; color: var(--fg); background: var(--surface);
  border: 1px solid var(--rule-strong); border-radius: 5px; padding: 4px 6px;
}

.period-note { flex-basis: 100%; margin: 0; font-size: 12px; color: var(--fg-muted); font-variant-numeric: tabular-nums; }

.tabs { display: flex; flex-wrap: wrap; gap: 2px; margin: 20px 0 0; border-bottom: 1px solid var(--rule); }
.tab {
  appearance: none; border: 1px solid transparent; border-bottom: 0; background: none;
  font: inherit; font-size: 13px; color: var(--fg-muted);
  padding: 7px 15px; margin-bottom: -1px; cursor: pointer; border-radius: 5px 5px 0 0;
}
.tab:hover { color: var(--fg); }
.tab.on {
  background: var(--surface); border-color: var(--rule);
  border-bottom: 1px solid var(--surface); color: var(--fg); font-weight: 600;
}

.panel { background: var(--surface); border: 1px solid var(--rule); border-top: 0; padding: 22px 20px 26px; }

.board-wrap { position: relative; }
/* The board is the one thing that can exceed the viewport, so it carries its own
   scroller: the page body must never scroll sideways. */
.board-scroll { overflow-x: auto; overflow-y: hidden; padding-bottom: 6px; }

.cap rect { stroke: var(--cap-stroke); stroke-width: 1; }
.cap text { text-anchor: middle; dominant-baseline: central; pointer-events: none; }
.cap .pri { font-weight: 600; }
.cap .cnt { font-variant-numeric: tabular-nums; font-weight: 600; }
.cap .shr, .cap .sec { font-variant-numeric: tabular-nums; }
.cap:hover rect { stroke: var(--fg); stroke-width: 1.6; }

.cap.uncountable rect { fill: var(--cap-excluded); stroke-dasharray: 4 3; stroke: var(--rule-strong); }
.cap.uncountable text { fill: var(--fg-faint); }
/* A noted cap keeps its heat fill. Setting `fill` here would win over the
   presentation attribute the script writes and flatten it back to neutral. */
.cap.noted rect { stroke-dasharray: 4 3; stroke: var(--rule-strong); }
.mark-excl { fill: none; stroke: var(--fg-faint); stroke-width: 1.2; }
.mark-shared { fill: var(--accent); opacity: .85; }

.tip {
  position: absolute; z-index: 5; pointer-events: none;
  min-width: 170px; max-width: 320px;
  background: var(--surface); color: var(--fg);
  border: 1px solid var(--rule-strong); border-radius: 6px;
  padding: 8px 10px; font-size: 12px; line-height: 1.5;
}
.tip-row { display: flex; gap: 10px; justify-content: space-between; }
.tip-k { color: var(--fg-muted); white-space: nowrap; }
.tip-v { font-variant-numeric: tabular-nums; text-align: right; }
.tip-note { margin-top: 5px; padding-top: 5px; border-top: 1px solid var(--rule); color: var(--fg-muted); }

.scale { margin: 20px 0 0; max-width: 520px; }
.scale-head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 12px; font-size: 12px; color: var(--fg-muted); letter-spacing: .06em; margin-bottom: 6px; }
.scale-hint { letter-spacing: 0; color: var(--fg-faint); }
.scale-bar { display: block; width: 100%; height: 12px; border: 1px solid var(--rule); border-radius: 3px; }
.scale-ticks { display: flex; justify-content: space-between; font-size: 11px; color: var(--fg-muted); font-variant-numeric: tabular-nums; margin-top: 3px; }
.scale-keys { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 16px; margin-top: 10px; font-size: 11.5px; color: var(--fg-muted); }
.key-swatch { display: inline-block; width: 13px; height: 13px; border-radius: 3px; vertical-align: -2px; margin-right: 5px; }
.key-swatch.zero { background: rgb(var(--ramp-0)); border: 1px solid var(--cap-stroke); }
.key-swatch.excl { background: var(--cap-excluded); border: 1px dashed var(--rule-strong); }
.key-swatch.noted { background: rgb(var(--ramp-0)); border: 1px dashed var(--rule-strong); }
.key-swatch.shared { background: var(--accent); opacity: .85; clip-path: polygon(100% 0, 100% 100%, 0 0); }

/* The caveats are the honest part of the picture, not a warning: a quiet left
   rule and body-sized text, no alarm colour. */
.caveats { margin: 22px 0 0; border-left: 2px solid var(--rule-strong); padding: 2px 0 2px 14px; }
.caveat-head { margin: 0 0 4px; font-size: 12px; letter-spacing: .06em; color: var(--fg-muted); }
.caveats ul { margin: 0; padding-left: 18px; }
.caveats li { font-size: 12.5px; color: var(--fg-muted); }

.tables { display: grid; grid-template-columns: minmax(0, 1.7fr) minmax(0, 1fr); gap: 26px; margin-top: 28px; }
@media (max-width: 880px) { .tables { grid-template-columns: minmax(0, 1fr); } }

.table-scroll { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
th, td { padding: 4px 10px; border-bottom: 1px solid var(--rule); text-align: left; white-space: nowrap; }
th { font-size: 11.5px; font-weight: 600; color: var(--fg-muted); letter-spacing: .04em; }
td { font-size: 13px; }
td.num, th.num { text-align: right; }
td.rank { color: var(--fg-faint); }
td.absent { color: var(--fg-faint); }
.bar-head { width: 34%; }
.bar { height: 6px; min-width: 56px; background: var(--rule); border-radius: 3px; overflow: hidden; }
.bar span { display: block; height: 100%; }
.table-note { margin: 8px 0 0; font-size: 11.5px; color: var(--fg-muted); }
.table-empty { color: var(--fg-faint); }
"""#
}

// MARK: - Script

extension KeyFrequencyReportRenderer {
    private static let script = #"""
(function () {
  'use strict';

  var NS = 'http://www.w3.org/2000/svg';
  var DATA = JSON.parse(document.getElementById('report-data').textContent);

  // One key unit in pixels. The board is drawn in this space and then scaled by
  // the viewBox, so the number only fixes how much room the four rows of cap text
  // get relative to each other; 60 is the smallest value at which a five-digit
  // count still fits inside a 1u cap.
  var UNIT = 60;
  // Shaved off every side so that neighbouring caps read as separate keys without
  // the geometry having to carry gaps in its coordinates.
  var INSET = 3;

  var PERIOD_LABELS = { all: '全期間', w7: '直近7日', w30: '直近30日', day: '単日' };

  // ---- storage -------------------------------------------------------------
  // Every access is guarded: a thumbnail or preview context can throw on the mere
  // act of touching localStorage, and losing the remembered tab must never cost
  // the reader the report.
  function remember(key, value) {
    try { window.localStorage.setItem('wkr.report.' + key, value); } catch (e) { /* ignored */ }
  }
  function recall(key) {
    try { return window.localStorage.getItem('wkr.report.' + key); } catch (e) { return null; }
  }

  // ---- data ----------------------------------------------------------------
  var days = (DATA.store && DATA.store.days ? DATA.store.days.slice() : []).sort(function (a, b) {
    return a.date < b.date ? -1 : (a.date > b.date ? 1 : 0);
  });
  var dayNames = days.map(function (d) { return d.date; });
  var geometries = DATA.geometries || [];

  // Caps grouped by model. The Cornix layer boards are separate tabs of one
  // physical keyboard, so "how many caps send this identity" has to be asked
  // across the whole family: a keycode drawn on layer 0 and layer 2 is one
  // shared total shown twice, not two independent numbers. JIS and US are
  // families of one, so nothing changes for them.
  var familyCaps = {};
  geometries.forEach(function (geo) {
    familyCaps[geo.model] = (familyCaps[geo.model] || []).concat(geo.caps);
  });

  var state = {
    period: 'all',
    day: dayNames.length ? dayNames[dayNames.length - 1] : null,
    tab: 0
  };

  function idKey(identity) { return identity.keyCode + (identity.isShifted ? 's' : 'u'); }

  function hex(code) {
    var text = code.toString(16).toUpperCase();
    return '0x' + (text.length < 2 ? '0' + text : text);
  }

  // Names for key codes a board may record without drawing. A split keyboard
  // routes modifiers through tap-holds and wraps, so the plain modifier codes
  // (a wrap's right Shift above all) can be counted while no cap claims them,
  // and a ranking row reading 0x3C tells the reader nothing. Only well-known
  // fixed codes belong here; anything else stays honest hex.
  var FALLBACK_NAMES = {
    0x38: 'LShift', 0x3C: 'RShift', 0x3B: 'LCtrl', 0x3E: 'RCtrl',
    0x3A: 'LOpt', 0x3D: 'ROpt', 0x37: 'LCmd', 0x36: 'RCmd',
    0x39: 'CapsLock', 0x3F: 'Fn', 0x35: 'Esc', 0x66: '英数', 0x68: 'かな'
  };

  function num(value) { return value.toLocaleString('ja-JP'); }

  function share(count, total) {
    if (!total) { return '—'; }
    var pct = count / total * 100;
    return (pct >= 1 ? pct.toFixed(1) : pct.toFixed(2)) + '%';
  }

  function selectedDays() {
    if (state.period === 'all') { return days; }
    if (state.period === 'day') {
      return days.filter(function (d) { return d.date === state.day; });
    }
    var windows = DATA.windows || { recent7: [], recent30: [] };
    var window_ = state.period === 'w7' ? windows.recent7 : windows.recent30;
    return days.filter(function (d) { return window_.indexOf(d.date) >= 0; });
  }

  function aggregate(chosen) {
    var counts = {};
    var total = 0;
    chosen.forEach(function (day) {
      day.entries.forEach(function (entry) {
        var key = idKey(entry);
        counts[key] = (counts[key] || 0) + entry.count;
        total += entry.count;
      });
    });
    return { counts: counts, total: total };
  }

  // Per-geometry facts that depend on the period: what each cap totals, how many
  // caps claim each identity, and the maximum the colour scale runs to.
  //
  // The test is whether a cap holds an identity, NOT whether it carries an
  // exclusion. Those are different questions: an exclusion is a caveat about how
  // the number was obtained, and several of them sit on keys that very much do
  // have numbers. On a Corne, Space, 英数 and Backspace often live under
  // layer-tap keys, and Shift under a modifier; reading the caveat as "no data"
  // would blank the most-pressed keys on the board.
  function analyse(geo, agg) {
    var claims = {};
    (familyCaps[geo.model] || geo.caps).forEach(function (cap) {
      cap.identities.forEach(function (identity) {
        var key = idKey(identity);
        claims[key] = (claims[key] || 0) + 1;
      });
    });
    var max = 0;
    var counts = geo.caps.map(function (cap) {
      var total = 0;
      cap.identities.forEach(function (identity) { total += agg.counts[idKey(identity)] || 0; });
      if (cap.identities.length && total > max) { max = total; }
      return total;
    });
    return { claims: claims, counts: counts, max: max };
  }

  // ---- colour --------------------------------------------------------------
  function triple(name) {
    var raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    var parts = raw.split(/[\s,]+/).map(Number);
    return parts.length === 3 && parts.every(function (v) { return isFinite(v); }) ? parts : [128, 128, 128];
  }

  function palette() {
    return {
      stops: [0, 1, 2, 3, 4].map(function (i) { return triple('--ramp-' + i); }),
      inkDark: triple('--ink-dark'),
      inkLight: triple('--ink-light')
    };
  }

  function rampColor(stops, t) {
    if (!(t > 0)) { return stops[0]; }
    if (t >= 1) { return stops[stops.length - 1]; }
    var scaled = t * (stops.length - 1);
    var index = Math.floor(scaled);
    var f = scaled - index;
    var a = stops[index];
    var b = stops[index + 1];
    return [0, 1, 2].map(function (k) { return Math.round(a[k] + (b[k] - a[k]) * f); });
  }

  function css(rgb) { return 'rgb(' + rgb[0] + ', ' + rgb[1] + ', ' + rgb[2] + ')'; }

  function luminance(rgb) {
    var linear = rgb.map(function (v) {
      var c = v / 255;
      return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
  }

  // Rank-normalised, not linear. Key frequencies are Zipf-like — the top key on a
  // real tally runs eighty to a hundred times the median — so a linear ramp puts
  // everything except a handful of keys within one shade of the cold end and the
  // board stops carrying information. sqrt was chosen over log because log lifts a
  // key pressed twice most of the way up the scale, which reads as "warm" when the
  // truth is "almost never"; sqrt puts a key at 1% of the maximum at 10% of the
  // ramp, far enough off the floor to be told apart from an unused key while
  // leaving the busiest keys visibly alone at the top.
  function heat(count, max) { return max > 0 && count > 0 ? Math.sqrt(count / max) : 0; }

  // ---- svg helpers ---------------------------------------------------------
  function svgEl(name, attrs) {
    var node = document.createElementNS(NS, name);
    if (attrs) {
      Object.keys(attrs).forEach(function (key) { node.setAttribute(key, attrs[key]); });
    }
    return node;
  }

  function capText(text, size, cls, dy, cx, cy, fill) {
    var node = svgEl('text', { x: cx, y: cy + dy, 'font-size': size, 'class': cls });
    if (fill) { node.setAttribute('fill', fill); }
    node.textContent = text;
    return node;
  }

  // ---- tooltip -------------------------------------------------------------
  var tip = document.getElementById('tip');
  var boardWrap = document.getElementById('board-wrap');

  function hideTip() { tip.hidden = true; }

  function showTip(event, lines) {
    tip.textContent = '';
    lines.forEach(function (line) {
      var row = document.createElement('div');
      if (line.k) {
        row.className = 'tip-row';
        var k = document.createElement('span');
        k.className = 'tip-k';
        k.textContent = line.k;
        var v = document.createElement('span');
        v.className = 'tip-v';
        v.textContent = line.v;
        row.appendChild(k);
        row.appendChild(v);
      } else {
        row.className = 'tip-note';
        row.textContent = line.v;
      }
      tip.appendChild(row);
    });
    tip.hidden = false;
    // Positioned against the wrapper rather than the scroller so the tooltip is
    // never clipped by the board's own overflow and needs no scroll arithmetic.
    var rect = boardWrap.getBoundingClientRect();
    var left = event.clientX - rect.left + 14;
    var top = event.clientY - rect.top + 14;
    tip.style.left = Math.max(0, Math.min(left, boardWrap.clientWidth - tip.offsetWidth - 2)) + 'px';
    tip.style.top = top + 'px';
  }

  function tipLines(cap, count, shared, agg) {
    var lines = [];
    lines.push({
      k: '刻印',
      v: cap.legend.primary + (cap.legend.secondary ? ' / ' + cap.legend.secondary : '')
    });
    cap.identities.forEach(function (identity) {
      lines.push({
        k: 'キーコード',
        v: hex(identity.keyCode) + (identity.isShifted ? '（Shiftあり）' : '（Shiftなし）')
      });
    });
    if (cap.identities.length) {
      lines.push({ k: '打鍵数', v: num(count) });
      lines.push({ k: '割合', v: share(count, agg.total) });
      if (shared > 1) {
        lines.push({ v: 'この数値は同じキーコードを送る ' + shared + ' 箇所の合計（別のレイヤーのキーを含むことがある）で、どのキーで打ったかは区別できない。' });
      }
    } else {
      lines.push({ v: 'このキーの打鍵は数えられない。' });
    }
    if (cap.exclusion) {
      lines.push({ v: '注記：' + (DATA.exclusionNames[cap.exclusion] || cap.exclusion) });
    }
    return lines;
  }

  // ---- board ---------------------------------------------------------------
  var boardHost = document.getElementById('board');

  function drawBoard(geo, board, agg) {
    var pal = palette();
    var width = geo.widthUnits * UNIT;
    var height = geo.heightUnits * UNIT;
    var svg = svgEl('svg', {
      viewBox: '0 0 ' + width + ' ' + height,
      role: 'img',
      'aria-label': geo.displayName + ' の打鍵頻度'
    });
    svg.style.display = 'block';
    svg.style.width = '100%';
    svg.style.height = 'auto';
    svg.style.maxWidth = width + 'px';
    // Below this the legends stop being readable, so the board scrolls instead of
    // shrinking further.
    svg.style.minWidth = Math.min(width, 720) + 'px';

    geo.caps.forEach(function (cap, index) {
      var count = board.counts[index];
      var claimed = cap.identities.reduce(function (most, identity) {
        return Math.max(most, board.claims[idKey(identity)] || 0);
      }, 0);
      var x = cap.x * UNIT + INSET;
      var y = cap.y * UNIT + INSET;
      var w = cap.width * UNIT - INSET * 2;
      var h = cap.height * UNIT - INSET * 2;
      var cx = cap.x * UNIT + cap.width * UNIT / 2;
      var cy = cap.y * UNIT + cap.height * UNIT / 2;

      // Two states, not one. `uncountable` is a cap no key event can name, and it
      // is drawn neutral because there is genuinely no number. `noted` is a cap
      // that does have a number and also has something the reader should know
      // about how it was obtained; it keeps its heat colour and gains the dashed
      // outline and the ring.
      var countable = cap.identities.length > 0;
      var state = countable ? (cap.exclusion ? ' noted' : '') : ' uncountable';
      var group = svgEl('g', { 'class': 'cap' + state });
      if (cap.rotation) {
        group.setAttribute('transform', 'rotate(' + cap.rotation + ' ' + cx + ' ' + cy + ')');
      }

      var rect = svgEl('rect', { x: x, y: y, width: w, height: h, rx: 6 });
      var ink = null;
      if (countable) {
        var fill = rampColor(pal.stops, heat(count, board.max));
        rect.setAttribute('fill', css(fill));
        ink = css(luminance(fill) > 0.5 ? pal.inkDark : pal.inkLight);
      }
      group.appendChild(rect);

      var primary = cap.legend.primary;
      var secondary = cap.legend.secondary;
      var primarySize = primary.length <= 1 ? 17 : (primary.length <= 3 ? 12.5 : 10);
      var showCount = countable && count > 0;

      if (showCount) {
        if (secondary) { group.appendChild(capText(secondary, 10, 'sec', -18, cx, cy, ink)); }
        group.appendChild(capText(primary, primarySize, 'pri', secondary ? -4 : -9, cx, cy, ink));
        group.appendChild(capText(num(count), 11.5, 'cnt', secondary ? 11 : 8, cx, cy, ink));
        group.appendChild(capText(share(count, agg.total), 8.5, 'shr', secondary ? 22 : 20, cx, cy, ink));
      } else {
        if (secondary) { group.appendChild(capText(secondary, 10, 'sec', -11, cx, cy, ink)); }
        group.appendChild(capText(primary, primarySize, 'pri', secondary ? 8 : 0, cx, cy, ink));
      }

      // A hollow ring for "cannot be seen from here" and a filled corner wedge for
      // "this number belongs to more than one cap". Two different shapes rather
      // than two colours, because the cap underneath them is already carrying the
      // colour channel.
      if (cap.exclusion) {
        group.appendChild(svgEl('circle', { cx: x + w - 9, cy: y + h - 9, r: 3.4, 'class': 'mark-excl' }));
      }
      if (claimed > 1) {
        group.appendChild(svgEl('path', {
          d: 'M' + (x + w - 13) + ' ' + (y + 1) + 'H' + (x + w - 1) + 'V' + (y + 13) + 'Z',
          'class': 'mark-shared'
        }));
      }

      group.addEventListener('mousemove', function (event) {
        showTip(event, tipLines(cap, count, claimed, agg));
      });
      group.addEventListener('mouseleave', hideTip);

      svg.appendChild(group);
    });

    boardHost.textContent = '';
    boardHost.appendChild(svg);
  }

  // ---- colour scale --------------------------------------------------------
  function drawScale(max) {
    var pal = palette();
    var host = document.getElementById('scale');
    host.textContent = '';
    var steps = 60;
    var svg = svgEl('svg', { viewBox: '0 0 ' + steps + ' 8', preserveAspectRatio: 'none' });
    svg.setAttribute('class', 'scale-bar');
    for (var i = 0; i < steps; i++) {
      svg.appendChild(svgEl('rect', {
        x: i, y: 0, width: 1.02, height: 8,
        fill: css(rampColor(pal.stops, i / (steps - 1)))
      }));
    }
    host.appendChild(svg);

    var ticks = document.getElementById('scale-ticks');
    ticks.textContent = '';
    if (!max) {
      // Five zeroes under a full ramp would read as a scale that runs from
      // nothing to nothing. With no maximum there is no scale to label.
      var none = document.createElement('span');
      none.textContent = 'この期間は目盛が付かない（打鍵なし）';
      ticks.appendChild(none);
      return;
    }
    [0, 0.25, 0.5, 0.75, 1].forEach(function (t) {
      var span = document.createElement('span');
      // The ramp is driven by sqrt(count / max), so the count a tick stands for is
      // max * t². The labels have to undo the normalisation or the strip would be
      // claiming a linear scale it does not have.
      span.textContent = num(Math.round(max * t * t));
      ticks.appendChild(span);
    });
  }

  // ---- ranking -------------------------------------------------------------
  // The legend to print for one identity, read off the current board. `secondary`
  // is only trusted as the shifted legend when the same cap also claims the
  // unshifted identity: on a staggered board that pairing is what "shifted legend"
  // means, while on a split board a lone secondary is a hold action and would be
  // the wrong answer entirely.
  function labelIn(caps, key) {
    for (var c = 0; c < caps.length; c++) {
      var cap = caps[c];
      for (var i = 0; i < cap.identities.length; i++) {
        var identity = cap.identities[i];
        if (idKey(identity) !== key) { continue; }
        if (!identity.isShifted) { return cap.legend.primary; }
        var pairs = cap.identities.some(function (other) {
          return other.keyCode === identity.keyCode && other.isShifted !== identity.isShifted;
        });
        // The legend says whether its second line is the shifted printing or a
        // hold action; guessing from the pairing alone once named Shift+Enter
        // "LAlt_T".
        return pairs && cap.legend.secondary && cap.legend.secondaryIsShifted
          ? cap.legend.secondary
          : cap.legend.primary + ' + Shift';
      }
    }
    return null;
  }

  function labelFor(geo, key) {
    return labelIn(geo.caps, key);
  }

  // A readable name for an identity this board does not draw: first the same
  // keyboard's other layers, then the other boards. Only the raw code is
  // hopeless enough for the hex fallback.
  function borrowedLabel(geo, key) {
    var family = familyCaps[geo.model] || [];
    var label = labelIn(family, key);
    if (label !== null) { return label; }
    for (var g = 0; g < geometries.length; g++) {
      if (geometries[g].model === geo.model) { continue; }
      label = labelIn(geometries[g].caps, key);
      if (label !== null) { return label; }
    }
    return null;
  }

  function drawRanking(geo, agg) {
    var body = document.querySelector('#ranking tbody');
    body.textContent = '';
    var rows = Object.keys(agg.counts).map(function (key) {
      return { key: key, count: agg.counts[key] };
    }).sort(function (a, b) {
      return b.count - a.count || (a.key < b.key ? -1 : 1);
    }).slice(0, 25);

    if (!rows.length) {
      var empty = document.createElement('tr');
      var span = document.createElement('td');
      span.colSpan = 5;
      span.className = 'table-empty';
      span.textContent = 'この期間の記録はありません。';
      empty.appendChild(span);
      body.appendChild(empty);
      return;
    }

    var pal = palette();
    var top = rows[0].count;
    rows.forEach(function (row, index) {
      var tr = document.createElement('tr');
      var label = labelFor(geo, row.key);
      var shifted = row.key.charAt(row.key.length - 1) === 's';
      var code = parseInt(row.key.slice(0, -1), 10);

      tr.appendChild(cell(String(index + 1), 'rank'));
      var borrowed = label === null ? borrowedLabel(geo, row.key) : null;
      tr.appendChild(cell(
        label !== null
          ? label
          : (borrowed !== null
              ? borrowed
              : (FALLBACK_NAMES[code] || hex(code)) + (shifted ? ' + Shift' : ''))
            + '（この図に無いキー）',
        label !== null ? '' : 'absent'
      ));
      tr.appendChild(cell(num(row.count), 'num'));
      tr.appendChild(cell(share(row.count, agg.total), 'num'));

      var barCell = document.createElement('td');
      var bar = document.createElement('div');
      bar.className = 'bar';
      var fillBar = document.createElement('span');
      fillBar.style.width = (row.count / top * 100) + '%';
      fillBar.style.background = css(rampColor(pal.stops, heat(row.count, top)));
      bar.appendChild(fillBar);
      barCell.appendChild(bar);
      tr.appendChild(barCell);

      body.appendChild(tr);
    });
  }

  function cell(text, cls) {
    var td = document.createElement('td');
    if (cls) { td.className = cls; }
    td.textContent = text;
    return td;
  }

  // ---- fingers -------------------------------------------------------------
  function drawFingers(geo, agg) {
    // An identity is attributed to a finger only when every cap that sends it
    // belongs to the same finger. macOS delivers one keycode from all of them
    // and cannot say which was struck, so the moment two fingers can produce a
    // code, no finger has earned it.
    //
    // Picking the first claimant instead is worse than it sounds. On a Corne
    // that assigns Enter to several keys across both halves, first-wins gave
    // the whole total to one hand and printed 右親指 0 for a thumb that is
    // struck constantly. A visibly absurd zero is the good case — the same rule
    // shifts smaller amounts invisibly. Contested codes go to the unattributed
    // row, where the reader can see how much is unaccounted for.
    var owner = {};
    var contested = {};
    (familyCaps[geo.model] || geo.caps).forEach(function (cap) {
      cap.identities.forEach(function (identity) {
        var key = idKey(identity);
        // A cap with no finger still contests the code: a key struck by a hand
        // this table does not model is exactly as unattributable.
        var claim = cap.finger || null;
        if (!(key in owner)) { owner[key] = claim; }
        else if (owner[key] !== claim) { contested[key] = true; }
      });
    });
    var ambiguous = Object.keys(contested).length > 0;

    var totals = {};
    var attributed = 0;
    Object.keys(agg.counts).forEach(function (key) {
      if (contested[key]) { return; }
      var finger = owner[key];
      if (!finger) { return; }
      totals[finger] = (totals[finger] || 0) + agg.counts[key];
      attributed += agg.counts[key];
    });

    var body = document.querySelector('#fingers tbody');
    body.textContent = '';
    DATA.fingerOrder.forEach(function (finger) {
      var count = totals[finger] || 0;
      var tr = document.createElement('tr');
      tr.appendChild(cell(DATA.fingerNames[finger] || finger, ''));
      tr.appendChild(cell(num(count), 'num'));
      tr.appendChild(cell(share(count, agg.total), 'num'));
      body.appendChild(tr);
    });

    var rest = agg.total - attributed;
    if (rest > 0) {
      var tr = document.createElement('tr');
      tr.appendChild(cell('指の割り当てなし・この鍵盤に無いキー', 'absent'));
      tr.appendChild(cell(num(rest), 'num absent'));
      tr.appendChild(cell(share(rest, agg.total), 'num absent'));
      body.appendChild(tr);
    }

    document.getElementById('finger-note').textContent = ambiguous
      ? '同じキーコードを複数の指が送るキーがある。macOS はどちらで打ったか報告しないため、どの指にも割り当てず下段へまとめている。片方の指へ寄せると、その手の負担を実際より重く見せてしまう。'
      : '';
  }

  // ---- caveats -------------------------------------------------------------
  function drawCaveats(geo) {
    var host = document.getElementById('caveats');
    host.textContent = '';
    if (!geo.caveats || !geo.caveats.length) {
      host.hidden = true;
      return;
    }
    host.hidden = false;
    var head = document.createElement('p');
    head.className = 'caveat-head';
    head.textContent = 'この図が知り得ないこと';
    host.appendChild(head);
    var list = document.createElement('ul');
    geo.caveats.forEach(function (caveat) {
      var item = document.createElement('li');
      item.textContent = caveat;
      list.appendChild(item);
    });
    host.appendChild(list);
  }

  // ---- chrome --------------------------------------------------------------
  var periodBox = document.getElementById('period');
  var periodButtons = Array.prototype.slice.call(periodBox.querySelectorAll('button'));
  var daySelect = document.getElementById('daypick');
  var dayLabel = document.getElementById('daypick-label');
  var tabBox = document.getElementById('tabs');

  function restore() {
    var period = recall('period');
    if (period === 'all' || period === 'w7' || period === 'w30' || (period === 'day' && dayNames.length)) {
      state.period = period;
    }
    var day = recall('day');
    if (day && dayNames.indexOf(day) >= 0) { state.day = day; }
    var tab = parseInt(recall('tab'), 10);
    if (tab >= 0 && tab < geometries.length) { state.tab = tab; }
  }

  function buildChrome() {
    periodButtons.forEach(function (button) {
      if (button.dataset.period === 'day' && !dayNames.length) { button.disabled = true; }
      button.addEventListener('click', function () {
        state.period = button.dataset.period;
        remember('period', state.period);
        render();
      });
    });

    dayNames.forEach(function (name) {
      var option = document.createElement('option');
      option.value = name;
      option.textContent = name;
      daySelect.appendChild(option);
    });
    if (state.day) { daySelect.value = state.day; }
    daySelect.addEventListener('change', function () {
      state.day = daySelect.value;
      remember('day', state.day);
      render();
    });

    geometries.forEach(function (geo, index) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'tab';
      button.setAttribute('role', 'tab');
      button.textContent = geo.displayName;
      button.addEventListener('click', function () {
        state.tab = index;
        remember('tab', String(index));
        render();
      });
      tabBox.appendChild(button);
    });
  }

  function drawHeader() {
    var grand = 0;
    days.forEach(function (day) {
      day.entries.forEach(function (entry) { grand += entry.count; });
    });
    document.getElementById('fact-total').textContent = num(grand) + ' 打鍵';
    document.getElementById('fact-range').textContent = dayNames.length
      ? (dayNames[0] === dayNames[dayNames.length - 1]
          ? dayNames[0]
          : dayNames[0] + ' 〜 ' + dayNames[dayNames.length - 1]) + '（' + dayNames.length + '日）'
      : '—';
    document.getElementById('empty-note').hidden = dayNames.length > 0;
  }

  function render() {
    hideTip();
    var geo = geometries[state.tab];

    periodButtons.forEach(function (button) {
      var on = button.dataset.period === state.period;
      button.classList.toggle('on', on);
      button.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    Array.prototype.forEach.call(tabBox.children, function (button, index) {
      var on = index === state.tab;
      button.classList.toggle('on', on);
      button.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    dayLabel.hidden = state.period !== 'day';

    var chosen = selectedDays();
    var agg = aggregate(chosen);

    var label = PERIOD_LABELS[state.period];
    document.getElementById('period-note').textContent = chosen.length
      ? label + '：' + chosen[0].date
        + (chosen[0].date === chosen[chosen.length - 1].date ? '' : ' 〜 ' + chosen[chosen.length - 1].date)
        + ' の ' + chosen.length + '日、' + num(agg.total) + ' 打鍵'
      : label + '：この期間の記録はありません。';

    if (!geo) { return; }
    var board = analyse(geo, agg);
    drawBoard(geo, board, agg);
    drawScale(board.max);
    drawRanking(geo, agg);
    drawFingers(geo, agg);
    drawCaveats(geo);
  }

  restore();
  buildChrome();
  drawHeader();
  render();

  // The ramp is read out of the stylesheet, so a theme flip has to redraw or every
  // cap keeps the colours of the theme it was drawn under.
  if (window.matchMedia) {
    var dark = window.matchMedia('(prefers-color-scheme: dark)');
    if (dark.addEventListener) { dark.addEventListener('change', render); }
    else if (dark.addListener) { dark.addListener(render); }
  }
}());
"""#
}
