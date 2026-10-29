#!/bin/sh
set -eu

: "${MLH_STAGE_DIR:?Set MLH_STAGE_DIR to the directory produced by build.sh}"
prefix=${MLH_PREFIX:-"$HOME/.local"}
data=${XDG_DATA_HOME:-"$HOME/.local/share"}
mkdir -p "$prefix/bin" "$prefix/lib/mlh" "$data/mlh/Dictionary" "$data/ibus/component"
install -m 755 "$MLH_STAGE_DIR/bin/mlh-ibus" "$prefix/bin/mlh-ibus"
install -m 755 "$MLH_STAGE_DIR/bin/mlh-gnome-terminal" "$prefix/bin/mlh-gnome-terminal"
install -m 755 "$MLH_STAGE_DIR/lib/mlh/libMLHBridge.so" "$prefix/lib/mlh/libMLHBridge.so"
cp -Rf "$MLH_STAGE_DIR/share/mlh/Dictionary/." "$data/mlh/Dictionary/"
"$prefix/bin/mlh-ibus" --component-xml "$prefix/bin/mlh-ibus" > "$data/ibus/component/mlh.xml"
printf 'Installed mlh in %s\n' "$prefix"
printf 'IBus component: %s\n' "$data/ibus/component/mlh.xml"
