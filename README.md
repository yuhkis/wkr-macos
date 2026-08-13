# WKR macOS

**わから配列を、macOS標準のApple日本語入力（Kotoeri）の前段で解釈する常駐アプリです。**

> **English summary.** `wkr-macos` lets you type Japanese with the
> [Wakara layout](https://github.com/yuhkis/wkr-layout) (wkr) on macOS, without giving up
> Apple's built-in Japanese input. Apple Japanese Input has no custom romaji table, so this app
> sits in front of it: a `CGEventTap` intercepts the physical keys, a pure finite-state transducer
> resolves them into kana, and the app replays the equivalent **standard romaji** as synthetic key
> events. Kotoeri therefore sees ordinary romaji typing and keeps its pre-edit buffer, Space
> conversion, and learning intact. Requires a **JIS keyboard**, Apple Japanese Input in Hiragana
> mode, Input Monitoring and Accessibility permissions. It stores nothing and has no network code.
> Build from source — see [docs/install.md](./docs/install.md). MIT licensed.

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

## ドキュメント

| | |
| --- | --- |
| [docs/how-it-works.md](./docs/how-it-works.md) | **どういう原理で動くのか。** 変換モデル、3つの出力方式、安全ゲート |
| [docs/install.md](./docs/install.md) | **インストールと使い方。** 必要環境、ビルド、権限、自動起動、アンインストール |
| [docs/layout-reference.md](./docs/layout-reference.md) | 配列リファレンス。1キー目の表示、訓令式綴り、上流との差分 |
| [docs/design.md](./docs/design.md) | 設計判断の記録。採用／不採用の理由と安全境界 |
| [docs/verification.md](./docs/verification.md) | 公開可能な検証結果と確認範囲 |
| [docs/roadmap.md](./docs/roadmap.md) | 未着手・未完了の項目 |

## 対応範囲と既知の限界

- 上流 `wkr-layout` のかな全行、小書き、特殊かな、`Y`記号レイヤーを **222件の正規化規則**として実装しています。
- 常用方式は **prefix-romaji**（ログイン時起動もこれ）。CLI の既定値は最も安全な deferred-romaji です。
- **JISキーボード専用**で、Apple日本語入力の「ローマ字入力」「ひらがな」以外では完全に素通しします。
- かな全行・訓令式綴り・Unicode経路・取り消し枝の代表列は **TextEdit で実機確認済み**です。
  記号レイヤー59件も2026-08-13に実機確認済みです。
- 基本動作は TextEdit・Notes・Safari・Terminal・VS Code・Slack・Discord・Notion・ChatGPT入力欄で確認しています。
  **Unicode直接注入を含むアプリ別の網羅的な互換性確認は未完了です。**
- 署名済みの配布バイナリはありません。**ソースからビルドして使います。**
- メニューバー表示はまだありません（[ロードマップ](./docs/roadmap.md)）。停止は `make stop` です。

限界の全一覧は [docs/how-it-works.md](./docs/how-it-works.md#8-既知の限界) にあります。

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

かなの主経路は標準ローマ字の再送です。Apple日本語入力で一意なローマ字列を保証しにくい
`ヶ` / `ヴ` / `ゐ` / `ゑ` / `ゎ` と記号だけは、マーカー付きUnicodeイベントで送ります。
Unicodeイベントはその場で確定するため、Space変換を残したい `「` / `」` / `『` / `』` の
JIS括弧キーは横取りせず、Apple日本語入力へそのまま通します。

InputMethodKit で自前IMEを作れば未確定文字列を完全に制御できますが、その場合
Apple日本語入力の変換エンジンだけを公開APIで借りることはできません。詳細は
[docs/how-it-works.md](./docs/how-it-works.md) を参照してください。

## プライバシーと権限

このアプリは「入力監視」とイベント送信（アクセシビリティ）の許可を必要とします。だからこそ、
変換しない条件を広く取っています。

- **入力文字列、クリップボード、変換候補を、ログ・ファイル・ネットワークへ一切出しません。**
  ネットワーク機能を持ちません。ログに出るのは権限状態、モード、入力ソースID、状態コード、
  エラー種別、集計件数だけです。
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
- **かな自体は上流と同一です。** Apple日本語入力へ送るローマ字の綴りだけが訓令式へ揃えてあります。
  差分の全一覧は [docs/layout-reference.md](./docs/layout-reference.md) にあります。

配列表のスナップショットは `wkr-layout` revision
[`a8c102fa6dab6b7d7fdf9678ec9ce2e646facec8`](https://github.com/yuhkis/wkr-layout/commit/a8c102fa6dab6b7d7fdf9678ec9ce2e646facec8)
（2026-08-11 取得）に基づきます。

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
`Sources/WKRCore/WKRLayout.swift` は同リポジトリ revision `a8c102fa6dab6b7d7fdf9678ec9ce2e646facec8`
の内容を正規化したスナップショットを含みます。

- [Scrapbox「わから配列」](https://scrapbox.io/yuhkis/%E3%82%8F%E3%81%8B%E3%82%89%E9%85%8D%E5%88%97)
- [yuhkis/wkr-layout](https://github.com/yuhkis/wkr-layout)
