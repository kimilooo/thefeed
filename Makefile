.PHONY: all build build-server build-client test clean lint fmt vet \
	ios-bind ios-bind-catalyst ios-build ios-test ios-clean ios-list-sims ios-deps \
	push push-tags release setup-remotes

BINARY_SERVER = thefeed-server
BINARY_CLIENT = thefeed-client
BUILD_DIR = build

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
DATE    ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS = -s -w \
	-X github.com/sartoopjj/thefeed/internal/version.Version=$(VERSION) \
	-X github.com/sartoopjj/thefeed/internal/version.Commit=$(COMMIT) \
	-X github.com/sartoopjj/thefeed/internal/version.Date=$(DATE)

GOFLAGS = -trimpath -ldflags="$(LDFLAGS)"
export CGO_ENABLED = 0

# CLIENT_GOFLAGS appends the platform-specific AssetTemplate so the
# in-app GitHub update check (internal/update) can point users at the
# right published binary. {V} is replaced at runtime with the version
# string read from the public VERSION file. Pass the asset filename as
# the first argument.
#   $(call CLIENT_GOFLAGS,thefeed-client-{V}-linux-amd64)
CLIENT_GOFLAGS = -trimpath -ldflags="$(LDFLAGS) -X github.com/sartoopjj/thefeed/internal/version.AssetTemplate=$(1)"

all: test build

build: build-server build-client

build-server:
	@mkdir -p $(BUILD_DIR)
	go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_SERVER) ./cmd/server

build-client:
	@mkdir -p $(BUILD_DIR)
	go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_CLIENT) ./cmd/client

test:
	go test -race -count=1 ./...

lint: vet
	@command -v golangci-lint >/dev/null 2>&1 || echo "golangci-lint not found, skipping"
	@command -v golangci-lint >/dev/null 2>&1 && golangci-lint run ./... || true

vet:
	go vet ./...

fmt:
	gofmt -s -w .

clean:
	rm -rf $(BUILD_DIR)

# Cross-compilation targets
build-all: build-linux-amd64 build-linux-arm64 build-darwin-amd64 build-darwin-arm64 build-freebsd-amd64 build-freebsd-arm64 build-windows-amd64 build-android-arm64 build-android-arm

build-linux-amd64:
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=amd64 go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_SERVER)-linux-amd64 ./cmd/server
	GOOS=linux GOARCH=amd64 go build $(call CLIENT_GOFLAGS,thefeed-client-{V}-linux-amd64) -o $(BUILD_DIR)/$(BINARY_CLIENT)-linux-amd64 ./cmd/client

build-linux-arm64:
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=arm64 go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_SERVER)-linux-arm64 ./cmd/server
	GOOS=linux GOARCH=arm64 go build $(call CLIENT_GOFLAGS,thefeed-client-{V}-linux-arm64) -o $(BUILD_DIR)/$(BINARY_CLIENT)-linux-arm64 ./cmd/client

build-darwin-amd64:
	@mkdir -p $(BUILD_DIR)
	GOOS=darwin GOARCH=amd64 go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_SERVER)-darwin-amd64 ./cmd/server
	GOOS=darwin GOARCH=amd64 go build $(call CLIENT_GOFLAGS,thefeed-client-{V}-darwin-amd64) -o $(BUILD_DIR)/$(BINARY_CLIENT)-darwin-amd64 ./cmd/client

build-darwin-arm64:
	@mkdir -p $(BUILD_DIR)
	GOOS=darwin GOARCH=arm64 go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_SERVER)-darwin-arm64 ./cmd/server
	GOOS=darwin GOARCH=arm64 go build $(call CLIENT_GOFLAGS,thefeed-client-{V}-darwin-arm64) -o $(BUILD_DIR)/$(BINARY_CLIENT)-darwin-arm64 ./cmd/client

build-freebsd-amd64:
	@mkdir -p $(BUILD_DIR)
	GOOS=freebsd GOARCH=amd64 go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_SERVER)-freebsd-amd64 ./cmd/server
	GOOS=freebsd GOARCH=amd64 go build $(call CLIENT_GOFLAGS,thefeed-client-{V}-freebsd-amd64) -o $(BUILD_DIR)/$(BINARY_CLIENT)-freebsd-amd64 ./cmd/client

build-freebsd-arm64:
	@mkdir -p $(BUILD_DIR)
	GOOS=freebsd GOARCH=arm64 go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_SERVER)-freebsd-arm64 ./cmd/server
	GOOS=freebsd GOARCH=arm64 go build $(call CLIENT_GOFLAGS,thefeed-client-{V}-freebsd-arm64) -o $(BUILD_DIR)/$(BINARY_CLIENT)-freebsd-arm64 ./cmd/client

