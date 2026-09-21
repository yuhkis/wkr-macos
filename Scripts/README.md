# 開発用コマンド

- `build-app.sh`: releaseビルドを`build/WKRPublic.app`へ組み立て、既定ad-hoc署名で検査する。ローカルパスをcompilerのprefix mapで除き、debug情報を生成せずに配布実行ファイルをstripする。インストールはしない。`CONFIGURATION`で構成、`CODESIGN_IDENTITY`で承認済みidentityだけを明示できる。
- `sync-layout.py --upstream PATH --revision COMMIT`: 公開`wkr-layout`の指定commitから規則と教材を許可リストで取り込む。`--check`は一致検査。`--imported-on YYYY-MM-DD`で取り込み日を指定でき、省略時は同じpinの記録済み日付（新規pinは当日）を使う。開発時だけ`--working-tree`を使えるが、この状態の配布zip作成は拒否する。
- `check-public.py`: Publicの実装に禁止された研究レコーダー・設定・CLI・橋渡しが入っていないこと、生成教材のハッシュと版、設定・保存先がPublic専用であることを検査する。全Git履歴の公開監査は別に必要。
- `package-public.py` / `make package`: cleanなcommitからアプリをビルドし、導入・移行・検証文書と参照先の公開作業規約をzipにする。`build/distribution/<アプリ版>/`へzip・manifest.json・SHA256SUMSを出力し、旧候補と分ける。公開時は確認した版の3ファイルを指定する。push、署名identity変更、公証、インストールはしない。
- `install-app.sh SOURCE [DEST]`: Public IDだけを許可し、既存の同名アプリを控えてからコピーする。実機での承認範囲内だけで使う。
- `start-app.sh APP [ARGS...]`: 指定Publicアプリを起動する。プロセスが存在しても変換中とは限らないため、メニューと権限・入力源を確認する。
- `install-login-agent.sh` / `uninstall-login-agent.sh`: Publicのログイン起動だけを登録・解除する。

ルートのMakefileに`test`、`check-public`、`app`、`practice`、`start`、`start-installed`、`stop`、`package`、日別集計用の操作をまとめる。`INPUT_SOURCE_ID` / `INPUT_MODE_ID`はApple日本語入力の既定ID、`MODE`はprefix。詳細は[導入](../docs/install.md)。
