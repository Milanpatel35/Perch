.PHONY: bootstrap build test lint fmt run release site clean

bootstrap:
	@command -v xcodegen  >/dev/null || brew install xcodegen
	@command -v swiftlint >/dev/null || brew install swiftlint
	@command -v swift-format >/dev/null || brew install swift-format
	xcodegen generate

build:
	xcodebuild -scheme Perch -configuration Debug build | xcbeautify

test:
	xcodebuild -scheme Perch -destination 'platform=macOS' test | xcbeautify

lint:
	swiftlint --strict
	swift-format lint --recursive --strict Sources Tests App

fmt:
	swift-format format --in-place --recursive Sources Tests App

run: build
	open build/Debug/Perch.app

release:
	bash Scripts/release.sh

site:
	cd Website && python3 -m http.server 8000

clean:
	rm -rf build DerivedData .build Perch.xcodeproj
