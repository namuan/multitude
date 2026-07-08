.PHONY: all build run clean distclean release app

APP_NAME   := Multitude
APP_BUNDLE := $(APP_NAME).app
BUILD_DIR  := .build/debug
BINARY     := $(BUILD_DIR)/$(APP_NAME)

# ────────────────────────────────────
# Multitude — Multi‑account Gmail for Mac
# ────────────────────────────────────

all: build

build:
	swift build

# Build a proper .app bundle and launch it.
run: app
	open $(APP_BUNDLE)

# Build the .app bundle without launching.
app: build
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n' > "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '<plist version="1.0"><dict>\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '  <key>CFBundleExecutable</key><string>$(APP_NAME)</string>\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '  <key>CFBundleIdentifier</key><string>com.multitude.macos</string>\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '  <key>CFBundleName</key><string>Multitude</string>\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '  <key>CFBundlePackageType</key><string>APPL</string>\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '  <key>LSUIElement</key><false/>\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@printf '</dict></plist>\n' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo "Created $(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

distclean:
	rm -rf .build $(APP_BUNDLE)

release:
	swift build -c release
