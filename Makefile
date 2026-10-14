.PHONY: app app-native run run-native open clean install run-raw icon dmg dmg-native

CONFIGURATION ?= release
VERSION ?= 1.1.0
NATIVE_ARCH := $(shell uname -m)
ICONSET = ForexMarketHours.iconset
ICNS = Resources/AppIcon.icns

## Regenerate the app icon from Scripts/make-icon.swift (runs automatically when missing)
icon: $(ICNS)

$(ICNS): Scripts/make-icon.swift
	rm -rf $(ICONSET) && mkdir -p $(ICONSET)
	swift Scripts/make-icon.swift $(ICONSET)
	iconutil -c icns $(ICONSET) -o $(ICNS)

app: icon
	Scripts/build-app.sh $(CONFIGURATION)

app-native: icon
	Scripts/build-app.sh $(CONFIGURATION) $(NATIVE_ARCH)

## Drag-to-install DMG (universal app + /Applications link + LICENSE) into ./dist
dmg: app
	Scripts/make-dmg.sh $(VERSION)

dmg-native: app-native
	Scripts/make-dmg.sh $(VERSION)

CONFIGURATION ?= release
NATIVE_ARCH := $(shell uname -m)

app:
	Scripts/build-app.sh $(CONFIGURATION)

app-native:
	Scripts/build-app.sh $(CONFIGURATION) $(NATIVE_ARCH)

run: app
	open build/ForexMarketHours.app

run-native: app-native
	open build/ForexMarketHours.app

open:
	open build/ForexMarketHours.app

run-raw:
	swift run -c $(CONFIGURATION) ForexMarketHours

install: app
	rm -rf /Applications/ForexMarketHours.app
	cp -R build/ForexMarketHours.app /Applications/ForexMarketHours.app
	@echo "Installed /Applications/ForexMarketHours.app"

clean:
	swift package clean
	rm -rf build .build-universal
