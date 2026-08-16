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
env CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' make app
```

キーチェーンにある証明書を自動で拾うことはしません。**他人や他事業者に発行された証明書で
うっかり署名してしまうのを防ぐため**です。ビルドスクリプトが証明書を作成・インストールする
こともありません。

### 自己署名の証明書を使うと、再許可が要らなくなります

**ad-hoc署名のままだと、ビルドし直すたびに「入力監視」と「アクセシビリティ」を許可し直す
ことになります。** TCC がアプリの同一性を何で判断しているかを見ると理由が分かります。

```bash
codesign -d -r- /Applications/WKRMacOS.app
```

| 署名 | 表示される designated requirement |
| --- | --- |
| ad-hoc | `cdhash H"…"` |
| 証明書 | `identifier "io.github.yuhkis.wkr-macos" and certificate leaf = H"…"` |

ad-hoc は**バイナリのハッシュ**が条件なので、1行変えれば別のアプリになります。証明書で署名すると
条件から バイナリ由来の項目が消え、**再ビルドしても同じアプリとして扱われます。**

配布しないのであれば、Apple Developer Program は不要です。自己署名のコード署名証明書で足ります。

1. **キーチェーンアクセス.app** →「証明書アシスタント」→「証明書を作成…」
2. 名前を決める（例 `wkr-macos-local`）。この文字列を `CODESIGN_IDENTITY` に渡します
3. Identity Type は「**自己署名ルート**」、証明書のタイプは「**コード署名**」
4. 「デフォルトを無効化」にチェックし、有効期間を長めにする（既定は365日。切れると作り直しに
   なり、再許可が1回発生します）

```bash
env CODESIGN_IDENTITY=wkr-macos-local make app
```

`security find-identity -v -p codesigning` には `CSSMERR_TP_NOT_TRUSTED` として現れず有効一覧から
外れますが、**署名にも検証にも支障はありません。** 信頼設定を変える必要はありません。

**切り替えた回だけは再許可が必要です。** 署名方式が変わるためで、それ以降は不要になります。
他人へ渡せる `.app` を作りたくなったときは、Developer ID 署名と公証が要るので、そのときに
Apple Developer Program を検討してください。

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

初回は権限がないため、アプリは `permissions listen=false post=false` を記録して終了します。
`CGRequestListenEventAccess()` は許可を待たずに戻るので、これは設計どおりの fail closed です。

**`make start` はこれを見越して、アプリが起動したままになるまで自動で再試行します。**
コマンドを実行したまま、「システム設定」→「プライバシーとセキュリティ」で
**「入力監視」と「アクセシビリティ」の両方**を許可してください。許可した時点で次の再試行が成功し、
`Started: ...` を出して終わります。既定では最大5分待ち、5秒ごとに試します
（`WKR_START_TIMEOUT` と `WKR_START_RETRY_INTERVAL` で変更できます）。

再試行しているのは `Scripts/start-app.sh` です。アプリ側の「権限が無ければ即終了」という
安全規則はそのままにして、手作業の再起動だけをなくしています。1回ごとに新しいプロセスなので、
実行中のプロセスが権限の変化を見られるかどうかに依存しません。

**権限の要求は1回目の起動でだけ行います。** 毎回要求すると数秒おきに新しいダイアログが出て、
許可しようとしているスイッチが押せなくなるためです。2回目以降は、既に許可されているかどうかを
見るだけです。

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
`make start-installed` も許可されるまで自動で再試行するので、コマンドを実行したまま許可すれば
そのまま起動します。

> **配備後は `build/WKRMacOS.app` を起動しないでください。**
> 両者は Bundle ID が同じで ad-hoc 署名だけが違うため、`build/` 側に許可を与えると
> **`/Applications` 側の許可が外れます。** 2026-08-16 にこれで変換が止まりました
> （[verification.md](./verification.md)）。ログイン項目は `KeepAlive` が false なので
> 自動では復帰せず、`conversion-not-started reason=permissions` を残して終了します。
> 手を入れたビルドを実機で試すときは、`Scripts/install-app.sh` で `/Applications` へ
> 入れ替えてから `make start-installed` を使ってください。許可の付け替えが1回で済みます。

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

## 記号（`Y` レイヤー）の制約と無効化

`Y` 記号レイヤー55件と、`WJ → ヴ`、`T,` `T.` `T/` を合わせた59件は、ローマ字ではなく
Unicode を直接送っています。この経路には2つの制約があります。

- **その場で確定します。** 未確定文字列にならないので Space で変換し直せず、
  `英数` 連打の読み戻しも効きません。
- **未確定文字列があるときは送れません。** Apple日本語入力がイベントを捨てるためで、
  文の途中で記号を打っても何も起きません（2026-08-16 実測、[verification.md](./verification.md)）。

矢印4件（`Y` → `H` `J` `K` `L`）と `EY → ヶ`、`WU → ゐ`、`WI → ゑ`、`WY → ゎ` は
**ことえりのローマ字表にある綴りで送るので、この制約を受けません。** 文中でも動き、
Space 変換も `英数` 2回押しの読み戻しも効きます。

2つ目については、届かないと分かっている状態では**送らずにログへ残します**。

```
unicode-injection-skipped reason=pre-edit-open
```

このとき仮表示の `z` は消えるので、画面は記号を打つ前の状態に戻ります。**記号を入れたい
場合は、Enter で未確定文字列を確定してから打ち直してください。** Space は変換であって
確定ではないので、押しても状況は変わりません。

### `Y` レイヤーを無効にする

変換の余地なく確定してしまうのが困る場合、`Y` 記号レイヤー55件を丸ごと外せます。

```bash
make stop && make start-installed \
  INPUT_SOURCE_ID=com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese \
  INPUT_MODE_ID=com.apple.inputmethod.Japanese \
  MODE=prefix SYMBOL_LAYER=off
