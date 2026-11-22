#!/bin/sh
set -eu
backend=$1
server=$2
dmg=$3
digest=$4
size=$5
source_app=$6
work=$7
destination="$work/system-cli/Library/Input Methods/mlh.app"
mkdir -p "$(dirname "$destination")"
cp -R "$source_app" "$destination"
plutil -replace CFBundleShortVersionString -string 9.9.8 "$destination/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string 9.9.8 \
    "$destination/Contents/Resources/mlh-settings.app/Contents/Info.plist"
codesign --force --sign - "$destination/Contents/Resources/mlh-settings.app"
codesign --force --sign - "$destination"

"$server" "$work" "$work/system-cli.port" "$work/system-cli.ready" \
    "$work/system-cli.release" "$dmg" "$digest" "$size" > "$work/system-cli-server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT HUP INT TERM
attempt=0
while test ! -s "$work/system-cli.port" && test "$attempt" -lt 50; do
    sleep 0.1
    attempt=$((attempt + 1))
done
test -s "$work/system-cli.port"
port=$(cat "$work/system-cli.port")
touch "$work/system-cli.release.api-release"
run_backend() {
    MLH_UPDATE_TEST_SYSTEM_DESTINATION="$destination" \
    MLH_UPDATE_TEST_PRIVATE_DIRECTORY="$work/private-system-copy" \
    MLH_UPDATE_TEST_API_URL="http://127.0.0.1:$port/latest" \
        "$backend" install-update system "$dmg" "$1"
}
if run_backend v9.9.10 > "$work/system-cli-mismatch.log" 2>&1; then
    echo 'system CLI: mismatched release was accepted' >&2
    exit 1
fi
test "$(plutil -extract CFBundleShortVersionString raw -o - "$destination/Contents/Info.plist")" = 9.9.8
run_backend v9.9.9
test "$(plutil -extract CFBundleShortVersionString raw -o - "$destination/Contents/Info.plist")" = 9.9.9
codesign --verify --deep --strict "$destination"
test ! -e "$work/private-system-copy"
echo 'system CLI: fixed release, private copy, and isolated destination passed'
