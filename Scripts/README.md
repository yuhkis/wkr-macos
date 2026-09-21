# 開発用コマンド

- `build-app.sh`: releaseビルドを`build/WKRPublic.app`へ組み立て、既定ad-hoc署名で検査する。ローカルパスをcompilerのprefix mapで除き、debug情報を生成せずに配布実行ファイルをstripする。インストールはしない。`CONFIGURATION`で構成、`CODESIGN_IDENTITY`で承認済みidentityだけを明示できる。
- `sync-layout.py --upstream PATH --revision COMMIT`: 公開`wkr-layout`の指定commitから規則と教材を許可リストで取り込む。`--check`は一致検査。`--imported-on YYYY-MM-DD`で取り込み日を指定でき、省略時は同じpinの記録済み日付（新規pinは当日）を使う。開発時だけ`--working-tree`を使えるが、この状態の配布zip作成は拒否する。
- `check-public.py`: Publicの実装に禁止された研究レコーダー・設定・CLI・橋渡しが入っていないこと、生成教材のハッシュと版、設定・保存先がPublic専用であることを検査する。全Git履歴の公開監査は別に必要。
- `package-public.py` / `make package`: cleanなcommitからアプリをビルドし、導入・移行・検証文書と参照先の公開作業規約をzipにする。`build/distribution/<アプリ版>/`へzip・manifest.json・SHA256SUMSを出力し、旧候補と分ける。公開時は確認した版の3ファイルを指定する。push、署名identity変更、公証、インストールはしない。
- `install-app.sh SOURCE [DEST]`: Public IDだけを許可し、既存の同名アプリを控えてからコピーする。実機での承認範囲内だけで使う。
- `start-app.sh APP [ARGS...]`: 指定Publicアプリを起動する。プロセスが存在しても変換中とは限らないため、メニューと権限・入力源を確認する。
- `install-login-agent.sh` / `uninstall-login-agent.sh`: Publicのログイン起動だけを登録・解除する。

ルートのMakefileに`test`、`check-public`、`app`、`practice`、`start`、`start-installed`、`stop`、`package`、日別集計用の操作をまとめる。`INPUT_SOURCE_ID` / `INPUT_MODE_ID`はApple日本語入力の既定ID、`MODE`はprefix。詳細は[導入](../docs/install.md)。

## 公開操作のガード

`publication_guard.py` はPython標準ライブラリとGitを使います。GitHubの接続先照合には認証済みの`gh`が必要です。新しい公開作業場だけに `python3 Scripts/publication_guard.py install` で設置します。global設定やPrivateの作業場には適用しません。

- `audit --report PATH [--file PATH ...]`: 全refの到達履歴、identity、許可パス、配布zip等を検査し、非公開の監査ファイルへfingerprintを保存します。
- `install --repository-id ID`: 確認した公開先の数値ID、履歴の基点、検査コードと方針をGit管理外へ固定し、pre-push hookを設定します。IDを省略した設置ではpushを止めたままにします。
- `authorize --report PATH --evidence PATH --operation push --ref refs/heads/codex/BRANCH [--file PATH ...]`: 同じ対象を再検査し、別途作成した内容確認・利用者承認の記録が揃った場合だけ24時間の承認記録を作ります。監査対象のファイルをすべて同じ`--file`で指定します。
- `check-upload --operation pr|release --file PATH`: 承認に含めたPR本文・Release本文・配布物が同一かを操作直前に検査します。`authorize`にも該当する`--operation`を追加します。アップロード自体は行いません。
- `python3 Scripts/test_publication_guard.py`: 実データを使わず、一時Git履歴とZIPで公開拒否条件を確認します。

履歴・ref・方針・配布物が変わると承認は無効です。方針や検査コードの変更後は、差分レビュー・監査・再設置が必要です。詳細と限界は[公開前監査](../docs/publication-audit.md)を参照してください。

## v1対応アプリの保存ソース

`python3 Scripts/check-v1-archive.py`は`Legacy/wkr-macos-v1/archive-source.json`の全ファイルSHA256と、詳細ログを残さない境界を検査します。`make -C Legacy/wkr-macos-v1 test`と`make -C Legacy/wkr-macos-v1 app`で保存版を検証・ビルドします。ビルドはad-hoc署名のみで、インストールや起動をしません。

`python3 Scripts/package-v1-archive.py`はcleanなcommitから、`build/distribution/0.7.0-archive.1/<commit>/`へソースzip・manifest・SHA256SUMSを作ります。出力対象は固定manifestのソースだけで、build・Git履歴・ローカル記録を含みません。既存の異なる配布物は上書きせず、保存ソースを変更する場合は保存版を上げます。

## 個人情報を入れない継続設定

公開作業では毎回、専用Gitに `python3 Scripts/publication_guard.py install --repository-id ID` で検査を設置します。pre-commitは作業ファイルではなくstage済みの全ファイルと著者情報、commit-msgは本文を検査し、許可外メール・ローカルパス・秘密情報・私的記録を含むcommitを拒否します。既存のpre-pushも維持します。未設置・検査失敗・由来不明は公開停止とし、`--no-verify`やhookの無効化で回避しません。

`check-index` で同じ検査を手動実行できます。`check-assets --file PATH` は生成したZIP・本文を検査しますが、アップロード承認にはなりません。Pagesも `authorize --operation pages` と `check-upload --operation pages --file PATH` の対象です。アプリ・サイトは固定の収録リストから作り、実データ・個人設定・監査原記録をコピーしません。検出語はログへ出しません。自動検査に加えて出所と内容を確認し、未検出を「個人情報ゼロ」の証明とは扱いません。
