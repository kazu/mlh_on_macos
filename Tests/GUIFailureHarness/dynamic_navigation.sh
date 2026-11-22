#!/bin/sh
set -eu
gui=$1
backend=$2
apply_log=$3/.dynamic-apply.json
rm -f "$apply_log"
MLH_SETTINGS_BACKEND_PATH="$backend" MLH_SETTINGS_FIXTURE_APPLY_LOG="$apply_log" "$gui" > /dev/null 2>&1 &
gui_pid=$!
trap 'kill "$gui_pid" 2>/dev/null || true; wait "$gui_pid" 2>/dev/null || true' EXIT HUP INT TERM
sleep 1
buttons=$(osascript -e "tell application \"System Events\" to get name of every button of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)")
case "$buttons" in
    *"この設定を削除…"*) ;;
    *) echo 'dynamic remove action missing' >&2; exit 1 ;;
esac
value=$(osascript -e "tell application \"System Events\"" \
    -e "tell (first application process whose unix id is $gui_pid)" \
    -e 'set value of text field 1 of scroll area 2 of window 1 to "edited-command"' \
    -e 'click row 2 of table 1 of scroll area 1 of window 1' \
    -e 'click row 1 of table 1 of scroll area 1 of window 1' \
    -e 'get value of text field 1 of scroll area 2 of window 1' \
    -e 'end tell' -e 'end tell')
test "$value" = edited-command
osascript -e "tell application \"System Events\" to click button \"保存\" of window 1 of (first application process whose unix id is $gui_pid)" > /dev/null
test -s "$apply_log"
if grep -q 'execute.entry.2.backend' "$apply_log"; then
    echo 'unselected dynamic backend was saved as command' >&2
    exit 1
fi
rm "$apply_log"
echo 'dynamic entry: controls and unsaved edits preserved across sections'
