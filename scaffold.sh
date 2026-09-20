#!/usr/bin/env bash
#
# scaffold.sh — generates the Perch repository skeleton.
#
#   bash scaffold.sh [target-dir]      # default: ./perch
#
# Creates the folder tree, git repo with main + dev branches, and all the
# boilerplate files that are too small to keep as separate documents.
# README.md, CONTRIBUTING.md, CLAUDE.md and docs/ are shipped separately —
# copy them in after running this.
#
# Module folders follow docs/FEATURES.md — all 18, P0 through P2. The P2 ones
# are created empty on purpose: an empty directory is a cheap reminder of what
# was promised.
#
# No nested heredocs: every block is a single-quoted, uniquely-named heredoc.

set -euo pipefail

TARGET="${1:-perch}"
ORG="${ORG:-your-org}"
YEAR="$(date +%Y)"

echo "==> Scaffolding Perch into ./${TARGET}"
mkdir -p "$TARGET"
cd "$TARGET"

# ---------------------------------------------------------------- folders ---

mkdir -p \
  App \
  Sources/PerchCore/Island \
  Sources/PerchCore/Geometry \
  Sources/PerchCore/Services \
  Sources/PerchUI/Panel \
  Sources/PerchUI/Motion \
  Sources/PerchUI/Preferences \
  Sources/PerchModules/NowPlaying \
  Sources/PerchModules/Shelf \
  Sources/PerchModules/Clipboard \
  Sources/PerchModules/Focus \
  Sources/PerchModules/Battery \
  Sources/PerchModules/Calendar \
  Sources/PerchModules/HUD \
  Sources/PerchModules/Notifications \
  Sources/PerchModules/Camera \
  Sources/PerchModules/SystemStats \
  Sources/PerchModules/Weather \
  Sources/PerchModules/Windows \
  Sources/PerchModules/Shortcuts \
  Sources/PerchModules/Notes \
  Sources/PerchModules/Voice \
  Sources/PerchModules/Screenshot \
  Sources/PerchModules/HideNotch \
  Tests/PerchCoreTests \
  Tests/PerchUITests/__Snapshots__ \
  Tests/Fixtures \
  Resources/Assets.xcassets \
  Resources/en.lproj \
  Scripts \
  Website/assets/fonts \
  Website/assets/img \
  Website/js/demos \
  Website/data \
  Website/press \
  docs/adr \
  .claude/skills/add-feature \
  .github/workflows \
  .github/ISSUE_TEMPLATE

# Git does not track directories, only files. Without these, a module folder
# that has not been filled in yet simply does not exist on a fresh clone —
# and XcodeGen refuses to generate against a source path that is missing.
for dir in Sources/PerchModules/*/ Sources/PerchCore/Services \
           Tests/PerchUITests/__Snapshots__ Tests/Fixtures Website/press \
           Website/assets Website/js/demos; do
  [ -d "$dir" ] && touch "$dir/.gitkeep"
done

touch Sources/PerchCore/Island/.gitkeep \
      Tests/Fixtures/.gitkeep \
      Website/assets/.gitkeep \
      Website/js/demos/.gitkeep \
      Website/press/.gitkeep

# ------------------------------------------------------------- gitignore ---

cat > .gitignore <<'EOF_GITIGNORE'
# Generated project — edit project.yml instead
*.xcodeproj
*.xcworkspace
!*.xcodeproj/project.xcworkspace

# Build
build/
DerivedData/
.build/
*.dmg
*.zip

# SPM
.swiftpm/
Package.resolved

# macOS
.DS_Store

# Secrets
.env
*.p12
*.provisionprofile
Scripts/notarize.local.sh

# Snapshot failures
Tests/**/__Snapshots__/**/*.failure.png
EOF_GITIGNORE

# ----------------------------------------------------------------- licence ---

cat > LICENSE <<EOF_LICENSE
MIT License

Copyright (c) ${YEAR} Perch contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF_LICENSE

# ------------------------------------------------------- code of conduct ---

cat > CODE_OF_CONDUCT.md <<'EOF_COC'
# Code of Conduct

## Our pledge

We want Perch to be a project where people enjoy contributing, regardless of
experience level, background, or how they found us.

## Expected behaviour

