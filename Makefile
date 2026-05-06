export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
XCODEBUILD := xcodebuild
PROJECT    := BeeBusy.xcodeproj
SCHEME     := BeeBusy
DERIVED    := .build/DerivedData

BUILD_FLAGS := \
	-project $(PROJECT) \
	-scheme $(SCHEME) \
	-derivedDataPath $(DERIVED) \
	-configuration Debug \
	-destination 'platform=macOS' \
	CODE_SIGN_IDENTITY="" \
	CODE_SIGNING_REQUIRED=NO

.PHONY: build run test clean

build:
	$(XCODEBUILD) build $(BUILD_FLAGS) \
		2>&1 | grep -E '^(.*error:|.*warning:|Build succeeded|BUILD SUCCEEDED|BUILD FAILED)'

run: build
	open $(DERIVED)/Build/Products/Debug/BeeBusy.app

test:
	$(XCODEBUILD) test $(BUILD_FLAGS) \
		2>&1 | grep -E '(Test Suite|Test Case|error:|FAILED|passed|failed)'

clean:
	rm -rf .build/
