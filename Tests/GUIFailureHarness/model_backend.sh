#!/bin/sh
set -eu

case "$1" in
    snapshot)
        printf '{"schema":1,"sections":[{"id":"zenzai","label":"Zenzai"}],"fields":[{"id":"zenzai.model","section":"zenzai","label":"モデルファイル","kind":"text","value":"%s","origin":"%s","options":[],"editable":true,"description":"","has_value":false}],"actions":[]}' "$MLH_SETTINGS_FIXTURE_MODEL_PATH" "${MLH_SETTINGS_FIXTURE_MODEL_ORIGIN:-default}"
        ;;
    *) exit 1 ;;
esac
