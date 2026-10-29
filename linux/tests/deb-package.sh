#!/bin/sh
set -eu

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
dpkg-deb -x "${1:?supply the built deb}" "$work"
doc="$work/usr/share/doc/mlh-ibus"
test -x "$work/usr/bin/mlh-ibus"
test -f "$work/usr/share/ibus/component/mlh.xml"
test -f "$doc/licenses/rust/percent-encoding-2.3.2/LICENSE-MIT"
test -f "$doc/licenses/swift/AzooKeyKanaKanjiConverter/LICENSE"
test -f "$doc/azooKey-dictionary-LICENSE.gz"
grep -q GPL-3-or-later "$doc/copyright"
