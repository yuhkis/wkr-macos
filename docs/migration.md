# Public / Private と既存利用者の移行

| 項目 | 新Public | 旧公開版・従来のPrivate | 今後のPrivateで採用する契約 |
| --- | --- | --- | --- |
| アプリ | WKRPublic.app（WKR macOS Public） | WKRMacOS.app | WKRPrivate.app |
| Bundle ID / defaults | io.github.yuhkis.wkr-macos.public | io.github.yuhkis.wkr-macos | io.github.yuhkis.wkr-macos.private |
| Application Support | 同名の.publicフォルダ | 旧IDフォルダ | 同名の.privateフォルダ |
| ログイン起動 | .public.login | 旧ID.login | .private.login |
| 内容 | 変換・停止・権限案内・練習・任意の日別頻度 | 版によって研究機能を含む | 日常運用・研究・個人補正 |

右端はPrivateタスクへの設計上の引き継ぎであり、このPublic作業ではアプリの改名、配備、個人設定、既存データの移動を行っていません。既存データは旧フォルダに保持します。

## 旧版からPublicへ

1. 旧版の版、Bundle ID、起動方法、設定・データの保存先を確認し、必要な控えを取る。研究ログや旧設定全体をPublicへコピーしない。
2. 旧版のログイン起動を解除し、旧版を終了する。両機への変更はPrivateタスクで端末ごとに行う。
3. Publicを別名で導入し、新しいPublicの権限を許可する。TCC権限を自動移行しない。
4. Publicは初期状態で日別集計・練習保存ともオフ。必要な機能だけを本人が有効にする。キーマップは必要ならPublicのメニューから本人のローカルファイルを選ぶ。
5. TextEditで変換・Space・Enter・Backspace・停止を確認し、その後にPublicのログイン起動を任意で登録する。

旧版に戻す場合はPublicのログイン起動を解除し、Publicを終了してから旧版を起動します。Private側の元データをPublicの生成物で上書きしません。

## 同時変換を防ぐ契約

新しいPublicと、同じ契約を取り込んだPrivateは、利用者の一時領域の `wkr-converter-<uid>.lock` に非ブロッキングの排他ロックを取り、変換エンジンが終了するまで保持します。二つ目のエンジンは開始できません。別プロセスの通常終了・異常終了でもOSがロックを解放します。ロックファイルにキー・PID・履歴は保存しません。

Publicは旧Bundle ID・Public・Privateの起動状態も確認し、別版が稼働していれば開始せず、後から別版が起動した通知では安全側で終了します。ただし旧beta.28は共通ロックを知らないため、旧版を含む全起動順序の原子的な相互排他は提供できません。**旧版を終了して切り替える手順を必須とします。** Privateへの共通排他処理の反映はPrivate側の残件として扱い、Privateの改名・配備完了を初回Publicベータの公開条件にはしません。

`--practice-only`は変換エンジンを作らず、排他ロックや入力権限も使いません。Publicで変換しながら練習する場合は、通常起動中の練習メニューを使います。複数のPublicプロセスを並べる運用はせず、練習専用からPublic変換へ移るときは先に練習専用を終了します。旧版が稼働中でも練習専用画面だけを開けることは今回確認しました。

## Privateタスクへの引き継ぎ

- 稼働中の版と設定を再確認し、公開版の採番とPrivateの採番を分ける。
- `WKRCore`の公開版ピン・Publicとの排他ロックを取り込み、Private固有のロガーはPrivate内だけで維持する。
- 新しいPrivate ID / 保存先への移行対象を具体化し、既存データを保全してから実機へ反映する。
- 内蔵Enterの反転、RSft Enter推定補正、両機への配備・ログイン項目・TCC権限はPrivateで扱う。
- 各機で旧版を終了し、片方だけが変換すること、通常入力への復帰、スリープ復帰、練習の実IME入力を確認する。
