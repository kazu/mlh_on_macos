# macOS のビルドとインストール

```sh
make build      # build/mlh.app を作成（ad-hoc 署名済み）
make test       # Core のテストを実行
make install    # ~/Library/Input Methods/mlh.app に配置し、入力ソースとして登録・有効化
make uninstall  # ~/Library/Input Methods/mlh.app を削除
make clean      # build/ と .build/（SwiftPM の作業ディレクトリ）を削除
```

`make install` は実行中の mlh プロセスを終了し（`killall mlh`）、アプリを置き換えたうえで
`scripts/register.swift` で `TISRegisterInputSource` / `TISEnableInputSource` を呼び出します。

## App Store 版のアプリ（Slack など）でも使う場合

サンドボックスで動く App Store 版のアプリからは、`~/Library/Input Methods` に置いた入力メソッドが
見えないことがあります（App Store 版 Slack では mlh に切り替えられず、ショートカットで切り替えると
Slack が落ちました）。その場合はシステム全体の場所に入れてください。

```sh
make install-system   # /Library/Input Methods/mlh.app に配置（sudo が必要）
```

初めて `/Library/Input Methods` に入れたときは、**一度ログアウトしてログインし直す**まで
システム設定の一覧に出てきません。以後の更新（`make install-system` の再実行）ではログアウトは不要です。
アクセシビリティの許可も `/Library/Input Methods/mlh.app` に対して追加し直してください。

## 入力ソースへの追加（初回のみ）

最近の macOS では、サードパーティの入力メソッドをプログラムから有効化しても反映されないため、
初回は手動で追加してください。

1. 「システム設定」→「キーボード」→「テキスト入力」の「入力ソース」の「編集…」を開く
2. 左下の「+」を押し、言語の一覧から「日本語」を選ぶ
3. 「mlh」を選んで「追加」
4. メニューバーの入力メニュー（`/␣` アイコン）から mlh を選択

一覧に出てこない場合は、システム設定を開き直すか、一度ログアウトして再ログインしてください。
mlh は常に ASCII がそのまま入る入力メソッドなので、普段から mlh を選んだままで使えます。

## アクセシビリティの許可

Ghostty などのターミナルや、Chrome・Discord・Slack・VS Code などの Chromium/Electron 系アプリでは、
元の文字列を消すためにバックスペースのキーイベントを合成します（[制限事項](usage.md#制限事項)を参照）。
このため「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で mlh を許可してください。

- 「+」のファイル選択では `~/Library` が隠れているので、⌘⇧G で `~/Library/Input Methods` を開くか、
  `open ~/Library/Input\ Methods` で開いた Finder から mlh.app を一覧へドラッグします。
- 署名が変わると許可が無効になります。ad-hoc 署名でビルドし直した場合は、一覧から mlh を「−」で
  削除して追加し直し、入力ソースを一度切り替えてください（固定の署名を使う方法は「署名」を参照）。

## 署名

ad-hoc 署名のままだと、ビルドし直すたびにアクセシビリティの許可が無効になります。
マシンごとに一度だけ自己署名のコード署名用 ID を作っておくと、以後の `make build` はその ID で署名し、
許可が保たれます。

```sh
make signing-identity   # ログインキーチェーンに "MLH Local Code Signing" を作成（openssl と security を使用）
```

初回の署名時に「codesign がキーチェーンのキーにアクセスしようとしています」と表示されたら、
パスワードを入力して「常に許可」を選んでください。ID がない場合は従来どおり ad-hoc 署名になります。
ID を作った直後の 1 回だけは署名が変わるので、アクセシビリティの許可を追加し直してください。
