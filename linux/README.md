# Linux でのモードレス日本語入力

IBus を使い、Wayland 上のアプリで macOS 版と同じ変換操作を使えます。Rust 製の IBus エンジンから Swift 製の変換処理を呼び出します。

## Debian パッケージ

Ubuntu 26.04 でビルド・動作確認しています。パッケージのインストール時には IBus と Swift の実行時ライブラリ `libswiftlang` が必要です。ビルドには Rust 1.89 以上と Cargo、次のパッケージを使います。Rust は既存の `rustup` またはディストリビューションの `cargo` を使えます。

```sh
sudo apt install debhelper clang gcc git libobjc-15-dev swiftlang dbus-daemon
make deb
sudo apt install ../mlh-ibus_0.1.0_amd64.deb
```

`make deb` はリポジトリのルートで実行します。Swift と Cargo の依存ライブラリは初回にネットワークから取得します。`.deb` はリポジトリの親ディレクトリに生成され、アーキテクチャ部分はビルドしたマシンによって変わります。`libswiftlang` と互換性のある同じディストリビューション向けにビルドしてください。

配置後、入力中の文章を確定してから `ibus restart` を実行するか、ログインし直します。その後、デスクトップの入力ソースに `mlh` を追加します。既に動いているアプリでは、新しく開いたウィンドウでまず試してください。

開発時は `make build` でビルドし、`make test` でテストできます。ビルド用データは既定で `~/.cache/mlh-wayland` に置き、`MLH_WORK_DIR`、`SWIFT_BUILD_DIR`、`CARGO_TARGET_DIR` で変更できます。`make install PREFIX=/usr DESTDIR=/一時ディレクトリ` はパッケージング用の配置です。

GNOME 50.1 の Wayland セッションでは、周辺文字列を提供しないアプリで、GNOME 側が mlh の送る削除キーを処理できず、変換前のローマ字が残ることがあります。入力先がターミナルと通知される場合は、端末に削除文字を送って対応します。それ以外の GTK アプリは、新しく起動する際に `GTK_IM_MODULE=ibus` を設定すると、GTK が IBus に直接接続する経路で回避できます。既に動いているアプリにはこの環境変数は反映されません。

GNOME Terminal では `mlh-gnome-terminal` を実行すると、既存のターミナルとは別のプロセスで、IBus に直接接続する窓を開けます。

## 設定

ユーザー辞書は `~/.config/mlh/userdict.txt`、`x/` の番号別設定は `~/.config/mlh/execute.json` です。`XDG_CONFIG_HOME` が指定されている場合は、その下の `mlh` ディレクトリを使います。ファイル形式と入力操作は[本体の説明](../README.md)を参照してください。`apps` のキーには、IBus が渡すアプリのプログラム名を指定します。アプリ名が渡されない入力経路では共通設定を使います。

漢字変換は azooKey がデフォルトです。`MLH_TRANSLITERATOR=google` をエンジンの環境に設定すると Google の変換 API を使えます。`x/` の番号なしの実行方式は `MLH_EXEC_BACKEND` に `command` または `openai` を指定します。外部コマンドのデフォルトの場所は `~/.config/mlh/execute` です。

OpenAI 互換サーバーのデフォルト設定は `MLH_OPENAI_BASE_URL`、`MLH_OPENAI_MODEL`、`MLH_OPENAI_INSTRUCTIONS`、`MLH_OPENAI_REASONING_EFFORT` で指定できます。API キーが必要な場合は `OPENAI_API_KEY` を使います。これらは IBus がエンジンを起動するときの環境に設定してください。

`x/` の実行中は元の文章を残し、応答をその後ろに未確定文字として表示します。完了すると応答に置き換わります。キャンセルやフォーカス移動時には元の文章が残ります。
