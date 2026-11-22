#!/bin/sh
set -eu
gui=$1
server=$2
dmg=$3
digest=$4
size=$5
work=$6
backend=$(cd "$(dirname "$0")/../GUIFailureHarness" && pwd)/model_backend.sh
"$server" "$work" "$work/states.port" "$work/states.ready" "$work/states.release" \
    "$dmg" "$digest" "$size" > "$work/states-server.log" 2>&1 &
server_pid=$!
gui_pid=
cleanup() {
    if test -n "$gui_pid"; then kill "$gui_pid" 2>/dev/null || true; wait "$gui_pid" 2>/dev/null || true; fi
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
attempt=0
while test ! -s "$work/states.port" && test "$attempt" -lt 50; do sleep 0.1; attempt=$((attempt + 1)); done
test -s "$work/states.port" || { cat "$work/states-server.log" >&2; exit 1; }
port=$(cat "$work/states.port")
start_gui() {
    MLH_SETTINGS_BACKEND_PATH="$backend" MLH_SETTINGS_FIXTURE_MODEL_PATH="$work/missing.gguf" \
    MLH_UPDATE_TEST_VERSION="$1" MLH_UPDATE_TEST_CHANNEL="$2" \
    MLH_UPDATE_TEST_CACHE="$work/cache-$3.json" \
    MLH_UPDATE_TEST_API_URL="http://127.0.0.1:$port/$3" \
        "$gui" > "$work/gui-$3.log" 2>&1 &
    gui_pid=$!
    sleep 1
    osascript -e "tell application \"System Events\" to set selected of row 2 of table 1 of scroll area 1 of window 1 of (first application process whose unix id is $gui_pid) to true"
}
stop_gui() {
    kill "$gui_pid" 2>/dev/null || true
    wait "$gui_pid" 2>/dev/null || true
    gui_pid=
}
button_enabled() {
    osascript -e "tell application \"System Events\" to get enabled of button \"アップグレード…\" of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)"
}
page_text() {
    osascript -e "tell application \"System Events\" to get value of every static text of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)"
}

start_gui 0.1.0 development latest
test "$(button_enabled)" = false
case "$(page_text)" in *"開発版"*) ;; *) exit 1 ;; esac
test ! -e "$work/states.ready.api-ready"
stop_gui

start_gui 9.9.9 release latest
attempt=0
while test ! -e "$work/states.ready.api-ready" && test "$attempt" -lt 50; do sleep 0.1; attempt=$((attempt + 1)); done
test -e "$work/states.ready.api-ready"
touch "$work/states.release.api-release"
attempt=0
while test "$attempt" -lt 50; do
    case "$(page_text)" in *"現在のバージョンが最新です"*) break ;; esac
    sleep 0.1
    attempt=$((attempt + 1))
done
test "$attempt" -lt 50
test "$(button_enabled)" = false
stop_gui

start_gui 9.9.8 release error.gguf
attempt=0
while test "$attempt" -lt 50; do
    case "$(page_text)" in *"確認できませんでした"*) break ;; esac
    sleep 0.1
    attempt=$((attempt + 1))
done
test "$attempt" -lt 50
test "$(button_enabled)" = false
stop_gui
echo 'update GUI: development, current release, and network error states passed'
