# wkr-macos の作業方針

`wkr-layout` が配列の意図・配列表の上流、ここは macOS 上の実装です。
端末固有の指示は、この worktree の `AGENTS.local.md` を参照します。無ければ
`git worktree list --porcelain` の先頭にある主 worktree が通常の checkout（`bare` でない）かを確認し、
そこに `AGENTS.local.md` があれば読みます。主 worktree は `main` ブランチの所在という意味ではありません。
どちらにも無ければローカル指示の適用対象はありません。本文や端末固有のパスは追跡ファイルへコピーしません。

## 常に守る境界

- 開始・完了時に branch、worktree、stage、変更パス、必要な remote との差分を確認し、既存の作業を上書きしない。commit 前に差分と生成物混入を確認する。
- キー列、入力本文、クリップボード、変換候補をファイル、標準出力、解析サービスへ記録・送信しない。英字への打ち直し用履歴は、打鍵数と寿命を制限したメモリ内だけに保持する。
- **例外は、明示的に有効にした打鍵頻度のローカル集計と、練習の課題別集計だけ。** 保存できるのは `(キーコード, Shiftの有無) → 回数` と暦日、その日に数えた規則表の識別子（上流の commit 名）だけで、順序・暦日より細かい時刻・入力文字列は保存しない。規則表が変わったら集計ファイルを `archive/` へ**退避してから**新しく数え直す（削除はしない）。読めないファイルも上書きせず退避する。ネットワークへ出さず、詳細条件は [design.md](docs/design.md) 9節に従う。
- 練習は明示的な保存有効化時だけ、課題ID・配列版・完了回数・最高正答率を保存できる。入力本文・誤入力・キー列・時刻・行別履歴は保存しない。ブラウザと同梱版は上流の同一教材を使い、Privateの任意ページ・記録用橋渡しを持ち込まない。詳細は [public-beta.md](docs/public-beta.md)。
- Secure Event Input の保持プロセスは、ログにも画面にも PID の数値と生死だけを出す。プロセス名・パス・バンドルIDを出さない。ログ・画面表示を変えるときは下表の許可範囲を確認する。
- 安全条件を満たせないときは変換せず、仮状態を安全に破棄して通常入力に戻れることを優先する。対象外のキーを不必要に抑止しない。入力ソースを自動選択しない。
- event tap callback 内で重い処理、ファイルI/O、ネットワークI/Oをしない。event tap と同じ main run loop の timer・表示・メニュー操作も長時間ブロックしない。
- 公開予定先は [yuhkis/wkr-macos](https://github.com/yuhkis/wkr-macos)。remoteは公開操作の承認時に接続先のrepository IDと独立履歴を確認して設定する。追跡ファイルへ個人の絶対パス、機体名、学内ホスト名、raw log、実キーマップを含めない。手順は `~` 起点か相対パスで書く。
- `WORKLOG.md`、`docs/archive/`、`AGENTS.local.md` はローカル専用。`git add -f` で追跡しない。このリポジトリは確認済みの公開ソースから始めた独立履歴。旧リポジトリやPrivateのGitオブジェクト、branch、tag、PR refをfetch・merge・接続しない。旧履歴の保全・監査は別のリポジトリで行う。
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
- 公開検証は `docs/verification.md` に、製品版・再現条件・期待結果・確認結果・未確認事項を記す。個人設定、日常利用の時系列、実打鍵集計、実キーマップ、raw log は非追跡の `WORKLOG.md` / `docs/archive/` へ保全する。集計例はテストで生成した合成値を使い、出所を明記する。公開文書の不適切な記載は原記録を非公開で保全して整理し、最新ファイルの修正と過去履歴の解決を区別する。新しいアプリでの確認は `docs/roadmap.md` にも反映する。
- ローカル編集・commit・公開 PR / merge・実機配備を区別して報告する。操作の成功応答だけで保存・公開・動作を確認済みにしない。
