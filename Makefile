.PHONY: bootstrap build test lint fmt run release site clean

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

site:
	cd Website && python3 -m http.server 8000

clean:
	rm -rf build DerivedData .build Perch.xcodeproj
