# WKR macOS v2 Public Beta の構成と公開ゲート

## 製品名と公開段階

通常の製品名は「WKR macOS v1」「WKR macOS v2」、練習帳は「わから配列 練習帳」です。一般公開の試験版には「Public Beta」を付け、開発用の別製品は「Private」と明示します。通常版・保存版・練習帳へ一律にPublicを付けません。既存アプリのBundle ID・設定・保存先の分離は表示名と独立して保持します。

「Public Beta」は一般公開する試験版を表します。通常の製品名へ一律にPublicを付ける意味ではありません。正規のReleaseタグは `v0.8.0-public.beta.5` です。配布済みファイルとアプリ内の版表示は変更していません。

`beta` は公開範囲を指定しないベータ版、`public.beta` は一般公開のベータ版を表します。番号が同じでも同一版とは扱わず、公開済みの版に意味の異なる別名タグを追加しません。

## 採用する構成

- 配列2.0.0-beta.1: `wkr-layout`の233規則JSONが正本。macOSの綴りもそのJSONのdeliveryから生成。
- macOS 0.8.0-public.beta.5: 確認済みの公開ソースから独立した履歴で管理する。`public.beta` は一般公開の試験版を表す。ビルド番号45。以前の候補と配布物の内容を区別する。
- 練習0.1.0: `wkr-layout/practice`が正本。同じHTML / JS / CSS / data.jsをアプリへ同梱し、固定commitとハッシュを記録する。
- Public / Privateの変換ロジックは`WKRCore`へ集約する。研究用の変更はこの公開branchへmergeしない。Privateへは公開されたCoreと同じ排他処理を選択して反映する。

## 入力と保存の境界

公開用に確認したソースだけを収録する。配列の値と、変換に必要なShift+/対応・句読点後の英字打ち直しの安全修正を含む。規則の完了ID列や研究用のレコーダー、旧リポジトリの履歴は収録しない。

`DetailedLog`、`KeyPairTiming`、`RulePairCount`、`ShiftEnterAttribution`、`PracticePagePath`、Privateの練習ログ橋渡しは読み取る実装を持たない。未対応の長いCLIオプションは起動前に拒否する。入力ごとのstateログも出さず、通常ログは起動・権限・安全停止・保存処理の成否へ絞る。

日別集計は明示的に有効化した場合だけ、論理キーごとの回数を暦日単位で保存する。キーボード別集計は初回ベータでは見送る。接続分類は打鍵元の同定ではなく、誤解しない表示とデータ移行の検証が必要なため。機器情報自体を収集するコードを含めない。

練習では課題ID・完了回数・最高正答率・配列版だけを明示的保存の対象にする。ブラウザはlocalStorage、同梱版はPublic専用 `practice-progress.json`（0600）。時刻・所要時間・誤入力・キー列・行別の成績は保存しない。同梱版の読み込めない既存成績は上書きせず、利用者が削除を選べる。同梱WKWebViewは非永続、同梱ページだけを読み、HTTP(S)通信と任意ページへの遷移を拒否する。

## 年会費を前提にしない配布

公開ベータは、ソースビルドとad-hoc署名・未公証のアプリzipを候補にする。Apple Developer Programの会費やDeveloper ID取得を公開条件にしない。どの添付物を公開するかは、検証結果を添えて公開承認時に確定する。

既定ビルドはad-hoc署名で、`codesign --verify --deep --strict`で構造を検査する。Developer IDによる発行者確認やApple公証ではなく、ダウンロード後の初回起動にmacOSの個別許可が必要になる場合がある。配布物名・Release本文にこの状態を明記し、[導入文書](install.md)でApple公式の個別起動許可手順を案内する。Gatekeeper全体の無効化は求めない。

将来、Developer ID署名・公証済みの配布へ変える場合に限り、利用者が承認したidentity、hardened runtime、公証成功、staple、Gatekeeperの既定評価を確認する。これは今回の無償配布の必須条件ではない。[Appleの配布方法](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)を参照。

今回の候補はDeveloper ID署名・公証を行わない。配布物名と検証記録にad-hoc署名・未公証を明記する。開発環境の証明書一覧や個人の署名設定は公開資料に含めない。

## 公開前

全公開refと到達可能な全履歴、PR ref、Release本文・添付、artifact、LFS、Actionsログを監査する。初回候補はremoteのない新規リポジトリの最小基点と実装branchから構成し、以前のGitオブジェクトを共有しない。旧履歴の保全・アクセス管理と、新候補の公開判定は別に記録する。新しいGitHubリポジトリを使い、旧リポジトリのPR・Release・Actionsを移さない。

ローカルcommitと配布候補・ハッシュ・Release文案・検証結果が揃ってから、push / PR / Releaseの承認を得る。WKR macOSはbranchとPRを使い、CI `swift-test`成功後、署名付きcommitを残すmerge commitで統合する。mainへの直接push・force pushはしない。空の新規リポジトリにはPRの比較先がないため、初回の最小基点の登録方法も公開操作案に明示して承認を得る。実装をPRなしでmainへ載せない。

配布zipを展開したアプリの `codesign --verify --deep --strict` は成功しました。`stapler validate` は公証チケットなし、`spctl --assess --type execute` は rejected でした。これは未公証候補の既定評価の記録です。公開可否は、この評価だけで決めず、未公証であることの表示、個別起動許可の手順、確認した範囲を含めて判断します。


## ベータの実機確認範囲

利用者の選択により、実機1台でPublic版の「初回起動・必要な権限」「短い日本語入力」「終了後の通常入力」を軽く確認する。旧WKRを先に終了し、既存アプリ・設定を保持して切り戻せるようにする。別のMac、複数OS、専用ユーザー、長時間運用、Privateの改名・保存先移行を初回ベータ公開の必須条件にはしない。未実施の項目は検証記録へ残す。アプリzipを配布する場合のダウンロード後の起動経路も、ローカルビルドの確認と区別する。
