PROJECT = WhisperClaud.xcodeproj
SCHEME  = WhisperClaud
DERIVED = build
APP     = $(DERIVED)/Build/Products/Debug/WhisperClaud.app

# Signing: ad-hoc by default. Create mac/Local.mk (git-ignored) to use your certificate, e.g.
#   CODE_SIGN_IDENTITY = Apple Development
#   DEVELOPMENT_TEAM   = ABCDE12345
CODE_SIGN_IDENTITY ?= -
DEVELOPMENT_TEAM   ?=
-include Local.mk
export CODE_SIGN_IDENTITY DEVELOPMENT_TEAM

.PHONY: generate build run test clean

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS' build 2>&1 | grep -E "error:|warning: .*WhisperClaud/|BUILD " | sort -u

run: build
	-pkill -x WhisperClaud 2>/dev/null; sleep 0.3
	open "$(APP)"

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) -destination 'platform=macOS' test 2>&1 | grep -E "error:|Test Case|Executed|BUILD|TEST " | sort -u

clean:
	rm -rf $(DERIVED) $(PROJECT)
