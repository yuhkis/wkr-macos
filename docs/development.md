# 開発時の参照

常に守る境界は [AGENTS.md](../AGENTS.md) にあります。この文書は該当する作業の節だけを読みます。
仕組みや設計判断の本文は既存の文書を正本とし、ここには変更時の確認点を置きます。

## 上流との同期

- 配列仕様を変える前に [yuhkis/wkr-layout](https://github.com/yuhkis/wkr-layout) と
  [Scrapbox「わから配列」](https://scrapbox.io/yuhkis/%E3%82%8F%E3%81%8B%E3%82%89%E9%85%8D%E5%88%97) の該当箇所を確認する。上流ファイルを無断で書き換えない。
- 取り込みには URL、commit SHA、取り込み日を残す。現行の上流同期は submodule を使わず、正規化したスナップショットと検証テストを用いる。同期スクリプトを追加する場合は README に使い方も書く。
- 配列のピンは [layout-reference.md](layout-reference.md) 末尾と `WKRLayout.sourceRevision` を参照し、更新時はそれを固定するテストも同時に更新する。仕様解釈の変更には根拠となる上流行とテストケースを記録する。
- ヒートマップの役割名は規則表から導出する。`WakaraKeyLegendTests` の上流 README 対照表を、中核10列の図と照合する。規則表と README の revision が異なる点は [design.md](design.md) 9.11節を参照する。
- かな規則と記号レイヤーは分けて検証する。過去の件数や実測範囲は [verification.md](verification.md) の日付付き記録で確認し、現在の検証済み範囲と混同しない。

## 入力処理を変えるとき

設計は [design.md](design.md) 4〜7節が持つ。変更時には次の境界を確認する。

- session-level active filter の `CGEventTap` が、変換対象の原キーだけを抑止する。純粋な FST / Trie は AppKit / Core Graphics に依存させない。
- 通常かなは標準ローマ字の合成イベントで送り、識別マーカーで再入を防ぐ。CLI 既定の deferred、常用の prefix、明示フラグを要する実験用 optimistic の位置づけは同文書5節を参照する。Unicode を既定のかな出力へ広げず、採用済みの特殊かな・記号の経路と分ける。InputMethodKit から Apple日本語入力のエンジンを公開APIで連鎖利用できるとは仮定しない。
- `かな` / `英数` の押下だけで判断せず、ユーザーが選んだ Apple日本語入力の実際の TIS 入力ソースと変更通知を照合する。`TISSelectInputSource` で自動選択しない。
- Secure Event Input、パスワード欄、権限不足、tap 無効化、対象外の入力ソースでは変換しない。Command / Control / Option、未対応修飾キー、マウス、フォーカス・アプリ・カーソル・入力ソース変更、Escape、Undo / Redo の境界では規定どおり flush / cancel する。
- deferred の未出力状態に対する Backspace は先に内部の保留を取り消し、既存本文を削除しない。
- `IsSecureEventInputEnabled()` を event tap callback で直接呼ばず、安全な実行コンテキストで確認した状態を参照する。tap の timeout / 無効化時は [design.md](design.md) 6節どおり自動再有効化せず、状態を捨てて fail closed で終了する。
- TCC 対象は固定 Bundle ID `io.github.yuhkis.wkr-macos` と固定出力先の最小 `.app` とする。署名は既定 ad-hoc、`CODESIGN_IDENTITY` の明示時だけその証明書を使い、キーチェーンから自動選択しない。証明書を操作する承認境界は AGENTS.md に従う。

## ログと表示

通常ログの許可範囲は次のとおり。診断項目を増やすときも入力の実文字を含めない。

- 権限状態、モード、入力ソースID、エラー種別、集計件数、変換ゲートが閉じていた秒数。
- Secure Event Input の保持 PID の数値と生死。プロセス名・パス・バンドルIDはログにも画面にも出さない。画面共有・スクリーンショットへの写り込みを考慮する。理由は [design.md](design.md) 7節。
- メニューバー生成結果 `status-item created= glyph= reason=`、メニュー開閉 `status-menu open=`。
- キーマップ指定の有無 `heatmap-keymap selected=`。ログへパスを出さない。メニューのキーマップ表示はファイル名だけにする。
- 打鍵頻度は `key-frequency flush=ok days=3` のような処理結果だけ。キー別集計そのものはログへ出さない。

頻度の保存・計数・保持条件は [design.md](design.md) 9節に集約する。既定無効で明示的な
`--key-frequency on` のときだけ動かし、保存は 0600、保持期間の既定上限は設けない。
必要な上限は `--key-frequency-retention <日数>` で指定する。これらの設定を変える場合は
[install.md](install.md) も更新する。

## 検証と記録

- FST、曖昧接頭辞、未定義キーの再処理、リセット条件の変更はユニットテストで確認する。変換の代表ケースは `E`、`EK`、`ESK`、`WER`、`HT`、`TH`、`EY`、`YJ`。
- 入力動作や互換性を判断する実機テストは TextEdit を起点とし、Notes と Safari の通常テキスト欄でも再現する。表示文字だけでなく、Space の変換候補、Enter 確定、Backspace、カーソル移動、アプリ切替後の状態を確認する。
- Unicode のアプリ別互換性は通常かなと別に記録する。以前確認したアプリ・版・経路を新しい変更の証拠にしない。影響のない文書変更に実機入力テストは不要。
- 公開可能な入力ソース・対象アプリ・期待値・実測値・未確認事項は [verification.md](verification.md) に追記する。新しいアプリの確認は [roadmap.md](roadmap.md) に反映する。端末名や raw log を含む記録は非追跡の `WORKLOG.md` に置く。

## 指示構成の整理記録（2026-09-12）

[OpenAI の記事](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra) を踏まえ、
常時必要な境界と作業別の詳細を分けた。特定モデルだけを前提にした実行規約にはしていない。

| 以前 AGENTS.md にあった内容 | 現在の参照先 |
| --- | --- |
| 毎回4文書を通読 | AGENTS.md の作業別参照表 |
| 上流のピン・古い修正状況・役割図の対照 | layout-reference.md、design.md 4節・9.11節と本書の「上流との同期」 |
| 技術方針・状態遷移の細部 | design.md 4〜8節と本書の「入力処理を変えるとき」 |
| ログ許可範囲・頻度集計の細部 | 本書の「ログと表示」、design.md 9節 |
| 代表入力・実機テストの手順 | 本書の「検証と記録」 |
| 機密・承認・履歴保全・PRでのmerge・完了条件 | AGENTS.md に保持 |
| 現在の worktree にあるローカル指示だけを参照 | AGENTS.md：不在時は主 worktree の同名ファイルを参照。どちらにも無ければ適用対象なし |

旧 AGENTS.md の「timeout後に再有効化」「Unicodeは比較実験限定」は既存の design.md と
不一致だったため、既存設計の「fail closedで終了」「特殊かな・記号に限定して採用」への参照に
揃えた。アプリの処理、テスト、配列データ、過去の検証結果は変更していない。
文書の差分、参照先の存在、境界の保持を確認し、アプリのビルド・配備・実機入力は行っていない。

ローカル指示の探索は、Git が一覧の先頭に主 worktree を出す仕様に基づく。同じリポジトリの
主 worktree と linked worktree から同じローカル指示へ到達することを確認した。別の clone に
ローカル指示が無い場合は探索先を広げない。機密本文や端末固有のパスは追跡文書へ移していない。
