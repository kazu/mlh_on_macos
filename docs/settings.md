# 設定

この文書の設定例とファイルの場所は macOS 向けです。
Linux の設定とファイルの場所は [Linux 版の手順](../linux/README.md#設定)を参照してください。

## 行の書き換え（`x`）

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

### 番号付き（`2x/` など）

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

### アプリごとの設定

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

### 外部コマンド

`~/Library/Application Support/mlh/execute` に実行可能ファイルを置きます。
行を標準入力に渡し、標準出力（末尾の改行は除く）で置き換えます。終了コードが 0 以外なら失敗です。
環境変数 `MLH_CLIENT_BUNDLE_ID` に入力先アプリのバンドル ID が入ります。

```sh
#!/bin/sh
# 例: 行を大文字にする
tr a-z A-Z
```

### 組み込みの OpenAI

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
確認が出るので許可してください。エラーの内容はログに記録されます（[プライバシーについて](../README.md#プライバシーについて)を参照）。

## 漢字変換のエンジン

漢字変換の候補をどこから取るかは、`KanjiBackend` で選びます。

| `KanjiBackend` | エンジン |
|---|---|
| `azookey`（デフォルト） | 端末内の [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter)。ネットワーク不要で、読みは外部に送信されません |
| `google` | Google の変換 API。固有名詞や新しい言葉に強い一方、ネットワーク接続が必要で、読みを Google に送信します |

```sh
defaults write com.github.kazu.inputmethod.mlh KanjiBackend -string google   # Google に切り替える
defaults delete com.github.kazu.inputmethod.mlh KanjiBackend                 # デフォルト（azooKey）に戻す
```

設定は次の変換から使われます（再起動は不要です）。azooKey の辞書（約 35MB）は
`mlh.app/Contents/Resources/Dictionary` に入っています。
文節は azooKey の品詞の情報から、自立語ごとに区切ります。

### 文脈を使った変換（Zenzai）

macOS では azooKey のニューラル変換 Zenzai を使えます。Linux では Zenzai を利用できません。
Zenzai は、変換する位置より前の文字列（同じ行の、すでに入力した部分）を
文脈として使って候補を選びます。mlh は `kisha/` のように短く区切って変換することが多いので、
文脈があると精度が大きく上がります（例: 「駅から」のあとの `kisha/` は「汽車」、「新聞社の」のあとでは「記者」）。

Zenzai は zenz という小さな言語モデルを llama.cpp で動かします。モデル（約 72MB）は同梱していないので、
一度ダウンロードしてください。モデルがあれば Zenzai を使い、なければ通常の azooKey で変換します。
次の 2 行で `~/Library/Application Support/mlh/zenz.gguf` に置きます（`curl` を使います）。
ソースからビルドした場合は、リポジトリのルートで `make zenz-model` でも同じことができます。

Bash、zsh:

```sh
mkdir -p "$HOME/Library/Application Support/mlh"
curl -fL -o "$HOME/Library/Application Support/mlh/zenz.gguf" https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf
```

Nushell:

```nu
mkdir ($env.HOME | path join 'Library/Application Support/mlh')
^curl -fL -o ($env.HOME | path join 'Library/Application Support/mlh/zenz.gguf') https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf
```

| 設定 | デフォルト | 意味 |
|---|---|---|
| `ZenzaiModel` | `~/Library/Application Support/mlh/zenz.gguf` | モデルのパス |
| `ZenzaiContextLength` | 40 | 文脈として渡す文字数（0 で文脈なし） |
| `ZenzaiInferenceLimit` | 10 | 候補を評価し直す回数の上限 |

- デフォルトのビルドは CPU 版です。`MLH_ZENZAI=gpu make build` で GPU（Metal）版、`MLH_ZENZAI=off make build` で
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
