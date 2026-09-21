# WKR macOS v1 — 0.7.0 保存ソース

配列 **1.1.0** に対応したWKR macOS **0.7.0** を元にする保存版です。保存版のタグと識別名は **0.7.0-archive.1**。現在の[WKR macOS Public 0.8.0-public.beta.5](https://github.com/yuhkis/wkr-macos/releases/tag/v0.8.0-public.beta.5)は配列v2用であり、この版とは別です。

[配列1.1.0の保存資料](https://github.com/yuhkis/wkr-layout/releases/tag/v1.1.0-archive.1)と組み合わせて参照してください。かなの規則はv1.1に対応します。Apple日本語入力へ送るローマ字の綴り、JIS記号の素通し、Unicode記号の確定方法はIMEテーブルと異なります。正規化できない旧テーブルの行は`WKRLayout.quarantinedUpstreamEntries`に列挙しています。

## 原版から整理した範囲

v0.7.0の変換規則と変換Coreを保持しています。旧Git履歴・旧文書・利用記録は含めません。過去の個人観測に由来するソースコメントを省き、テストのPIDは合成値へ変更しました。キーごとの状態ログ、打鍵数のログ、前面アプリ識別子のログを削除し、未対応CLIを拒否します。これらと保存版の識別・排他制御を変更したため、元のv0.7.0と同一の配布物とは扱いません。

設定と保存先は `io.github.yuhkis.wkr-macos.v1-archive`、アプリ名は `WKRV1Archive.app` です。旧版・Private・Public v2の設定を自動移行しません。Public v2と共通の排他ロックを使います。旧版やPrivateは先に終了してください。練習アプリは同梱しません。

## ビルドと参照

macOS 14以降、Swift 6.2以降、Apple Silicon、JIS、Apple日本語入力「ひらがな」・ローマ字入力を前提にしています。この保存版はソース配布です。

```sh
make test
make app
build/WKRV1Archive.app/Contents/MacOS/WKRV1Archive --version
```

`make app`はad-hoc署名で作成するだけで、インストール・起動・証明書の選択を行いません。出力が既にあるときは上書きを拒否します。新しいソース展開先を使ってください。

動作確認が必要な場合は、他のWKRを終了した後、Apple日本語入力で次を実行して入力ソースID・モードIDを確認します。

```sh
build/WKRV1Archive.app/Contents/MacOS/WKRV1Archive --print-input-source
open -n build/WKRV1Archive.app --args --input-source-id SOURCE_ID --input-mode-id MODE_ID --mode prefix --key-frequency off --request-permissions
```

`SOURCE_ID`と`MODE_ID`を表示された値に置き換えます。macOSの入力監視・アクセシビリティはこのアプリへ個別に許可します。停止はメニューの終了を使い、起動し直す前に通常入力へ戻ったことを確認してください。自動起動は登録しません。削除時は終了後にこのビルド済みappを取り除き、macOS設定でこのappの権限を取り消します。

日別キー集計は既定オフです。明示的に`--key-frequency on`を指定した場合だけ、暦日・キーコード・Shiftの有無・回数・規則表識別子をローカル保存します。キー順序・入力本文は保存しません。接続機器や打鍵元を識別する機能はありません。保存先は`~/Library/Application Support/io.github.yuhkis.wkr-macos.v1-archive/`です。集計の削除は終了後、`build/WKRV1Archive.app/Contents/MacOS/WKRV1Archive --key-frequency-reset`で行えます。アプリ設定を初期化するときは`defaults delete io.github.yuhkis.wkr-macos.v1-archive`を使います。

この保存版での実機入力は再検証していません。自動テストとビルド確認を、実機入力や現行Public v2の互換性確認と区別します。

MIT License。テストの入力・集計・PID・日付・キーマップはテストコードで作る合成値です。`archive-source.json`に保存版の全ファイルSHA256を記録しています。
