# 文件说明：构建 CLI 工具和 native runtime dylib

DIST_DIR := dist
BUILD_DIR := .build
MODULE_CACHE_DIR := $(BUILD_DIR)/ModuleCache
# 和 App 声明的最低系统版本保持一致，避免跟随构建机器抬高启动要求
SWIFT_TARGET := $(shell uname -m)-apple-macos11.0
CLI_SOURCES := $(wildcard Sources/PatcherCLI/*.swift)
APP_SOURCES := $(wildcard Sources/PatcherApp/*.swift)
RUNTIME_HEADERS := $(wildcard Runtime/*.h)
CLI_BINARY := $(DIST_DIR)/nmlrc-bg-patcher
RUNTIME_BINARY := $(DIST_DIR)/NMLyricBackgroundPatch.dylib
APP_BUNDLE := $(DIST_DIR)/MusicBar.app
APP_BINARY := $(APP_BUNDLE)/Contents/MacOS/MusicBar
APP_ICON := Packaging/NMLyricBackgroundPatcher.icns
DMG_NAME := MusicBar
DMG_STAGING := $(DIST_DIR)/MusicBar-dmg
DMG_RW := $(DIST_DIR)/MusicBar-rw.dmg
DMG_FINAL := $(DIST_DIR)/MusicBar.dmg

.PHONY: build clean dmg

build: $(CLI_BINARY) $(RUNTIME_BINARY) $(APP_BUNDLE)

dmg: build $(DMG_FINAL)

$(DIST_DIR):
	mkdir -p $(DIST_DIR)

$(MODULE_CACHE_DIR):
	mkdir -p $(MODULE_CACHE_DIR)

$(CLI_BINARY): $(CLI_SOURCES) Makefile | $(DIST_DIR) $(MODULE_CACHE_DIR)
	swiftc -O -target $(SWIFT_TARGET) -module-cache-path $(MODULE_CACHE_DIR) -o $@ $(CLI_SOURCES)

$(RUNTIME_BINARY): Runtime/NMLyricBackgroundPatch.m $(RUNTIME_HEADERS) Makefile | $(DIST_DIR) $(MODULE_CACHE_DIR)
	clang -dynamiclib -fobjc-arc -fblocks -mmacosx-version-min=11.0 \
		-fmodules-cache-path=$(MODULE_CACHE_DIR) \
		-framework AppKit -framework QuartzCore \
		-install_name @rpath/NMLyricBackgroundPatch.dylib \
		-current_version 0.1.3 -compatibility_version 0.1.0 \
		-o $@ Runtime/NMLyricBackgroundPatch.m

$(APP_BUNDLE): $(APP_SOURCES) $(CLI_SOURCES) $(CLI_BINARY) $(RUNTIME_BINARY) Packaging/NMLyricBackgroundPatcher-Info.plist $(APP_ICON) | $(DIST_DIR) $(MODULE_CACHE_DIR)
	rm -rf $(APP_BUNDLE)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp Packaging/NMLyricBackgroundPatcher-Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	printf "APPL????" > "$(APP_BUNDLE)/Contents/PkgInfo"
	cp $(APP_ICON) "$(APP_BUNDLE)/Contents/Resources/MusicBar.icns"
	cp $(CLI_BINARY) "$(APP_BUNDLE)/Contents/Resources/nmlrc-bg-patcher"
	cp $(RUNTIME_BINARY) "$(APP_BUNDLE)/Contents/Resources/NMLyricBackgroundPatch.dylib"
	swiftc -O -target $(SWIFT_TARGET) -module-cache-path $(MODULE_CACHE_DIR) -o "$(APP_BINARY)" $(filter-out Sources/PatcherCLI/main.swift,$(CLI_SOURCES)) $(APP_SOURCES)
	chmod +x "$(APP_BINARY)" "$(APP_BUNDLE)/Contents/Resources/nmlrc-bg-patcher"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

$(DMG_FINAL): $(APP_BUNDLE) Packaging/DMGBackground.swift | $(DIST_DIR)
	rm -rf "$(DMG_STAGING)" "$(DMG_RW)" "$(DMG_FINAL)"
	mkdir -p "$(DMG_STAGING)/.background"
	ditto "$(APP_BUNDLE)" "$(DMG_STAGING)/MusicBar.app"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	swift Packaging/DMGBackground.swift "$(DMG_STAGING)/.background/background.png"
	hdiutil create -volname "$(DMG_NAME)" -srcfolder "$(DMG_STAGING)" -ov -format UDRW "$(DMG_RW)"
	@set -e; \
	hdiutil detach "/Volumes/$(DMG_NAME)" >/dev/null 2>&1 || true; \
	hdiutil detach "/Volumes/$(DMG_NAME) 1" >/dev/null 2>&1 || true; \
	DEVICE=$$(hdiutil attach "$(DMG_RW)" -readwrite -noverify -noautoopen | awk 'END {print $$1}'); \
	osascript \
		-e 'tell application "Finder"' \
		-e 'tell disk "$(DMG_NAME)"' \
		-e 'open' \
		-e 'delay 1' \
		-e 'set current view of container window to icon view' \
		-e 'set toolbar visible of container window to false' \
		-e 'set statusbar visible of container window to false' \
		-e 'set pathbar visible of container window to false' \
		-e 'set the bounds of container window to {120, 120, 760, 390}' \
		-e 'set theViewOptions to the icon view options of container window' \
		-e 'set arrangement of theViewOptions to not arranged' \
		-e 'set icon size of theViewOptions to 96' \
		-e 'set background picture of theViewOptions to file ".background:background.png"' \
		-e 'set position of item "MusicBar.app" of container window to {172, 118}' \
		-e 'set position of item "Applications" of container window to {468, 118}' \
		-e 'close' \
		-e 'end tell' \
		-e 'end tell'; \
	sync; \
	hdiutil detach "$$DEVICE"
	hdiutil convert "$(DMG_RW)" -format UDZO -imagekey zlib-level=9 -o "$(DMG_FINAL)"
	rm -rf "$(DMG_STAGING)" "$(DMG_RW)"

clean:
	rm -rf $(DIST_DIR)
