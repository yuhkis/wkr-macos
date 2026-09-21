# WKR macOS — わから配列 v1 / v2

Apple日本語入力の前段で、わから配列v2のキーを標準ローマ字に置き換えるmacOSアプリです。`W E R` + Enterで「わから」、`E K`で「き」と入力できます。かな漢字変換はApple日本語入力を使います。

**今回の配布候補: v1アプリ0.7.1-public.1 / v2アプリ0.8.0-public.beta.6 / 練習帳0.2.0**。配列はそれぞれ1.1.0 / 2.0.0-beta.1です。配列は233規則です。Pの短縮形はベータで評価中です。

公開済みbeta.5の[アプリzipとSHA256SUMS](https://github.com/yuhkis/wkr-macos/releases/tag/v0.8.0-public.beta.5)を公式Releaseから入手できます。

## 配列とアプリの対応

| 配列 | macOSアプリ |
| --- | --- |
| [2.0.0-beta.1](https://github.com/yuhkis/wkr-layout/releases/tag/v2.0.0-beta.1) | [Public 0.8.0-public.beta.5](https://github.com/yuhkis/wkr-macos/releases/tag/v0.8.0-public.beta.5) |
| [1.1.0 保存資料](https://github.com/yuhkis/wkr-layout/releases/tag/v1.1.0-archive.1) | [0.7.0 保存ソース](https://github.com/yuhkis/wkr-macos/releases/tag/v0.7.0-archive.1) |

新しい3製品の選び方・アプリ名・保存先は[アプリ配布の導入手順](docs/distribution.md)を参照してください。v1はWKRV1.app、v2はWKRPublic.app、v2練習帳はWakaraPractice.appです。新候補はローカル準備中で、公開済みの版とは別です。

v1保存版は[Legacy/wkr-macos-v1](Legacy/wkr-macos-v1/README.md)へ隔離しています。保存ソースを変更せず、公開済みv1規則を現在の共通変換処理に組み合わせたWKRV1.appを別に作ります。各アプリ内でv1/v2は切り替えません。保存版の作成は`python3 Scripts/package-v1-archive.py`、固定ソースの検査は`python3 Scripts/check-v1-archive.py`です。[スクリプトの説明](Scripts/README.md)を参照してください。

## 初めて使う方へ

[ダウンロード・権限設定・停止・アンインストール](docs/distribution.md)の順に進めます。macOS 14以降、Apple日本語入力のローマ字入力・ひらがなモード、JISキーボードを対象とします。今回のローカル配布候補はApple Silicon用です。ソースからのビルドと、ad-hoc署名・未公証のアプリzipによる導入を用意します。Apple Developer Programへの加入を前提にせず、アプリzipではmacOSの個別の起動許可が必要になる場合があります。

起動すると権限不足や別のWKRの起動状態を案内します。変換中はメニューバーで一時停止・再開・終了できます。安全条件を失ったときは状態を捨てて停止します。入力ソースを自動で切り替えません。

メニューの「わから v2 を練習する」から、母音・行キーから短文へ進む練習帳を開けます。教材はアプリに同梱され、オフラインで使えます。`--practice-only`なら変換エンジンや入力権限を使わずに練習画面だけを開きます。ブラウザ版・独立したWakaraPractice.appと同じ公開教材です。QWERTY体験はABC・英数で、導入済みWKRでの練習は「WKR・IMEで練習」で使います。

## 記録とPublic / Private

入力本文・キー列・規則実行履歴・細かな時刻・2キー計測・規則ペア計測・RSft Enter推定補正は実装しません。旧設定や旧CLIで有効化する経路はありません。日別キー頻度は既定オフで、明示的な有効化時だけローカルに保存します。キーボードの図は論理キー集計の表示で、実際に打った機器を識別しません。機器別の集計はこのベータでは保留です。

練習成績も既定では保存しません。有効化時だけ課題別の完了回数・最高正答率をローカル保存し、画面から削除できます。[保存内容と境界](docs/public-beta.md)を参照してください。

Publicは `WKRPublic.app` / `io.github.yuhkis.wkr-macos.public` を使います。旧版・Privateのデータや設定を自動移行しません。[既存利用者の移行とPrivateへの引き継ぎ](docs/migration.md)を確認してください。

## 開発と検証

```sh
make test
make test-v1
make check-public
make app
make app-v1
make practice-app
make package-all
```

`make app`は専用の`build/WKRPublic.app`をad-hoc署名で作ります。証明書を自動選択せず、インストールや起動はしません。`make app-v1`はWKRV1.app、`make practice-app`はWakaraPractice.appを作ります。`make package`はv2のみ、`make package-all`は3製品を`build/distribution/<アプリ版>/<commit>/`へ出力します。公開対象はその版のzip・manifest.json・SHA256SUMSを明示します。配布時はad-hoc署名・未公証であることと初回起動手順を明記します。[配布方式と公開前の確認](docs/public-beta.md)を参照してください。

配列と教材の同期は `python3 Scripts/sync-layout.py --upstream ../wkr-layout --revision <commit>`、手順は[Scripts/README.md](Scripts/README.md)。`--check`で一致を検査し、取り込み日は同じpinの記録を保ちます。日付の明示指定には`--imported-on YYYY-MM-DD`を使います。純粋な変換処理は`WKRCore`へ集約し、Public/Privateで別の配列表を手書きしません。

練習帳の表示・入力・採点は画面で確認済みです。v1 / v2の配布候補は、入力権限の再登録と許可後の変換確認が未完了のため配布を保留しています。

- [配列とmacOS用綴り](docs/layout-reference.md)
- [仕組み](docs/how-it-works.md)・[設計](docs/design.md)・[開発時の確認](docs/development.md)
- [検証記録](docs/verification.md)・[残件](docs/roadmap.md)・[v2 Release文案](docs/release-0.8.0-public.beta.6.md)・[v1](docs/release-0.7.1-public.1.md)・[練習帳](docs/release-practice-0.2.0.md)
- [公開作業規約](AGENTS.md)

MIT License。配列と教材の正本は [wkr-layout](https://github.com/yuhkis/wkr-layout)。取り込んだcommitとファイルSHA256は `Resources/upstream-manifest.json` に記録します。

この公開ベータは、確認済みのソースだけから始めた独立履歴です。以前のリポジトリの履歴・PR・Releaseを引き継ぎません。[公開前監査](docs/publication-audit.md)で全ref・配布物と公開範囲を確認してから公開します。

公開作業を始めるときは `python3 Scripts/publication_guard.py install` で、このリポジトリだけのpush前ガードを設置します。接続先のrepository IDと監査済みの内容に対する承認が揃うまではpushを拒否します。[公開前監査](docs/publication-audit.md)に監査と承認記録の手順があります。

## 個人情報を入れない継続設定

公開作業では毎回、専用Gitに `python3 Scripts/publication_guard.py install --repository-id ID` で検査を設置します。pre-commitは作業ファイルではなくstage済みの全ファイルと著者情報、commit-msgは本文を検査し、許可外メール・ローカルパス・秘密情報・私的記録を含むcommitを拒否します。既存のpre-pushも維持します。未設置・検査失敗・由来不明は公開停止とし、`--no-verify`やhookの無効化で回避しません。

`check-index` で同じ検査を手動実行できます。`check-assets --file PATH` は生成したZIP・本文を検査しますが、アップロード承認にはなりません。Pagesも `authorize --operation pages` と `check-upload --operation pages --file PATH` の対象です。アプリ・サイトは固定の収録リストから作り、実データ・個人設定・監査原記録をコピーしません。検出語はログへ出しません。自動検査に加えて出所と内容を確認し、未検出を「個人情報ゼロ」の証明とは扱いません。
