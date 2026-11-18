# 開発時の参照

常に守る境界は [AGENTS.md](../AGENTS.md) にあります。この文書は該当する作業の節だけを読みます。
仕組みや設計判断の本文は既存の文書を正本とし、ここには変更時の確認点を置きます。

## 上流との同期

- 配列仕様を変える前に [yuhkis/wkr-layout](https://github.com/yuhkis/wkr-layout) と
  [Scrapbox「わから配列」](https://scrapbox.io/yuhkis/%E3%82%8F%E3%81%8B%E3%82%89%E9%85%8D%E5%88%97) の該当箇所を確認する。上流ファイルを無断で書き換えない。
- 取り込みには URL、commit SHA、取り込み日を残す。現行の上流同期は submodule を使わず、正規化したスナップショットと検証テストを用いる。同期スクリプトを追加する場合は README に使い方も書く。
- 配列のピンは [layout-reference.md](layout-reference.md) 冒頭と `WKRLayout.sourceRevision` を参照し、更新時はそれを固定するテストも同時に更新する。仕様解釈の変更には根拠となる上流行とテストケースを記録する。
- ヒートマップの役割名は規則表から導出する。`WakaraKeyLegendTests` で現行v2の中核キーを照合し、`PublicLayoutTests` で正本JSONとの全規則一致を確認する。過去の差異は [design.md](design.md) 9.11節に残し、現行の統一方針は11節を参照する。
- かな規則と記号レイヤーは分けて検証する。現在と過去の候補の確認範囲は [verification.md](verification.md) で分け、以前の試験を現行版の確認済み結果へ繰り上げない。

## 入力処理を変えるとき

設計は [design.md](design.md) 4〜7節が持つ。変更時には次の境界を確認する。

- session-level active filter の `CGEventTap` が、変換対象の原キーだけを抑止する。純粋な FST / Trie は AppKit / Core Graphics に依存させない。
- 通常かなは標準ローマ字の合成イベントで送り、識別マーカーで再入を防ぐ。Public既定の prefix、比較用の deferred、明示フラグを要する実験用 optimistic の位置づけは同文書5節を参照する。Unicode を既定のかな出力へ広げず、採用済みの特殊かな・記号の経路と分ける。InputMethodKit から Apple日本語入力のエンジンを公開APIで連鎖利用できるとは仮定しない。
- `かな` / `英数` の押下だけで判断せず、ユーザーが選んだ Apple日本語入力の実際の TIS 入力ソースと変更通知を照合する。`TISSelectInputSource` で自動選択しない。
- Secure Event Input、パスワード欄、権限不足、tap 無効化、対象外の入力ソースでは変換しない。Command / Control / Option、未対応修飾キー、マウス、フォーカス・アプリ・カーソル・入力ソース変更、Escape、Undo / Redo の境界では規定どおり flush / cancel する。
- deferred の未出力状態に対する Backspace は先に内部の保留を取り消し、既存本文を削除しない。
- `IsSecureEventInputEnabled()` を event tap callback で直接呼ばず、安全な実行コンテキストで確認した状態を参照する。tap の timeout / 無効化時は [design.md](design.md) 6節どおり同じtapを自動再有効化せず、状態を捨てる。キーを受け取る前のtimeoutだけ有限な起動回復へ進み、それ以外は fail closed で終了する。
- tapはUI・監視通知・安全timer・初期コンテキストを準備してから最後に開始する。初回未許可の案内を維持し、権限の有限再確認と新プロセスのtap再試行を分ける。後継の前プロセス終了待ちは起動処理から戻った後の有限timerで行い、main threadをsleepで塞がない。生存中はengine lease・許可要求・tapを開始しない。`EventTapStartupRetryTests`で前プロセスの生存／終了／期限後の状態遷移、上限、引数解析、初回案内の維持、初キー後の回復禁止を確認する。v1共有処理は`StartupBoundaryTests`で同じ境界を確認する。
- TCC 対象は固定 Bundle ID `io.github.yuhkis.wkr-macos.public` と固定出力先の最小 `.app` とする。署名は既定 ad-hoc、`CODESIGN_IDENTITY` の明示時だけその証明書を使い、キーチェーンから自動選択しない。配布版は専用の自己署名証明書で署名する（[design.md](design.md) 12節、手順は [Scripts/README.md](../Scripts/README.md)）。証明書を操作する承認境界は AGENTS.md に従う。

## ログと表示

通常ログの許可範囲は次のとおり。診断項目を増やすときも入力の実文字を含めない。

- 権限状態、モード、入力ソースID、エラー種別、集計件数、変換ゲートが閉じていた秒数。
- Secure Event Input の保持 PID の数値と生死。プロセス名・パス・バンドルIDはログにも画面にも出さない。画面共有・スクリーンショットへの写り込みを考慮する。理由は [design.md](design.md) 7節。
- 起動回復は固定の失敗種別、試行回数、待機秒数だけ。`permissions-check action=setup-wait-ended`、`event-tap-start` / `event-tap-timeout` の `failed=true action=relaunch attempt= elapsed-seconds= wait-seconds=`、`event-tap-start relaunched=true attempts= after-seconds=`、`conversion-not-started reason= attempts= waited-seconds=`を許可する。前プロセスの待機上限では固定理由`conversion-not-started reason=predecessor-exit-timeout`だけを出し、PID・名前・パスは追加しない。timeout直後は`event-tap-disabled type= action=fail-closed`、最初のキー前だけ`conversion-stopped reason=event-tap-disabled-timeout action=relaunch keys-handled=0`。実行中のキー数や時刻は追加しない。
- メニューバー生成結果 `status-item created= glyph= reason=`、メニュー開閉 `status-menu open=`。
- キーマップ指定の有無 `heatmap-keymap selected=`、過去の集計を開いたこと `key-frequency-archive opened=`。ログへパスを出さない。メニューのキーマップ表示はファイル名だけにする。
- 打鍵頻度は `key-frequency flush=ok days=<日数>`、退避 `key-frequency rotate=ok days=<日数>` / `rotate=ok reason=unreadable` / `rotate=failed`、退避できず書き出しを見送った `key-frequency flush=failed stage=archive` のような処理結果だけ（値は書式上のplaceholder）。キー別集計そのものはログへ出さない。退避ファイル名もログへ出さない。

頻度の保存・計数・保持条件は [design.md](design.md) 9節に集約する。既定無効で明示的な
`--key-frequency on` のときだけ動かし、保存は 0600、保持期間の既定上限は設けない。
必要な上限は `--key-frequency-retention <日数>` で指定する。規則表が変わったら起動時に
`archive/` へ退避してから数え直す（9.6.1）。**退避と「読めないファイル」の扱いでは、
元のファイルを削除・上書きしない方を必ず選ぶ。** これらの設定を変える場合は
[install.md](install.md) も更新する。

## 検証と記録

- 状態表示の回帰では、権限未許可・tapなし・作成後未開始・稼働tapを分け、メニューの開閉で未開始を変換中と表示しないことを確認する。権限待機の期限前後と、見出し・詳細・対処が一つの状態を表すことも対象にする。`ConversionStatus.resolve`の権限・稼働状態と`StatusItemController.renderStateRows`を検査し、行のテストは`NSMenuItem`だけで行って実際のステータス項目を作らない。実機確認は新しく生成した候補ZIPで別に行う。

- FST、曖昧接頭辞、未定義キーの再処理、リセット条件の変更はユニットテストで確認する。変換の代表ケースは `E`、`EK`、`ESK`、`WER`、`QH`、`QP`、`Y`、`WJH`。
- 入力動作や互換性を判断する実機テストは TextEdit を起点とし、Notes と Safari の通常テキスト欄でも再現する。表示文字だけでなく、Space の変換候補、Enter 確定、Backspace、カーソル移動、アプリ切替後の状態を確認する。
- Unicode のアプリ別互換性は通常かなと別に記録する。以前確認したアプリ・版・経路を新しい変更の証拠にしない。影響のない文書変更に実機入力テストは不要。
- 公開記録は製品版・再現条件・期待結果・確認結果・未確認事項に絞り、[verification.md](verification.md) に記す。新しいアプリの確認は [roadmap.md](roadmap.md) に反映する。
- 個人の端末設定、日常の利用時系列、実打鍵集計、実キーマップ、raw log は非追跡の `WORKLOG.md` / `docs/archive/` に保全する。集計の説明とfixtureにはテストで生成した値を使い、実測と混同しない。実データの値を置換しただけのものを合成データと呼ばない。
- 公開前は識別子の検索に加え、全追跡文書と配布物の内容・出所を読む。原記録の公開理由がないものは載せない。過去の公開ref・PR・Release・artifact・LFS・Actionsは別に監査し、現行ファイルから消えたことだけで解決済みとしない。

## Public v2 の同期・検査

配列と教材は `Scripts/sync-layout.py --upstream PATH --revision COMMIT` で固定した公開commitから同時に取り込む。`--check`、`make check-public`、`make test`、`make app`、`make package`を実施する。新しい設定・コマンドは [install.md](install.md) と [Scripts/README.md](../Scripts/README.md)に同時に記載する。

Privateの履歴と研究レコーダーを取り込まない。規則値・共通Coreの修正だけを選び、全規則を正本JSONとテストで比較する。通常ログへ入力ごとのstate、規則ID、キー、前面アプリIDを出さない。新しい同梱WebViewの連携は `PracticeProgress` の許可項目だけを使う。

## 独立した公開履歴

旧リポジトリのGitオブジェクトをfetch・mergeしない。旧履歴の調査は別の保全用リポジトリで行う。共通Coreの修正を採用するときは、必要なソース差分だけをレビューし、新しい公開commitとして記録する。`WORKLOG.md`や監査の原記録を公開branchへ追加しない。

公開前は全refの祖先、author / committer、commit本文、tag、全追跡ファイルと配布DMGを確認する。PR・Release・Actionsの本文やログにも個人の値を再掲しない。許可する識別子は著作権・公開著者・公開サービスの識別に必要なものに限り、個人メール、機体情報、端末設定、日常の利用記録、実打鍵集計を除く。
