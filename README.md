# WKR macOS

**わから配列を、macOS標準のApple日本語入力（Kotoeri）の前段で解釈する常駐アプリです。**

> **English summary.** `wkr-macos` lets you type Japanese with the
> [Wakara layout](https://github.com/yuhkis/wkr-layout) (wkr) on macOS, without giving up
> Apple's built-in Japanese input. Apple Japanese Input has no custom romaji table, so this app
> sits in front of it: a `CGEventTap` intercepts the physical keys, a pure finite-state transducer
> resolves them into kana, and the app replays the equivalent **standard romaji** as synthetic key
> events. Kotoeri therefore sees ordinary romaji typing and keeps its pre-edit buffer, Space
> conversion, and learning intact. Type an English word in Japanese mode by mistake and Kotoeri's
> `英数` connect-back hands back the romaji this app synthesised rather than the keys you pressed
> (`thing` returns as `layunnh`), so tapping `英数` twice in quick succession restores your own
> letters. Requires a **JIS keyboard**, Apple Japanese Input in Hiragana mode, Input Monitoring and
> Accessibility permissions. To rewrite that text it holds the current pre-edit's physical keys in
> memory, bounded and discarded on any context change; nothing is written to disk or logged, and
> there is no network code. An opt-in, off-by-default key-frequency tally records per-key totals per
> calendar day — no order, no sub-day timing, no text — and renders them as a heatmap over a JIS, US
> or Corne-style split keyboard. Build from source — see [docs/install.md](./docs/install.md).
> MIT licensed.

`W` `E` `R` と打つと `わから` になります（`W`=わ行、`E`=か行、`R`=ら行）。
Google 日本語入力や azooKey ならローマ字テーブルを差し替えれば済みますが、
Apple日本語入力にはその機能がありません。かといって Apple日本語入力を捨てると、
macOS に統合された変換エンジンと学習も失われます。

そこで wkr-macos は、テーブルを差し替えるのではなく、**物理キーを横取りして標準ローマ字へ翻訳し、
Apple日本語入力へ打ち直します**。Apple日本語入力から見れば普通のローマ字入力なので、
未確定文字列も Space による変換候補もそのまま使えます。

常用方式の prefix-romaji では1キー目から表示を出し、取り消しが必要な枝をテストで固定しています。

| 入力 | 表示 |
| --- | --- |
| `E` | `k` |
| `E` `K` | `き` |
| `W` `E` `R` | `わかr` |
| `W` `E` `R` + Enter | `わから` |

日本語入力モードのまま英単語を打ってしまったときは、**`英数` を素早く2回**叩くと打ったとおりの
英字に戻ります。Apple日本語入力の読み戻しは wkr-macos が送ったローマ字を返すため
（`thing` のつもりが `layunnh`）、そこを置き換えています。詳細は
[docs/how-it-works.md](./docs/how-it-works.md#7-英字への打ち直し) にあります。

## ドキュメント

| | |
| --- | --- |
| [docs/how-it-works.md](./docs/how-it-works.md) | **どういう原理で動くのか。** 変換モデル、3つの出力方式、安全ゲート |
| [docs/install.md](./docs/install.md) | **インストールと使い方。** 必要環境、ビルド、権限、自動起動、アンインストール |
| [docs/layout-reference.md](./docs/layout-reference.md) | 配列リファレンス。1キー目の表示、訓令式綴り、上流との差分 |
| [docs/layout-coverage.md](./docs/layout-coverage.md) | かなの網羅状況。ことえりで打てるかなとの突き合わせ、上流への要検討事項 |
| [docs/design.md](./docs/design.md) | 設計判断の記録。採用／不採用の理由と安全境界 |
| [docs/verification.md](./docs/verification.md) | 公開可能な検証結果と確認範囲 |
| [docs/roadmap.md](./docs/roadmap.md) | 未着手・未完了の項目 |

## 対応範囲と既知の限界

- 上流 `wkr-layout` のかな全行、小書き、特殊かな、`Y`記号レイヤーを **215件の正規化規則**として実装しています。
  **Apple日本語入力のローマ字入力で打てるかな206種はすべて入力できます**（[docs/layout-coverage.md](./docs/layout-coverage.md)）。
- 常用方式は **prefix-romaji**（ログイン時起動もこれ）。CLI の既定値は最も安全な deferred-romaji です。
- **打鍵頻度のヒートマップ**を出せます（既定オフ）。`--key-frequency on` で数え、
  `--key-frequency-report` で JIS・US・Cornix の3配列（Cornix はレイヤーごとのタブ付き）に
  描き分けた HTML を1枚書き出します。tap / hold 兼用キーは上半分の **HOLD** と下半分の
  **TAP** を別々に表示し、同じ論理キーを複数の動作が送る場合は共有合計を `◇` 付きで示します。
- `英数` を素早く2回叩くと**打った物理キーどおりの英字へ打ち直します**。2026-08-15 に TextEdit と
  Claude.app で確認済みで、先行するテキストは削りません。Unicode 直接注入を使うため、そのイベントを
  無視するアプリでは働きません。`--english-fallback off` で無効にできます。
- **JISキーボード専用**で、Apple日本語入力の「ローマ字入力」「ひらがな」以外では完全に素通しします。
- かな全行・訓令式綴り・Unicode経路・取り消し枝の代表列は **TextEdit で実機確認済み**です。
  記号レイヤーも2026-08-13に実機確認済みです（当時59件、矢印4件がローマ字へ移り現在55件）。
- 基本動作は TextEdit・Notes・Safari・Terminal・VS Code・Slack・Discord・Notion・ChatGPT入力欄で確認しています。
  **Unicode直接注入を含むアプリ別の網羅的な互換性確認は未完了です。**
- 署名済みの配布バイナリはありません。**ソースからビルドして使います。**
- メニューバー表示はまだありません（[ロードマップ](./docs/roadmap.md)）。停止は `make stop` です。

限界の全一覧は [docs/how-it-works.md](./docs/how-it-works.md#9-既知の限界) にあります。
変換が急に効かなくなったときの切り分けは
[docs/install.md](./docs/install.md#変換が止まったときのログの見方) にあります。

## アーキテクチャ

```text
JISキーボード
  → CGEventTap（監視・対象キー抑止）
  → WKRCore（Trie/FSTによる状態遷移）
  → 出力アダプタ
      ├─ deferred-romaji（安全・1キー遅延）
      ├─ prefix-romaji（1キー目から表示・取り消し枝を固定）
      └─ optimistic-romaji（即時表示・差し替え実験）
  → 標準ローマ字の合成キーイベント
  → Apple日本語入力
  → 対象アプリの未確定文字列・変換候補
```

かなの主経路は標準ローマ字の再送です。ローマ字で表現できない記号58件だけは、マーカー付き
Unicodeイベントで送ります。**この経路は未確定文字列があるときは届かない**ので、そのときは
送らずログに残します。Unicodeイベントはその場で確定するため、Space変換を残したい
`「` / `」` / `『` / `』` の JIS括弧キーは横取りせず、Apple日本語入力へそのまま通します。

InputMethodKit で自前IMEを作れば未確定文字列を完全に制御できますが、その場合
Apple日本語入力の変換エンジンだけを公開APIで借りることはできません。詳細は
[docs/how-it-works.md](./docs/how-it-works.md) を参照してください。

## プライバシーと権限

このアプリは「入力監視」とイベント送信（アクセシビリティ）の許可を必要とします。だからこそ、
変換しない条件を広く取っています。

- **入力文字列、クリップボード、変換候補を、ログ・ファイル・ネットワークへ一切出しません。**
  ネットワーク機能を持ちません。ログに出るのは権限状態、モード、入力ソースID、状態コード、
  エラー種別、集計件数だけです。
- 打鍵頻度の記録（既定オフ）を明示的に有効にしたときだけ、キーごとの**累計回数**を暦日単位で
  ローカルに保存します。**打鍵の順序も、暦日より細かい時刻も、入力文字列も保存しません。**
  順序を落とした度数分布から入力文字列は復元できません。Secure Event Input・権限欠如・
  除外アプリ・対象外の入力ソースでは1回も数えません。保持期間の上限は既定で設けず、
  必要なら `--key-frequency-retention <日数>` で指定します。
- 対象外の入力ソース、英数、セキュア入力、パスワード欄、修飾キー付きショートカットでは変換しません。
- 仮想マシンやリモートデスクトップは `--exclude-app` で除外できます（キー入力がゲスト側の
  入力メソッドへ転送されるため）。詳細は [docs/install.md](./docs/install.md) を参照してください。
- 権限不足・event tap無効化・合成イベント生成失敗では自動再有効化せず、**fail closed** で
  常駐プロセスごと終了します。壊れた状態で動き続けるより、通常入力に戻れることを優先します。

Appleの案内: [Macで入力監視へのアクセスを制御する](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)

## 実装構成

```text
Package.swift
Sources/
  WKRCore/       # AppKit/Core Graphics非依存の正規化全配列とTrie/FST
  WKRMacOS/      # 権限、TIS、Secure Event Input、CGEventTap、イベント再送
Tests/
  WKRCoreTests/  # テーブル駆動の状態遷移テスト
Resources/
  Info.plist     # 固定Bundle ID io.github.yuhkis.wkr-macos、LSUIElement=true
Scripts/
  build-app.sh   # Releaseビルド、.app生成、ad-hoc署名／明示identityでの署名
```

## 上流との関係

- [`yuhkis/wkr-layout`](https://github.com/yuhkis/wkr-layout) が配列仕様の上流です。
  Google 日本語入力用ローマ字テーブルと azooKey 用カスタム入力テーブル、および配列の説明を持ちます。
- `wkr-macos` は macOS 実装を担当します。Input Monitoring／Accessibility権限、Swiftビルド、署名、
  常駐動作、アプリ別互換性を扱うため、リリース周期と検証対象が上流と異なります。
- **かなは上流と同一です。** Apple日本語入力へ送るローマ字の綴りだけが訓令式へ
  揃えてあります。ver 1.1 で `WJ` のかなを `ヴ` から `ゔ` へ変更し（ひらがなモードで
  カタカナ `ヴ` を出す綴りがことえりに無いため）、`QY → ヵ` を追加し、
  `KT → ぃ` を削除しました。いずれも上流 ver 1.1 に反映済みです。差分の全一覧は
  [docs/layout-reference.md](./docs/layout-reference.md)、根拠は
  [docs/layout-coverage.md](./docs/layout-coverage.md) にあります。

配列表のスナップショットは `wkr-layout` [ver 1.1](https://github.com/yuhkis/wkr-layout/releases/tag/v1.1.0)
revision [`03cba20a62c6`](https://github.com/yuhkis/wkr-layout/commit/03cba20a62c6d27bc90e6bc5572f89a13f14108a)
（2026-08-16 取得）に基づきます。

## 開発

```bash
make test
```

```bash
make app
```

貢献者向けの作業方針は [AGENTS.md](./AGENTS.md) にあります。実測結果は画面表示だけで
「動作確認済み」とせず、個人情報や端末固有情報を除いた確認範囲を
[docs/verification.md](./docs/verification.md) に残す運用です。

## ライセンス

MIT License — 詳細は [LICENSE](./LICENSE) を参照してください。

配列仕様の上流 [yuhkis/wkr-layout](https://github.com/yuhkis/wkr-layout) も MIT License です。
`Sources/WKRCore/WKRLayout.swift` は同リポジトリ revision `03cba20a62c6d27bc90e6bc5572f89a13f14108a`
の内容を正規化したスナップショットを含みます。

- [Scrapbox「わから配列」](https://scrapbox.io/yuhkis/%E3%82%8F%E3%81%8B%E3%82%89%E9%85%8D%E5%88%97)
- [yuhkis/wkr-layout](https://github.com/yuhkis/wkr-layout)
