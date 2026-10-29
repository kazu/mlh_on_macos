# Linux でのモードレス日本語入力

IBus を使い、Wayland 上のアプリで macOS 版と同じ変換操作を使えます。Rust 製の IBus エンジンから Swift 製の変換処理を呼び出します。

## 必要環境

Swift 6.1 以上、Rust、Cargo、Clang、GCC、Git、IBus が必要です。Ubuntu 26.04 では `swiftlang`、`cargo`、`clang`、`gcc`、`libobjc-15-dev`、`git`、`ibus` を使います。GTK アプリでは `ibus-gtk4` または `ibus-gtk3` も必要です。

## ビルドと配置

リポジトリのルートから実行します。ビルド先と配置用ディレクトリにはローカルディスクを指定してください。配置用ディレクトリが既にある場合は、削除せず別の場所を指定してください。

Bash:

```bash
MLH_WORK_DIR="$HOME/.cache/mlh-wayland"
export CARGO_TARGET_DIR="$MLH_WORK_DIR/tmp"
export MLH_STAGE_DIR="$MLH_WORK_DIR/stage"
sh linux/build.sh
sh linux/install.sh
```

Nushell:

```nushell
let work = ($nu.home-path | path join '.cache/mlh-wayland')
$env.CARGO_TARGET_DIR = ($work | path join 'tmp')
$env.MLH_STAGE_DIR = ($work | path join 'stage')
sh linux/build.sh
sh linux/install.sh
```

既定の配置先は `~/.local/bin`、`~/.local/lib/mlh`、`~/.local/share/mlh` です。`MLH_PREFIX` で実行ファイルとライブラリの配置先を、`XDG_DATA_HOME` で辞書と IBus のコンポーネント定義の配置先を変更できます。

IBus にコンポーネントを見つけさせるため、セッション起動時の `IBUS_COMPONENT_PATH` に、システムの IBus コンポーネントディレクトリと `~/.local/share/ibus/component` の両方を含めます。Ubuntu のシステム側は `/usr/share/ibus/component` です。既に別のディレクトリを指定している場合は、それも残してください。設定後、新しいデスクトップセッションで入力ソースに `mlh` を追加します。GTK の IBus モジュールを使う場合は、アプリの起動時に `GTK_IM_MODULE=ibus` を設定します。

GNOME 50.1 の Wayland セッションでは、周辺文字列を提供しないアプリで、GNOME 側が mlh の送る削除キーを処理できず、変換前のローマ字が残ることがあります。入力先がターミナルと通知される場合は、端末に削除文字を送って対応します。それ以外の GTK アプリは、新しく起動する際に `GTK_IM_MODULE=ibus` を設定すると、GTK が IBus に直接接続する経路で回避できます。既に動いているアプリにはこの環境変数は反映されません。

GNOME Terminal では `~/.local/bin/mlh-gnome-terminal` を実行すると、既存のターミナルとは別のプロセスで、IBus に直接接続する窓を開けます。

## 設定

ユーザー辞書は `~/.config/mlh/userdict.txt`、`x/` の番号別設定は `~/.config/mlh/execute.json` です。`XDG_CONFIG_HOME` が指定されている場合は、その下の `mlh` ディレクトリを使います。ファイル形式と入力操作は[本体の説明](../README.md)を参照してください。`apps` のキーには、IBus が渡すアプリのプログラム名を指定します。アプリ名が渡されない入力経路では共通設定を使います。

漢字変換は azooKey がデフォルトです。`MLH_TRANSLITERATOR=google` をエンジンの環境に設定すると Google の変換 API を使えます。`x/` の番号なしの実行方式は `MLH_EXEC_BACKEND` に `command` または `openai` を指定します。外部コマンドのデフォルトの場所は `~/.config/mlh/execute` です。

OpenAI 互換サーバーのデフォルト設定は `MLH_OPENAI_BASE_URL`、`MLH_OPENAI_MODEL`、`MLH_OPENAI_INSTRUCTIONS`、`MLH_OPENAI_REASONING_EFFORT` で指定できます。API キーが必要な場合は `OPENAI_API_KEY` を使います。これらは IBus がエンジンを起動するときの環境に設定してください。

`x/` の実行中は元の文章を残し、応答をその後ろに未確定文字として表示します。完了すると応答に置き換わります。キャンセルやフォーカス移動時には元の文章が残ります。
