# 公開前監査 — 独立履歴

初回候補は、確認済みの公開ソースだけから新しく始めたGit履歴です。配列・教材も同じ方針の独立した正本に固定しています。以前のリポジトリのGitオブジェクト、PR、tag、Release、artifact、Actionsを新しい公開先へ移しません。過去の履歴を残したまま削除commitを追加する方法は使いません。

## 公開する内容

製品のソース、合成テスト、配列・教材、導入・停止・削除の手順、再現条件と確認結果を公開します。個人の端末設定、日常利用の時系列、実打鍵集計、実キーマップ、入力本文、raw logは含めません。配布物に収録する文書も同じ基準で読み直します。

検証対象として選んだアプリ名と、テストコードが生成する値は用途を明示します。著作権表示・公開著者名・GitHubのアカウントとnoreply identityは残します。個人の連絡用メールとは区別し、「個人情報ゼロ」という表現は使いません。

## 初回候補の構成

macOSはREADME・LICENSE・除外規則だけの署名付き最小基点と、公開実装を加える署名付きbranchで構成します。新規のobject storeを使い、旧リポジトリとのalternates、共通の.git、remote設定は持ちません。配列・教材の固定commitは `Resources/upstream-manifest.json` に記録します。

全branch・tag・remote ref・PR refと到達可能なcommit / tag / tree / blobを列挙します。author / committer、commit本文、ファイル内容、LFS pointer、秘密情報・ローカルパス等の検査と、文書・fixtureの出所を読む確認を併用します。文字列検査の結果だけで公開可能と判断しません。監査の原記録はGit管理外に保存します。

公開準備中はremote未設定です。新リポジトリにはPR・Release・artifact・Actionsログがまだありません。GitHub上に作成した後も、公開直前に対象repository IDと全ref、PR、Release、artifact、LFS、Actionsログを再確認します。CIを実行するとログが増えるため、その内容も公開判断に含めます。

## 配布物と公開操作

配布zipはcleanな署名付きcommitから生成し、全収録ファイル、同梱文書のリンク、アプリ内のローカルパス、展開後の署名を確認します。元commit、各版とSHA256はmanifestに記録し、古い候補と別の出力先へ保存します。原記録や監査の作業ファイルは収録しません。

対象branch・commit・配布物・監査結果を揃えてから、公開先の作成・push・PR・Releaseを最終確認します。macOSの実装はPRで追加し、CI `swift-test`成功後に署名付きcommitを保持するmerge commitで統合します。新規リポジトリに必要な最小基点の初回登録方法も承認対象です。

以前のリポジトリは別に保全し、アクセス管理を行います。新しい候補の準備や公開によって、第三者が既に取得したclone・cacheを回収したとは扱いません。
