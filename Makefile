# MLH (modeless Japanese input, after Emacs egg-mlh.el) for macOS.
# Requires only the Command Line Tools (swiftc, codesign).

APP_NAME     := MLH
BUILD_DIR    := build
APP          := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS     := $(APP)/Contents
EXECUTABLE   := $(CONTENTS)/MacOS/$(APP_NAME)
PLIST        := $(CONTENTS)/Info.plist
ICON         := $(CONTENTS)/Resources/icon.tiff
TEST_BIN     := $(BUILD_DIR)/mlh-tests
STRINGS      := $(patsubst Resources/%,$(CONTENTS)/Resources/%,$(wildcard Resources/*.lproj/InfoPlist.strings))

ARCH         := $(shell uname -m)
TARGET       := $(ARCH)-apple-macos13.0

SWIFTC       := swiftc
SWIFTFLAGS   := -O -swift-version 5 -target $(TARGET)
FRAMEWORKS   := -framework InputMethodKit -framework Carbon -framework Cocoa

CORE_SOURCES := $(wildcard Sources/Core/*.swift)
IME_SOURCES  := $(wildcard Sources/IME/*.swift)
TEST_SOURCES := $(wildcard Tests/*.swift)

# The directory name contains a space: always quote it in recipes and never
# use it as a make target or prerequisite.
INSTALL_DIR  := $(HOME)/Library/Input Methods
INSTALLED    := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: all build test install uninstall clean

all: build

build: $(EXECUTABLE) $(PLIST) $(ICON) $(STRINGS)
	codesign --force --sign - "$(APP)"
	@echo "built $(APP)"

$(EXECUTABLE): $(CORE_SOURCES) $(IME_SOURCES)
	@mkdir -p "$(dir $@)"
	$(SWIFTC) $(SWIFTFLAGS) $(FRAMEWORKS) -module-name MLH -o "$@" $(CORE_SOURCES) $(IME_SOURCES)

$(CONTENTS)/Resources/%.lproj/InfoPlist.strings: Resources/%.lproj/InfoPlist.strings
	@mkdir -p "$(dir $@)"
	cp "$<" "$@"

$(PLIST): Resources/Info.plist
	@mkdir -p "$(dir $@)"
	plutil -lint Resources/Info.plist
	cp Resources/Info.plist "$@"

$(ICON): scripts/make-icon.swift
	@mkdir -p "$(dir $@)"
	swift scripts/make-icon.swift "$@"

test: $(TEST_BIN)
	./$(TEST_BIN)

$(TEST_BIN): $(CORE_SOURCES) $(TEST_SOURCES)
	@mkdir -p "$(BUILD_DIR)"
	$(SWIFTC) -swift-version 5 -target $(TARGET) -module-name MLHTests -o "$@" $(CORE_SOURCES) $(TEST_SOURCES)

install: build
	-killall $(APP_NAME) 2>/dev/null
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" "$(INSTALLED)"
	swift scripts/register.swift "$(INSTALLED)"

uninstall:
	-killall $(APP_NAME) 2>/dev/null
	rm -rf "$(INSTALLED)"
	@echo "removed $(INSTALLED); remove MLH from System Settings > Keyboard > Input Sources if it is still listed."

clean:
	rm -rf "$(BUILD_DIR)"
