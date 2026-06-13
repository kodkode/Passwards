#!/bin/bash
# Regenerate the Safari Web Extension's bundled resources from the single source
# of truth in BrowserExtension/ (the same tree Chrome/Brave load unpacked).
#
# The only Safari-specific differences are in the manifest: the Chrome-only
# pinned-id "key" is dropped (Safari warns on it) and a minimum Safari version
# is declared (X25519 WebCrypto landed in Safari 18.4). Everything else — the
# background service worker, content script, popup, pairing page — is copied
# verbatim. Re-run this whenever BrowserExtension/ changes.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo/BrowserExtension"
dst="$repo/SafariExtension/Resources"

mkdir -p "$dst"

# Copy the verbatim assets.
for f in background.js content.js popup.js popup.html pairing.js pairing.html icon128.png; do
  cp "$src/$f" "$dst/$f"
done

# Transform the manifest: drop "key", add the Safari min-version gate.
python3 - "$src/manifest.json" "$dst/manifest.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    m = json.load(f)
m.pop("key", None)  # Chrome-only pinned extension id; Safari warns on it
m["browser_specific_settings"] = {"safari": {"strict_min_version": "18.4"}}
with open(dst, "w") as f:
    json.dump(m, f, indent=2)
    f.write("\n")
PY

echo "Synced Safari extension resources -> $dst"
