APP_NAME = Miaou
APP_BUNDLE = $(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
APP_DIR = $(HOME)/Applications
CLI_NAME = miaou
CLI_EMBED = miaou-cli
CLI_BIN ?= $(shell command -v $(CLI_NAME) 2>/dev/null || echo $(HOME)/.cargo/bin/$(CLI_NAME))

.PHONY: build app install-app icon clean

build:
	swift build -c release

icon:
	mkdir -p .build
	swiftc scripts/icon/main.swift Sources/Miaou/MistralLogo.swift Sources/Miaou/Chaton.swift -o .build/icongen
	.build/icongen Resources/AppIcon.icns

app: build
	@test -x "$(CLI_BIN)" || { echo "error: $(CLI_NAME) not found (looked in PATH and ~/.cargo/bin)."; echo "Install it first: cargo install --path cli (monorepo root)"; exit 1; }
	rm -rf $(APP_BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/$(APP_NAME) $(CONTENTS)/MacOS/$(APP_NAME)
	cp "$(CLI_BIN)" $(CONTENTS)/MacOS/$(CLI_EMBED)
	cp Info.plist $(CONTENTS)/Info.plist
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) (ad-hoc signed, LSUIElement: no Dock icon)"

install-app: app
	rm -rf "$(APP_DIR)/$(APP_BUNDLE)"
	cp -R $(APP_BUNDLE) "$(APP_DIR)/"
	@echo "Installed to $(APP_DIR)/$(APP_BUNDLE)"
	@echo "Launch it from there, then enable 'Lancer au démarrage' in its settings."

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
