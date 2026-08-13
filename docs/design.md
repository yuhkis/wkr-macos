# 設計判断の記録

このドキュメントは wkr-macos で **何を採用し、何を採用しなかったか、その根拠** を記録します。
仕組みそのものの説明は [how-it-works.md](./how-it-works.md)、配列表と綴りは
[layout-reference.md](./layout-reference.md)、公開可能な検証結果は [verification.md](./verification.md) にあります。

## 1. 目的

JISキーボードの物理キー列を「わから配列」として解釈し、既存のApple日本語入力へ渡す。
中心となる要件は次のとおり。

- `E` を押した時点で「か」を扱える。
- 続けて `K` を押すと「き」になる。
- `E S K` は「か」→「かさ」→「かし」となる。
- `W K R` ではなく、`W E R` で「わから」となる。
- `かな` で有効、`英数` で無効になる。
- 最終的なかな列はApple日本語入力の未確定文字列としてSpace変換できる。

## 2. 非目的

- 独自のかな漢字変換エンジンを作ること。
- Apple日本語入力の私有APIや内部データへ依存すること。
- すべてのアプリ、リモートデスクトップ、ゲーム、仮想環境へ対応すること。
- App Store配布、自動更新、設定同期。
- 上流 `wkr-layout` の曖昧な記号規則を推測で確定すること。

## 3. 前提として確認したAPI

- `CGEventTap` は低レベル入力イベントを監視・フィルタできる。
- 現行SDKに `CGPreflightListenEventAccess`、`CGRequestListenEventAccess`、
  `CGPreflightPostEventAccess`、`CGRequestPostEventAccess` がある。
- JISキーコード `kVK_JIS_Eisu = 0x66`、`kVK_JIS_Kana = 0x68` が現行HIToolboxヘッダにある。
- TISには現在の入力ソース取得、入力ソース選択、選択変更通知がある。
- `IsSecureEventInputEnabled()` で、いずれかのプロセスがSecure Event Inputを有効にしているか確認できる。

一方、**外部プロセスからApple日本語入力の未確定文字列を直接編集する公開APIは確認できませんでした。**
これが、Unicode直接注入ではなく標準ローマ字の再送を主経路にしている理由です。

## 4. 変換モデル

### 4.1 正規化ルール

わから配列を、物理キー列からかな／記号出力へのTrieまたは有限状態トランスデューサとして表す。

各ノードは少なくとも次を持つ。

- `children`: 継続可能な物理キー。
- `output`: そのノード単独で成立する出力。
- `isAmbiguous`: 単独出力があり、かつ子ノードもあるか。
- `source`: 上流URL、revision、元規則。

入力処理は、未定義の次キーを捨てず、直前の成立出力を処理した後で同じキーをルートから再処理する。これにより `E S K` の `S` を失わない。

### 4.2 上流データの扱い

初期PoCではREADMEとテーブルの一致が明確なコアかな規則だけを正規化した。基本接続の成立後、同じrevisionからかな全行、小書き、特殊かな、JISで一意な記号行まで正規化範囲を拡大した。

2026-08-11の調査では、Google日本語入力用 `romantable.txt` とazooKey用TSVの記号領域に次の疑いが見つかった。

- `y`、`■x` の重複。
- `ば{` など区切りまたはキーの誤りらしい行。
- `{『`、`}』` の区切り欠落。
- 一部行への制御文字・置換文字混入。
- 記号の対応関係が2形式間で一致しない箇所。

したがって、生ファイルをそのまま実行時にロードしない。`WKRLayout.rules` をrevision固定の正規化スナップショットとし、かな14行、単打、小書き前置／後置、`T`レイヤー、JISで一意な`Y`記号レイヤーを222規則として置く。JIS括弧キーは2026-08-12にApple日本語入力への素通しへ変更し、規則から外した（5.3参照）。重複、制御文字、区切り欠落、JISで物理キーを一意に決められないANSI記号行は `WKRLayout.quarantinedUpstreamEntries` に隔離し、実行時Trieへ入れない。

## 5. 出力方式

### 5.1 deferred-romaji（安全方式）

曖昧な接頭辞は、継続しない次キーまたは確定操作が来るまで保留する。

例:

1. `E` を押す: 内部状態は「か」だが、まだ出力しない。
2. `K` を押す: `EK → き` が確定したため、Apple日本語入力へ標準ローマ字 `ki` を再送する。
3. `E` の次に `S` を押す: `E → か` を `ka` として再送し、`S` を新しい曖昧状態として保持する。
4. Spaceが来る: 保留中の出力を先に再送してからSpaceを通過させる。

利点:

