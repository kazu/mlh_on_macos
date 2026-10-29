# mlh for macOS — モードレス日本語入力

**mlh** は NIIBE Yutaka さんが 1990 年に NEmacs 用に作ったモードレスな変換ツールで、Mule の時代には
Egg・Canna・SJ3 と組み合わせて使われ、のちに Emacs の入力システム Egg（たまご）V4 に
egg-mlh.el (Modeless Conversion Facility) として取り込まれました。
本プロジェクトは egg-mlh.el の操作体系を、macOS の入力メソッド (InputMethodKit) として再現したものです。

- 「日本語モード」「英数モード」の切り替えはありません。入力メソッドは常に有効で、
  普段のキー入力はそのままアプリケーションに渡されます（ASCII がそのまま入力されます）。
- 直前に入力したローマ字などの末尾に `/` と変換方式を表す文字を付けて **スペース** を押すと、
  その場で（カーソル直前のテキストを遡って）変換します。
  例: `nihongo/` + Space → `日本語`（漢字変換モードに入ります）
- 漢字変換は Egg の変換モード（`egg-conversion-map`）のキー操作を再現しています。
  変換候補は端末内で動く azooKey (AzooKeyKanaKanjiConverter) から取得します。設定で
  Google の変換 API (Google CGI API for Japanese Input) に切り替えることもできます。
- **現在は日本語と Latin-1（`l` 方式）のみ対応しています。** Egg（たまご）は多言語の入力システムで、
  日本語のほかにも中国語（ピンイン・注音）、韓国語（ハングル）、タイ語、ギリシャ文字、アイヌ語のカナなど、
  多くの言語・文字を扱えました。それ以外の言語・文字への対応はこれからです。

Linux の Wayland 環境では、IBus を使って同じ操作で入力できます。ビルドと設定は
[Linux 版の手順](linux/README.md)を参照してください。

## 必要環境

- macOS 13 以降（開発・確認は macOS 15 / Apple Silicon）
- Command Line Tools for Xcode（Swift 6.1 以上の `swift` と `codesign`）。Xcode 本体は不要です。
- 初回のビルドでは SwiftPM が依存パッケージ（AzooKeyKanaKanjiConverter とその辞書など）を取得するため、
  ネットワーク接続が必要です。

## ビルドとインストール

```sh
make build      # build/mlh.app を作成（ad-hoc 署名済み）
make test       # Core のテストを実行
make install    # ~/Library/Input Methods/mlh.app に配置し、入力ソースとして登録・有効化
make uninstall  # ~/Library/Input Methods/mlh.app を削除
make clean      # build/ と .build/（SwiftPM の作業ディレクトリ）を削除
```

`make install` は実行中の mlh プロセスを終了し（`killall mlh`）、アプリを置き換えたうえで
`scripts/register.swift` で `TISRegisterInputSource` / `TISEnableInputSource` を呼び出します。

#### App Store 版のアプリ（Slack など）でも使う場合

サンドボックスで動く App Store 版のアプリからは、`~/Library/Input Methods` に置いた入力メソッドが
見えないことがあります（App Store 版 Slack では mlh に切り替えられず、ショートカットで切り替えると
Slack が落ちました）。その場合はシステム全体の場所に入れてください。

```sh
make install-system   # /Library/Input Methods/mlh.app に配置（sudo が必要）
```

初めて `/Library/Input Methods` に入れたときは、**一度ログアウトしてログインし直す**まで
システム設定の一覧に出てきません。以後の更新（`make install-system` の再実行）ではログアウトは不要です。
アクセシビリティの許可も `/Library/Input Methods/mlh.app` に対して追加し直してください。

### 入力ソースへの追加（初回のみ）

最近の macOS では、サードパーティの入力メソッドをプログラムから有効化しても反映されないため、
初回は手動で追加してください。

1. 「システム設定」→「キーボード」→「テキスト入力」の「入力ソース」の「編集…」を開く
2. 左下の「+」を押し、言語の一覧から「日本語」を選ぶ
3. 「mlh」を選んで「追加」
4. メニューバーの入力メニュー（`/␣` アイコン）から mlh を選択

一覧に出てこない場合は、システム設定を開き直すか、一度ログアウトして再ログインしてください。
mlh は常に ASCII がそのまま入る入力メソッドなので、普段から mlh を選んだままで使えます。

### アクセシビリティの許可

