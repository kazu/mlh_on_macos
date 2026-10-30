#!/bin/sh
# Sets the release version (scripts/set-version.sh 0.2.0, run in the
# repository) in the Debian changelog, the Rust package (the IBus
# component's version) and the app's Info.plist.
set -eu
version=${1:?usage: scripts/set-version.sh 0.2.0}

# A changelog entry, unless the latest one is for the version.
if ! head -1 debian/changelog | grep -qF "($version)"; then
    { printf 'mlh-ibus (%s) unstable; urgency=medium\n\n  * Release %s.\n\n -- %s  %s\n\n' "$version" "$version" \
        "$(sed -n 's/^Maintainer: //p' debian/control)" "$(date -R)"; cat debian/changelog; } > debian/changelog.new
    mv debian/changelog.new debian/changelog
fi
# The first version line in Cargo.toml is the package's.
sed -i.bak "1,/^version = /s/^version = .*/version = \"$version\"/" linux/Cargo.toml
sed -i.bak "/^name = \"mlh-ibus\"\$/{n;s/^version = .*/version = \"$version\"/;}" linux/Cargo.lock
sed -i.bak "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>.*</string>|<string>$version</string>|;}" Resources/Info.plist
rm linux/Cargo.toml.bak linux/Cargo.lock.bak Resources/Info.plist.bak
