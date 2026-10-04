#!/usr/bin/env bash
#
# sign-build.sh — sign a release archive for Sparkle, and print the line its
# release notes must carry for the appcast to list it.
#
#   Scripts/sign-build.sh Perch-0.13.0-unsigned.zip path/to/Perch.app
#
# The private key is read from the maintainer's login Keychain (account
# app.perch.Perch), where `generate_keys` put it. It is never written to
# disk, never committed and never given to CI. Back it up once with
#
#   generate_keys --account app.perch.Perch -x perch-sparkle-key.txt
#
# and keep that file somewhere safe: an installed Perch only accepts updates
# signed with this key, so losing it means every install has to be updated
# by hand, once. RELEASE.md has the whole release chain.

set -euo pipefail

ARCHIVE="$1"
APP="$2"

SIGN_UPDATE="${SIGN_UPDATE:-$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*artifacts/sparkle/Sparkle/bin/sign_update' -type f 2>/dev/null | head -1)}"
[ -x "$SIGN_UPDATE" ] || { echo "sign_update not found — build Perch once in Xcode" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
SHORT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

# Prints: sparkle:edSignature="…" length="…"
SIGNED=$("$SIGN_UPDATE" --account app.perch.Perch "$ARCHIVE")
SIGNATURE=$(sed -n 's/.*edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNED")
LENGTH=$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<<"$SIGNED")

echo "<!-- sparkle version=\"$VERSION\" shortVersion=\"$SHORT\" edSignature=\"$SIGNATURE\" length=\"$LENGTH\" -->"
