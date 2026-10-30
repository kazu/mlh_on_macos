# mlh — モードレス日本語入力

macOS と、Wayland を使う Linux で動く、モードレスな日本語入力メソッドです。
英数・日本語のモードを切り替えず、入力したローマ字をその場で変換できます。

**mlh** は g新部（NIIBE Yutaka）さんが 1990 年に NEmacs 用に作ったモードレスな変換ツールで、Mule の時代には
Egg・Canna・SJ3 と組み合わせて使われ、のちに Emacs の入力システム Egg（たまご）V4 に
egg-mlh.el (Modeless Conversion Facility) として取り込まれました。
本プロジェクトは egg-mlh.el の操作体系を再現したものです。macOS では InputMethodKit、
Linux では IBus を使います。

- 「日本語モード」「英数モード」の切り替えはありません。入力メソッドは常に有効で、
  普段の英数字はそのまま入力できます。
- 直前に入力したローマ字などの末尾に `/` と変換方式を表す文字を付けて **スペース** を押すと、
  その場で（カーソル直前のテキストを遡って）変換します。
  例: `nihongo/` + Space → `日本語`（漢字変換モードに入ります）
- 漢字変換は Egg の変換モード（`egg-conversion-map`）のキー操作を再現しています。
  変換候補は端末内で動く azooKey (AzooKeyKanaKanjiConverter) から取得します。設定で
  Google の変換 API (Google CGI API for Japanese Input) に切り替えることもできます。
- **現在は日本語と Latin-1（`l` 方式）のみ対応しています。** Egg（たまご）は多言語の入力システムで、
  日本語のほかにも中国語（ピンイン・注音）、韓国語（ハングル）、タイ語、ギリシャ文字、アイヌ語のカナなど、
  多くの言語・文字を扱えました。それ以外の言語・文字への対応はこれからです。

## インストール

[リリース](https://github.com/kazu/mlh_on_macos/releases)から、macOS は dmg、Linux は deb をダウンロードして入れます。
ソースからビルドする場合は [macOS でのビルド](docs/macos.md)、[Linux でのビルド](linux/README.md)を参照してください。

### macOS

macOS 13.3 以降で、Apple Silicon と Intel の両方で動きます。

1. `mlh-v<バージョン>.dmg` を開き、`mlh.app` を `Input Methods`（`/Library/Input Methods` へのリンク）にドラッグします。
   管理者のパスワードを求められます。
2. dmg の mlh は Apple の公証を受けていないので、ダウンロードの印（quarantine）を外します（Bash、zsh、Nushell 共通）。

   ```sh
   sudo xattr -dr com.apple.quarantine "/Library/Input Methods/mlh.app"
   ```

3. 一度ログアウトしてログインし直します。初めて `/Library/Input Methods` に入れたときは、
   ログインし直すまでシステム設定の一覧に出てきません。
4. 入力ソースに追加します。サードパーティの入力メソッドは、プログラムから有効化しても反映されないため、手動で追加してください。
   1. 「システム設定」→「キーボード」→「テキスト入力」の「入力ソース」の「編集…」を開く
   2. 左下の「+」を押し、言語の一覧から「日本語」を選ぶ
   3. 「mlh」を選んで「追加」
   4. メニューバーの入力メニュー（`/␣` アイコン）から mlh を選択
5. アクセシビリティを許可します。Ghostty などのターミナルや、Chrome・Discord・Slack・VS Code などの
   Chromium/Electron 系アプリでは、元の文字列を消すためにバックスペースのキーイベントを合成します
   （[制限事項](docs/usage.md#制限事項)を参照）。「システム設定」→「プライバシーとセキュリティ」→
   「アクセシビリティ」の「+」で、`/Library/Input Methods/mlh.app` を追加してください。

mlh は常に ASCII がそのまま入る入力メソッドなので、普段から mlh を選んだままで使えます。
文脈を使った変換（Zenzai）のモデルは dmg に入っていません。使う場合は[設定](docs/settings.md#文脈を使った変換zenzai)を参照してください。

### Linux

deb は Ubuntu 26.04 向けで、Wayland と IBus で動きます。`0.1.3` の部分は、ダウンロードしたバージョンに合わせてください（Bash、zsh、Nushell 共通）。

```sh
sudo apt install ./mlh-ibus_0.1.3_amd64.deb
```

入れたあと、入力中の文章を確定してから `ibus restart` を実行するか、ログインし直します。
その後、デスクトップの入力ソースに `mlh` を追加します。既に動いているアプリでは、新しく開いたウィンドウでまず試してください。

## 使い方

入力したローマ字に `/` を付けて Space を押すと、漢字変換できます。
例えば `nihongo/` + Space で漢字変換を始め、候補を選んで Enter で確定します。
`ko-hi-k/` + Space なら「コーヒー」、`hiraganaf/` + Space なら「ひらがな」になります。

変換方式とキー操作は [入力と変換](docs/usage.md)、ユーザー辞書や外部コマンド、
変換エンジンの設定は [設定](docs/settings.md)を参照してください。

macOS では、文脈を使って変換する Zenzai も利用できます。

## プライバシーについて

漢字変換のエンジンを `google` にしたときは、変換対象の読み（ひらがな）を **Google のサーバー**
（`https://www.google.com/transliterate`）へ送信します。デフォルトの `azookey` では送信しません。
漢字変換を行う方式（`a i u e o n - , .` と `H`）以外の変換は、すべて端末内で処理され、外部には送信されません。
ただし `x` 方式を使うと、行が外部コマンドに渡されるか、組み込みの OpenAI 呼び出しでは **OpenAI のサーバー** に送信されます。
この API は Google が無償で公開しているものですが、提供が予告なく変更・終了される可能性があります。
その場合、Google を使う漢字変換は読み（ひらがな・カタカナ）の候補だけになります（azooKey は影響を受けません）。
ログ（`log stream --predicate 'subsystem == "com.github.kazu.inputmethod.mlh"' --level debug`）には、
入力テキストはプライベート扱いでしか記録されません。

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
アプリには含まれず、別にダウンロードします（[設定](docs/settings.md#文脈を使った変換zenzai)を参照）。

Apache License 2.0 は GPL version 3 とは両立しますが、version 2 とは両立しないとされています。
そのため、ビルドしたアプリを配布する場合は GPL version 3 の条件で配布してください。
