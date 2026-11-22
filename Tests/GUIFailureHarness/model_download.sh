#!/bin/sh
set -eu

gui=$1
backend=$2
work=$(mktemp -d "$3/.model-fixture.XXXXXX")
server=$4
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
printf 'invalid-model' > "$work/server/invalid.gguf"
"$server" "$work/server" "$work/port" "$work/slow.ready" "$work/slow.release" > "$work/server.log" 2>&1 &
server_pid=$!
attempt=0
while test ! -s "$work/port" && test "$attempt" -lt 50; do sleep 0.1; attempt=$((attempt + 1)); done
port=$(cat "$work/port")

start_gui() {
    MLH_SETTINGS_BACKEND_PATH="$backend" \
    MLH_SETTINGS_FIXTURE_MODEL_PATH="$work/models/zenz.gguf" \
    MLH_SETTINGS_FIXTURE_MODEL_ORIGIN="${2:-default}" \
    MLH_SETTINGS_MODEL_URL="http://127.0.0.1:$port/$1" \
        "$gui" > "$work/gui.log" 2>&1 &
    gui_pid=$!
    sleep 1
}
stop_gui() {
    kill "$gui_pid" 2>/dev/null || true
    wait "$gui_pid" 2>/dev/null || true
    gui_pid=
}
click_download() {
    osascript -e "tell application \"System Events\" to click button \"モデルをダウンロード…\" of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)" > /dev/null
}

start_gui model.gguf
click_download
attempt=0
while test ! -f "$work/models/zenz.gguf" && test "$attempt" -lt 50; do
    sleep 0.2
    attempt=$((attempt + 1))
done
test "$(cat "$work/models/zenz.gguf")" = GGUFfixture-model
stop_gui
echo 'model download: saved fixture'

start_gui model.gguf
count=$(osascript -e "tell application \"System Events\" to get count of (every button of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid) whose name is \"モデルをダウンロード…\")")
test "$count" = 0
test "$(cat "$work/models/zenz.gguf")" = GGUFfixture-model
stop_gui
echo 'model download: existing file preserved'

rm "$work/models/zenz.gguf"
start_gui invalid.gguf
click_download
sleep 2
test ! -e "$work/models/zenz.gguf"
stop_gui
echo 'model download: invalid response rejected'

start_gui missing.gguf
click_download
sleep 1
test ! -e "$work/models/zenz.gguf"
stop_gui
start_gui error.gguf
click_download
sleep 1
test ! -e "$work/models/zenz.gguf"
stop_gui
echo 'model download: HTTP errors rejected'

start_gui slow.gguf
click_download
attempt=0
while test ! -e "$work/slow.ready" && test "$attempt" -lt 50; do
    sleep 0.1
    attempt=$((attempt + 1))
done
test -e "$work/slow.ready"
progress=1
attempt=0
while test "$attempt" -lt 50; do
    progress=$(osascript -e "tell application \"System Events\" to get value of progress indicator 1 of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)" 2>/dev/null || echo 0)
    if awk -v value="$progress" 'BEGIN { exit !(value > 0 && value < 1) }'; then break; fi
    sleep 0.1
    attempt=$((attempt + 1))
done
awk -v value="$progress" 'BEGIN { exit !(value > 0 && value < 1) }'
touch "$work/slow.release"
attempt=0
while test ! -f "$work/models/zenz.gguf" && test "$attempt" -lt 50; do
    sleep 0.2
    attempt=$((attempt + 1))
done
test -f "$work/models/zenz.gguf"
stop_gui
rm "$work/models/zenz.gguf"
echo 'model download: progress advances before completion'

rm -f "$work/slow.ready" "$work/slow.release"
start_gui unknown.gguf
click_download
attempt=0
while test ! -e "$work/slow.ready" && test "$attempt" -lt 50; do
    sleep 0.1
    attempt=$((attempt + 1))
done
test -e "$work/slow.ready"
busy_count=$(osascript -e "tell application \"System Events\" to get count of busy indicators of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)")
progress_count=$(osascript -e "tell application \"System Events\" to get count of progress indicators of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)")
if test "$busy_count,$progress_count" != 1,0; then
    echo "unknown-size progress roles: busy=$busy_count progress=$progress_count" >&2
    exit 1
fi
touch "$work/slow.release"
attempt=0
while test ! -f "$work/models/zenz.gguf" && test "$attempt" -lt 50; do
    sleep 0.2
    attempt=$((attempt + 1))
done
test -f "$work/models/zenz.gguf"
stop_gui
rm "$work/models/zenz.gguf"
echo 'model download: unknown size shows active progress'

start_gui model.gguf userDefaults
click_download
attempt=0
while test ! -f "$work/models/zenz.gguf" && test "$attempt" -lt 50; do
    sleep 0.2
    attempt=$((attempt + 1))
done
test "$(cat "$work/models/zenz.gguf")" = GGUFfixture-model
stop_gui
echo 'model download: missing custom path populated'
