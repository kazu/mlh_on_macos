# macOS でのビルド

ビルドには Command Line Tools for Xcode（Swift 6.1 以上の `swift` と `codesign`）が必要です。Xcode 本体は不要です。
初回のビルドでは SwiftPM が依存パッケージ（AzooKeyKanaKanjiConverter とその辞書など）を取得するため、
ネットワーク接続が必要です。リポジトリのルートで実行します（Bash、zsh、Nushell 共通）。

```sh
make build      # build/mlh.app を作成（ad-hoc 署名済み）
make test       # Core のテストを実行
make install    # ~/Library/Input Methods/mlh.app に配置し、入力ソースとして登録・有効化
make uninstall  # ~/Library/Input Methods/mlh.app を削除
make clean      # build/ と .build/（SwiftPM の作業ディレクトリ）を削除
```

`make install` は実行中の mlh プロセスを終了し（`killall mlh`）、アプリを置き換えたうえで
`scripts/register.swift` で `TISRegisterInputSource` / `TISEnableInputSource` を呼び出します。
初めて入れたときは、README の[インストール](../README.md#macos)の手順 4・5（入力ソースへの追加とアクセシビリティの許可）を行ってください。
`make install` で入れた場合、アクセシビリティに追加するのは `~/Library/Input Methods/mlh.app` です。
「+」のファイル選択では `~/Library` が隠れているので、⌘⇧G で `~/Library/Input Methods` を開いてください。

dmg は `make dmg` で作れます（`build/mlh.dmg`）。`ARCHS="arm64 x86_64"` を付けると両方の CPU 向けにビルドして 1 つにまとめます。

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

## 署名

ad-hoc 署名のままだと、ビルドし直すたびにアクセシビリティの許可が無効になります。
そのときは一覧から mlh を「−」で削除して追加し直し、入力ソースを一度切り替えてください。
マシンごとに一度だけ自己署名のコード署名用 ID を作っておくと、以後の `make build` はその ID で署名し、
許可が保たれます。

```sh
make signing-identity   # ログインキーチェーンに "MLH Local Code Signing" を作成（openssl と security を使用）
```

初回の署名時に「codesign がキーチェーンのキーにアクセスしようとしています」と表示されたら、
パスワードを入力して「常に許可」を選んでください。ID がない場合は従来どおり ad-hoc 署名になります。
ID を作った直後の 1 回だけは署名が変わるので、アクセシビリティの許可を追加し直してください。