- Be direct about code, kind about people. Critique the patch, not the person.
- Assume good faith. Most disagreements are missing context, not malice.
- Accept that maintainers say no sometimes, and that "no" to a feature is not a
  judgement of you.
- Keep discussion in public issues where possible, so decisions stay findable.

## Unacceptable behaviour

Harassment, personal attacks, discriminatory language, deliberate intimidation,
publishing others' private information, and sustained disruption of discussion.

## Enforcement

Report problems to `conduct@<domain>`. Reports are handled privately.
Maintainers may warn, temporarily block, or permanently ban, depending on
severity. Maintainers who break these rules face the same consequences as
anyone else.

Adapted from the Contributor Covenant, version 2.1.
EOF_COC

# --------------------------------------------------------------- security ---

cat > CHANGELOG.md <<'EOF_CHANGELOG'
# Changelog

All notable changes to Perch. Format follows [Keep a Changelog]; versions
follow [Semantic Versioning]. Entries are generated from Conventional Commit
subjects, so the commit prefix matters — see CONTRIBUTING.md.

The release process that moves `Unreleased` into a version is in RELEASE.md.

## [Unreleased]

### Added
- Nothing yet.

[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
EOF_CHANGELOG

# Sparkle appcast generator, called by .github/workflows/pages.yml
cat > Scripts/appcast.sh <<'EOF_APPCAST'
#!/usr/bin/env bash
#
# appcast.sh — regenerate Sparkle's appcast.xml from published GitHub releases.
#
#   Scripts/appcast.sh Website/appcast.xml
#
# Requires: gh (authenticated). Existing installs poll this file, so a broken
# appcast means nobody gets updates — it is generated, never hand-edited.

set -euo pipefail

OUT="${1:-Website/appcast.xml}"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

mkdir -p "$(dirname "$OUT")"

{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
  echo '  <channel>'
  echo '    <title>Perch</title>'
  echo '    <description>Updates for Perch</description>'
  echo '    <language>en</language>'

  gh release list --repo "$REPO" --limit 20 --json tagName,isDraft,isPrerelease \
    -q '.[] | select(.isDraft == false and .isPrerelease == false) | .tagName' |
  while read -r TAG; do
    VER="${TAG#v}"
    URL=$(gh release view "$TAG" --repo "$REPO" --json assets \
          -q '.assets[] | select(.name | endswith(".dmg")) | .url' | head -1)
    [ -z "$URL" ] && continue
    SIZE=$(gh release view "$TAG" --repo "$REPO" --json assets \
          -q '.assets[] | select(.name | endswith(".dmg")) | .size' | head -1)
    DATE=$(gh release view "$TAG" --repo "$REPO" --json publishedAt -q .publishedAt)

    echo "    <item>"
    echo "      <title>${VER}</title>"
    echo "      <pubDate>${DATE}</pubDate>"
    echo "      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>"
    echo "      <enclosure url=\"${URL}\""
    echo "                 sparkle:version=\"${VER}\""
    echo "                 sparkle:shortVersionString=\"${VER}\""
    echo "                 length=\"${SIZE}\""
    echo "                 type=\"application/octet-stream\"/>"
    echo "    </item>"
  done

  echo '  </channel>'
  echo '</rss>'
} > "$OUT"

echo "==> wrote $OUT"

# NOTE: Sparkle requires an EdDSA signature per enclosure
# (sparkle:edSignature). Add it with Sparkle's sign_update tool and the private
# key held in repo secrets before the first public release — without it,
# Sparkle will refuse the update.
EOF_APPCAST
chmod +x Scripts/appcast.sh

cat > SECURITY.md <<'EOF_SECURITY'
# Security policy

## Supported versions

The latest released version is supported. Older versions are not patched.

## Reporting a vulnerability

Do not open a public issue.

Email `security@<domain>` with a description, reproduction steps, and the
version and macOS version affected. You will get an acknowledgement within 72
hours and an assessment within seven days.

If you prefer, use GitHub's private vulnerability reporting on the Security tab.

## Scope

Particularly interested in: clipboard or shelf data leaking outside the app
container, privilege escalation through the Accessibility permission, unsigned
or tampered update delivery through Sparkle, and anything that causes Perch to
make an unexpected network request.

## Disclosure

We aim to ship a fix before public disclosure and will credit you in the
release notes unless you ask us not to.
EOF_SECURITY

# -------------------------------------------------------------- templates ---

cat > .github/PULL_REQUEST_TEMPLATE.md <<'EOF_PR'
## What this changes

<!-- One or two sentences. -->

Closes #

## Type

- [ ] Feature
- [ ] Bug fix
- [ ] Performance
- [ ] Refactor
- [ ] Docs
- [ ] Build / CI

## Screenshots or recording

<!-- Required for anything visual. Before and after if you changed existing UI. -->

## Checklist

- [ ] Targets `dev`, not `main`
- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] Tests reference the case IDs from `docs/TEST-PLAN.md`
- [ ] `PerchCore` still imports neither SwiftUI nor AppKit
- [ ] New module is individually switchable and inert when off
- [ ] Nothing polls; idle CPU unchanged
- [ ] No sampler, timer or capture session outlives the view that owns it
- [ ] No new network request (Weather and the public-IP readout are the only
      two permitted, both off by default — see CLAUDE.md §5.2)
