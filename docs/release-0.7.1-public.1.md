# WKR macOS v1 0.7.1-public.1 — Release文案

配列1.1.0の公開済み規則を、現在の権限案内・一時停止・排他処理と組み合わせたv1用アプリです。0.7.0-archive.1の保存ソースは保持します。v2の教材は同梱しません。

Apple Silicon / macOS 14以降向けのad-hoc署名・未公証ZIPです。利用者側のXcodeや有料のApple開発者登録は不要です。macOSの個別の起動許可が必要になる場合があります。ZIP・manifest.json・SHA256SUMSを組で配布し、入手元・ハッシュ・版を確認してください。

[導入・権限・練習・停止・削除](https://github.com/yuhkis/wkr-macos/blob/main/docs/distribution.md)を参照してください。入力本文・キー列・細かな時刻を保存する機能は含めません。任意の日別頻度は既定オフ・ローカル保存です。

確認状況は[検証記録](https://github.com/yuhkis/wkr-macos/blob/main/docs/verification.md)に記載します。配布候補そのものを使い、Apple日本語入力でE Iから「きゅ」の入力、Space候補、Enter確定、Backspace、一時停止・再開、終了後の通常入力を確認しました。確認はmacOS 27.0 / Apple Siliconの画面共有によるキー操作です。権限設定直後の別セッションで入力監視のタイムアウトによる安全終了を1回確認しました。再起動後の短い確認では再発していませんが、原因と長時間利用時の再現性は未特定です。ダウンロード後の起動許可と物理打鍵は未確認です。Google日本語入力・azooKeyはWKRアプリの初回対応範囲に含めず、専用テーブルによる別の導入経路を案内します。Intel・他キーボード配列・全OS版・支援技術は未確認です。

この文書は公開前の候補です。添付ハッシュと最終検証結果を揃えてから公開します。