```

ユーザーデフォルトでも指定できます。フラグの方が優先されます。

```bash
defaults write io.github.yuhkis.wkr-macos SymbolLayer off
```

ログイン項目で使う場合は `Resources/io.github.yuhkis.wkr-macos.login.plist` に
`--symbol-layer` `off` を足して `make install-login-agent` し直すか、上のユーザーデフォルトを
書いてください。実際に使われた値は `conversion-started` の `symbol-layer=` に出ます。

**矢印4件は外れません。** ローマ字で送るので即確定せず、無効にする理由が当てはまらない
ためです。`Y` は矢印の前置キーとして残り、押すと仮表示の `z` が出ます。

外れるのは `Y` から始まる Unicode 出力55件だけです。`SY → しぇ`、`FY → ちぇ`、`EY → ヶ`
のように `Y` が2打鍵目の規則は行の派生なので残ります。

**この設定の意味づけはまだ確定していません。** `Y` キー自体を空けたい場合は矢印も外す形に
なりますが、まず `--symbol-layer on` の挙動を実機で固めてから判断します
（[roadmap.md](./roadmap.md)）。

## 英字への打ち直し

日本語入力モードのまま英単語を打ってしまったとき、`英数` キーの連打による読み戻しは
物理キー列ではなく wkr-macos が送った標準ローマ字を返します。`thing` のつもりで打った
`T` `H` `I` `N` `G` は `layunnh` になります。

**`英数` を素早く2回叩くと、`thing` に置き換わります。**

読み戻しに必要な `英数` の回数はアプリによって違います（2回のアプリも3回のアプリもあります）。
wkr-macos は回数を数えず、**連打が終わったことを合図に**動きます。必要なだけ叩いてください。
1回だけの `英数` は通常のモード切替のままで、何も起きません。

置き換えは連打が止まってから 0.25 秒後に走ります。

置き換えが起きない条件（design.md の 8.6）に当たると、何も起きません。Space で変換候補を
出した後、Backspace を押した後、記号（`Y` レイヤーや `ヴ`）を打った後、12打鍵を超えた後などです。
小書きの後置形や `EY → ヶ` のように取り消しを伴う規則は、2026-08-16 から対象に入っています。

### トリガキーを変える

`--english-fallback` か、同じ値を持つユーザーデフォルトで変更します。フラグの方が優先されます。

| 値 | 意味 |
| --- | --- |
| `eisu+eisu` | `英数` の連打が終わったときに置き換える（既定） |
| `eisu+return` | `英数` を押しながら Enter |
| `eisu+tab` | `英数` を押しながら Tab |
| `off` | 無効にする |

`eisu+return` と `eisu+tab` は待ち時間なしで発火しますが、**`英数` を押したまま別のキーへ
指を伸ばす必要があります。** 実際には Enter を押す時点で `英数` が離れていることが多く、
既定にはしていません。押しながらの Enter は、置き換えが起きなかった場合も前面アプリへ渡しません
（チャットアプリで意図しない送信をしないためです）。

```bash
defaults write io.github.yuhkis.wkr-macos EnglishFallbackTrigger off
```

書き換えた後は `make stop && make start …` で再起動してください。設定ウィンドウは
まだありません（[roadmap.md](./roadmap.md)）。実装されたら同じユーザーデフォルトを読み書きします。

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
| `unicode-injection-skipped reason=pre-edit-open` | 未確定文字列があったため記号を送りませんでした（下記） |

いずれも出ていなければ、変換ゲートは開いています。常駐しているかどうかは `pgrep WKRMacOS`
で確認できます。

`secure-event-input enabled=true` のまま戻らない場合は、パスワードマネージャのロック解除
ダイアログが開いたままになっていないか、ターミナルの Secure Keyboard Entry が有効になって
いないかを確認してください。**Secure Event Input はフィールド単位ではなくセッション全体に
効く**ため、前面が普通のテキスト欄でも止まったままになります。メニューバー表示が未実装で、
止まっていることが画面から分からない点は [roadmap.md](./roadmap.md) の課題です。

実測例は [verification.md](./verification.md) にあります。

Apple の案内: [Macで入力監視へのアクセスを制御する](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
