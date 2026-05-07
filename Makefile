export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
XCODEBUILD := xcodebuild
PROJECT    := CalendarCloak.xcodeproj
SCHEME     := CalendarCloak
DERIVED    := .build/DerivedData

BUILD_FLAGS := \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-derivedDataPath $(DERIVED) \
	-configuration Debug \
	-destination 'platform=macOS' \
	CODE_SIGN_IDENTITY="" \
	CODE_SIGNING_REQUIRED=NO

.PHONY: build run test clean generate archive

generate:
	xcodegen generate

archive: generate
	$(XCODEBUILD) archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath build/CalendarCloak-arm64.xcarchive \
		ARCHS=arm64 \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

build: generate
	$(XCODEBUILD) build $(BUILD_FLAGS) 2>&1 | tee /tmp/xcodebuild.log | \
		grep -E '(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)' || true
	@grep -q 'BUILD SUCCEEDED' /tmp/xcodebuild.log

run: build
	open $(DERIVED)/Build/Products/Debug/CalendarCloak.app

test:
	$(XCODEBUILD) test $(BUILD_FLAGS) 2>&1 | \
		grep -E '(Test Suite|Test Case|error:|FAILED|passed|failed)' || true

clean:
	rm -rf .build/