Ghostty などのターミナルや、Chrome・Discord・Slack・VS Code などの Chromium/Electron 系アプリでは、
元の文字列を消すためにバックスペースのキーイベントを合成します（後述の「制限事項」参照）。
このため「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で mlh を許可してください。

- 「+」のファイル選択では `~/Library` が隠れているので、⌘⇧G で `~/Library/Input Methods` を開くか、
  `open ~/Library/Input\ Methods` で開いた Finder から mlh.app を一覧へドラッグします。
- 署名が変わると許可が無効になります。ad-hoc 署名でビルドし直した場合は、一覧から mlh を「−」で
  削除して追加し直し、入力ソースを一度切り替えてください（固定の署名を使う方法は「署名」を参照）。

### 署名

ad-hoc 署名のままだと、ビルドし直すたびにアクセシビリティの許可が無効になります。
マシンごとに一度だけ自己署名のコード署名用 ID を作っておくと、以後の `make build` はその ID で署名し、
許可が保たれます。

```sh
make signing-identity   # ログインキーチェーンに "MLH Local Code Signing" を作成（openssl と security を使用）
```

初回の署名時に「codesign がキーチェーンのキーにアクセスしようとしています」と表示されたら、
パスワードを入力して「常に許可」を選んでください。ID がない場合は従来どおり ad-hoc 署名になります。
ID を作った直後の 1 回だけは署名が変わるので、アクセシビリティの許可を追加し直してください。

## 使い方

テキストはいつも通り ASCII で入力します。変換したい語の末尾に「方式文字 + `/`」を付けて
（漢字変換の場合は単に `/` を付けて）スペースを押します。スペースの直前の文字が `/` でない場合や、
変換対象がない場合は普通にスペースが入力されます。

```
watasiha/    + Space → 私は        （漢字変換モード）
ko-hi-k/     + Space → コーヒー
hiraganaf/   + Space → ひらがな
emacsc/      + Space → Emacs
unixp/       + Space → UNIX
3w/          + Space → 半角スペース 3 個
fullZ/       + Space → ｆｕｌｌ
3042j/       + Space → 安          （JIS コード 0x3042）
espan~oll/   + Space → español     （Latin-1）
and/orq/     + Space → and/or      （q/ を取り除くだけ。リテラルの "/" を残したいとき）
```

`/` で区切った複数の語は、後ろから前へ順に遡って一度に変換されます
（例: `Emacsc/de/nihongo/` → `Emacsでにほんご` となり、ここから先頭の語を含めて漢字変換）。
漢字変換の範囲は、遡った中で最初に変換された語の先頭からになります（egg の `henkan-begin`）。
ただし `f`（ひらがな）と `q` `X` はその直後から漢字変換の範囲を始めます。
英数字の語どうしの間には自動的に空白が挿入されます（`mlh-do-spacing`）。

### 方式文字の一覧

`/` の直前の文字で変換方式が決まります（`mlh-conversion-scheme-table`）。

| 文字 | 由来 | 変換 |
|---|---|---|
| `a` `i` `u` `e` `o` `n` `-` `,` `.` | (ローマ字の末尾) | ローマ字をひらがなにして **漢字変換**。方式文字自体も語の一部です（`nihongo/` の `o`） |
| `H` | Hiragana to kanji | 直前のひらがなを漢字変換 |
| `f` | (h)iragana | ローマ字 → ひらがな |
| `k` | Katakana | ローマ字 → カタカナ |
| `l` | Latin-1 | 後置記法で Latin-1 の文字に（`espan~oll/` → `español`、下記参照）。egg では未実装だった ligature の枠を使っています |
| `c` | Capitalize | 先頭を大文字に（`emacsc/` → `Emacs`） |
| `p` | uPcase | 大文字に（`unixp/` → `UNIX`） |
| `s` | Small letter | 変換しない（`s/` を取り除くだけ） |
| `Z` | Zenkaku | 全角英数記号に |
| `w` | White space | 直前の数字の個数だけ半角スペース（数字なしは 1 個） |
| `W` | zenkaku White space | 直前の数字の個数だけ全角スペース |
| `j` | Jis code | 直前の 4 桁の 16 進数を JIS X 0208 コードとして文字に |
| `d` | user Definition | ユーザー辞書で置換（候補が複数あれば選択モード。未登録なら `?udef?`） |
| `q` | Quit | ここで遡りを止める（`q/` を取り除く） |
| `X` | eXit | ここで遡りを止め、空白を 1 つ入れる |
| `x` | eXecute | 行を外部コマンドか OpenAI に渡し、その結果で置き換える（`2x/` のように番号で設定を切り替え。下記参照）。設定がなければ `x/` を取り除くだけ |
| その他 | | 変換せず、普通にスペースを入力 |

