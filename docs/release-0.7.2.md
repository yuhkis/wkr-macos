# WKR macOS v1 0.7.2 — Release文案

未公開の配布候補です。配列1.1.0の保存規則を変更せず、公開v2と共通の変換・起動安全処理で動かします。起動時の権限待ちと最初のキー前の監視timeoutを有限の再試行で扱い、入力を扱った後の無効化は安全終了します。以前の未配布候補0.7.1-public.1の内容や番号は差し替えません。

Apple Silicon用DMG、macOS 14以降、Apple日本語入力です。DMGと中のアプリはv2と同じ自己署名証明書「WKR macOS Release」（SHA-1 `a0d1dd008c6e8a07de11dca7c2c79b43c926e000`）で署名した未公証のものです。v2の教材は同梱しません。設定と日別頻度はv1専用の保存先を使い、旧版・Privateから自動移行しません。他のWKR変換アプリを終了してから起動します。

[配列1.1の保存資料](https://github.com/yuhkis/wkr-layout/releases/tag/v1.1.0-archive.1)、[導入・停止・削除](https://github.com/yuhkis/wkr-macos/blob/main/docs/distribution.md)、[検証記録](https://github.com/yuhkis/wkr-macos/blob/main/docs/verification.md)を参照してください。今回のDMGでの日本語実入力・停止・再開・初回起動許可・更新・アンインストールは未確認です。

権限未許可・入力監視の未開始をメニューに明示し、メニューを開いただけで「変換中」と誤表示しないようにしました。監視開始前の一時停止操作は無効です。
