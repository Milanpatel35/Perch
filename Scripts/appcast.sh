#!/usr/bin/env bash
#
# appcast.sh — regenerate Sparkle's appcast.xml from published GitHub releases.
#
#   Scripts/appcast.sh Website/appcast.xml
#
# Requires: gh (authenticated) and jq. Existing installs read this file to
# learn about updates, so a broken appcast means nobody gets one — it is
# generated, never hand-edited.
#
# A release is listed only if its notes carry the line `Scripts/sign-build.sh`
# writes — the build number, the version, and the archive's EdDSA signature
# and length:
#
#   <!-- sparkle version="14" shortVersion="0.13.0" edSignature="…" length="…" -->
#
# Releases without it — every build before updates existed — are left out
# rather than listed unsigned, because Sparkle would refuse them anyway.
#
# RELEASES_JSON=<file> reads the releases from a file instead of GitHub, in
# the shape `gh release list --json` returns plus `body` and `assets`; the
# tests use it (TC-UPD-006).

set -euo pipefail

OUT="${1:-Website/appcast.xml}"

if [ -n "${RELEASES_JSON:-}" ]; then
  RELEASES=$(cat "$RELEASES_JSON")
else
  REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
  RELEASES=$(gh api "repos/$REPO/releases?per_page=30" | jq '[.[] | {
      tagName: .tag_name, isDraft: .draft, publishedAt: .published_at,
      url: .html_url, body: (.body // ""),
      assets: [.assets[] | {name, url: .browser_download_url}] }]')
fi

# Pulls one attribute out of the sparkle comment in a release's notes.
attr() { sed -n "s/.*<!-- sparkle .*$1=\"\([^\"]*\)\".*-->.*/\1/p" <<<"$2" | head -1; }

xml() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<<"$1"; }

mkdir -p "$(dirname "$OUT")"

{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
  echo '  <channel>'
  echo '    <title>Perch</title>'
  echo '    <description>Updates for Perch</description>'
  echo '    <language>en</language>'

  COUNT=$(jq 'length' <<<"$RELEASES")
  for ((i = 0; i < COUNT; i++)); do
    REL=$(jq ".[$i]" <<<"$RELEASES")
    [ "$(jq -r '.isDraft' <<<"$REL")" = "true" ] && continue

    BODY=$(jq -r '.body' <<<"$REL")
    VERSION=$(attr version "$BODY")
    SHORT=$(attr shortVersion "$BODY")
    SIGNATURE=$(attr edSignature "$BODY")
    LENGTH=$(attr length "$BODY")
    [ -z "$VERSION" ] || [ -z "$SHORT" ] || [ -z "$SIGNATURE" ] || [ -z "$LENGTH" ] && continue

    ARCHIVE=$(jq -r '[.assets[] | select(.name | endswith(".zip"))][0].url // empty' <<<"$REL")
    [ -z "$ARCHIVE" ] && continue

    echo "    <item>"
    echo "      <title>Perch $(xml "$SHORT")</title>"
    echo "      <pubDate>$(jq -r '.publishedAt' <<<"$REL")</pubDate>"
    echo "      <sparkle:version>$(xml "$VERSION")</sparkle:version>"
    echo "      <sparkle:shortVersionString>$(xml "$SHORT")</sparkle:shortVersionString>"
    echo "      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>"
    echo "      <sparkle:releaseNotesLink>$(xml "$(jq -r '.url' <<<"$REL")")</sparkle:releaseNotesLink>"
    echo "      <enclosure url=\"$(xml "$ARCHIVE")\""
    echo "                 sparkle:edSignature=\"$(xml "$SIGNATURE")\""
    echo "                 length=\"$(xml "$LENGTH")\""
    echo "                 type=\"application/octet-stream\"/>"
    echo "    </item>"
  done

  echo '  </channel>'
  echo '</rss>'
} > "$OUT"

echo "==> wrote $OUT"
