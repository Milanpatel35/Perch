.PHONY: bootstrap build test lint fmt run release site screenshots clean

# Pretty output if xcbeautify is around, raw xcodebuild if it is not. CI
# runners do not all ship it, and a missing formatter must not read as a
# failing build.
PRETTY := $(shell command -v xcbeautify 2>/dev/null || echo cat)

bootstrap:
	@command -v xcodegen  >/dev/null || brew install xcodegen
	@command -v swiftlint >/dev/null || brew install swiftlint
	@command -v xcbeautify >/dev/null || brew install xcbeautify
	xcodegen generate

build:
	set -o pipefail && xcodebuild -scheme Perch -configuration Debug build | $(PRETTY)

test:
	set -o pipefail && xcodebuild -scheme Perch -destination 'platform=macOS' test | $(PRETTY)

# swift-format ships inside the Swift toolchain as `swift format`. Prefer it
# over a separately installed binary so the formatter always matches the
# compiler — two versions of it disagree about indentation, and CI notices.
FORMAT := $(shell command -v swift-format 2>/dev/null || echo "swift format")

lint:
	swiftlint --strict
	$(FORMAT) lint --recursive --strict Sources Tests App

fmt:
	$(FORMAT) format --in-place --recursive Sources Tests App

run: build
	open build/Debug/Perch.app

release:
	bash Scripts/release.sh

# `build.js` first: the per-competitor pages are generated from
# data/comparison.json, so without it the footer's "vs …" links 404 locally
# while working perfectly in production, which is the worst way round.
site:
	cd Website && node build.js && python3 -m http.server 8000

# Re-render the website's screenshots from the app's own views.
#
# The TEST_RUNNER_ prefix is not decoration: it is how xcodebuild passes an
# environment variable into the test process rather than into itself, and
# without it the capture runs and writes nothing. Nobody would guess that,
# which is why this target exists (#15).
SHOTS ?= Website/assets/img/shots

screenshots:
	@mkdir -p $(SHOTS)
	set -o pipefail && TEST_RUNNER_PERCH_CAPTURE_DIR="$(CURDIR)/$(SHOTS)" \
		xcodebuild -project Perch.xcodeproj -scheme Perch \
		-destination 'platform=macOS' \
		test -only-testing:PerchUITests/IslandSnapshots | $(PRETTY)
	@echo "wrote:" && ls -1 $(SHOTS)

clean:
	rm -rf build DerivedData .build Perch.xcodeproj
