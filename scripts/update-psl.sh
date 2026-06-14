#!/usr/bin/env bash
#
# Refresh the bundled Public Suffix List from the authoritative source.
#
# The PSL is a security artifact: it defines the eTLD+1 boundary the browser
# bridge uses to decide which saved credential may be released to a page. The
# repo ships a curated baseline; run this to replace it with the full official
# list (recommended) and re-run periodically to keep it current.
#
# Usage: scripts/update-psl.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_ROOT/Packages/TwoPasswordCore/Sources/TwoPasswordCore/Resources/public_suffix_list.dat"
URL="https://publicsuffix.org/list/public_suffix_list.dat"

echo "Downloading $URL"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP"

# Sanity-check the download before overwriting the shipped boundary: the real
# list is large and contains these stable anchors.
if ! grep -q '===BEGIN ICANN DOMAINS===' "$TMP" \
   || ! grep -qx 'co.uk' "$TMP" \
   || ! grep -qx 'github.io' "$TMP" \
   || [ "$(wc -l < "$TMP")" -lt 5000 ]; then
  echo "error: downloaded file does not look like the Public Suffix List; not updating." >&2
  exit 1
fi

mv "$TMP" "$DEST"
trap - EXIT
echo "Updated $(basename "$DEST") ($(wc -l < "$DEST") lines)."
echo "Rebuild so SPM re-copies the resource into the app bundle."
