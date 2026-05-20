#!/usr/bin/env bash
# Binary-safe cliphist paste. Detects MIME type from binary content
# and passes the correct type to wl-copy, fixing image paste.
# Usage: clipboard-paste.sh <entry-id>

set -euo pipefail

ID="${1:?Usage: clipboard-paste.sh <entry-id>}"

TMPFILE=$(mktemp /tmp/qs-clip-XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

# Decode preserving raw binary data
cliphist decode "$ID" > "$TMPFILE" 2>/dev/null

# Detect actual MIME type from content (not filename)
MIME=$(file --mime-type -b "$TMPFILE" 2>/dev/null || echo "application/octet-stream")

case "$MIME" in
    image/png)   wl-copy --type image/png    < "$TMPFILE" ;;
    image/jpeg)  wl-copy --type image/jpeg   < "$TMPFILE" ;;
    image/gif)   wl-copy --type image/gif    < "$TMPFILE" ;;
    image/webp)  wl-copy --type image/webp   < "$TMPFILE" ;;
    image/*)     wl-copy --type "$MIME"      < "$TMPFILE" ;;
    text/*)      wl-copy                     < "$TMPFILE" ;;
    *)           wl-copy                     < "$TMPFILE" ;;
esac