- 外部の未確定文字列をBackspaceで書き換えない。
- 内部状態と対象アプリの状態がずれにくい。

欠点:

- あ段の見た目が原則1キー遅れる。
- 行末ではSpace、Enter、句読点、タイムアウト等のflush設計が必要。

タイムアウトによる自動flushは誤分岐を生み得るため、最初は境界キーによるflushだけで評価し、必要性を実測してから追加する。

境界キーは一律に扱わない。

- Space、Return、句読点、Tab、カーソル移動を入力中に検出した場合は、保留出力を現在の対象へ順序どおり送ってから原イベントを通す。
- 保留入力だけがあり画面へまだ出ていない状態でBackspaceを受けた場合は、Backspaceを消費して保留入力を取り消す。原イベントを通して既存本文を削除してはいけない。
- 入力ソース通知やアプリ切替通知を、切替後に初めて受けた場合は、別の対象へ誤送信せず保留状態を破棄する。
- Command / Control / Option付き操作、Escape、Undo/Redoは、「flushして通す」「破棄して通す」「保留分だけ消費する」の期待挙動をケースごとにテストで固定する。

### 5.2 optimistic-romaji（即時方式）

曖昧ノードの単独出力を、Apple日本語入力が受理する標準ローマ字として即時再送する。継続キーが来たら直前の仮出力をBackspaceで削除し、新しい標準ローマ字列を再送する。

例:

1. `E` を抑止して `k` `a` を合成送信し、「か」を表示する。
2. `K` を抑止してBackspaceを送り、`k` `i` を合成送信し、「き」に置き換える。

この方式はBackspaceの単位とIMEの状態に依存する。TextEditだけで成功しても既定化せず、NotesとSafariでも同じ結果になることを最低条件とする。prefix-romajiは取り消しが必要な枝を79件に限定し、多くの枝で仮かなの差し替えを避けるため、現在この方式は実験用途に留めている。

実装では削除回数をグローバル定数にせず、直前の仮出力を識別する正規化規則IDごとの `OptimisticDeletionProfile` とした。全行の単一かな仮出力はBackspace 1回、`X → ふぁ` は2回を実験値として設定する。`E → か` の1回削除はTextEdit・Notes・Safariで成立済みだが、他行と `X` は実測前なので `--allow-unverified-optimistic` がない起動は引き続き拒否する。削除プロファイルがない規則の置換は、原キーや既存本文を推測で削除せずfail closedで抑止する。同じ出力を確定する `EH → か` 等ではBackspaceも再送も行わず、内部の仮状態だけを確定する。

### 5.3 prefix-romaji（ちらつき抑制方式・2026-08-12追加、常用方式）

通常のローマ字入力に近い見え方で、1キー目から表示を出す方式である。共有接頭辞がある曖昧ノードでは、そのノードから到達し得る全ローマ字出力が共有する接頭辞の先頭1文字を送り、確定時に残りを送る。共有接頭辞がない一部ノードは自ノード出力または仮表示を先に流し、既知の継続枝ではBackspace 1回で取り消す。したがって取り消しをゼロにする方式ではなく、発生する枝を79件に固定している。

例:

1. `E` を押す: `か` 行の全出力 `ka` / `ki` / `ku` / `ke` / `ko` / `kya` / `kyu` / `kyo` が共有する `k` だけを送る。画面表示は `k`。
2. `K` を押す: `EK → き` が確定するので残りの `i` を送る。画面表示は `き`。
3. `E` の次に `R` を押す: 先に `E` の残り `a` を送って `か` を確定し、続けて `ら` 行の共有接頭辞 `r` を送る。画面表示は `かr`。
4. Enterが来る: 保留中の残り母音 `a` を先に送ってからEnterを通す。押鍵数は変わらず `わから` が確定する。

方針は「1キー目で必ず表示を出す」である。Trieの各ノードに、部分木の全ローマ字出力が共有する最長接頭辞と、実際に流す文字列を事前計算する。流す量は次の順で決める。

1. 共有接頭辞が空でなければ、その1文字目を流す。全枝を保護できるので取り消しが起きない。
2. 共有接頭辞が空でも、同じ1文字目で始まる出力が他にもあれば1文字目を流す。`X` 行の `ふぁ` / `ふぃ` / `ふゅ` / `ふぇ` / `ふぉ` は `f` を共有するため、`X` は `f` を流す。
3. その1文字目で始まる出力が自分だけなら、**自ノードの出力を全部流す**。1文字だけでは何も保護できず、かなも表示されないためである。`H → あ` と同じ即時表示を `U → や`、`I → ゆ`、`O → よ` でも得るのがこの規則で、唯一の枝である後置小書き `UT → ゃ` はBackspace 1回で取り消す。

