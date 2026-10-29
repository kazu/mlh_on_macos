#!/bin/sh
set -eu

: "${CARGO_TARGET_DIR:?Set CARGO_TARGET_DIR to a local build directory}"
: "${MLH_STAGE_DIR:?Set MLH_STAGE_DIR to a staging directory}"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
dictionary="$root/.build/checkouts/AzooKeyKanaKanjiConverter/Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary"
if [ -e "$MLH_STAGE_DIR" ]; then
    echo "Staging directory already exists: $MLH_STAGE_DIR" >&2
    exit 1
fi
objc=$(gcc -print-file-name=libobjc.so)
export LIBRARY_PATH="$(dirname "$objc")${LIBRARY_PATH:+:$LIBRARY_PATH}"

swift build --package-path "$root" --product MLHBridge -c release -j 2
MLH_BRIDGE_DIR="$root/.build/release" cargo build --manifest-path "$root/linux/Cargo.toml" --release -j 2
mkdir -p "$MLH_STAGE_DIR/bin" "$MLH_STAGE_DIR/lib/mlh" "$MLH_STAGE_DIR/share/mlh"
install -m 755 "$CARGO_TARGET_DIR/release/mlh-ibus" "$MLH_STAGE_DIR/bin/mlh-ibus"
install -m 755 "$root/linux/mlh-gnome-terminal" "$MLH_STAGE_DIR/bin/mlh-gnome-terminal"
install -m 755 "$root/.build/release/libMLHBridge.so" "$MLH_STAGE_DIR/lib/mlh/libMLHBridge.so"
cp -R "$dictionary" "$MLH_STAGE_DIR/share/mlh/Dictionary"
