.PHONY: all build run clean

APP_NAME   := Multitude
APP_BUNDLE := $(APP_NAME).app
BUILD_DIR  := .build/debug
BINARY     := $(BUILD_DIR)/$(APP_NAME)

all: build

build:
	swift build

run: app
	open "$(APP_BUNDLE)"

app: build
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Supporting/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@echo "Created $(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)"
