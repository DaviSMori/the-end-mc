#!/bin/bash
#
# Builds mods/ and config/ for the server from THIS packwiz directory.
#
#   ./make-server.sh [output-dir] [--force]
#
# output-dir defaults to ./server-out. Copy its mods/ and config/ folders to the
# server, replacing the existing ones. Run `packwiz refresh` (update.ps1) first
# if you changed anything, so index.toml matches the files on disk.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOTSTRAP_URL="https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar"

OUT="$SCRIPT_DIR/server-out"
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --force)   FORCE=true ;;
        -h|--help) sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "Unknown option: $arg" >&2; exit 1 ;;
        *)         OUT="$arg" ;;
    esac
done

command -v java >/dev/null || { echo "java not found in PATH" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl not found in PATH" >&2; exit 1; }

# Git Bash: accept C:\Windows\style paths too.
if command -v cygpath >/dev/null; then
    OUT="$(cygpath -u "$OUT")"
    PACK_URL="file:///$(cygpath -m "$SCRIPT_DIR")/pack.toml"
else
    PACK_URL="file://$SCRIPT_DIR/pack.toml"
fi

if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then
    if [ "$FORCE" = true ]; then
        rm -rf "$OUT"
    else
        echo "Output dir is not empty: $OUT (use --force to replace it)" >&2
        exit 1
    fi
fi
mkdir -p "$OUT"

# The installer litters its working dir (jars, packwiz.json, plus root files like
# options.txt), so it runs in a scratch dir and only mods/ and config/ are kept.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Installing server-side mods and configs from $PACK_URL"
curl -fsSL -o "$WORK/packwiz-installer-bootstrap.jar" "$BOOTSTRAP_URL"
(cd "$WORK" && java -jar packwiz-installer-bootstrap.jar -g -s server "$PACK_URL")

for dir in mods config; do
    if [ -d "$WORK/$dir" ]; then
        mv "$WORK/$dir" "$OUT/$dir"
    else
        echo "WARNING: pack produced no $dir/ folder" >&2
    fi
done

echo
echo "Done: $OUT"
echo "    mods:   $(find "$OUT/mods" -type f 2>/dev/null | wc -l) files"
echo "    config: $(find "$OUT/config" -type f 2>/dev/null | wc -l) files"
echo "Replace the server's mods/ and config/ with these."
