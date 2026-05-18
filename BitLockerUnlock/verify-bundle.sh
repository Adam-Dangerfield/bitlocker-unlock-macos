#!/usr/bin/env bash
# verify-bundle.sh — re-compute SHA-256 hashes for every file inside
# BitLockerUnlock.app and diff them against the manifest produced by
# make-app.sh (F7-05 remediation).
#
# Usage:
#   ./verify-bundle.sh [path/to/BitLockerUnlock.app]
#
# If no argument is supplied the script looks for BitLockerUnlock.app in the
# same directory as this script (i.e., the standard build output location).
#
# Exit codes:
#   0  — all hashes match; bundle integrity verified
#   1  — one or more files differ from the manifest, or the manifest is missing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_PATH="${1:-$SCRIPT_DIR/BitLockerUnlock.app}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: App bundle not found at: $APP_PATH" >&2
    echo "       Build first with: swift build -c release && ./make-app.sh" >&2
    exit 1
fi

MANIFEST="$APP_PATH/Contents/MANIFEST.sha256"

if [[ ! -f "$MANIFEST" ]]; then
    echo "error: Manifest not found: $MANIFEST" >&2
    echo "       Rebuild the bundle with make-app.sh to regenerate the manifest." >&2
    exit 1
fi

# Re-compute hashes for all current files (excluding the manifest itself, which
# was not included in the recorded hashes).
TMPFILE="$(mktemp /tmp/verify-bundle-XXXXXX.sha256)"
trap 'rm -f "$TMPFILE"' EXIT

find "$APP_PATH/Contents" -type f \
    ! -name "MANIFEST.sha256" \
    -exec shasum -a 256 {} \; \
    | sort > "$TMPFILE"

# Compare recorded manifest against fresh hashes.
if diff -q "$MANIFEST" "$TMPFILE" > /dev/null 2>&1; then
    echo "OK — bundle integrity verified."
    echo "  App:      $APP_PATH"
    echo "  Manifest: $MANIFEST"
    echo "  Files:    $(wc -l < "$MANIFEST" | tr -d ' ')"
    exit 0
else
    echo "MISMATCH: bundle integrity check FAILED." >&2
    echo "  App:      $APP_PATH" >&2
    echo "  Manifest: $MANIFEST" >&2
    echo "" >&2
    echo "Differing files (< expected from manifest, > current on disk):" >&2
    diff "$MANIFEST" "$TMPFILE" | grep '^[<>]' | while IFS= read -r line; do
        echo "  $line" >&2
    done
    echo "" >&2
    echo "The bundle has been tampered with or rebuilt without updating the manifest." >&2
    exit 1
fi
