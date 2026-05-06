export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
XCODEBUILD := xcodebuild
PROJECT    := BeeBusy.xcodeproj
SCHEME     := BeeBusy
DERIVED    := $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: build run test clean

build:
	$(XCODEBUILD) build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		| grep -E '(error:|warning:|BUILD)'

run: build
	@APP=$$($(XCODEBUILD) build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		-showBuildSettings 2>/dev/null \
		| grep ' BUILT_PRODUCTS_DIR' | awk '{print $$3}'); \
	open "$$APP/BeeBusy.app"

test:
	$(XCODEBUILD) test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		| grep -E '(Test Suite|Test Case|error:|FAILED|passed|failed)'

clean:
	rm -rf $(DERIVED)/BeeBusy-*
