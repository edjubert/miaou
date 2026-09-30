APP_NAME = VibeGod
APP_BUNDLE = $(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
APP_DIR = $(HOME)/Applications

.PHONY: build app install-app clean

build:
	swift build -c release

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(CONTENTS)/MacOS
	cp .build/release/$(APP_NAME) $(CONTENTS)/MacOS/$(APP_NAME)
	cp Info.plist $(CONTENTS)/Info.plist
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
