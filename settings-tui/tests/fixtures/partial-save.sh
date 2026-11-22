#!/bin/sh
set -eu
state="$0.state"
case "$1" in
  snapshot)
    value=old
    if [ -e "$state" ]; then value=new; fi
    printf '{"schema":1,"sections":[{"id":"openai","label":"OpenAI"}],"fields":[{"id":"openai.model","section":"openai","label":"モデル","kind":"text","value":"%s","origin":"file","options":[],"editable":true,"description":"","has_value":false},{"id":"openai.apiKey","section":"openai","label":"API キー","kind":"secret","value":null,"origin":"default","options":[],"editable":true,"description":"","has_value":false}],"actions":[]}\n' "$value"
    ;;
  apply)
    cat > "$state.request"
    : > "$state"
    printf '%s\n' 'Secret Service write failed' >&2
    exit 1
    ;;
  *) exit 2 ;;
esac
