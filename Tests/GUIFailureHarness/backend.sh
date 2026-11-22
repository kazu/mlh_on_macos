#!/bin/sh

set -eu
: "${MLH_SETTINGS_FIXTURE_STATE:?}"

case "$1" in
    snapshot)
        value=before
        if test -f "$MLH_SETTINGS_FIXTURE_STATE"; then
            value=after
            if test "${MLH_SETTINGS_FIXTURE_RELOAD_FAIL_ONCE:-}" = 1 && test ! -f "$MLH_SETTINGS_FIXTURE_STATE.reload-failed"; then
                touch "$MLH_SETTINGS_FIXTURE_STATE.reload-failed"
                printf '再読み込みに失敗しました\n' >&2
                exit 1
            fi
        fi
        printf '{"schema":1,"sections":[{"id":"general","label":"一般"}],"fields":[{"id":"example.value","section":"general","label":"値","kind":"text","value":"%s","origin":"default","options":[],"editable":true,"description":"","has_value":false}],"actions":[{"id":"example.add","section":"general","label":"追加","inputs":[]}]}' "$value"
        ;;
    apply)
        IFS= read -r request || true
        test -n "$request"
        touch "$MLH_SETTINGS_FIXTURE_STATE"
        printf '一部だけ保存したあとに失敗しました\n' >&2
        exit 1
        ;;
    *) exit 64 ;;
esac
