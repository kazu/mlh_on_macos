# mlh (modeless Japanese input, after Emacs egg-mlh.el).
ifeq ($(shell uname -s),Linux)
include linux/Makefile
else

# Requires only the Command Line Tools (swift, codesign). The Swift packages
# (Package.swift) are fetched by SwiftPM on the first build.

APP_NAME     := mlh
BUILD_DIR    := build
APP          := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS     := $(APP)/Contents
EXECUTABLE   := $(CONTENTS)/MacOS/$(APP_NAME)
PLIST        := $(CONTENTS)/Info.plist
ICON         := $(CONTENTS)/Resources/iconTemplate.tiff
DICTIONARY   := $(CONTENTS)/Resources/Dictionary
LICENSES     := $(CONTENTS)/Resources/Licenses
FRAMEWORKS   := $(CONTENTS)/Frameworks
SETTINGS_APP := $(CONTENTS)/Resources/mlh-settings.app
SETTINGS_CONTENTS := $(SETTINGS_APP)/Contents
SETTINGS_EXECUTABLE := $(SETTINGS_CONTENTS)/MacOS/mlh-settings
SETTINGS_BACKEND := $(SETTINGS_CONTENTS)/MacOS/mlh-settings-backend
SETTINGS_TUI := $(SETTINGS_CONTENTS)/MacOS/mlh-settings-tui
SETTINGS_PLIST := $(SETTINGS_CONTENTS)/Info.plist
TUI_TARGET_DIR := $(if $(CARGO_TARGET_DIR),$(CARGO_TARGET_DIR),settings-tui/target)
# The zenz model for azooKey's neural conversion (CC-BY-SA 4.0, not bundled).
ZENZ_MODEL_URL := https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf
MLH_SUPPORT  := $(HOME)/Library/Application Support/mlh
ZENZ_MODEL   := $(MLH_SUPPORT)/zenz.gguf
STRINGS      := $(patsubst Resources/%,$(CONTENTS)/Resources/%,$(wildcard Resources/*.lproj/InfoPlist.strings))

SWIFT_BUILD  := swift build -c release
BIN_DIR      := .build/release
# CPUs to build the executable for, joined with lipo (`ARCHS="arm64 x86_64"`
# for a universal app); this Mac's by default.
ARCHS        ?= $(shell uname -m)
DMG          := $(BUILD_DIR)/$(APP_NAME).dmg
# Tests use @testable, so they get their own build directory with testing on.
TEST_BUILD   := $(SWIFT_BUILD) -Xswiftc -enable-testing --build-path .build/test
TEST_BIN     := .build/test/release/mlh-tests
# The azooKey dictionary, from the AzooKeyKanaKanjiConverter checkout (each
# build directory has its own).
AZOOKEY_DICT_PATH := AzooKeyKanaKanjiConverter/Sources/KanaKanjiConverterModuleWithDefaultDictionary/azooKey_dictionary_storage/Dictionary
AZOOKEY_DIR  := .build/checkouts/AzooKeyKanaKanjiConverter
AZOOKEY_DICT := .build/checkouts/$(AZOOKEY_DICT_PATH)

# The directory name contains a space: always quote it in recipes and never
# use it as a make target or prerequisite.
INSTALL_DIR  := $(HOME)/Library/Input Methods
INSTALLED    := $(INSTALL_DIR)/$(APP_NAME).app

# Signing identity: the self-signed one from scripts/make-signing-identity.sh
# when it exists (keeps the Accessibility permission across rebuilds), else ad-hoc.
SIGN_NAME    := MLH Local Code Signing
SIGN_IDENTITY ?= $(shell security find-certificate -c "$(SIGN_NAME)" >/dev/null 2>&1 && echo "$(SIGN_NAME)" || echo -)

.PHONY: all build executable test test-updates test-gui install install-system dmg verify-bundle uninstall clean signing-identity zenz-model

all: build

build: executable $(PLIST) $(SETTINGS_PLIST) $(ICON) $(STRINGS)
	if [ -d "$(FRAMEWORKS)" ]; then codesign --force --sign "$(SIGN_IDENTITY)" "$(FRAMEWORKS)"/*.framework; fi
	codesign --force --sign "$(SIGN_IDENTITY)" "$(SETTINGS_BACKEND)"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(SETTINGS_TUI)"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(SETTINGS_APP)"
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP)"
	@echo "built $(APP)"

verify-bundle:
	codesign --verify --deep --strict "$(APP)"
	test -x "$(SETTINGS_EXECUTABLE)"
	test -x "$(SETTINGS_TUI)"
	@set -e; snapshot=$$(mktemp "$(BUILD_DIR)/.settings-snapshot.XXXXXX"); \
		trap 'rm -f "$$snapshot"' 0; \
		"$(SETTINGS_BACKEND)" snapshot > "$$snapshot"; \
		test -s "$$snapshot"

# SwiftPM tracks the sources itself, so this always runs it.
executable:
	@mkdir -p "$(dir $(EXECUTABLE))" "$(DICTIONARY)" "$(dir $(SETTINGS_EXECUTABLE))"
	for arch in $(ARCHS); do \
		for product in $(APP_NAME) mlh-settings mlh-settings-backend; do \
			$(SWIFT_BUILD) --arch $$arch --product $$product || exit 1; \
		done; \
	done
	lipo -create $(foreach arch,$(ARCHS),".build/$(arch)-apple-macosx/release/$(APP_NAME)") -output "$(EXECUTABLE)"
	lipo -create $(foreach arch,$(ARCHS),".build/$(arch)-apple-macosx/release/mlh-settings") -output "$(SETTINGS_EXECUTABLE)"
	lipo -create $(foreach arch,$(ARCHS),".build/$(arch)-apple-macosx/release/mlh-settings-backend") -output "$(SETTINGS_BACKEND)"
	@set --; for arch in $(ARCHS); do \
		case $$arch in arm64) rust_arch=aarch64 ;; *) rust_arch=$$arch ;; esac; \
		CARGO_TARGET_DIR="$(TUI_TARGET_DIR)" cargo build --release --locked --manifest-path settings-tui/Cargo.toml --target "$$rust_arch-apple-darwin" || exit 1; \
		set -- "$$@" "$(TUI_TARGET_DIR)/$$rust_arch-apple-darwin/release/mlh-settings-tui"; \
	done; lipo -create "$$@" -output "$(SETTINGS_TUI)"
	rsync -a --delete "$(AZOOKEY_DICT)/" "$(DICTIONARY)/"
	@mkdir -p "$(LICENSES)"
	install -m 644 "$(AZOOKEY_DIR)/LICENSE" "$(LICENSES)/AzooKeyKanaKanjiConverter.txt"
	install -m 644 "$(AZOOKEY_DICT)/../LICENSE" "$(LICENSES)/azooKey_dictionary_storage.txt"
	install -m 644 LICENSE "$(LICENSES)/mlh.txt"
	# llama.framework, linked when azooKey is built with Zenzai (MLH_ZENZAI).
	rm -rf "$(FRAMEWORKS)"
	if otool -L "$(EXECUTABLE)" | grep -q llama.framework; then \
		mkdir -p "$(FRAMEWORKS)" && rsync -a "$(BIN_DIR)/llama.framework" "$(FRAMEWORKS)/" && \
		install -m 644 Resources/ThirdParty/llama.cpp-LICENSE.txt "$(LICENSES)/llama.cpp.txt"; \
	fi

$(CONTENTS)/Resources/%.lproj/InfoPlist.strings: Resources/%.lproj/InfoPlist.strings
	@mkdir -p "$(dir $@)"
	cp "$<" "$@"

$(PLIST): Resources/Info.plist
	@mkdir -p "$(dir $@)"
	plutil -lint Resources/Info.plist
	cp Resources/Info.plist "$@"

$(SETTINGS_PLIST): Resources/SettingsInfo.plist $(PLIST)
	@mkdir -p "$(dir $@)"
	plutil -lint Resources/SettingsInfo.plist
	cp Resources/SettingsInfo.plist "$@"
	plutil -replace CFBundleShortVersionString -string "$$(plutil -extract CFBundleShortVersionString raw -o - '$(PLIST)')" "$@"
	plutil -replace CFBundleVersion -string "$$(plutil -extract CFBundleVersion raw -o - '$(PLIST)')" "$@"

$(ICON): scripts/make-icon.swift
	@mkdir -p "$(dir $@)"
	swift scripts/make-icon.swift "$@"

test:
	$(TEST_BUILD) --product mlh-tests
	MLH_AZOOKEY_DICTIONARY=".build/test/checkouts/$(AZOOKEY_DICT_PATH)" ./$(TEST_BIN)
	$(SWIFT_BUILD) --product mlh-update-tests
	./.build/release/mlh-update-tests
	sh Tests/Updates/installer_fixture.sh "$(CURDIR)/.build/release/mlh-update-tests" "$(CURDIR)/$(BUILD_DIR)"

test-updates:
	$(SWIFT_BUILD) --product mlh-update-tests
	./.build/release/mlh-update-tests
	sh Tests/Updates/installer_fixture.sh "$(CURDIR)/.build/release/mlh-update-tests" "$(CURDIR)/$(BUILD_DIR)"

# Requires a logged-in macOS desktop with Accessibility access for System Events.
test-gui:
	@mkdir -p "$(BUILD_DIR)"
	@set -e; bin="$(CURDIR)/$(BUILD_DIR)/.settings-test/debug/mlh-settings"; server="$(CURDIR)/$(BUILD_DIR)/mlh-settings-http-test"; state="$(CURDIR)/$(BUILD_DIR)/.settings-gui-failure-state"; \
		trap 'rm -f "$$server" "$$state"' 0; \
		swift build -c debug --build-path "$(BUILD_DIR)/.settings-test" --product mlh-settings -Xswiftc -DMLH_TESTING; \
		swiftc Tests/GUIFailureHarness/model_http_server.swift -o "$$server"; \
		swift build -c debug --build-path "$(BUILD_DIR)/.settings-test" --product mlh-update-tests -Xswiftc -DMLH_TESTING; \
		swift build -c debug --build-path "$(BUILD_DIR)/.settings-test" --product mlh-settings-backend -Xswiftc -DMLH_TESTING; \
		swift Tests/GUIFailureHarness/main.swift "$$bin" "$(CURDIR)/Tests/GUIFailureHarness/backend.sh" "$$state"; \
		sh Tests/GUIFailureHarness/model_download.sh "$$bin" "$(CURDIR)/Tests/GUIFailureHarness/model_backend.sh" "$(CURDIR)/$(BUILD_DIR)" "$$server"; \
		sh Tests/GUIFailureHarness/model_races.sh "$$bin" "$(CURDIR)/Tests/GUIFailureHarness/model_backend.sh" "$(CURDIR)/$(BUILD_DIR)" "$$server" busy; \
		sh Tests/GUIFailureHarness/model_races.sh "$$bin" "$(CURDIR)/Tests/GUIFailureHarness/model_backend.sh" "$(CURDIR)/$(BUILD_DIR)" "$$server" cancel; \
		sh Tests/GUIFailureHarness/dynamic_navigation.sh "$$bin" "$(CURDIR)/Tests/GUIFailureHarness/dynamic_backend.sh" "$(CURDIR)/$(BUILD_DIR)"; \
		sh Tests/Updates/installer_fixture.sh "$(CURDIR)/$(BUILD_DIR)/.settings-test/debug/mlh-update-tests" "$(CURDIR)/$(BUILD_DIR)" "$$bin" "$$server" "$(CURDIR)/$(BUILD_DIR)/.settings-test/debug/mlh-settings-backend"

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

# A disk image with the app and a link to /Library/Input Methods to drag it to.
dmg: build
	rm -rf "$(BUILD_DIR)/dmg" "$(DMG)"
	ditto "$(APP)" "$(BUILD_DIR)/dmg/$(notdir $(APP))"
	ln -s "/Library/Input Methods" "$(BUILD_DIR)/dmg/Input Methods"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(BUILD_DIR)/dmg" -format UDZO "$(DMG)"
	rm -rf "$(BUILD_DIR)/dmg"

uninstall:
	-killall $(APP_NAME) 2>/dev/null
	rm -rf "$(INSTALLED)"
	@echo "removed $(INSTALLED); remove mlh from System Settings > Keyboard > Input Sources if it is still listed."

clean:
	rm -rf "$(BUILD_DIR)" .build

signing-identity:
	scripts/make-signing-identity.sh "$(SIGN_NAME)"

endif

# Downloads the zenz model used by azooKey's neural conversion.
zenz-model:
	mkdir -p "$(MLH_SUPPORT)"
	curl -fL -o "$(ZENZ_MODEL)" "$(ZENZ_MODEL_URL)"