- [ ] Any new permission is requested lazily with a reason shown
- [ ] Checked with a second display attached
- [ ] Checked with Reduce Motion on
- [ ] No new dependency (or it was agreed in an issue first)

## Notes for reviewers

<!-- Anything you are unsure about, or want a second opinion on. -->
EOF_PR

cat > .github/ISSUE_TEMPLATE/bug_report.yml <<'EOF_BUG'
name: Bug report
description: Something is broken
labels: ["bug", "needs triage"]
body:
  - type: textarea
    id: what
    attributes:
      label: What happened
      description: And what you expected instead
    validations:
      required: true
  - type: textarea
    id: steps
    attributes:
      label: Steps to reproduce
      placeholder: |
        1.
        2.
        3.
    validations:
      required: true
  - type: input
    id: version
    attributes:
      label: Perch version
    validations:
      required: true
  - type: input
    id: macos
    attributes:
      label: macOS version and Mac model
      placeholder: "macOS 15.4, 14-inch MacBook Pro M3"
    validations:
      required: true
  - type: dropdown
    id: displays
    attributes:
      label: Display setup
      options:
        - Built-in only
        - Built-in plus one external
        - Built-in plus two or more externals
        - Lid closed, external only
        - Mirrored
        - Desktop Mac, external only
    validations:
      required: true
  - type: textarea
    id: modules
    attributes:
      label: Which modules are enabled
  - type: textarea
    id: media
    attributes:
      label: Screenshot or recording
      description: Drag files in here. Very helpful for layout and animation bugs.
EOF_BUG

cat > .github/ISSUE_TEMPLATE/feature_request.yml <<'EOF_FEAT'
name: Feature request
description: Suggest something new
labels: ["enhancement", "needs triage"]
body:
  - type: textarea
    id: problem
    attributes:
      label: What problem does this solve
      description: Describe the situation, not the solution.
    validations:
      required: true
  - type: textarea
    id: proposal
    attributes:
      label: What you have in mind
  - type: dropdown
    id: competitors
    attributes:
      label: Do other notch apps have this?
      options:
        - "Yes, several"
        - "Yes, one"
        - "No, this would be new"
        - "Not sure"
  - type: checkboxes
    id: checks
    attributes:
      label: Checks
      options:
        - label: I read docs/PLAN.md and this is not already on the roadmap
          required: true
        - label: This can be switched off and would cost nothing when off
          required: true
EOF_FEAT

cat > .github/ISSUE_TEMPLATE/config.yml <<'EOF_ICFG'
blank_issues_enabled: false
contact_links:
  - name: Questions and ideas
    url: https://github.com/your-org/perch/discussions
    about: Use Discussions for anything that is not a bug or a concrete feature.
EOF_ICFG

# ---------------------------------------------------------------- actions ---

cat > .github/workflows/ci.yml <<'EOF_CI'
name: CI

on:
  pull_request:
    branches: [dev, main]
  push:
    branches: [dev, main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: brew install swiftlint swift-format
      - run: make lint

  test:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-14, macos-15]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: .build
          key: spm-${{ matrix.os }}-${{ hashFiles('project.yml') }}
      - run: brew install xcodegen
      - run: make bootstrap
      - run: make test
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: snapshot-failures-${{ matrix.os }}
          path: Tests/**/__Snapshots__/**/*.failure.png
