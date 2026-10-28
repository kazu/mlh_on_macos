# mlh (modeless Japanese input, after Emacs egg-mlh.el) for macOS.
# Requires only the Command Line Tools (swiftc, codesign).

APP_NAME     := mlh
BUILD_DIR    := build
APP          := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS     := $(APP)/Contents
EXECUTABLE   := $(CONTENTS)/MacOS/$(APP_NAME)
PLIST        := $(CONTENTS)/Info.plist
ICON         := $(CONTENTS)/Resources/iconTemplate.tiff
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

# Signing identity: the self-signed one from scripts/make-signing-identity.sh
# when it exists (keeps the Accessibility permission across rebuilds), else ad-hoc.
SIGN_NAME    := MLH Local Code Signing
SIGN_IDENTITY ?= $(shell security find-certificate -c "$(SIGN_NAME)" >/dev/null 2>&1 && echo "$(SIGN_NAME)" || echo -)

.PHONY: all build test install install-system uninstall clean signing-identity

all: build

build: $(EXECUTABLE) $(PLIST) $(ICON) $(STRINGS)
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP)"
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

# Installs into /Library/Input Methods (needs sudo). Sandboxed apps such as
# the App Store version of Slack may not see input methods in ~/Library.
SYSTEM_INSTALLED := /Library/Input Methods/$(APP_NAME).app

install-system: build
	-killall $(APP_NAME) 2>/dev/null
	rm -rf "$(INSTALLED)"
	sudo rm -rf "$(SYSTEM_INSTALLED)"
	sudo cp -R "$(APP)" "$(SYSTEM_INSTALLED)"
	sudo chown -R root:wheel "$(SYSTEM_INSTALLED)"
	swift scripts/register.swift "$(SYSTEM_INSTALLED)"

uninstall:
	-killall $(APP_NAME) 2>/dev/null
	rm -rf "$(INSTALLED)"
	@echo "removed $(INSTALLED); remove mlh from System Settings > Keyboard > Input Sources if it is still listed."

clean:
	rm -rf "$(BUILD_DIR)"

signing-identity:
	scripts/make-signing-identity.sh "$(SIGN_NAME)"
