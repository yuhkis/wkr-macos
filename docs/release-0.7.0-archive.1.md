# WKR macOS v1 — 0.7.0-archive.1（保存ソース）

[わから配列1.1.0の保存資料](https://github.com/yuhkis/wkr-layout/releases/tag/v1.1.0-archive.1)に対応する、WKR macOS 0.7.0を元にした保存用Releaseです。タグと保存版識別名は **v0.7.0-archive.1** です。

配列1.1.0の変換規則・変換Coreを保持し、個人記録を含む旧文書・コメントやGit履歴は収録していません。キーごとの状態・打鍵数・前面アプリ識別子のログを除き、保存版専用の設定・保存先と、Public v2と共通の二重起動防止を加えました。元のv0.7.0と同じ内容の再配布ではないため、保存版として区別しています。

## 入手するファイル

- `WKR-macOS-0.7.0-archive.1-source.zip`: v1用のソース、合成テスト、ビルド手順、ライセンス。
- `manifest.json`: 保存版・対応配列・ソースcommit・各ファイルSHA256。
- `SHA256SUMS`: 添付ファイルの検査用ハッシュ。

当時と同じソース配布で、ビルド済みapp・練習アプリは添付しません。v1のソースだけを取得する場合は上記zipを使ってください。GitHub自動生成の「Source code」はv2を含むリポジトリ全体です。

ビルドと起動・停止・設定削除は[保存版README](../Legacy/wkr-macos-v1/README.md)を参照してください。アプリ名は`WKRV1Archive.app`、設定・保存先の識別子は`io.github.yuhkis.wkr-macos.v1-archive`です。旧版やPrivateは先に終了してください。保存版を実機へ配備する操作は今回行っていません。

元のv0.7.0の変換テストに、旧設定・未対応CLI・排他制御の検査を加え、自動検証とビルドを行っています。この保存版での実機入力は未確認です。新しくv2を使う場合は[WKR macOS v2 Public Beta 0.8.0-public.beta.5](https://github.com/yuhkis/wkr-macos/releases/tag/v0.8.0-public.beta.5)を参照してください。
