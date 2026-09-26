# 導入と使い方 — Public v2

3製品のダウンロード版の共通手順は[distribution.md](distribution.md)へ。以下はv2の詳細設定・開発用操作です。

対象はmacOS 14以降・Apple日本語入力（ローマ字入力）・JISキーボードです。現在の配布候補はApple Silicon用です。v2候補0.8.0-public.beta.6（配列2.0.0-beta.1、未公開）の権限付与後の短い変換・停止・再開は、Apple日本語入力と画面共有のキー操作で確認しています。配列2.0.0-beta.2の0.8.0-public.beta.7では、公開前に同じ確認をやり直します。[確認済み範囲](verification.md)を先に確認してください。

## 1. 入手・ビルド

公開ベータは[公式Release](https://github.com/yuhkis/wkr-macos/releases/tag/v0.8.0-public.beta.5)から入手できます。Apple Developer Programへの加入を前提にせず、次の二つの導入経路を用意します。

- アプリzip: Apple Silicon用の `WKR-macOS-0.8.0-public.beta.5-arm64-adhoc.zip` を展開する。利用者側のXcodeは必要ありません。ad-hoc署名・未公証なので、初回の個別起動許可が必要になる場合があります。
- ソースビルド: 下記の手順で自分のMac上にアプリを作る。

アプリzipを使う場合は、公式Release URLと `SHA256SUMS` を照合してから展開します。ad-hoc署名はコードの整合性を検査するもので、Appleによる開発元の確認や公証を意味しません。

Swift 6.2以降を含むXcodeを用意し、公開用mainまたはReleaseのtagから実行します。

```sh
make test
make check-public
make app
```

`build/WKRPublic.app`が作られます。ビルドはインストール済みアプリや個人設定を変更しません。自分の証明書での署名が必要な場合だけ `CODESIGN_IDENTITY` を明示します。証明書を自動で選択・作成する処理はありません。

## 2. 旧版を終了して導入

旧WKR / Privateの変換エンジンと同時に起動しないでください。[移行手順](migration.md)に従い、旧版のログイン起動を解除して終了します。Publicは旧版の終了や設定削除を自動では行いません。

Finderで `WKRPublic.app` を `/Applications` へコピーするか、ソース作業場から次を実行します。

```sh
./Scripts/install-app.sh build/WKRPublic.app /Applications/WKRPublic.app
```

Publicの同名アプリが既にある場合はバックアップ名へ退避してからコピーします。旧 `WKRMacOS.app` は対象外です。今回のPublic準備作業では、この配備操作は実行していません。

## 3. 初回起動・権限と日本語入力

アプリzipの初回起動で「開発元を検証できない」「Appleが悪質なソフトウェアかどうかを確認できない」等の警告が出た場合は、公式Releaseとハッシュを確認したうえで、システム設定 → プライバシーとセキュリティ →「このまま開く」から、そのアプリの起動を承認します。[Appleの案内](https://support.apple.com/ja-jp/102445)に従ってください。Gatekeeper全体を無効にするコマンドやquarantine属性の一括削除は使いません。個別起動を許可する操作と、以下の入力権限の許可は別です。

実際にインターネットから取得したzipの初回警告・許可の流れは、実機で確認予定です。ローカルビルドやSSH転送で開けたことだけを、ダウンロード後の初回起動の検証として扱いません。

1. `WKRPublic.app` を開きます。権限が足りない間は変換を開始せず、案内画面を表示します。
2. 案内から「システム設定 → プライバシーとセキュリティ → 入力監視」と「アクセシビリティ」を開き、**WKR macOS Public**（画面によっては **WKRPublic**）をオンにします。一覧になければ「＋」から、起動している **WKRPublic.app** を選びます。別フォルダの試験用コピーを使うときも、その実体を指定してください。
3. 「状態を再確認して変換を開始」を選びます。初回はmacOSの許可要求が表示される場合があります。
4. Apple日本語入力の「ひらがな」を自分で選びます。アプリが入力ソースを切り替えることはありません。
5. 破棄できるTextEditの新規書類で `E K` → き、`W E R` + Enter → わからを試します。次にSpace変換、Backspace、カーソル移動、アプリ切替を確認します。

日本語入力が対象外ならメニューに待機理由を表示します。英字入力・他のIMEでは変換しません。設定した対象IDの確認は次で行えます（変更しません）。

```sh
/Applications/WKRPublic.app/Contents/MacOS/WKRPublic --print-input-source
```

既定IDは `com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese` / `com.apple.inputmethod.Japanese`。別IDが実測されたときは `--input-source-id` と `--input-mode-id` で両方を明示します。曖昧な部分一致で変換対象を広げません。

再ビルドでad-hoc署名が変わると再許可が必要になる場合があります。以前の署名の許可登録が残り、設定画面がオンでもアプリは未許可になる現象を配布候補で確認しています。見かけの許可状態と実際の権限を区別し、案内画面で再確認してください。未許可のままなら変換確認は完了していません。

今回のv2候補では、対象アプリの許可を設定し直した後、アプリ自身が両権限を許可済みと判定し、短い変換・停止・再開まで復旧することを確認しました。画面がオンであることだけで判断せず、対象アプリの案内と実際の入力で確認します。他アプリの許可やmacOS全体の保護を変更せず、[検証記録と残件](verification.md)を確認してください。証明書・権限の変更は端末ごとに行います。

## 4. 練習

メニュー「わから v2 を練習する」を選びます。0.2.0では「QWERTYで体験」をABC・英数で使うと練習欄の中だけでかなへ変換します。「WKR・IMEで練習」はWKR v2でひらがなを確定後、もう一度Enterで採点します。独立したWakaraPractice.appも同じ2モードで、変換エンジンを起動しません。

```sh
open /Applications/WKRPublic.app --args --practice-only
```

この起動はevent tapを作らず、入力権限を要求しません。通常起動中ならメニューから練習を開いてください。成績保存は画面で有効化したときだけで、同じ画面の削除ボタンで消せます。

読み込み中は案内が表示されます。教材を開けない、通信遮断の準備ができない、表示処理が停止した場合は「再読み込み」を選べます。15秒で読み込みが終わらない場合も同じ案内を出します。再読み込みは練習の画面を初期化するため、途中の入力は破棄されます。有効化済みの課題別成績は残ります。権限設定を追加したり、通信遮断を解除したりする必要はありません。

## 5. 停止・再開・自動起動

メニューの「変換を一時停止」で保留を捨て、通常入力へ戻ります。「変換を再開」は安全条件を再照合します。終了はメニューの終了項目、またはPublicの作業場で `make stop`。停止コマンドは `WKRPublic` プロセスだけを対象にします。

権限の取消し、event tapの無効化、合成イベント失敗では安全側で終了します。原因を直してアプリを開き直してください。Secure Event Input中は変換せず、解除後に現在の入力ソースを再確認します。保持者表示はPID数値と生死のみです。

ログイン時起動は任意です。手動起動が動作することを確かめてから行います。

```sh
make install-login-agent
make uninstall-login-agent
```

Public専用ラベルは `io.github.yuhkis.wkr-macos.public.login`。旧版のラベルとは異なります。両方を登録したままにしないでください。

## 6. 設定と日別集計

設定ドメインは `io.github.yuhkis.wkr-macos.public` です。旧版のdefaultsや研究設定は自動で読みません。起動引数が設定より優先します。

| 項目 | 既定 / 指定 |
| --- | --- |
| 出力方式 | prefix。`--mode deferred`は保留型。optimisticは実験用の明示確認付き |
| 記号レイヤー | on。`--symbol-layer off` / `SymbolLayer off`で55件のP Unicode記号を無効化（矢印は残る） |
| 英字への打ち直し | 英数の短時間2回。`--english-fallback` / `EnglishFallbackTrigger` |
| 日別キー頻度 | off。`--key-frequency on` / `KeyFrequencyLog on`で明示有効化 |
| 保持期間 | 全日。`--key-frequency-retention DAYS` / `KeyFrequencyRetentionDays`で上限日数 |
| ヒートマップの配列図 | JIS / US / Cornix。`--vil PATH` / `VialKeymapPath`は利用者自身のローカルファイル |
| 除外アプリ | `--exclude-app BUNDLE_ID`を必要な対象だけ指定 |

```fish
defaults write io.github.yuhkis.wkr-macos.public KeyFrequencyLog on
```

再起動後から数えます。保存は `~/Library/Application Support/io.github.yuhkis.wkr-macos.public/key-frequency.json`（0600）。日付・規則表ID・（論理キーコード、Shift）ごとの回数だけです。キーボード別の打鍵元を識別せず、接続情報による自動分類もしません。JIS / US / Cornixは同じ論理合計の描画図です。

集計の保存は120秒ごとに専用queueで行い、入力監視のrun loopではファイル処理をしません。メニューか `--key-frequency-report --open` で保存済み集計を表示します。最後の最大120秒分は保存前には表示されません。

規則表が変わると旧集計を `archive/` へ退避します。読めない集計も上書きせず退避し、起動時の退避に失敗した場合は、その起動中の計数も止めます。変換自体は続けられます。保存時にも規則表の違いを再検査し、退避できなければ書き出しません。`--key-frequency-store PATH`は明示した別ファイルの読取・操作用です。旧PrivateデータをPublicで再保存しないでください。

集計の削除はPublicを終了してから `--key-frequency-reset`。archive内の過去データは削除対象外です。保存を止めるには `KeyFrequencyLog off` にして再起動します。

## アンインストール

1. Publicのログイン起動を登録していた場合は `make uninstall-login-agent`。
2. Publicのメニューから終了（または `make stop`）。
3. Finderで `/Applications/WKRPublic.app` をゴミ箱へ移す。
4. 入力監視・アクセシビリティのPublicエントリを削除する。
5. 成績を消す場合は事前に練習画面の削除ボタンを使う。日別集計・archiveも不要なら、PublicのApplication Supportフォルダだけを確認して削除する。
6. Public設定も不要なら `defaults delete io.github.yuhkis.wkr-macos.public`。

アプリの削除と利用者データの削除は別です。旧版 / Privateのフォルダを削除対象へ含めません。

## トラブルシュート

版と対応配列はメニュー、練習のヘッダー、`--version`で確認できます。二重起動の案内が出たら、使わない方を先に終了します。起動中に別版が始まった場合はPublicが停止します。古いPrivateは排他ロックを実装していないため、ログイン項目も含めた切替手順を守ってください。

変換の実機確認ではTextEdit、Notes、Safariを分け、入力ソース、期待したかな、停止方法を決めます。ブラウザの合成イベントによる教材テストを実IMEの確認として扱いません。


## 変換が止まったときのログの見方

メニューの停止理由を先に確認します。追加の切り分けには、Publicの通常ログだけを読みます。

```fish
/usr/bin/log show --predicate 'subsystem == "io.github.yuhkis.wkr-macos.public"' --last 5m --style compact
```

通常ログにはOSが診断イベントの時刻を付けます。WKRは入力単位の時刻・間隔、キー列、規則実行履歴を記録しません。ログの原文は公開Issueへ添付せず、権限・停止理由など必要な状態だけに整理してください。