EOF_CI

cat > .github/workflows/release.yml <<'EOF_REL'
name: Release

on:
  push:
    tags: ["v*"]

jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen create-dmg
      - run: make bootstrap
      - name: Build, sign, notarise
        env:
          SIGNING_CERT_P12: ${{ secrets.SIGNING_CERT_P12 }}
          SIGNING_CERT_PASSWORD: ${{ secrets.SIGNING_CERT_PASSWORD }}
          NOTARY_APPLE_ID: ${{ secrets.NOTARY_APPLE_ID }}
          NOTARY_TEAM_ID: ${{ secrets.NOTARY_TEAM_ID }}
          NOTARY_PASSWORD: ${{ secrets.NOTARY_PASSWORD }}
        run: make release
      - uses: softprops/action-gh-release@v2
        with:
          files: build/Perch-*.dmg
          generate_release_notes: true
EOF_REL

cat > .github/workflows/pages.yml <<'EOF_PAGES'
name: Pages

# Deploys the marketing site and regenerates the Sparkle appcast.
# Runs on every push to main, and after a release publishes its .dmg.

on:
  push:
    branches: [main]
    paths: ["Website/**", ".github/workflows/pages.yml"]
  release:
    types: [published]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deploy.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - name: Build site
        run: |
          cd Website
          node build.js || echo "no build step yet — publishing static files"
      - name: Generate appcast from releases
        run: Scripts/appcast.sh Website/appcast.xml
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: Website
      - id: deploy
        uses: actions/deploy-pages@v4
EOF_PAGES

# --------------------------------------------------------------- makefile ---

cat > Makefile <<'EOF_MAKE'
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
EOF_MAKE

# ----------------------------------------------------------- placeholders ---

cat > docs/adr/0001-record-architecture-decisions.md <<'EOF_ADR'
# 1. Record architecture decisions

Date: today
Status: accepted

## Context

Notch apps accumulate irreversible decisions early — panel level, state
ownership, how geometry is resolved. Six months in, nobody remembers why.

## Decision

Every decision that would be expensive to reverse gets a short ADR here,
numbered sequentially. Format: context, decision, consequences. One page.

## Consequences

Slightly slower to decide things, much faster to revisit them.
EOF_ADR

cat > Resources/en.lproj/Localizable.strings <<'EOF_LOC'
/* Island */
"island.collapsed.accessibilityLabel" = "Perch island";
"island.expanded.accessibilityLabel" = "Perch island, expanded";

/* Permissions */
"permission.calendar.reason" = "Perch needs calendar access to show your next meeting in the notch. Nothing leaves your Mac.";
"permission.accessibility.reason" = "Perch needs accessibility access to replace the system volume and brightness overlays.";

/* Empty states */
"shelf.empty" = "Drag a file to the top of the screen to park it here.";
"clipboard.empty" = "Anything you copy will show up here.";
EOF_LOC

# ------------------------------------------------------------------- git ---

if [ ! -d .git ]; then
  git init -q -b main
  git add -A
  git commit -q -m "chore: scaffold repository structure"
  git branch dev
  echo "==> git initialised: main (committed) + dev (branched)"
  echo "    Next: git remote add origin git@github.com:${ORG}/perch.git"
  echo "          git push -u origin main && git push -u origin dev"
else
  echo "==> existing git repo left alone"
fi

echo "==> Done."
echo "    Copy in: README.md, CONTRIBUTING.md, CLAUDE.md, RELEASE.md,"
echo "             .claude/skills/add-feature/SKILL.md, and into docs/ —"
echo "             FEATURES.md, PLAN.md, COMPARISON.md, TEST-PLAN.md,"
echo "             WEBSITE-PLAN.md. Move index.html to Website/index.html."
echo "    Then:    make bootstrap"
echo
echo "    Before the first release, on GitHub:"
echo "      - protect main and dev (PR required, CI required, no force push,"
echo "        include administrators) — see RELEASE.md"
echo "      - enable Pages, source: GitHub Actions"
echo "      - add secrets: SIGNING_CERT_P12, SIGNING_CERT_PASSWORD,"
echo "        NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD"
echo "      - add the Sparkle EdDSA private key and sign the appcast"
