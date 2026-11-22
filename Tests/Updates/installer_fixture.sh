#!/bin/sh
set -eu
test_binary=$1
mkdir -p "$2"
work=$(mktemp -d "$2/.installer-fixture.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

app="$work/dmg-root/mlh.app"
settings="$app/Contents/Resources/mlh-settings.app"
mkdir -p "$app/Contents/MacOS" "$settings/Contents/MacOS"
cat > "$work/main.c" <<'EOF'
int main(void) { return 0; }
EOF
clang -arch arm64 "$work/main.c" -o "$work/arm64"
clang -arch x86_64 "$work/main.c" -o "$work/x86_64"
lipo -create "$work/arm64" "$work/x86_64" -output "$work/universal"
for binary in "$app/Contents/MacOS/mlh" \
    "$settings/Contents/MacOS/mlh-settings" \
    "$settings/Contents/MacOS/mlh-settings-backend" \
    "$settings/Contents/MacOS/mlh-settings-tui"; do
    cp "$work/universal" "$binary"
done
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.github.kazu.inputmethod.mlh</string>
<key>CFBundleExecutable</key><string>mlh</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>9.9.9</string>
<key>CFBundleVersion</key><string>9.9.9</string>
<key>MLHBuildChannel</key><string>release</string>
</dict></plist>
EOF
cat > "$settings/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.github.kazu.inputmethod.mlh.settings</string>
<key>CFBundleExecutable</key><string>mlh-settings</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>9.9.9</string>
<key>CFBundleVersion</key><string>9.9.9</string>
<key>MLHBuildChannel</key><string>release</string>
</dict></plist>
EOF
codesign --force --sign - "$settings/Contents/MacOS/mlh-settings-backend"
codesign --force --sign - "$settings/Contents/MacOS/mlh-settings-tui"
codesign --force --sign - "$settings"
codesign --force --sign - "$app"
hdiutil create -quiet -volname mlh-update-fixture -srcfolder "$work/dmg-root" -format UDZO "$work/release.dmg"
digest=$(shasum -a 256 "$work/release.dmg" | awk '{print $1}')
size=$(stat -f %z "$work/release.dmg")
"$test_binary" "$work/release.dmg" "$digest" "$size" "$work"
if test "$#" -ge 4; then
    sh "$(dirname "$0")/gui_states.sh" "$3" "$4" "$work/release.dmg" "$digest" "$size" "$work"
    sh "$(dirname "$0")/gui_update.sh" "$3" "$4" "$work/release.dmg" "$digest" "$size" "$work" "$app"
fi
if test "$#" -ge 5; then
    sh "$(dirname "$0")/system_cli.sh" "$5" "$4" "$work/release.dmg" "$digest" "$size" "$app" "$work"
fi
