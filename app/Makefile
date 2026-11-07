APP_NAME = Miaou
APP_BUNDLE = $(APP_NAME).app
APP_DIR = $(HOME)/Applications
CLI_NAME = miaou
CLI_BIN ?= $(shell command -v $(CLI_NAME) 2>/dev/null || echo $(HOME)/.cargo/bin/$(CLI_NAME))

# Package.swift enumerates sources; cached manifests can omit newly added files.
.PHONY: build app install-app install-only icon clean test

build:
	swift build --manifest-cache none -c release

icon:
	mkdir -p .build
	swiftc scripts/icon/main.swift Sources/Miaou/MistralLogo.swift Sources/Miaou/PetGlyph.swift Sources/Miaou/Chaton.swift Sources/Miaou/Chonk.swift -o .build/icongen
	.build/icongen Resources/AppIcon.icns

app:
	CLI_BIN="$(CLI_BIN)" python3 build-app.py

install-only:
	INSTALL_DIR="$(APP_DIR)" python3 build-app.py --install-only

install-app: app install-only

test:
	swift test --manifest-cache none
	python3 -m unittest discover -s scripts/tests

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
