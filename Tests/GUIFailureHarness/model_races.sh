#!/bin/sh
set -eu
gui=$1
backend=$2
work=$(mktemp -d "$3/.model-race.XXXXXX")
server=$4
case_name=$5
gui_pid=
server_pid=
cleanup() {
    if test -n "$gui_pid"; then kill "$gui_pid" 2>/dev/null || true; wait "$gui_pid" 2>/dev/null || true; fi
    if test -n "$server_pid"; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$work/server" "$work/models"
printf 'GGUFfixture-model' > "$work/server/model.gguf"
"$server" "$work/server" "$work/port" "$work/slow.ready" "$work/slow.release" > "$work/server.log" 2>&1 &
server_pid=$!
attempt=0
while test ! -s "$work/port" && test "$attempt" -lt 50; do sleep 0.1; attempt=$((attempt + 1)); done
port=$(cat "$work/port")
MLH_SETTINGS_BACKEND_PATH="$backend" \
MLH_SETTINGS_FIXTURE_MODEL_PATH="$work/models/zenz.gguf" \
MLH_SETTINGS_MODEL_URL="http://127.0.0.1:$port/model.gguf" \
MLH_MODEL_COMMIT_GATE="$work/gate" \
    "$gui" > "$work/gui.log" 2>&1 &
gui_pid=$!
sleep 1
osascript -e "tell application \"System Events\" to click button \"モデルをダウンロード…\" of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)" > /dev/null
attempt=0
while test ! -e "$work/gate.ready" && test "$attempt" -lt 50; do
    sleep 0.1
    attempt=$((attempt + 1))
done
test -e "$work/gate.ready"

if test "$case_name" = busy; then
    state=$(osascript -e "tell application \"System Events\" to get (enabled of button \"保存\" of window 1 of (first application process whose unix id is $gui_pid) as text) & \",\" & (enabled of button \"再読み込み\" of window 1 of (first application process whose unix id is $gui_pid) as text) & \",\" & (enabled of text field 1 of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid) as text)")
    osascript -e "tell application \"System Events\" to click button \"再読み込み\" of window 1 of (first application process whose unix id is $gui_pid)" > /dev/null 2>&1 || true
    cancel_count=$(osascript -e "tell application \"System Events\" to get count of (every button of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid) whose name is \"中止\")")
    progress=$(osascript -e "tell application \"System Events\" to get value of progress indicator 1 of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)")
    touch "$work/gate.release"
    test "$state" = false,false,false
    test "$cancel_count" = 1
    test "$progress" = 1.0
    echo 'model download: editing blocked and progress retained'
elif test "$case_name" = cancel; then
    osascript -e "tell application \"System Events\" to click button \"中止\" of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)" > /dev/null
    touch "$work/gate.release"
    sleep 1
    test ! -e "$work/models/zenz.gguf"
    restored=$(osascript -e "tell application \"System Events\" to get (enabled of button \"保存\" of window 1 of (first application process whose unix id is $gui_pid) as text) & \",\" & (count of (every button of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid) whose name is \"モデルをダウンロード…\") as text)")
    test "$restored" = true,1
    echo 'model download: cancel cannot race with file commit'
else
    echo "unknown test: $case_name" >&2
    exit 1
fi
