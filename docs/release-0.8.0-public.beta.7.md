# WKR macOS Public 0.8.0-public.beta.7 — Release文案

配列2.0.0-beta.2の233規則を使います。2.0.0-beta.1で入れ替えていた ん・っ を、v1と同じ ん＝N、っ＝M に戻しました（[変更点](https://github.com/yuhkis/wkr-layout/blob/v2.0.0-beta.2/docs/compatibility.md#200-beta2-での変更)）。ほかの規則は2.0.0-beta.1と同じです。同梱の練習帳は0.2.1で、QWERTYで体験するモードとWKR・IMEでひらがなを入力するモードを備えます。既存の成績0.1.0は保持し、新しい採点方式とは保存先を分けます。

0.8.0-public.beta.6は配列2.0.0-beta.1で準備した未公開の候補です。公開せず、この番号は別の内容に使いません。

Apple Silicon / macOS 14以降向けのad-hoc署名・未公証ZIPです。利用者側のXcodeや有料のApple開発者登録は不要です。macOSの個別の起動許可が必要になる場合があります。ZIP・manifest.json・SHA256SUMSを組で配布し、入手元・ハッシュ・版を確認してください。

[導入・権限・練習・停止・削除](https://github.com/yuhkis/wkr-macos/blob/main/docs/distribution.md)を参照してください。入力本文・キー列・細かな時刻を保存する機能は含めません。任意の集約成績や日別頻度は既定オフ・ローカル保存です。

確認状況は[検証記録](https://github.com/yuhkis/wkr-macos/blob/main/docs/verification.md)に記載します。0.8.0-public.beta.6の候補では、Apple日本語入力で短いかな入力、Space候補、Enter確定、Backspace、一時停止・再開、終了後の通常入力と、同梱練習での入力・採点を画面共有のキー操作で確認しました。beta.7はその候補から配列と練習の教材データ・版の記載だけを変えたもので、同じ確認をbeta.7のZIPでやり直してから公開します。ダウンロード後の起動許可と物理打鍵は未確認です。Google日本語入力・azooKeyはWKRアプリの初回対応範囲に含めず、専用テーブルによる別の導入経路を案内します。Intel・他キーボード配列・全OS版・支援技術は未確認です。

この文書は公開前の候補です。添付ハッシュと最終検証結果を揃えてから公開します。
