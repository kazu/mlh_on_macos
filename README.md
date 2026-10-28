# MLH for macOS — モードレス日本語入力

Emacs の Egg に含まれる **mlh (egg-mlh.el, Modeless Conversion Facility)** の操作体系を、
macOS の入力メソッド (InputMethodKit) として再現したものです。

- 「日本語モード」「英数モード」の切り替えはありません。入力メソッドは常に有効で、
  普段のキー入力はそのままアプリケーションに渡されます（ASCII がそのまま入力されます）。
- 直前に入力したローマ字などの末尾に `/` と変換方式を表す文字を付けて **スペース** を押すと、
  その場で（カーソル直前のテキストを遡って）変換します。
  例: `nihongo/` + Space → `日本語`（漢字変換モードに入ります）
- 漢字変換は Egg の変換モード（`egg-conversion-map`）のキー操作を再現しています。
  変換候補は Google の変換 API (Google CGI API for Japanese Input) から取得します。
- **現在は日本語のみ対応しています。** Egg（たまご）は Wnn・Canna・sj3・Anthy などの変換サーバーを
  使い分ける多言語の入力システムで、中国語や韓国語も扱えました。日本語以外の言語への対応はこれからです。

## 必要環境

- macOS 13 以降（開発・確認は macOS 15 / Apple Silicon）
- Command Line Tools for Xcode（`swiftc`, `swift`, `codesign`）。Xcode 本体は不要です。

## ビルドとインストール

```sh
make build      # build/MLH.app を作成（ad-hoc 署名済み）
make test       # Core のテストを実行
make install    # ~/Library/Input Methods/MLH.app に配置し、入力ソースとして登録・有効化
make uninstall  # ~/Library/Input Methods/MLH.app を削除
make clean      # build/ を削除
```

`make install` は実行中の MLH プロセスを終了し（`killall MLH`）、アプリを置き換えたうえで
`scripts/register.swift` で `TISRegisterInputSource` / `TISEnableInputSource` を呼び出します。

#### App Store 版のアプリ（Slack など）でも使う場合

サンドボックスで動く App Store 版のアプリからは、`~/Library/Input Methods` に置いた入力メソッドが
見えないことがあります（App Store 版 Slack では MLH に切り替えられず、ショートカットで切り替えると
Slack が落ちました）。その場合はシステム全体の場所に入れてください。

```sh
make install-system   # /Library/Input Methods/MLH.app に配置（sudo が必要）
```

初めて `/Library/Input Methods` に入れたときは、**一度ログアウトしてログインし直す**まで
システム設定の一覧に出てきません。以後の更新（`make install-system` の再実行）ではログアウトは不要です。
アクセシビリティの許可も `/Library/Input Methods/MLH.app` に対して追加し直してください。

### 入力ソースへの追加（初回のみ）

最近の macOS では、サードパーティの入力メソッドをプログラムから有効化しても反映されないため、
初回は手動で追加してください。

1. 「システム設定」→「キーボード」→「テキスト入力」の「入力ソース」の「編集…」を開く
2. 左下の「+」を押し、言語の一覧から「日本語」を選ぶ
3. 「MLH」を選んで「追加」
4. メニューバーの入力メニュー（`m/` アイコン）から MLH を選択

一覧に出てこない場合は、システム設定を開き直すか、一度ログアウトして再ログインしてください。
MLH は常に ASCII がそのまま入る入力メソッドなので、普段から MLH を選んだままで使えます。

### アクセシビリティの許可

Ghostty などのターミナルや、Chrome・Discord・Slack・VS Code などの Chromium/Electron 系アプリでは、
元の文字列を消すためにバックスペースのキーイベントを合成します（後述の「制限事項」参照）。
このため「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で MLH を許可してください。

- 「+」のファイル選択では `~/Library` が隠れているので、⌘⇧G で `~/Library/Input Methods` を開くか、
  `open ~/Library/Input\ Methods` で開いた Finder から MLH.app を一覧へドラッグします。
- 署名が変わると許可が無効になります。ad-hoc 署名でビルドし直した場合は、一覧から MLH を「−」で
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
| `x` | eXecute | ユーザー定義関数（本実装では未対応のため `x/` を取り除くだけ） |
| その他 | | 変換せず、普通にスペースを入力 |

Emacs 固有の `L`（Lisp 式の評価）と、egg で未定義の `g`（ギリシャ文字）は対応していません。

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

## ユーザー辞書

`d` 方式（`foo` + `d/`）で使う辞書（`mlh-userdef-table` 相当）です。

- 場所: `~/Library/Application Support/MLH/userdict.txt`
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

漢字変換では、変換対象の読み（ひらがな）を **Google のサーバー**
（`https://www.google.com/transliterate`）へ送信します。漢字変換を行う方式（`a i u e o n - , .` と `H`）
以外の変換は、すべて端末内で処理され、外部には送信されません。
この API は Google が無償で公開しているものですが、提供が予告なく変更・終了される可能性があります。
その場合、漢字変換は読み（ひらがな・カタカナ）の候補だけになります。
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
  - タイプ履歴は MLH を通して入力した文字だけを記録し、Return・矢印キー・マウスクリック・
    ⌘/Ctrl 付きのキーなどでリセットされます。カーソルを動かした後や貼り付けた文字列は変換できません。
  - バックスペースを合成する場合は、トリガーのスペースもいったんアプリに入力させ、元の文字列と一緒に
    消します（Ghostty などは IME が処理したスペースも入力してしまうため）。合成には
    アクセシビリティの許可が必要で、許可がない場合はビープ音を鳴らしてスペースを入力します。
- 漢字変換の範囲に英数字が含まれると、Google の変換結果では全角になることがあります。
- 漢字変換はネットワーク接続が必要です。通信できない場合は読み（ひらがな）のまま変換モードに入ります。
- 日本語以外の言語（Egg が対応していた中国語・韓国語など）は今後対応予定です。
- 一度に遡るのは現在行のカーソル直前、最大 1024 文字（UTF-16）までです。
- `L`（Lisp 式）と `x` のユーザー定義関数には対応していません。

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