build-windows-amd64:
	@mkdir -p $(BUILD_DIR)
	GOOS=windows GOARCH=amd64 go build $(GOFLAGS) -o $(BUILD_DIR)/$(BINARY_SERVER)-windows-amd64.exe ./cmd/server
	GOOS=windows GOARCH=amd64 go build $(call CLIENT_GOFLAGS,thefeed-client-{V}-windows-amd64.exe) -o $(BUILD_DIR)/$(BINARY_CLIENT)-windows-amd64.exe ./cmd/client

build-android-arm64:
	@mkdir -p $(BUILD_DIR)
	GOOS=android GOARCH=arm64 go build $(call CLIENT_GOFLAGS,thefeed-client-android-arm64) -o $(BUILD_DIR)/$(BINARY_CLIENT)-android-arm64 ./cmd/client

build-android-arm:
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=arm GOARM=7 go build $(call CLIENT_GOFLAGS,thefeed-client-android-arm) -o $(BUILD_DIR)/$(BINARY_CLIENT)-android-arm ./cmd/client

# ===== iOS / Mac Catalyst =====
# Requires: Xcode + gomobile (go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init)

IOS_DIR = ios
IOS_FRAMEWORK = $(IOS_DIR)/Mobile.xcframework
IOS_SCHEME = Thefeed
IOS_PROJECT = $(IOS_DIR)/Thefeed.xcodeproj
# Default simulator: pick the first available iPhone (override with IOS_SIM_NAME='iPhone 17').
IOS_SIM_NAME ?= $(shell xcrun simctl list devices available 2>/dev/null | awk -F'[()]' '/-- iOS [0-9]/{ios=1;next} /^-- /{ios=0} ios && /iPhone/{print $$1; exit}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//')

# Strip a leading 'v' so MARKETING_VERSION accepts e.g. v0.18.0 / 0.18.0.
IOS_MARKETING_VERSION = $(patsubst v%,%,$(VERSION))
# Build number must be a positive integer; commit count is monotonic.
IOS_BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
IOS_LDFLAGS = -X github.com/sartoopjj/thefeed/internal/version.Version=$(VERSION) \
              -X github.com/sartoopjj/thefeed/internal/version.Commit=$(COMMIT) \
              -X github.com/sartoopjj/thefeed/internal/version.Date=$(DATE)
IOS_XCODE_VERSIONS = MARKETING_VERSION="$(IOS_MARKETING_VERSION)" CURRENT_PROJECT_VERSION="$(IOS_BUILD_NUMBER)"

ios-deps:
	@grep -q "golang.org/x/mobile" go.mod || go get golang.org/x/mobile/bind golang.org/x/mobile/bind/objc
	go mod tidy

ios-bind: ios-deps
	@command -v gomobile >/dev/null 2>&1 || { echo "gomobile not found. Run: go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init"; exit 1; }
	gomobile bind -iosversion=14.0 -target=ios,iossimulator -ldflags='$(IOS_LDFLAGS)' -o $(IOS_FRAMEWORK) ./mobile

ios-bind-catalyst: ios-deps
	@command -v gomobile >/dev/null 2>&1 || { echo "gomobile not found"; exit 1; }
	gomobile bind -iosversion=14.0 -target=ios,iossimulator,maccatalyst -ldflags='$(IOS_LDFLAGS)' -o $(IOS_FRAMEWORK) ./mobile

ios-list-sims:
	xcrun simctl list devices available

ios-build: $(IOS_FRAMEWORK)
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) \
		-destination 'platform=iOS Simulator,name=$(IOS_SIM_NAME)' \
		$(IOS_XCODE_VERSIONS) \
		build

ios-test: $(IOS_FRAMEWORK)
	xcodebuild test -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) \
		-destination 'platform=iOS Simulator,name=$(IOS_SIM_NAME)' \
		$(IOS_XCODE_VERSIONS)

$(IOS_FRAMEWORK):
	$(MAKE) ios-bind

ios-clean:
	rm -rf $(IOS_FRAMEWORK) $(IOS_DIR)/build $(IOS_DIR)/DerivedData

# ===== Android (gomobile in-process) =====
# Requires: gomobile + Android SDK/NDK. The APK loads the Go HTTP server
# via JNI System.loadLibrary instead of exec'ing a bundled binary —
# avoids W^X / SELinux / 16 KB-page / AV pitfalls of the subprocess
# approach. ANDROID_HOME and ANDROID_NDK_HOME must be set.

