# WKR macOS Public 0.8.0-public.beta.6 — Release文案

配列2.0.0-beta.1の233規則を使います。練習帳を0.2.0へ更新し、QWERTYで体験するモードとWKR・IMEでひらがなを入力するモードを同梱しました。既存の成績0.1.0は保持し、新しい採点方式とは保存先を分けます。

Apple Silicon / macOS 14以降向けのad-hoc署名・未公証ZIPです。利用者側のXcodeや有料のApple開発者登録は不要です。macOSの個別の起動許可が必要になる場合があります。ZIP・manifest.json・SHA256SUMSを組で配布し、入手元・ハッシュ・版を確認してください。

[導入・権限・練習・停止・削除](https://github.com/yuhkis/wkr-macos/blob/main/docs/distribution.md)を参照してください。入力本文・キー列・細かな時刻を保存する機能は含めません。任意の集約成績や日別頻度は既定オフ・ローカル保存です。

確認状況は[検証記録](https://github.com/yuhkis/wkr-macos/blob/main/docs/verification.md)に記載します。配布候補そのものを使い、Apple日本語入力で短いかな入力、Space候補、Enter確定、Backspace、一時停止・再開、終了後の通常入力を確認しました。同梱練習でも、このv2変換エンジンによる入力と確定・採点を確認しています。以前の許可登録との不一致は、対象候補の両権限を設定した後に復旧しました。確認はmacOS 27.0 / Apple Siliconの画面共有によるキー操作で、ダウンロード後の起動許可と物理打鍵は未確認です。Google日本語入力・azooKeyはWKRアプリの初回対応範囲に含めず、専用テーブルによる別の導入経路を案内します。Intel・他キーボード配列・全OS版・支援技術は未確認です。

この文書は公開前の候補です。添付ハッシュと最終検証結果を揃えてから公開します。
