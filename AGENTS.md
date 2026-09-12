# wkr-macos の作業方針

`wkr-layout` が配列の意図・配列表の上流、ここは macOS 上の実装です。
端末固有の指示は、存在する場合に `AGENTS.local.md` も参照します。

## 常に守る境界

- 開始・完了時に branch、worktree、stage、変更パス、必要な remote との差分を確認し、既存の作業を上書きしない。commit 前に差分と生成物混入を確認する。
- キー列、入力本文、クリップボード、変換候補をファイル、標準出力、解析サービスへ記録・送信しない。英字への打ち直し用履歴は、打鍵数と寿命を制限したメモリ内だけに保持する。
- **例外は、明示的に有効にした打鍵頻度のローカル集計だけ。** 保存できるのは `(キーコード, Shiftの有無) → 回数` と暦日だけで、順序・暦日より細かい時刻・入力文字列は保存しない。ネットワークへ出さず、詳細条件は [design.md](docs/design.md) 9節に従う。
- Secure Event Input の保持プロセスは、ログにも画面にも PID の数値と生死だけを出す。プロセス名・パス・バンドルIDを出さない。ログ・画面表示を変えるときは下表の許可範囲を確認する。
- 安全条件を満たせないときは変換せず、仮状態を安全に破棄して通常入力に戻れることを優先する。対象外のキーを不必要に抑止しない。入力ソースを自動選択しない。
- event tap callback 内で重い処理、ファイルI/O、ネットワークI/Oをしない。event tap と同じ main run loop の timer・表示・メニュー操作も長時間ブロックしない。
- `origin` は公開 [yuhkis/wkr-macos](https://github.com/yuhkis/wkr-macos)。追跡ファイルへ個人の絶対パス、機体名、学内ホスト名、raw log、実キーマップを含めない。手順は `~` 起点か相対パスで書く。
- `WORKLOG.md`、`docs/archive/`、`AGENTS.local.md` はローカル専用。`git add -f` で追跡しない。公開 `main` 以前の私的履歴を復元・接続・公開しない。
- GitHubリポジトリ作成、push、release、署名証明書の作成・インストール・選択・変更、ログイン項目登録はユーザーの明示依頼の範囲内で行う。一括削除・移動・リネームも対象と内容の明示確認が必要。既に得た承認を同じ範囲で問い直さない。
- `main` への直接pushは禁止。公開する変更は branch と PR を使い、CI `swift-test` 成功後、署名付き commit を保持する **merge commit**（`gh pr merge --merge`）で統合する。承認者は不要。force push、`--force-with-lease`、一括 tag push は別途明示依頼なしに行わない。

## 作業に応じて読む資料

全資料を通読せず、変更する機能の行・節を読む。`README.md` は利用者向けの入口です。

| 作業 | 参照先 |
| --- | --- |
| 配列仕様・上流の取り込み・キートップの役割表示 | [development.md](docs/development.md) の「上流との同期」、[layout-reference.md](docs/layout-reference.md)、[design.md](docs/design.md) 4節・9.11節 |
| 変換・出力方式・入力監視・安全ゲート | [how-it-works.md](docs/how-it-works.md)、[design.md](docs/design.md) 4〜7節、[development.md](docs/development.md) の「入力処理を変えるとき」 |
| 英字への打ち直し | [design.md](docs/design.md) 8節（保持上限・破棄・fail closed 条件） |
| 打鍵頻度・ヒートマップ | [design.md](docs/design.md) 9節（既定無効・計数ゲート・0600・保持期間・非送信） |
| 通常ログ・Secure Event Input 表示・メニューバー | [development.md](docs/development.md) の「ログと表示」、[design.md](docs/design.md) 7節 |
| コマンド・設定・権限・署名・起動方法 | [install.md](docs/install.md)、[design.md](docs/design.md) 6節 |
| 検証・実機入力・互換性判断 | [development.md](docs/development.md) の「検証と記録」、[verification.md](docs/verification.md) の該当記録、[roadmap.md](docs/roadmap.md) |

## 変更の完了

- 実装変更は関連テスト・ビルド・手動確認をリスクに応じて行い、実施範囲と未確認事項を記録する。文書だけの変更はリンク・差分・意味の保持を確認する。
- 実機入力の確認前に対象アプリ・入力ソース・期待結果・停止方法を定める。ビルド成功や文字が見えたことだけで入力動作の完了としない。
- 仕組みは `docs/how-it-works.md`、採否と根拠は `docs/design.md`、配列表と綴りは `docs/layout-reference.md` に集約する。同じ表を複製しない。
- コマンド・設定・権限・起動方法を変えたら `docs/install.md` と必要な README の案内を同じ変更で更新する。README へ手順本文を書き戻さない。
- 公開可能な実測は `docs/verification.md` に追記し、過去記録を上書きしない。個人情報・端末固有情報・raw log は非追跡の `WORKLOG.md` に置く。新しいアプリでの確認は `docs/roadmap.md` にも反映する。
- ローカル編集・commit・公開 PR / merge・実機配備を区別して報告する。操作の成功応答だけで保存・公開・動作を確認済みにしない。