ローマ字を1つも持たない `Y` 記号レイヤーは、`WKRLayout.symbolLayerProvisionalRomaji` で明示した1文字（現在は `y`）を仮表示に使い、記号が決まった時点でBackspace 1回で取り消す。確定文字である `■` 等を仮表示に使わないのは、記号が決まる前に本文を書き換えることになるためである。

取り消し数は**表示されている単位**で数える。`k` や `f` のような未合成のローマ字は1文字が1単位、`や` のように送出2文字がすでに1かなへ合成されている場合は1単位である。ノードごとに「流した文字列が自ノード出力そのものならかな数、そうでなければ文字数」を事前計算して保持する。optimisticのように規則IDごとの削除回数を人手で与えるのではなく、表から導出する。

分岐は2種類ある。

- 共有接頭辞に基づく分岐: 到達し得る全出力が同じ1文字目で始まるため、取り消しは発生しない。か行、さ行、た行、な行、は行、ま行、ら行、が行、ざ行、だ行、ば行、ぱ行、わ行、`T` 前置小書きが該当する。
- 自ノード出力に基づく分岐: 一部の枝が別の1文字目を持つため、その枝へ入るときだけ、自分が送った1文字をBackspace 1回で消してから正しい出力を送る。

取り消しが起きる規則は次の79件で、テストで集合として固定している。想定外の規則が取り消しを始めたらテストが落ちる。

- 後置小書き8件（`HT → ぁ` 等）: 先に出した母音1かなを置き換える。ここだけは1かなのちらつきが残る。前置形 `TH → ぁ` にはちらつきがない。
- `X` 行の4件（`XY → てゅ`、`XU → てぃ`、`XI → でゅ`、`XO → でぃ`）: 行内で `ふ` / `て` / `で` が混在するため、`ふぁ` 系の `f` だけを流す。
- Unicode出力8件（`EY → ヶ`、`WJ → ヴ`、`WU → ゐ`、`WI → ゑ`、`WY → ゎ`、`T,` / `T.` / `T/`）: ローマ字で継続できない。
- `Y` 記号レイヤー59件: 仮表示の `y` をBackspace 1回で取り消してからUnicodeを送る。

ローマ字出力規則については、送出ローマ字からBackspace分を差し引いた最終文字列が宣言ローマ字と一致することをテストしている。Unicode出力規則については、仮表示をちょうど取り消し、最後のactionが宣言Unicodeになることを別テストで固定している。

境界とキャンセルの扱いは次のとおりである。

- Space、Return、Shift+Return、Tab、句読点は、保留中の残りを先に送ってから原キーを通す。Shift+Returnは多くのアプリで改行なので、Returnと同じ確定扱いにする。Shift付き句読点（JISの `？` = Shift+/ など）も、未対応Shift組合せとして保留を捨てず、句読点と同じ確定扱いにする。
- Shift+英字のように配列へ割り当てのないShift組合せは、保留を捨てずに確定扱いにする。Apple日本語入力ではShift+英字が「英字」モードへの切替なので、`G` の後の `Shift+O` は `は` を確定してから `O` を通し、`はO` になる。以前は「未対応の修飾キー付き入力」として保留を捨てており、送出済みの `h` が取り残されて `hO` になっていた。
- 出力を持たないノード（`T` や `Y` の単独状態）でSpace等の境界キーを受けた場合、仮表示の文字は削除しない。画面に出したものをWKRが自発的に消さない方針をEscapeと揃える。明示的なBackspaceだけが取り消し操作である。
- Escapeを含むreset系イベントでは、WKRは内部状態だけを破棄し、合成イベントを一切送らない。未確定文字列はApple日本語入力の所有物であり、Escapeで消えるか残るかはIME側の仕様に従う。ライブ変換中に残る挙動が正しい可能性もあり、WKRが独自の削除を足すと素のローマ字入力と挙動が食い違うためである。Escapeの判定は修飾キーフィルタより前に置き、resetの理由がEscapeとして記録されるようにする。
- 保留状態を捨てるresetはnotice levelでログする。捨てられた保留は、送出済みローマ字が未確定表示に取り残される唯一の経路であり、原因の切り分けにはその理由が要るためである。
- Backspaceは送出済みローマ字ちょうどを消し、既存本文へ触れない。

この方式のために、行内で1文字目が割れていた綴りをApple日本語入力が受理する訓令式へ変更した（`ち`=`ti`、`ふ`=`hu`、`じ`=`zi` など）。小書きは実測に基づき `x` 系から `l` 系へ統一した。**かな自体は変更していない。** 変更の全一覧と実測の根拠は [layout-reference.md](./layout-reference.md) にある。