Emacs 固有の `L`（Lisp 式の評価）と、egg で未定義の `g`（ギリシャ文字）は対応していません。

### Latin-1（`l`）

Emacs の `latin-1-postfix` と同じく、文字の後ろに記号を付けます。

| 書き方 | 文字 |
|---|---|
| `` a` `` `a'` `a^` `a~` `a"` | à á â ã ä（`e i o u y n` も同様。Latin-1 にある組み合わせのみ） |
| `c,` | ç |
| `a*` `e*` `o*` `d*` `t*` `s*` | å æ ø ð þ ß（`latin-1-postfix` の `/` の代わりに `*`。`/` は mlh の区切りのため） |
| `<<` `>>` `!*` `?*` | « » ¡ ¿ |

記号を 2 つ重ねると記号のまま残ります（`e''` → `e'`）。大文字も同様です（`` A` `` → À）。

### 行の書き換え（`x`）

egg の `mlh-userdef-function` の代わりに、`x/` の直前の行全体（`x/` は除く）を
**外部コマンド** か **組み込みの OpenAI 呼び出し** に渡し、その結果で行を置き換えます。

- 実行中は行が未確定の状態で表示されます（OpenAI では返答が届いた分から順に表示）。
  Esc / Ctrl-G で中止できます（行はそのまま残ります）。
- 失敗した場合や 60 秒で終わらない場合は、ビープ音を鳴らして行をそのまま残します。
- `x` が働くのは、カーソル直前の語（最後の `x/`）の場合だけです。
- 出力に改行が含まれると、そのまま改行として入力されます（ターミナルではコマンドが実行されることがあります）。

どちらを使うかは次の設定で選びます。

```sh
defaults write com.github.kazu.inputmethod.mlh ExecuteBackend command   # 外部コマンド
defaults write com.github.kazu.inputmethod.mlh ExecuteBackend openai    # 組み込みの OpenAI
```

設定しない場合は、外部コマンドのファイルがあればそれを、なければ OpenAI の API キーがあれば OpenAI を使います。
どちらもなければ `x/` を取り除くだけです（egg と同じ）。

#### 番号付き（`2x/` など）

`x` の前に数字を付けると、`~/Library/Application Support/mlh/execute.json` のその番号の設定を使います
（`3w/` などと同じく、数字は方式文字の前に置きます）。番号も用途も自由に決められます。

```json
{
  "2": { "instructions": "Translate the user text into natural English. Reply with only the translation." },
  "5": { "model": "qwen/qwen3.5-35b-a3b", "reasoningEffort": "low" },
  "9": { "command": "~/bin/mlh-filter" }
}
```

- 使える項目: `instructions` `model` `baseURL` `reasoningEffort`（OpenAI）、`command`（外部コマンドのパス）、
  `backend`（`openai` / `command`）。書かなかった項目は `defaults` の設定（`OpenAIModel` など）が使われます。
- `command` があれば外部コマンド、なければ OpenAI を使います。
- ファイルは変換のたびに読み直すので、編集後に再起動は不要です。
- `execute.json` にない番号は変換せず、数字は文字のまま残ります（`version 3x/` → `version 3`）。

#### アプリごとの設定

`"apps"` の下に、入力先アプリのバンドル ID ごとの設定を書くと、そのアプリでだけ上書きされます。
書いていないアプリでは、これまでどおりの設定で動きます。

```json
{
  "2": { "instructions": "Translate into English." },
  "apps": {
    "com.tinyspeck.slackmacgap": {
      "instructions": "…くだけた口調の日本語に…",
      "2": { "instructions": "Translate into casual English." }
    },
    "com.apple.mail": { "instructions": "…丁寧なビジネス文に…" }
  }
}
```

- アプリの項目に直接書いた設定は `x/`（番号なし）に、番号の項目は `2x/` などに使われます
  （番号付きは、全体の `"2"` にアプリの `"2"` を重ねたものになります）。
- バンドル ID は `osascript -e 'id of app "Slack"'` で調べられます。

#### 外部コマンド

`~/Library/Application Support/mlh/execute` に実行可能ファイルを置きます。
行を標準入力に渡し、標準出力（末尾の改行は除く）で置き換えます。終了コードが 0 以外なら失敗です。
環境変数 `MLH_CLIENT_BUNDLE_ID` に入力先アプリのバンドル ID が入ります。

```sh
#!/bin/sh
# 例: 行を大文字にする
tr a-z A-Z
```

#### 組み込みの OpenAI

IME から直接 OpenAI の Chat Completions API を呼びます（シェルなどは経由しません。接続は使い回します）。
API キーはログインキーチェーンに保存します。

```sh
security add-generic-password -s mlh-openai -a "$USER" -w 'sk-...' \
  -T "$HOME/Library/Input Methods/mlh.app"
