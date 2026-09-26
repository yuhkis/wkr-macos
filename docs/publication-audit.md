# 公開前監査 — 独立履歴

初回候補は、確認済みの公開ソースだけから新しく始めたGit履歴です。配列・教材も同じ方針の独立した正本に固定しています。以前のリポジトリのGitオブジェクト、PR、tag、Release、artifact、Actionsを新しい公開先へ移しません。過去の履歴を残したまま削除commitを追加する方法は使いません。

## 公開する内容

製品のソース、合成テスト、配列・教材、導入・停止・削除の手順、再現条件と確認結果を公開します。個人の端末設定、日常利用の時系列、実打鍵集計、実キーマップ、入力本文、raw logは含めません。配布物に収録する文書も同じ基準で読み直します。

検証対象として選んだアプリ名と、テストコードが生成する値は用途を明示します。著作権表示・公開著者名・GitHubのアカウントとnoreply identityは残します。個人の連絡用メールとは区別し、「個人情報ゼロ」という表現は使いません。

## 初回候補の構成

macOSはREADME・LICENSE・除外規則だけの署名付き最小基点と、公開実装を加える署名付きbranchで構成します。新規のobject storeを使い、旧リポジトリとのalternates、共通の.git、remote設定は持ちません。配列・教材の固定commitは `Resources/upstream-manifest.json` に記録します。

全branch・tag・remote ref・PR refと到達可能なcommit / tag / tree / blobを列挙します。author / committer、commit本文、ファイル内容、LFS pointer、秘密情報・ローカルパス等の検査と、文書・fixtureの出所を読む確認を併用します。文字列検査の結果だけで公開可能と判断しません。監査の原記録はGit管理外に保存します。

新しい公開先を作成するまではremoteを設定しません。GitHub上に作成した後も、公開直前に対象repository IDと全ref、PR、Release、artifact、LFS、Actionsログを再確認します。CIを実行するとログが増えるため、その内容も公開判断に含めます。

## 配布物と公開操作

配布zipはcleanな署名付きcommitから生成し、全収録ファイル、同梱文書のリンク、アプリ内のローカルパス、展開後の署名を確認します。元commit、各版とSHA256はmanifestに記録し、古い候補と別の出力先へ保存します。原記録や監査の作業ファイルは収録しません。

対象branch・commit・配布物・監査結果を揃えてから、公開先の作成・push・PR・Releaseを最終確認します。macOSの実装はPRで追加し、CI `swift-test`成功後に署名付きcommitを保持するmerge commitで統合します。新規リポジトリに必要な最小基点の初回登録方法も承認対象です。

以前のリポジトリは別に保全し、アクセス管理を行います。新しい候補の準備や公開によって、第三者が既に取得したclone・cacheを回収したとは扱いません。

## 継続的な公開前ゲート

公開URLは従来の `https://github.com/yuhkis/wkr-macos` を使用します。旧repositoryはPrivateの別名で保全し、旧checkoutのremoteを保全先へ変更した後でURLを再利用します。URLの文字列だけで新旧を区別せず、数値repository IDを照合します。旧Git履歴・PR・Releaseを新しい公開先へ移しません。

1. 新しい公開作業場で `python3 Scripts/publication_guard.py install` を実行します。Git common directory内へ検査コードと基点を固定し、そのリポジトリのpre-push hookを設置します。接続先IDをまだ指定しなければ公開はできません。
2. 全refを列挙し、監査対象の新repositoryから全branch・tag・PR refを取得します。旧repositoryのrefは別の保全用Gitで確認します。`audit --report PATH --file PATH ...`で全到達履歴と配布物・PR/Release本文を検査します。報告はGit管理外に置きます。
3. 文書・コメント・fixtureの出所・commit/tagのidentityと署名・配布物を読み直します。GitHub上の全ref、PR本文・コメント、Releaseと添付、artifact、LFS、Actionsログも取得して確認します。該当物がなければ件数0を記録します。自動検査が通っただけで内容確認済みとは扱いません。
4. 利用者が対象・内容を承認した後に限り、監査報告の`fingerprint`と下記の各項目を`true`にした非公開JSONを作り、`authorize`へ渡します。`sources_and_comments`、`fixture_provenance`、`identities_and_messages`、`archive_contents`、`github_refs_prs_releases_artifacts_lfs_actions`、`user_authorized_operations`。未確認の項目を自動で埋めません。
5. push直前にhookが全対象を再検査し、指定したref・commit・接続先ID・24時間以内の承認記録と照合します。mainへの直接push、削除、別refへの付け替え、非fast-forward、tagの置換を拒否します。新しいcommit、ref、配布物や方針の変更後は再監査・再承認が必要です。
6. PR/Release本文や添付をAPIで送る直前にも`check-upload`を使います。公開後も毎回この手順を通します。CIは全到達履歴を再検査しますが、push後に走るため、公開前の検査を代替しません。

`.publication-policy.json`は公開を認めるパス、著者identity、独立履歴の基点を明記します。Gitの全履歴から削除済みのファイルも検査し、未許可パス、他の基点、個人メールやホームパス、秘密鍵/token形式、未監査LFS、symlink/submoduleを拒否します。配布zipの全エントリも走査します。エラーには検出した値を転載しません。

この仕組みは誤操作を止めるためのもので、未知の個人情報をすべて自動判定する保証ではありません。Git hookを外す操作、`--no-verify`、ブラウザやAPIへの直接投稿までは強制できません。これらの迂回は使わず、公開用素材だけを専用作業場へ置き、文章の内容確認と併用します。承認記録・元ログ・個人設定を公開Gitへ追加しません。

## 個人情報を入れない継続設定

公開作業では毎回、専用Gitに `python3 Scripts/publication_guard.py install --repository-id ID` で検査を設置します。pre-commitは作業ファイルではなくstage済みの全ファイルと著者情報、commit-msgは本文を検査し、許可外メール・ローカルパス・秘密情報・私的記録を含むcommitを拒否します。既存のpre-pushも維持します。未設置・検査失敗・由来不明は公開停止とし、`--no-verify`やhookの無効化で回避しません。

`check-index` で同じ検査を手動実行できます。`check-assets --file PATH` は生成したZIP・本文を検査しますが、アップロード承認にはなりません。Pagesも `authorize --operation pages` と `check-upload --operation pages --file PATH` の対象です。アプリ・サイトは固定の収録リストから作り、実データ・個人設定・監査原記録をコピーしません。検出語はログへ出しません。自動検査に加えて出所と内容を確認し、未検出を「個人情報ゼロ」の証明とは扱いません。
