PREFIX ?= /usr/local
DESTDIR ?=
MLH_WORK_DIR ?= $(HOME)/.cache/mlh-wayland
SWIFT_BUILD_DIR ?= $(MLH_WORK_DIR)/swift
CARGO_TARGET_DIR ?= $(MLH_WORK_DIR)/cargo
JOBS ?= 2

AZOOKEY_DIR := $(SWIFT_BUILD_DIR)/checkouts/AzooKeyKanaKanjiConverter
DICTIONARY := $(AZOOKEY_DIR)/Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary
SWIFT_LIB := $(SWIFT_BUILD_DIR)/release/libMLHBridge.so
LINUX_BIN := $(CARGO_TARGET_DIR)/release/mlh-ibus
OBJC_LIB_DIR := $(dir $(shell gcc -print-file-name=libobjc.so))

.PHONY: all build install test deb
all: build

build:
	LIBRARY_PATH="$(OBJC_LIB_DIR):$(LIBRARY_PATH)" swift build --scratch-path "$(SWIFT_BUILD_DIR)" --product MLHBridge -c release -j $(JOBS)
	MLH_BRIDGE_DIR="$(SWIFT_BUILD_DIR)/release" CARGO_TARGET_DIR="$(CARGO_TARGET_DIR)" cargo build --locked --manifest-path linux/Cargo.toml --release -j $(JOBS)

install: build
	install -d "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/lib/mlh" "$(DESTDIR)$(PREFIX)/share/mlh/Dictionary" "$(DESTDIR)$(PREFIX)/share/ibus/component" "$(DESTDIR)$(PREFIX)/share/doc/mlh-ibus"
	install -m 755 "$(LINUX_BIN)" "$(DESTDIR)$(PREFIX)/bin/mlh-ibus"
	install -m 755 linux/mlh-gnome-terminal "$(DESTDIR)$(PREFIX)/bin/mlh-gnome-terminal"
	install -m 755 "$(SWIFT_LIB)" "$(DESTDIR)$(PREFIX)/lib/mlh/libMLHBridge.so"
	cp -Rf "$(DICTIONARY)/." "$(DESTDIR)$(PREFIX)/share/mlh/Dictionary/"
	install -m 644 "$(AZOOKEY_DIR)/LICENSE" "$(DESTDIR)$(PREFIX)/share/doc/mlh-ibus/AzooKeyKanaKanjiConverter-LICENSE"
	install -m 644 "$(DICTIONARY)/../LICENSE" "$(DESTDIR)$(PREFIX)/share/doc/mlh-ibus/azooKey-dictionary-LICENSE"
	swift linux/collect-licenses.swift "$(DESTDIR)$(PREFIX)/share/doc/mlh-ibus/licenses" "$(SWIFT_BUILD_DIR)/checkouts"
	"$(DESTDIR)$(PREFIX)/bin/mlh-ibus" --component-xml "$(PREFIX)/bin/mlh-ibus" > "$(DESTDIR)$(PREFIX)/share/ibus/component/mlh.xml"

test: build
	dbus-run-session -- env LD_LIBRARY_PATH="$(SWIFT_BUILD_DIR)/release:$(LD_LIBRARY_PATH)" MLH_BRIDGE_DIR="$(SWIFT_BUILD_DIR)/release" CARGO_TARGET_DIR="$(CARGO_TARGET_DIR)" cargo test --locked --manifest-path linux/Cargo.toml --release -j $(JOBS)

deb:
	dpkg-buildpackage -b -us -uc