```

`-T` で mlh を許可しておくと、キーを読むときの確認ダイアログが出ません（`/Library/Input Methods` に
入れた場合はそちらのパスを指定）。付けなかった場合は、初回に出るダイアログで「常に許可」を選んでください。

`translate into English: 今日はいい天気x/` + Space で、行が翻訳結果に置き換わります。
次の設定で、モデル、指示（システムプロンプト）、接続先（OpenAI 互換のサーバー）を変えられます。

```sh
defaults write com.github.kazu.inputmethod.mlh OpenAIModel gpt-4o-mini
defaults write com.github.kazu.inputmethod.mlh OpenAIInstructions '...'
defaults write com.github.kazu.inputmethod.mlh OpenAIBaseURL https://api.openai.com/v1
defaults write com.github.kazu.inputmethod.mlh OpenAIReasoningEffort none   # 設定したときだけ reasoning_effort を送る
```

LM Studio や Ollama など、手元の OpenAI 互換サーバーも使えます。キーチェーンに API キーがなければ
認証なしで送ります（その場合は `ExecuteBackend` を `openai` に設定してください）。
思考（reasoning）をするモデルは返答までに時間がかかるので、`OpenAIReasoningEffort none` で
止めると速くなります（LM Studio の gemma-4-e2b で約 3 秒 → 0.2 秒）。

```sh
defaults write com.github.kazu.inputmethod.mlh ExecuteBackend openai
defaults write com.github.kazu.inputmethod.mlh OpenAIBaseURL http://192.168.0.10:1234/v1
defaults write com.github.kazu.inputmethod.mlh OpenAIModel google/gemma-4-e2b
defaults write com.github.kazu.inputmethod.mlh OpenAIReasoningEffort none
```

macOS 15 以降では、LAN 内のサーバーに初めて接続するときに「ローカルネットワーク」へのアクセスの
確認が出るので許可してください。エラーの内容はログ（後述）に記録されます。

### 候補選択モード（ユーザー辞書の候補が複数あるとき）

`mlh-select-mode-map` を再現しています。候補ウィンドウが表示されます。

| キー | 動作 |
|---|---|
| Space / Ctrl-F | 次の候補 |
| Backspace / Ctrl-B | 前の候補 |
| `/` | 確定（次の選択箇所へ） |
| Return / その他の印字可能文字 | 確定して、そのキーをあらためて処理 |
| その他（矢印キー、⌘ショートカットなど） | すべて確定してキーをアプリケーションへ |

すべての選択を確定した後、漢字変換が必要な場合は漢字変換モードに移ります。

### 漢字変換モード

`egg-conversion-map` を再現しています。変換中の文字列は文節ごとに下線で表示され、
現在の文節が強調されます。

| キー | 動作 |
|---|---|
| Space / Ctrl-N / ↓ | 次の候補 |
| Ctrl-P / ↑ | 前の候補 |
| Ctrl-F / → | 次の文節へ |
| Ctrl-B / ← | 前の文節へ |
| Ctrl-A / Ctrl-E | 最初 / 最後の文節へ |
| Ctrl-I (Tab) / Shift-← | 文節を縮める |
| Ctrl-O / Shift-→ | 文節を伸ばす |
| Return / Ctrl-M / Ctrl-L | 確定（改行は入りません） |
| Ctrl-G / Ctrl-C / Esc / Backspace | 変換を取り消し、読み（ひらがな）で確定 |
| 1〜9（候補ウィンドウ表示中） | 表示中のページの候補を選択 |
| その他の印字可能文字 | 確定して、そのキーを通常どおり入力 |
| ⌘ 付きのキー | 確定して、キーをアプリケーションへ |

Egg は通常候補一覧を表示しませんが、本実装では同じ文節で次／前の候補を一度でも選ぶと
候補ウィンドウ（1 ページ 9 件）を表示します。

### 漢字変換のエンジン

漢字変換の候補をどこから取るかは、`KanjiBackend` で選びます。

| `KanjiBackend` | エンジン |
|---|---|
| `azookey`（既定） | 端末内の [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter)。ネットワーク不要で、読みは外部に送信されません |
| `google` | Google の変換 API。固有名詞や新しい言葉に強い一方、ネットワーク接続が必要で、読みを Google に送信します |

```sh
defaults write com.github.kazu.inputmethod.mlh KanjiBackend -string google   # Google に切り替える
defaults delete com.github.kazu.inputmethod.mlh KanjiBackend                 # 既定（azooKey）に戻す
```

設定は次の変換から使われます（再起動は不要です）。azooKey の辞書（約 35MB）は
`mlh.app/Contents/Resources/Dictionary` に入っています。
文節は azooKey の品詞の情報から、自立語ごとに区切ります。

#### 文脈を使った変換（Zenzai）

azooKey のニューラル変換 Zenzai を使うと、変換する位置より前の文字列（同じ行の、すでに入力した部分）を
文脈として使って候補を選びます。mlh は `kisha/` のように短く区切って変換することが多いので、
文脈があると精度が大きく上がります（例: 「駅から」のあとの `kisha/` は「汽車」、「新聞社の」のあとでは「記者」）。

Zenzai は zenz という小さな言語モデルを llama.cpp で動かします。モデル（約 72MB）は同梱していないので、
一度ダウンロードしてください。モデルがあれば Zenzai を使い、なければ通常の azooKey で変換します。

```sh
make zenz-model   # ~/Library/Application Support/mlh/zenz.gguf にダウンロード
```

| 設定 | 既定 | 意味 |
|---|---|---|
| `ZenzaiModel` | `~/Library/Application Support/mlh/zenz.gguf` | モデルのパス |
| `ZenzaiContextLength` | 40 | 文脈として渡す文字数（0 で文脈なし） |
| `ZenzaiInferenceLimit` | 10 | 候補を評価し直す回数の上限 |

- ビルドは既定で CPU 版です。`MLH_ZENZAI=gpu make build` で GPU（Metal）版、`MLH_ZENZAI=off make build` で
  Zenzai なしになります。Zenzai を使うビルドは macOS 13.3 以降が必要です。
- 参考（Intel Mac mini、CPU 版、17 例）: 文脈 40 文字で全問正解、1 回の変換は平均 250ms 前後。
  Zenzai なしでは 7/17、1 回 10ms 前後でした。
- mlh の起動時に辞書とモデルを読み込みます（Intel Mac mini で約 0.5 秒）。


## ユーザー辞書

`d` 方式（`foo` + `d/`）で使う辞書（`mlh-userdef-table` 相当）です。

- 場所: `~/Library/Application Support/mlh/userdict.txt`
- 形式: UTF-8、1 行 1 エントリ、タブ区切りで `キー<TAB>候補1[<TAB>候補2...]`
- 空行と `#` で始まる行は無視されます。同じキーが複数回あると後の行が優先されます。
- キーに使える文字は英字と `-` です。
- 入力メソッドが有効になるたびに、ファイルの更新日時が変わっていれば読み直します。

