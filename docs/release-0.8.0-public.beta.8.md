# WKR macOS v2 Public Beta 0.8.0-public.beta.8

**[Apple Silicon用DMGをダウンロード](https://github.com/yuhkis/wkr-macos/releases/download/v0.8.0-public.beta.8/WKRPublic-0.8.0-public.beta.8-arm64.dmg)**。macOS 14以降、JISキーボード、Apple日本語入力（ローマ字入力・ひらがな）が対象です。Xcodeは不要です。

## 試し方

1. Releaseに添付されたDMGと `SHA256SUMS` を取得し、[導入手順](https://github.com/yuhkis/wkr-macos/blob/v0.8.0-public.beta.8/docs/distribution.md)に沿ってチェックサムを確認します。
2. DMGを開き、`WKRPublic.app` を「Applications」にドラッグして起動します。DMGとアプリはプロジェクトの自己署名証明書で署名しており、Appleの公証は受けていません。macOSに止められた場合は、導入手順に沿って各項目の起動を個別に許可してください。
3. アプリの案内から入力監視とキー送出を許可します。ひらがな入力に切り替えて `E K` を打ち、「き」と出れば変換できています。以前の版からの更新で許可が反映されない場合は、導入手順の旧版からの更新方法を参照してください。

## 主な変更

- 入力監視が変換中にタイムアウトした場合は、保留入力を破棄し、新しいプロセスで変換を再開します。一時停止中や復旧後60秒未満の再発時は終了します。macOS 27.2.1の実機で、タイムアウトから3.448秒後に別プロセスが再開し、テスト入力が再び「き」になることを1回確認しました。今回の物理打鍵は未検証です。[検証記録](https://github.com/yuhkis/wkr-macos/blob/v0.8.0-public.beta.8/docs/verification.md)
- 配列を2.0.0-beta.5に更新しました。171規則で、D＝た行、F＝な行、M＝ん、U＝っ、P＝や・拗音列、N＝いぇ・ぇ列です。[配列表](https://github.com/yuhkis/wkr-macos/blob/v0.8.0-public.beta.8/docs/layout-reference.md)
- 練習帳0.5.1を同梱しています。入力本文や打鍵順序を収集する研究用ログは含みません。任意の日別頻度集計と課題別成績は既定オフで、有効にした場合はMac内に保存します。