ANDROID_AAR_DIR = android/app/libs
ANDROID_AAR = $(ANDROID_AAR_DIR)/mobile.aar
# -s -w strips the symbol table + DWARF debug info from the embedded
# libgojni.so. With the same imports the old subprocess client binary
# was ~8 MB; without these flags gomobile's .so was running >20 MB.
# -extldflags forces 16 KB page alignment so the .so loads on Android
# 15+ devices configured with 16 KB pages (NDK r28+ defaults to this).
ANDROID_LDFLAGS = -s -w \
                  -X github.com/sartoopjj/thefeed/internal/version.Version=$(VERSION) \
                  -X github.com/sartoopjj/thefeed/internal/version.Commit=$(COMMIT) \
                  -X github.com/sartoopjj/thefeed/internal/version.Date=$(DATE) \
                  -extldflags=-Wl,-z,max-page-size=16384

android-bind: ios-deps
	@command -v gomobile >/dev/null 2>&1 || { echo "gomobile not found. Run: go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init"; exit 1; }
	@mkdir -p $(ANDROID_AAR_DIR)
	gomobile bind -target=android/arm,android/arm64,android/386,android/amd64 -androidapi 24 -ldflags='$(ANDROID_LDFLAGS)' -o $(ANDROID_AAR) ./mobile

# Two gradle passes: first produces 4 per-ABI APKs (arm, arm64, x86,
# x86_64); second produces a universal APK containing 3 ABIs (no x86).
android-apk: android-bind
	@cd android && if [ ! -x ./gradlew ]; then gradle wrapper --gradle-version 8.10.2; fi && ./gradlew --no-daemon assembleRelease
	@cd android && ./gradlew --no-daemon -PuniversalBuild=true assembleRelease

android-clean:
	rm -f $(ANDROID_AAR)
	rm -rf android/app/build android/build android/.gradle

# ===== Git multi-remote =====
# We maintain two mirrors: origin (GitLab) and gh-origin (GitHub).
# The targets below push to both so the two repos never drift.
# Override with REMOTES=... to push to only a subset.
REMOTES ?= origin gh-origin
BRANCH  ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)

# Configure both mirrors on a fresh clone (one-time). Idempotent — calling
# it again just updates the URLs. Adjust the URLs here if a repo moves.
GITLAB_URL ?= https://gitlab.com/sartoopjj/thefeed.git
GITHUB_URL ?= https://github.com/sartoopjj/thefeed.git
setup-remotes:
	@if git remote | grep -q '^origin$$'; then \
		git remote set-url origin $(GITLAB_URL); \
	else \
		git remote add origin $(GITLAB_URL); \
	fi
	@if git remote | grep -q '^gh-origin$$'; then \
		git remote set-url gh-origin $(GITHUB_URL); \
	else \
		git remote add gh-origin $(GITHUB_URL); \
	fi
	@echo "Remotes configured:"
	@git remote -v

# Push the current branch to every remote in REMOTES. Stops at the first
# failure so you notice instead of silently desyncing the mirrors.
push:
	@for r in $(REMOTES); do \
		echo "→ $$r $(BRANCH)"; \
		git push $$r $(BRANCH) || exit $$?; \
	done

# Push all annotated tags to every remote in REMOTES.
push-tags:
	@for r in $(REMOTES); do \
		echo "→ $$r --tags"; \
		git push $$r --tags || exit $$?; \
	done

# Tag the current HEAD and push it everywhere. Use:
#   make release V=v0.19.0 [M="release notes"]
# The push runs after the tag so a tag-name typo aborts before any
# remote sees it. CI is wired to the v* tag pattern on GitHub.
release:
	@test -n "$(V)" || { echo "set V=vX.Y.Z (e.g. make release V=v0.19.0)" >&2; exit 1; }
	@case "$(V)" in v*) ;; *) echo "V must start with 'v' (got $(V))" >&2; exit 1 ;; esac
	@if git rev-parse "$(V)" >/dev/null 2>&1; then \
		echo "Tag $(V) already exists locally — delete it first or pick a new version" >&2; exit 1; \
	fi
	git tag -a $(V) -m "$(if $(M),$(M),Release $(V))"
	$(MAKE) push
	$(MAKE) push-tags

# UPX compression (requires upx in PATH) — only for Linux/Windows binaries
upx:
	@command -v upx >/dev/null 2>&1 || { echo "upx not found, skipping compression"; exit 0; }
	@for f in $(BUILD_DIR)/$(BINARY_SERVER)-linux-* $(BUILD_DIR)/$(BINARY_CLIENT)-linux-* \
	          $(BUILD_DIR)/$(BINARY_SERVER)-windows-*.exe $(BUILD_DIR)/$(BINARY_CLIENT)-windows-*.exe \
	          $(BUILD_DIR)/$(BINARY_CLIENT)-android-*; do \
		if [ -f "$$f" ]; then echo "UPX: $$f"; upx --best --lzma "$$f" || true; fi \
	done
