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
# The zenz model for azooKey's neural conversion (CC-BY-SA 4.0, not bundled).
ZENZ_MODEL_URL := https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf
MLH_SUPPORT  := $(HOME)/Library/Application Support/mlh
ZENZ_MODEL   := $(MLH_SUPPORT)/zenz.gguf
STRINGS      := $(patsubst Resources/%,$(CONTENTS)/Resources/%,$(wildcard Resources/*.lproj/InfoPlist.strings))

SWIFT_BUILD  := swift build -c release
BIN_DIR      := .build/release
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

.PHONY: all build executable test install install-system uninstall clean signing-identity zenz-model

all: build

build: executable $(PLIST) $(ICON) $(STRINGS)
	if [ -d "$(FRAMEWORKS)" ]; then codesign --force --sign "$(SIGN_IDENTITY)" "$(FRAMEWORKS)"/*.framework; fi
	codesign --force --sign "$(SIGN_IDENTITY)" "$(APP)"
	@echo "built $(APP)"

# SwiftPM tracks the sources itself, so this always runs it.
executable:
	$(SWIFT_BUILD) --product $(APP_NAME)
	@mkdir -p "$(dir $(EXECUTABLE))" "$(DICTIONARY)"
	cp "$(BIN_DIR)/$(APP_NAME)" "$(EXECUTABLE)"
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

$(ICON): scripts/make-icon.swift
	@mkdir -p "$(dir $@)"
	swift scripts/make-icon.swift "$@"

test:
	$(TEST_BUILD) --product mlh-tests
	MLH_AZOOKEY_DICTIONARY=".build/test/checkouts/$(AZOOKEY_DICT_PATH)" ./$(TEST_BIN)

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
	rm -rf "$(BUILD_DIR)" .build

signing-identity:
	scripts/make-signing-identity.sh "$(SIGN_NAME)"

endif

# Downloads the zenz model used by azooKey's neural conversion.
zenz-model:
	mkdir -p "$(MLH_SUPPORT)"
	curl -fL -o "$(ZENZ_MODEL)" "$(ZENZ_MODEL_URL)"