```
# キー	候補...
addr	東京都千代田区千代田1-1
sig	--	山田太郎
date	2026年	令和8年
```

## プライバシーについて

漢字変換のエンジンを `google` にしたときは、変換対象の読み（ひらがな）を **Google のサーバー**
（`https://www.google.com/transliterate`）へ送信します。既定の `azookey` では送信しません。
漢字変換を行う方式（`a i u e o n - , .` と `H`）以外の変換は、すべて端末内で処理され、外部には送信されません。
ただし `x` 方式を使うと、行が外部コマンドに渡されるか、組み込みの OpenAI 呼び出しでは **OpenAI のサーバー** に送信されます。
この API は Google が無償で公開しているものですが、提供が予告なく変更・終了される可能性があります。
その場合、Google を使う漢字変換は読み（ひらがな・カタカナ）の候補だけになります（azooKey は影響を受けません）。
ログ（`log stream --predicate 'subsystem == "com.github.kazu.inputmethod.mlh"' --level debug`）には、
入力テキストはプライベート扱いでしか記録されません。

## 制限事項

- **カーソル直前のテキストの取得と置き換え**: アプリケーションによって次の 3 通りで動作します。

  | アプリケーション | 読み取り | 置き換え |
  |---|---|---|
  | Cocoa の標準的なアプリ（TextEdit、メモ、LINE など） | 文書アクセス API（`selectedRange` / `attributedSubstring(from:)`） | `replacementRange` 指定の `insertText` / `setMarkedText` |
  | Chromium/Electron 系（Chrome、Discord、Slack、VS Code など） | 文書アクセス API | バックスペースの合成で削除してから挿入 |
  | API に対応しないアプリ（Ghostty などのターミナル） | タイプ履歴 | バックスペースの合成で削除してから挿入 |

  - Chromium/Electron 系は文字列を読めても `replacementRange` を無視するため、アプリ内に
    `Electron Framework.framework` や Chrome 系のフレームワークがあるかで自動判定しています。
    判定を上書きするには、バンドル ID を指定して次のように設定します。
    ```sh
    defaults write com.github.kazu.inputmethod.mlh SyntheticDeletionApps -array com.example.app  # 合成バックスペースを使う
    defaults write com.github.kazu.inputmethod.mlh ReplacementRangeApps -array com.example.app   # replacementRange を使う
    ```
  - タイプ履歴は mlh を通して入力した文字だけを記録し、Return・矢印キー・マウスクリック・
    ⌘/Ctrl 付きのキーなどでリセットされます。カーソルを動かした後や貼り付けた文字列は変換できません。
  - バックスペースを合成する場合は、トリガーのスペースもいったんアプリに入力させ、元の文字列と一緒に
    消します（Ghostty などは IME が処理したスペースも入力してしまうため）。合成には
    アクセシビリティの許可が必要で、許可がない場合はビープ音を鳴らしてスペースを入力します。
