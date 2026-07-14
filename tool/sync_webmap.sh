#!/usr/bin/env bash
#
# Rebuilds the CesiumJS web map bundle and syncs it into the Flutter app's
# assets, regenerating the asset directory list in pubspec.yaml.
#
# Run this whenever you change anything under webmap/ (or bump the Cesium
# version) so the bundled, offline-capable map stays up to date.
#
# Usage:  tool/sync_webmap.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEBMAP="$ROOT/webmap"
DEST="$ROOT/assets/webmap"

echo "==> Building web map bundle"
cd "$WEBMAP"
if [ ! -d node_modules ]; then
  npm install
fi
npm run build

echo "==> Copying bundle into $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$WEBMAP/dist/." "$DEST/"

echo "==> Regenerating asset directory list"
# Every directory must be listed explicitly; Flutter does not recurse.
ASSET_LINES="$(cd "$ROOT" && find assets/webmap -type d | sort | sed 's|$|/|' | sed 's|^|    - |')"

python3 - "$ROOT/pubspec.yaml" "$ASSET_LINES" <<'PY'
import sys, re
pubspec_path, asset_lines = sys.argv[1], sys.argv[2]
with open(pubspec_path) as f:
    text = f.read()

marker = "  assets:\n"
idx = text.index(marker)
head = text[: idx + len(marker)]
# Drop the previous asset entries (indented list items) after the marker.
rest = text[idx + len(marker):]
rest = re.sub(r"^(    - .*\n)+", "", rest)
with open(pubspec_path, "w") as f:
    f.write(head + asset_lines + "\n" + rest)
print("pubspec.yaml asset list updated")
PY

echo "==> Done"