#### JIS括弧キーを横取りしない理由

`「` / `」` / `『` / `』` はUnicode直接注入で送ると即座に確定し、Spaceで `（` 等へ変換できなくなる。JIS括弧キーはApple日本語入力自身が同じ文字を未確定文字列として出せるため、規則から外して素通しし、`（` / `＜` と同じ変換体験に揃える。対象は `WKRLayout.passThroughKeys` に4件として明示し、どのモードでも素通しすること、保留中のかなは先に確定することをテストで固定している。

### 5.4 Unicode直接注入（特殊かな・記号のみ）

通常かなはApple日本語入力の未確定文字列とSpace変換を維持するため標準ローマ字で送る。Apple日本語入力で一意なローマ字表現を保証しにくい `ヶ` / `ヴ` / `ゐ` / `ゑ` / `ゎ` と、矢印等の記号だけは `CGEvent.keyboardSetUnicodeString` のマーカー付きイベントで送る。Unicodeイベントを無視するアプリがあり得るため、この経路はアプリ別の物理確認を必要とし、通常かなへは広げない。

### 5.5 InputMethodKit（ラッパー不成立時）

InputMethodKitなら `setMarkedText` 相当の経路で自前の未確定文字列を管理できる。ただし同時にApple日本語入力を動かし、その変換エンジンだけを公開APIで利用できるとは確認できていない。採用する場合は「独自IME＋別の変換エンジン」という別プロジェクト級の判断になる。

## 6. macOS側コンポーネント

### WKRCore

- 物理キーを論理キーへ正規化。
- JIS上のShift付き数字・括弧・記号を、許可済みの論理キーだけへ正規化。
- Trie/FSTの状態遷移。
- provisional / committed出力の計算。
- flush、cancel、未定義キー再処理。
- 文字列やイベントを記録しない診断用状態コード。

### EventTapController

- `.cgSessionEventTap`、`.headInsertEventTap`、active filterを第一候補とする。
- keyDown / keyUpの対応を保ち、変換したキーの原イベントを抑止する。
- 合成イベントへ固定マーカーを付け、再入を防ぐ。
- `.tapDisabledByTimeout` / `.tapDisabledByUserInput` では変換状態を破棄し、自動再有効化せずfail closedでプロセスを終了する。
- callbackでは同期I/Oや重い処理をしない。
- 保留出力をSpace／Return等より先に届ける必要がある場合は、callbackの `CGEventTapProxy` に対して `CGEventTapPostEvent` で合成イベントを挿入する。このAPIの「callbackがreturnする原イベントより先に入る」という順序を利用し、原keyDownと原keyUpはコピーせずそのまま通す。
- 変換して抑止したkeyDownだけ対応keyUpを抑止する。autorepeatはFSTへ再投入せず、抑止済みキーのrepeatだけを抑止する。

### InputSourceMonitor

- `kVK_JIS_Kana` と `kVK_JIS_Eisu` は原則通過させる。
- `kTISNotifySelectedKeyboardInputSourceChanged` を監視し、実際の入力ソースIDを真の状態とする。
- Apple日本語入力のローマ字入力・ひらがなモード以外ではevent tapをバイパスし、FSTをリセットする。source IDだけでなくmode IDも実機で選択中のTIS状態から取得し、両方の完全一致を必要とする。
- JIS `かな` / `英数` とアプリ切替では通知を待つ前に変換ゲートを閉じ、main run loopの次回処理でTIS状態を更新する。TIS通知の遅延やアプリごとの入力ソースにも備えて定期的に実状態を再照合する。
- 入力ソースを勝手に切り替えない。

### PermissionController

- listen/post accessを起動時と実行中にmain threadでpreflightする。
- 不足時は説明して要求し、許可されるまでは変換を開始しない。
- 許可が取り消されたら通常入力を妨げず停止する。
- 固定Bundle ID `io.github.yuhkis.wkr-macos` の `.app` を安定したパスへ生成する。署名は既定でad-hocとし、自分が保有する証明書を `CODESIGN_IDENTITY` で明示した場合だけそのidentityを使う。キーチェーンからは自動選択しない。ad-hoc署名では再ビルドごとに別identityとして扱われ得るため、権限再許可が必要になる場合がある。TCC確認をTerminalやビルドごとに変わる実行パスへ結び付けない。

### SafetyGate

