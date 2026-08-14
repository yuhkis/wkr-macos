# インストールと使い方

wkr-macos は署名済みの配布バイナリを用意していません。**自分の Mac でソースからビルドして使います。**
理由は権限まわりの都合で、[トラブルシュート](#トラブルシュート)に書いてあります。

原理の説明は [how-it-works.md](./how-it-works.md)、キー配列と綴りの一覧は
[layout-reference.md](./layout-reference.md) を参照してください。

---

## 必要環境

| 項目 | 要件 |
| --- | --- |
| キーボード | **JIS配列**。物理キーの正規化がJIS前提です |
| 入力ソース | **Apple日本語入力**（「日本語 − ローマ字入力」）を追加済みで、「ひらがな」を選べること |
| macOS | 開発・実機確認は macOS 26.6.1 / Apple Silicon で行っています。bundle の `LSMinimumSystemVersion` は 14.0 ですが、macOS 14〜25 は未検証です |
| ビルド | Xcode 26 系（`Package.swift` が `swift-tools-version: 6.2`）。Command Line Tools だけでは不足します |
| 権限 | 「入力監視」と「アクセシビリティ」の2つを許可できること |

Apple日本語入力が入力ソースにない場合は、「システム設定」→「キーボード」→「テキスト入力」→
「入力ソース」→「編集…」から「日本語」を追加してください。

日本語モード中に `Shift+M` から `Mac` のような英単語へ切り替えたい場合は、同じ画面の
「日本語 − ローマ字入力」で、入力モードの**「ひらがな」と「英字」を両方有効**にします。
「英字」が無効だと Shift による切替先がなく、後続の英字キーを wkr-macos がかな配列として処理してしまいます。

## 1. 取得してビルドする

```bash
git clone https://github.com/yuhkis/wkr-macos.git
```

```bash
cd wkr-macos && make test && make app
```

`make app` は Release ビルドして `build/WKRMacOS.app` を作ります（リポジトリ内の固定パスです）。
シェルが fish でも `make` コマンドはそのまま実行できます。

署名は既定で **ad-hoc** です。自分が保有する証明書で署名したい場合だけ、明示的に指定します。

```bash
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' make app
```

キーチェーンにある証明書を自動で拾うことはしません。**他人や他事業者に発行された証明書で
うっかり署名してしまうのを防ぐため**です。ビルドスクリプトが証明書を作成・インストールする
こともありません。ad-hoc署名でも動作しますが、再ビルドのたびに権限の再許可が要る場合があります。

> フルXcodeが `/Applications/Xcode.app` にある場合、`make` はこのプロジェクトのコマンドだけ
> `DEVELOPER_DIR` を使います。システム全体の `xcode-select` は変更しません。

## 2. 入力ソースIDを確認する

wkr-macos は Apple日本語入力のIDを推測しません。**実際に選択中のIDを取得して渡します。**

まず Apple日本語入力の「ひらがな」に手動で切り替えてから、次を実行します。

```bash
make input-source
```

`source-id=...` と `mode-id=...` が表示されます。標準的な環境では次の値になります。

```text
source-id=com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese
mode-id=com.apple.inputmethod.Japanese
```

この2つが現在のTIS状態と**両方完全一致**するときだけ変換が有効になります。

## 3. 起動して権限を許可する

```bash
make start \
  INPUT_SOURCE_ID=com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese \
  INPUT_MODE_ID=com.apple.inputmethod.Japanese \
  MODE=prefix
```

初回は権限がないため、`permissions listen=false post=false` を記録して終了します。
「システム設定」→「プライバシーとセキュリティ」で、**「入力監視」と「アクセシビリティ」の両方**に
`build/WKRMacOS.app` を追加して許可し、もう一度上のコマンドを実行してください。

権限が揃うと `conversion-started output-mode=prefix` まで進み、Apple日本語入力の「ひらがな」を
選んでいる間だけ変換が有効になります。動作状況は次で確認できます。

```bash
/usr/bin/log stream --predicate 'subsystem == "io.github.yuhkis.wkr-macos"' --info
```

絶対パスで書いているのは、macOSの既定シェルであるzshに引数を取らない `log` ビルトインがあり、
`log stream ...` が `zsh:log:1: too many arguments` で失敗するためです。bashとfishでは
`log` のままでも動きます。

停止はいつでもできます。

```bash
make stop
```

## 4. 日常的に使う：`/Applications` へ配備する

開発ツリーの `build/WKRMacOS.app` は再ビルドのたびに署名が変わり得るので、常用には
`/Applications` へ配備した固定の bundle を使います。

```bash
Scripts/install-app.sh build/WKRMacOS.app
```

Bundle ID と署名を検証し、既存の `/Applications/WKRMacOS.app` があれば
`/Applications/WKRMacOS.app.backup-<timestamp>` へ退避してから置き換えます。

配備した bundle は `-installed` 系のターゲットで扱います。

```bash
make input-source-installed
```

```bash
make start-installed \
  INPUT_SOURCE_ID=com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese \
  INPUT_MODE_ID=com.apple.inputmethod.Japanese \
  MODE=prefix
```

**配備し直すと TCC 上の identity が変わるため、「入力監視」「アクセシビリティ」の再許可が必要です。**
このとき、既存エントリは古い署名に紐づいたまま有効に見えます。**`−` で削除してから追加し直してください。**

## 5. ログイン時に自動起動する

`/Applications/WKRMacOS.app` を、ログイン時に prefix モードで1回だけ起動する LaunchAgent を入れます。

```bash
make install-login-agent
```

インストール時に既存プロセスを停止し、LaunchAgent 管理下で起動し直します。異常終了時の
無限再起動を避けるため `KeepAlive` は使いません。設定ファイルは
`~/Library/LaunchAgents/io.github.yuhkis.wkr-macos.login.plist` です。

入力ソースIDが標準と違う場合は、`Resources/io.github.yuhkis.wkr-macos.login.plist` の
`--input-source-id` / `--input-mode-id` を自分の値に書き換えてからインストールしてください。

## 仮想マシン・リモートデスクトップでの扱い

前面アプリが変換対象外だと判断できる場合、`--exclude-app` に Bundle ID を渡すと、そのアプリが
前面にある間は変換せず保留状態も破棄します。複数指定する場合は繰り返します。

```bash
/Applications/WKRMacOS.app/Contents/MacOS/WKRMacOS --exclude-app com.example.app --print-input-source
```

常用する場合は `Resources/io.github.yuhkis.wkr-macos.login.plist` の `ProgramArguments` に追記して
`make install-login-agent` します。**既定では何も除外していません。**

Bundle ID は次で調べられます。

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' '/Applications/<アプリ名>.app/Contents/Info.plist'
```

除外が効いているかはログで確認できます。

```text
frontmost-application id=com.example.app excluded=true
```

### 仮想マシンは「除外する」とは限りません

リモートデスクトップのように別マシンへキーを送るだけの用途なら除外が正解です。しかし
**仮想マシンは、除外しないほうが良い場合があります。**

WKR が送るのは標準ローマ字です。それがゲストへ届くなら、ゲスト側の IME がそのローマ字をかなへ
変換します。**つまりゲスト側にわから配列を入れる必要がなくなります。**

これは実機で確かめる必要があります。仮想化ソフトがキー入力を CGEventTap より下の階層で取得して
いる場合、WKR の抑止も合成イベントも届かないためです。次の手順で判定してください。

1. WKR を `MODE=prefix` で起動し、**除外は指定しない**。macOSの入力ソースは Apple「ひらがな」。
2. ゲスト側でテキストエディタを開き、**ゲストの IME をオフ（直接入力）**にする。
3. 物理キーで `E` `K` と打つ。

| ゲストの表示 | 意味 | 対応 |
| --- | --- | --- |
| `ki` | WKRの合成イベントが届き、原キーも抑止されている | 除外しない。次の手順へ |
| `ek` | 原キーがそのまま届き、合成イベントは届いていない | ゲスト側に配列を入れるか、`--exclude-app` で除外する |
| `eki` など | 原キーと合成イベントの両方が届いている | **必ず `--exclude-app` で除外する** |

`ki` になった場合は、ゲストの IME を日本語（ローマ字入力）にしてから `W` `E` `R` と打ちます。
`わから` になれば、ホスト側の WKR とゲスト側の IME の組み合わせが成立しています。

### 入力モードを2つ揃える必要があります

この構成では、**macOSの入力ソースとゲストのIMEを同じ状態に保つ**必要があります。

| やりたいこと | macOS | ゲストのIME |
| --- | --- | --- |
| 日本語を入力 | Apple「ひらがな」（WKR有効） | オン（ローマ字入力） |
| 英語を入力 | 「英数」など（WKR無効） | オフ（直接入力） |

WKR は JIS の `かな` / `英数` キーを**横取りせずそのまま前面アプリへ渡します**。仮想化ソフト側で
これらをゲストの IME 切り替えへ割り当てられれば、1打鍵で両方を同時に切り替えられます。
割り当て可否は仮想化ソフトのキーボード設定によります。

### macOS 側の代替手段

「システム設定」→「キーボード」→「テキスト入力」→「入力ソース」→
「**書類ごとに入力ソースを自動的に切り替える**」を有効にすると、アプリごとに入力ソースを記憶します。
対象アプリで英語入力を選んでおけば、そのアプリが前面のとき WKR は自動的に無効になります。
手動設定に依存しますが、`--exclude-app` と違ってアプリ内で日本語へ切り替える余地が残ります。

## アンインストール

```bash
make uninstall-login-agent
```

```bash
make stop && rm -rf /Applications/WKRMacOS.app
```

`Scripts/install-app.sh` が作った `/Applications/WKRMacOS.app.backup-*` が残っていれば、
不要なものを削除します。最後に「システム設定」→「プライバシーとセキュリティ」→
「入力監視」「アクセシビリティ」から WKRMacOS のエントリを `−` で削除してください。

## 他の出力方式を試す

常用は `MODE=prefix` です。CLI の既定値は最も安全な `deferred` で、`MODE` を省略するとこちらになります。

```bash
make start \
  INPUT_SOURCE_ID=com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese \
  INPUT_MODE_ID=com.apple.inputmethod.Japanese
```

`optimistic` は実験用です。仮のかなを表示して Backspace で差し替えるため、削除回数が
未実測の規則が残っています。**破棄してよい無題文書だけで**、明示フラグ付きで起動してください。

```bash
make stop && make start \
  INPUT_SOURCE_ID=com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese \
  INPUT_MODE_ID=com.apple.inputmethod.Japanese \
  MODE=optimistic ALLOW_OPTIMISTIC=1
```

各方式の違いは [how-it-works.md](./how-it-works.md#5-出力方式どのタイミングで何を送るか) にあります。

## 動作確認

`Resources/LocalInputTest.html` はフォーム送信もスクリプトもないローカルページです。
ブラウザのテキスト欄での挙動確認と、パスワード欄で変換が起きない（Secure Event Input が
効いている）ことの確認に使えます。

```bash
open -a Safari Resources/LocalInputTest.html
```

prefix モードでの期待値は次のとおりです。

| 入力 | 表示 |
| --- | --- |
| `E` | `k` |
| `E` `K` | `き` |
| `W` `E` `R` | `わかr` |
| `W` `E` `R` + Enter | `わから` |
| `W` `E` `R` + Space | `わから` の読みで変換候補が出る |

## トラブルシュート

| 症状 | 原因と対処 |
| --- | --- |
| 起動直後に終了し、ログに `reason=permissions` | 「入力監視」「アクセシビリティ」が未許可。両方許可してから再起動 |
| 許可済みに見えるのに `listen=false` | 再ビルドや再配備で署名 identity が変わっている。既存エントリを `−` で削除してから追加し直す |
| 変換されない。ログに `matches-target=false` | 現在の入力ソースが Apple日本語入力「ひらがな」ではない。他社IMEや「英字」では設計どおり素通しします |
| パスワード欄で変換されない | 仕様です。Secure Event Input 中は全入力を素通しします |
| パスワード欄ではないのに、しばらくの間まったく変換されない | セッションのどこかで Secure Event Input が有効になっています。パスワードマネージャのロック解除ダイアログが開いたまま、ターミナルの Secure Keyboard Entry が有効、認証ダイアログが背後に残っている、が代表例です。下の「変換が止まったときのログの見方」を参照 |
| ログに `reason=duplicate-instance` | 既に常駐しています。`make stop` してから起動してください |
| `reason=not-a-bundle` | `.app` bundle の外から実行しています。`make start` / `make start-installed` を使ってください |
| ad-hoc署名で毎回再許可が必要 | 安定した署名 identity がない環境の既知の制約です。常用するなら `/Applications` へ配備した bundle を固定して使ってください |

### 変換が止まったときのログの見方

このアプリは変換を止めた理由をログに残します。症状が続いている最中なら `log stream`、
すでに直ってしまった後なら `log show` で振り返れます。

```bash
/usr/bin/log show --last 1h --predicate 'subsystem == "io.github.yuhkis.wkr-macos"' --style compact
```

| ログ | 意味 |
| --- | --- |
| `secure-event-input enabled=true` | Secure Event Input が有効。`enabled=false` が出るまで全入力を素通しします |
| `input-source ... matches-target=false` | 対象外の入力ソースです。他社IMEや「英字」に切り替わっています |
| `frontmost-application ... excluded=true` | `--exclude-app` で除外したアプリが前面です |
| `conversion-stopped` / `event-tap-disabled` | fail closed で終了しています。起動し直してください |

いずれも出ていなければ、変換ゲートは開いています。常駐しているかどうかは `pgrep WKRMacOS`
で確認できます。

`secure-event-input enabled=true` のまま戻らない場合は、パスワードマネージャのロック解除
ダイアログが開いたままになっていないか、ターミナルの Secure Keyboard Entry が有効になって
いないかを確認してください。**Secure Event Input はフィールド単位ではなくセッション全体に
効く**ため、前面が普通のテキスト欄でも止まったままになります。メニューバー表示が未実装で、
止まっていることが画面から分からない点は [roadmap.md](./roadmap.md) の課題です。

実測例は [verification.md](./verification.md) にあります。

Apple の案内: [Macで入力監視へのアクセスを制御する](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
