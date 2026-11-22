#!/bin/sh
set -eu
gui=$1
server=$2
dmg=$3
digest=$4
size=$5
work=$6
old_app=$7
backend=$(cd "$(dirname "$0")/../GUIFailureHarness" && pwd)/model_backend.sh
destination="$work/user-gui/Library/Input Methods/mlh.app"
mkdir -p "$(dirname "$destination")"
cp -R "$old_app" "$destination"
plutil -replace CFBundleShortVersionString -string 9.9.8 "$destination/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string 9.9.8 \
    "$destination/Contents/Resources/mlh-settings.app/Contents/Info.plist"
printf 'old' > "$destination/Contents/Resources/sentinel"
codesign --force --sign - "$destination/Contents/Resources/mlh-settings.app"
codesign --force --sign - "$destination"

"$server" "$work" "$work/port" "$work/download.ready" "$work/download.release" \
    "$dmg" "$digest" "$size" > "$work/server.log" 2>&1 &
server_pid=$!
gui_pid=
cleanup() {
    if test -n "$gui_pid"; then kill "$gui_pid" 2>/dev/null || true; wait "$gui_pid" 2>/dev/null || true; fi
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
attempt=0
while test ! -s "$work/port" && test "$attempt" -lt 50; do sleep 0.1; attempt=$((attempt + 1)); done
test -s "$work/port" || { cat "$work/server.log" >&2; exit 1; }
port=$(cat "$work/port")
MLH_SETTINGS_BACKEND_PATH="$backend" \
MLH_SETTINGS_FIXTURE_MODEL_PATH="$work/missing.gguf" \
MLH_UPDATE_TEST_VERSION=9.9.8 MLH_UPDATE_TEST_CHANNEL=release \
MLH_UPDATE_TEST_CACHE="$work/update-cache.json" \
MLH_UPDATE_TEST_API_URL="http://127.0.0.1:$port/latest" \
MLH_UPDATE_TEST_DESTINATION="$destination" \
    "$gui" > "$work/gui.log" 2>&1 &
gui_pid=$!
attempt=0
while test ! -e "$work/download.ready.api-ready" && test "$attempt" -lt 50; do sleep 0.1; attempt=$((attempt + 1)); done
test -e "$work/download.ready.api-ready"
window_count=$(osascript -e "tell application \"System Events\" to get count of windows of (first application process whose unix id is $gui_pid)")
test "$window_count" = 1
osascript -e "tell application \"System Events\" to set selected of row 2 of table 1 of scroll area 1 of window 1 of (first application process whose unix id is $gui_pid) to true"
check_count=$(osascript -e "tell application \"System Events\" to get count of (every button of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid) whose name is \"今すぐ確認\")")
test "$check_count" = 1
touch "$work/download.release.api-release"
attempt=0
enabled=false
while test "$attempt" -lt 50; do
    enabled=$(osascript -e "tell application \"System Events\" to get enabled of button \"アップグレード…\" of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)" 2>/dev/null || echo false)
    test "$enabled" = true && break
    sleep 0.1
    attempt=$((attempt + 1))
done
test "$enabled" = true
begin_upgrade() {
    osascript -e "tell application \"System Events\" to click button \"アップグレード…\" of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)" > /dev/null
    sleep 0.2
    osascript -e "tell application \"System Events\" to click button \"アップグレード\" of window 1 of (first application process whose unix id is $gui_pid)" > /dev/null
}
begin_upgrade
attempt=0
while test ! -e "$work/download.ready" && test "$attempt" -lt 50; do sleep 0.1; attempt=$((attempt + 1)); done
test -e "$work/download.ready"
test -e "$destination/Contents/Resources/sentinel"
attempt=0
progress=0
while test "$attempt" -lt 50; do
    progress=$(osascript -e "tell application \"System Events\" to get value of progress indicator 1 of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)" 2>/dev/null || echo 0)
    if awk -v value="$progress" 'BEGIN { exit !(value > 0 && value < 1) }'; then break; fi
    sleep 0.1
    attempt=$((attempt + 1))
done
awk -v value="$progress" 'BEGIN { exit !(value > 0 && value < 1) }'
osascript -e "tell application \"System Events\" to click button \"中止\" of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid)" > /dev/null
touch "$work/download.release"
attempt=0
restored=0
while test "$attempt" -lt 50; do
    restored=$(osascript -e "tell application \"System Events\" to get count of (every button of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid) whose name is \"アップグレード…\")" 2>/dev/null || echo 0)
    test "$restored" = 1 && break
    sleep 0.1
    attempt=$((attempt + 1))
done
test "$restored" = 1
test -e "$destination/Contents/Resources/sentinel"
sleep 0.3
rm "$work/download.ready" "$work/download.release"
begin_upgrade
attempt=0
while test ! -e "$work/download.ready" && test "$attempt" -lt 50; do sleep 0.1; attempt=$((attempt + 1)); done
test -e "$work/download.ready"
touch "$work/download.release"
attempt=0
while test -e "$destination/Contents/Resources/sentinel" && test "$attempt" -lt 100; do sleep 0.1; attempt=$((attempt + 1)); done
test ! -e "$destination/Contents/Resources/sentinel"
codesign --verify --deep --strict "$destination"
attempt=0
installed_count=0
while test "$attempt" -lt 50; do
    installed_count=$(osascript -e "tell application \"System Events\" to get count of (every button of scroll area 2 of window 1 of (first application process whose unix id is $gui_pid) whose name is \"インストール済み\")" 2>/dev/null || echo 0)
    test "$installed_count" = 1 && break
    sleep 0.1
    attempt=$((attempt + 1))
done
test "$installed_count" = 1
echo 'update GUI: asynchronous check, cancel, and manual install passed'
