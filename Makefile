.PHONY: all build run clean icons

APP_NAME   := Multitude
APP_BUNDLE := $(APP_NAME).app
BUILD_DIR  := .build/debug
BINARY     := $(BUILD_DIR)/$(APP_NAME)
ICON_SRC   := assets/logo.png
ICON_OUT   := Supporting/AppIcon.icns

all: build

icons:
	@scripts/generate-icons.sh

build:
	swift build

run: app
	open "$(APP_BUNDLE)"

app: build icons
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Supporting/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@cp "$(ICON_OUT)" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@echo "Created $(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)"
