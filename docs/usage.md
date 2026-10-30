# 入力と変換


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

## 方式文字の一覧

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
| `x` | eXecute | 行を外部コマンドか OpenAI に渡し、その結果で置き換える（`2x/` のように番号で設定を切り替え。[設定](settings.md)を参照）。設定がなければ `x/` を取り除くだけ |
| その他 | | 変換せず、普通にスペースを入力 |

Emacs 固有の `L`（Lisp 式の評価）と、egg で未定義の `g`（ギリシャ文字）は対応していません。

## Latin-1（`l`）

Emacs の `latin-1-postfix` と同じく、文字の後ろに記号を付けます。

| 書き方 | 文字 |
|---|---|
| `` a` `` `a'` `a^` `a~` `a"` | à á â ã ä（`e i o u y n` も同様。Latin-1 にある組み合わせのみ） |
| `c,` | ç |
| `a*` `e*` `o*` `d*` `t*` `s*` | å æ ø ð þ ß（`latin-1-postfix` の `/` の代わりに `*`。`/` は mlh の区切りのため） |
| `<<` `>>` `!*` `?*` | « » ¡ ¿ |

記号を 2 つ重ねると記号のまま残ります（`e''` → `e'`）。大文字も同様です（`` A` `` → À）。

## 候補選択モード（ユーザー辞書の候補が複数あるとき）

`mlh-select-mode-map` を再現しています。候補ウィンドウが表示されます。

| キー | 動作 |
|---|---|
| Space / Ctrl-F | 次の候補 |
| Backspace / Ctrl-B | 前の候補 |
| `/` | 確定（次の選択箇所へ） |
| Return / その他の印字可能文字 | 確定して、そのキーをあらためて処理 |
| その他（矢印キー、⌘ショートカットなど） | すべて確定してキーをアプリケーションへ |

すべての選択を確定した後、漢字変換が必要な場合は漢字変換モードに移ります。

## 漢字変換モード

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

## 制限事項

- **macOS でのカーソル直前のテキストの取得と置き換え**: アプリケーションによって次の 3 通りで動作します。

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
