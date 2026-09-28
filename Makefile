# FlowMoney developer entry points. `make help` lists targets.
SHELL := /bin/bash
PROJECT := FlowMoney.xcodeproj
SCHEME := FlowMoney
# A connected iPhone by default (override: make test DEVICE_ID=<udid>, or DESTINATION='platform=iOS Simulator,name=iPhone 16').
DEVICE_ID ?= $(shell xcrun xctrace list devices 2>/dev/null | grep -v Simulator | grep -E '\([0-9]+\.[0-9.]+\) \(' | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]+)\)$$/\1/')
DESTINATION ?= id=$(DEVICE_ID)
XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null || echo cat)
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath DerivedData -allowProvisioningUpdates

.PHONY: help bootstrap project open build run test test-unit test-ui lint format icon clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install tooling (XcodeGen, SwiftLint, SwiftFormat, xcbeautify)
	brew install xcodegen swiftlint swiftformat xcbeautify

project: ## Generate FlowMoney.xcodeproj from project.yml
	xcodegen generate

open: project ## Generate and open in Xcode
	open $(PROJECT)

build: project ## Debug build for the destination (default: connected iPhone)
	$(XCODEBUILD) -destination '$(DESTINATION)' build | $(XCBEAUTIFY)

run: build ## Build, install and launch on the connected iPhone
	xcrun devicectl device install app --device $(DEVICE_ID) DerivedData/Build/Products/Debug-iphoneos/FlowMoney.app
	xcrun devicectl device process launch --device $(DEVICE_ID) com.lynkto.flowmoney

test-unit: project ## Unit tests (swift-testing), hosted in the app so they run on a real iPhone
	$(XCODEBUILD) -destination '$(DESTINATION)' test -only-testing:FlowMoneyTests | $(XCBEAUTIFY)

test-ui: project ## Critical-path UI tests
	$(XCODEBUILD) -destination '$(DESTINATION)' test -only-testing:FlowMoneyUITests | $(XCBEAUTIFY)

test: test-unit test-ui ## All tests

lint: ## SwiftLint (strict) + SwiftFormat (check only)
	swiftlint lint --strict
	swiftformat --lint .

format: ## Auto-format sources
	swiftformat .
	swiftlint lint --fix

icon: ## Regenerate the App Store icon
	swift scripts/make_app_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
	python3 -c "from PIL import Image; p='App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'; Image.open(p).convert('RGB').save(p)"

clean: ## Remove build products
	rm -rf DerivedData build
