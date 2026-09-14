#!/usr/bin/env bash
# Build the KDE Store upload: dist/<KPlugin.Id>-<KPlugin.Version>.plasmoid
#
# A .plasmoid is a plain zip with metadata.json and contents/ at the archive
# root - nothing else, no store-specific wrapping (Phase 15.0.0: confirmed
# against four real Plasma 6 store uploads and KPackage's own installer,
# packagejobthread.cpp, which opens the file by MIME type and copies the
# archive root). kpackagetool6 has no create/pack option, and `zip` is not
# a base package on Arch, so this uses bsdtar (libarchive) in zip mode.
# "Get New Widgets" installs the download through the same KPackage code
# path as `kpackagetool6 --type Plasma/Applet --install <file>`.
#
# Packages exactly metadata.json + contents/ from plasmoid/ (never the
# working tree's stray files), then checks the entry count against the
# directory so a missing file cannot go unnoticed.
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLASMOID_DIR="${REPO_DIR}/plasmoid"
DIST_DIR="${REPO_DIR}/dist"

for tool in jq bsdtar unzip; do
    command -v "$tool" >/dev/null 2>&1 || { echo "build-plasmoid.sh: $tool not found on PATH" >&2; exit 1; }
done
[ -f "${PLASMOID_DIR}/metadata.json" ] || { echo "build-plasmoid.sh: ${PLASMOID_DIR}/metadata.json not found" >&2; exit 1; }

PLUGIN_ID="$(jq -er '.KPlugin.Id' "${PLASMOID_DIR}/metadata.json")"
VERSION="$(jq -er '.KPlugin.Version' "${PLASMOID_DIR}/metadata.json")"
OUT="${DIST_DIR}/${PLUGIN_ID}-${VERSION}.plasmoid"

mkdir -p "$DIST_DIR"
rm -f "$OUT"
# Archive root = metadata.json + contents/ (no leading ./, no top-level folder).
bsdtar --format zip -cf "$OUT" -C "$PLASMOID_DIR" metadata.json contents

expected="$(find "$PLASMOID_DIR/contents" -type f | wc -l)"
expected=$((expected + 1))   # + metadata.json
packed="$(unzip -Z1 "$OUT" | grep -vc '/$')"
if [ "$packed" -ne "$expected" ]; then
    echo "build-plasmoid.sh: packed $packed files, expected $expected" >&2
    exit 1
fi
echo "build-plasmoid.sh: wrote $OUT ($packed files, $(stat -c %s "$OUT") bytes)"
