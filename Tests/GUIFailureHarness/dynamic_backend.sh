#!/bin/sh
set -eu
if test "$1" = apply; then
    cat > "$MLH_SETTINGS_FIXTURE_APPLY_LOG"
elif test "$1" != snapshot; then
    exit 1
fi
cat <<'JSON'
{"schema":1,"sections":[{"id":"execute","label":"行の書き換え"},{"id":"openai","label":"OpenAI"}],"fields":[{"id":"execute.backend","section":"execute","label":"実行方式","kind":"select","value":"auto","origin":"default","options":[{"value":"auto","label":"auto"},{"value":"command","label":"command"},{"value":"openai","label":"openai"}],"editable":true,"description":"","has_value":false},{"id":"execute.entry.2.backend","section":"execute","label":"2x/: 処理方式","kind":"select","value":null,"origin":"default","options":[{"value":"command","label":"command"},{"value":"openai","label":"openai"}],"editable":true,"description":"","has_value":false},{"id":"execute.entry.2.command","section":"execute","label":"2x/: コマンド","kind":"text","value":"/bin/cat","origin":"file","options":[],"editable":true,"description":"","has_value":false},{"id":"openai.model","section":"openai","label":"モデル","kind":"text","value":"fixture-model","origin":"default","options":[],"editable":true,"description":"","has_value":false}],"actions":[{"id":"execute.entry.add","section":"execute","label":"番号別設定を追加","inputs":[{"id":"key","label":"番号","kind":"text"}]},{"id":"execute.entry.remove:execute.entry.2","section":"execute","label":"2x/ を削除","inputs":[]}]}
JSON
