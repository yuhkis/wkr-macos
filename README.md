# WKR macOS — わから配列 v2 Public Beta

Apple日本語入力の前段で、わから配列v2のキーを標準ローマ字に置き換えるmacOSアプリです。`W E R` + Enterで「わから」、`E K`で「き」と入力できます。かな漢字変換はApple日本語入力を使います。

**公開ベータ版: 0.8.0-public.beta.5 / 配列: 2.0.0-beta.1 / 練習: 0.1.0**。配列は233規則です。Pの短縮形はベータで評価中です。

[アプリzipとSHA256SUMS](https://github.com/yuhkis/wkr-macos/releases/tag/v0.8.0-public.beta.5)を公式Releaseから入手できます。

「Public Beta」は一般公開する試験版を表します。通常の製品名へ一律にPublicを付ける意味ではありません。正規のReleaseタグは `v0.8.0-public.beta.5` です。配布済みファイルとアプリ内の版表示は変更していません。

## 配列とアプリの対応

| 配列 | macOSアプリ |
| --- | --- |
| [2.0.0-beta.1](https://github.com/yuhkis/wkr-layout/releases/tag/v2.0.0-beta.1) | [v2 Public Beta 0.8.0-public.beta.5](https://github.com/yuhkis/wkr-macos/releases/tag/v0.8.0-public.beta.5) |
| [1.1.0 保存資料](https://github.com/yuhkis/wkr-layout/releases/tag/v1.1.0-archive.1) | [v1 0.7.0-archive.1 保存ソース](https://github.com/yuhkis/wkr-macos/releases/tag/v0.7.0-archive.1) |

v1保存版は[Legacy/wkr-macos-v1](Legacy/wkr-macos-v1/README.md)へ隔離しています。現行v2アプリはv1切替機能を持ちません。保存版の作成は`python3 Scripts/package-v1-archive.py`、固定ソースの検査は`python3 Scripts/check-v1-archive.py`です。[スクリプトの説明](Scripts/README.md)を参照してください。

## 初めて使う方へ

[導入・権限設定・停止・アンインストール](docs/install.md)の順に進めます。macOS 14以降、Apple日本語入力のローマ字入力・ひらがなモード、JISキーボードを対象とします。今回のローカル配布候補はApple Silicon用です。ソースからのビルドと、ad-hoc署名・未公証のアプリzipによる導入を用意します。Apple Developer Programへの加入を前提にせず、アプリzipではmacOSの個別の起動許可が必要になる場合があります。

起動すると権限不足や別のWKRの起動状態を案内します。変換中はメニューバーで一時停止・再開・終了できます。安全条件を失ったときは状態を捨てて停止します。入力ソースを自動で切り替えません。

メニューの「わから v2 を練習する」から、母音・行キーから短文へ進む練習帳を開けます。教材はアプリに同梱され、オフラインで使えます。`--practice-only`なら変換エンジンや入力権限を使わずに練習画面だけを開きます。ブラウザ版と同じ公開教材です。

## 記録とPublic / Private

入力本文・キー列・規則実行履歴・細かな時刻・2キー計測・規則ペア計測・RSft Enter推定補正は実装しません。旧設定や旧CLIで有効化する経路はありません。日別キー頻度は既定オフで、明示的な有効化時だけローカルに保存します。キーボードの図は論理キー集計の表示で、実際に打った機器を識別しません。機器別の集計はこのベータでは保留です。

練習成績も既定では保存しません。有効化時だけ課題別の完了回数・最高正答率をローカル保存し、画面から削除できます。[保存内容と境界](docs/public-beta.md)を参照してください。

Publicは `WKRPublic.app` / `io.github.yuhkis.wkr-macos.public` を使います。旧版・Privateのデータや設定を自動移行しません。[既存利用者の移行とPrivateへの引き継ぎ](docs/migration.md)を確認してください。

## 開発と検証

```sh
make test
make check-public
make app
make practice
make package
```

`make app`は専用の`build/WKRPublic.app`をad-hoc署名で作ります。証明書を自動選択せず、インストールや起動はしません。`make package`の出力先は`build/distribution/<アプリ版>/`です。公開対象はその版のzip・manifest.json・SHA256SUMSを明示します。配布時はad-hoc署名・未公証であることと初回起動手順を明記します。[配布方式と公開前の確認](docs/public-beta.md)を参照してください。

配列と教材の同期は `python3 Scripts/sync-layout.py --upstream ../wkr-layout --revision <commit>`、手順は[Scripts/README.md](Scripts/README.md)。`--check`で一致を検査し、取り込み日は同じpinの記録を保ちます。日付の明示指定には`--imported-on YYYY-MM-DD`を使います。純粋な変換処理は`WKRCore`へ集約し、Public/Privateで別の配列表を手書きしません。

- [配列とmacOS用綴り](docs/layout-reference.md)
- [仕組み](docs/how-it-works.md)・[設計](docs/design.md)・[開発時の確認](docs/development.md)
- [検証記録](docs/verification.md)・[残件](docs/roadmap.md)・[Release文案](docs/release-0.8.0-public.beta.5.md)
- [公開作業規約](AGENTS.md)

MIT License。配列と教材の正本は [wkr-layout](https://github.com/yuhkis/wkr-layout)。取り込んだcommitとファイルSHA256は `Resources/upstream-manifest.json` に記録します。

この公開ベータは、確認済みのソースだけから始めた独立履歴です。以前のリポジトリの履歴・PR・Releaseを引き継ぎません。[公開前監査](docs/publication-audit.md)で全ref・配布物と公開範囲を確認してから公開します。

公開作業を始めるときは `python3 Scripts/publication_guard.py install` で、このリポジトリだけのpush前ガードを設置します。接続先のrepository IDと監査済みの内容に対する承認が揃うまではpushを拒否します。[公開前監査](docs/publication-audit.md)に監査と承認記録の手順があります。
