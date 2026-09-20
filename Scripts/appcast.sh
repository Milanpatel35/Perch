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