- 漢字変換の範囲に英数字が含まれると、Google の変換 API では全角になることがあります。
- Google の変換 API を使う場合、漢字変換にはネットワーク接続が必要です。通信できない場合は読み（ひらがな）の
  まま変換モードに入ります。azooKey を使えばネットワークは不要です。
- 日本語と Latin-1 以外の言語・文字（Egg が対応していた中国語・韓国語・タイ語・ギリシャ文字など）は今後対応予定です。
- 一度に遡るのは現在行のカーソル直前、最大 1024 文字（UTF-16）までです。
- mlh を起動できない状態（入力ソースから外れた、など）のあいだに mlh を使おうとしたアプリは、
  mlh が直ったあとも、そのアプリを開き直すまで mlh に接続できません（キーが何も入らなくなります）。
- `L`（Lisp 式）には対応していません。`x` は Lisp 関数の代わりに外部コマンドか OpenAI を呼びます。

## ライセンス

本プロジェクト全体は **GNU General Public License version 2 またはそれ以降のバージョン
(GPL-2.0-or-later)** で配布します。全文はリポジトリ直下の [LICENSE](LICENSE) を参照してください。

`Sources/Core/MLHEngine.swift` は、Egg Input Method Architecture の一部である
**egg-mlh.el** を Swift に移植したものです。

- egg-mlh.el — Modeless Conversion Facility in Egg Input Method Architecture
- Copyright (C) 1999, 2000 Free Software Foundation, Inc
- Author: NIIBE Yutaka &lt;gniibe@fsij.org&gt;
- egg-mlh.el は GNU General Public License version 2 またはそれ以降のバージョンで配布されています。

本プロジェクトは egg-mlh.el の派生物であるため、同じ GPL-2.0-or-later を適用しています。

ビルドしたアプリには、次のものが含まれます（ライセンス文は `mlh.app/Contents/Resources/Licenses` にあります）。

- [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) — MIT License、Copyright (c) 2023 Miwa / Ensan
- [azooKey_dictionary_storage](https://github.com/azooKey/azooKey_dictionary_storage)（azooKey の辞書）— Apache License 2.0、Copyright 2024 Miwa / ensan
- [llama.cpp](https://github.com/ggml-org/llama.cpp)（Zenzai を使うビルドのみ）— MIT License、Copyright (c) 2023-2024 The ggml authors

Zenzai のモデル（[zenz-v3.1-small](https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf)）は CC BY-SA 4.0 で、
アプリには含まれず、`make zenz-model` で別にダウンロードします。

Apache License 2.0 は GPL version 3 とは両立しますが、version 2 とは両立しないとされています。
そのため、ビルドしたアプリを配布する場合は GPL version 3 の条件で配布してください。