- `IsSecureEventInputEnabled()` が真なら停止・リセットする。このAPIは現行SDKヘッダ上thread-safeではないため、event tap callbackで直接評価せず、main run loopのcommon mode Timerで確認する。
- Accessibilityからフォーカス要素がsecure text fieldと判定できる場合も停止。
- Command / Control / Option、対象外Shift、Fn、ナビゲーションキー、マウス、アプリ切替で規定どおりflush/cancelする。
- frontmost applicationと入力ソースが変わったら状態を持ち越さない。

## 7. 採否の記録（2026-08-11）

### 初期PoCで採用

- `WKRCore` はAppKit／Core Graphics非依存のTrie/FSTとし、上流revision `a8c102fa6dab6b7d7fdf9678ec9ce2e646facec8` から確認できたコアかな規則だけをコード内で正規化した。
- 既定出力はBackspaceを使わない `deferred-romaji` とした。
- 未定義の継続キーは直前の成立出力を処理した後、同じ物理キーをルートから再処理する。
- 合成出力は標準ローマ字の仮想キー列とし、Unicode直接注入経路は追加しなかった。
- 実入力ソースのsource IDとmode IDは `--print-input-source` で現在のTISソースから取得し、起動引数で明示した2値との完全一致だけを有効条件にした。Apple日本語入力らしい文字列を推測する判定は入れていない。
- `IsSecureEventInputEnabled()` はmain run loopのcommon mode Timer上で定期確認し、event tap callbackは共有済みのbooleanだけを参照する。JIS切替とアプリ切替の瞬間は先にcontextをinvalidにしてfail closedにする。
- 合成イベントは `CGEventTapPostEvent` で同じtap位置に挿入し、Space／Return等の原イベントはコピーせず通す方式へ固定した。
- 実行中の権限喪失、tap disable、合成イベント生成失敗は通常入力を失わせないため常駐プロセス終了とした。多重起動も拒否する。
- 固定Bundle ID `io.github.yuhkis.wkr-macos`、`LSUIElement=true`、固定出力先 `build/WKRMacOS.app` を採用した。署名identityを明示した場合とad-hoc署名の両方を検証対象とする。

### 後続の判断

- `optimistic-romaji` はdeferredと同じTrieを共有し、規則ID別削除プロファイルで実装した。`E` / `EK` の基本動作は実測済みだが、全配列は明示的な確認フラグを必要とし、まだ既定化しない。
- その後、Unicode直接注入は特殊かな・記号に限定して採用し、通常かなには使わない。

### 全配列拡張（2026-08-11）

- 上流 `wkr-layout` の最新commitが引き続き `a8c102fa6dab6b7d7fdf9678ec9ce2e646facec8` であることをGitHub APIで再確認し、同日のScrapbox本文とも照合した。
- `WKRLayout.rules` に219件を収録した。14子音行、11単打、前置／後置小書き、`T`句読点、特殊かな、JIS括弧、JISで一意な`Y`記号を含む。
- 全219入力が重複せず、deferredで宣言済みactionを1件だけ生成することをテーブル駆動テストで固定した。
- event tapはShiftを一律拒否せず、JIS記号表に明示したShift付きキーだけを論理キー化する。Command／Control／Option、未対応Shift、Caps Lock、Fnは従来どおりバイパスして状態を破棄する。
- Google表・azooKey表の破損または競合行は隔離した。上流修正なしに `〒`、`≥`、壊れた`?`行、ANSI quote競合を推測実装しない。

### 現在の判定

`WKRLayout.rules` は222件、`swift test` は34件で全て成功する。常用方式は prefix-romaji で、
実機では `/Applications` へ配備した bundle をログイン時起動して日常入力に使用している。
かな全行、訓令式綴り、Unicode経路、取り消し枝の代表列はTextEditで実機確認済み。
`E` / `EK` の基本動作はTextEdit・Notes・Safari・ChatGPT入力欄で確認済み。
**記号レイヤー59件は2026-08-13に実機確認済み。アプリ別の網羅的な互換性確認は未完了。**

## 8. 公式資料

- [CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)
- [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)
- [CGEvent.keyboardSetUnicodeString](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29)
- [IMKInputController](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller)
- [NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [CGPreflightListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29)
- [CGPreflightPostEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess%28%29)
- [NSTextInputContext.keyboardSelectionDidChangeNotification](https://developer.apple.com/documentation/appkit/nstextinputcontext/keyboardselectiondidchangenotification)
- [Secure Event Input (TN2150)](https://developer.apple.com/library/archive/technotes/tn2150/)
- [Apple Developer Forums: ad-hoc署名とTCC identity](https://developer.apple.com/forums/thread/819406)
- [Macで入力監視へのアクセスを制御する](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
