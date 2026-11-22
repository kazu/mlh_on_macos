#!/bin/sh
set -eu

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
dpkg-deb -x "${1:?supply the built deb}" "$work"
doc="$work/usr/share/doc/mlh-ibus"
test -x "$work/usr/bin/mlh-ibus"
test -x "$work/usr/bin/mlh-settings-gtk"
test -f "$work/usr/share/ibus/component/mlh.xml"
test -f "$work/usr/share/applications/mlh-settings.desktop"
grep -F "<version>$(dpkg-deb -f "$1" Version)</version>" "$work/usr/share/ibus/component/mlh.xml" >/dev/null
grep -F '<setup>&apos;/usr/bin/mlh-settings-gtk&apos;</setup>' "$work/usr/share/ibus/component/mlh.xml" >/dev/null
grep -Fx 'Exec=mlh-settings-gtk' "$work/usr/share/applications/mlh-settings.desktop" >/dev/null
"$work/usr/bin/mlh-ibus" --component-xml /usr/local/bin/mlh-ibus |
    grep -F '<setup>&apos;/usr/local/bin/mlh-settings-gtk&apos;</setup>' >/dev/null
test -f "$doc/licenses/rust/percent-encoding-2.3.2/LICENSE-MIT"
test -f "$doc/licenses/swift/AzooKeyKanaKanjiConverter/LICENSE"
test -f "$doc/azooKey-dictionary-LICENSE.gz"
grep -q GPL-3-or-later "$doc/copyright"
