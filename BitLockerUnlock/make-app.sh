#!/usr/bin/env bash
# make-app.sh — wrap the release-built BitLockerUnlock CLI binary into a
# minimal unsigned .app bundle suitable for double-clicking from Finder.
#
# Usage:
#   swift build -c release
#   ./make-app.sh
#
# Output: ./BitLockerUnlock.app (overwrites any prior bundle).
#
# The bundle is intentionally unsigned — Gatekeeper will refuse the first
# launch via double-click; right-click → Open to bypass.
#
# F7-05 integrity note: A SHA-256 manifest is written to
#   BitLockerUnlock.app/Contents/MANIFEST.sha256
# and a top-level copy is placed alongside the .app as
#   BitLockerUnlock.app.MANIFEST.sha256
# Run ./verify-bundle.sh after distributing the .app to confirm no tamper.
# Without code signing, this is the only integrity check available.

set -euo pipefail

# Resolve script directory so this works no matter where it's invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BIN_PATH=".build/release/BitLockerUnlock"
APP_PATH="BitLockerUnlock.app"

if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: $BIN_PATH not found or not executable." >&2
    echo "       Run 'swift build -c release' first." >&2
    exit 1
fi

# Wipe any prior bundle so we don't end up with stale Info.plist keys.
rm -rf "$APP_PATH"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/BitLockerUnlock"
chmod +x "$APP_PATH/Contents/MacOS/BitLockerUnlock"

# Bundle the `bl` Python CLI and dislocker binaries inside the app so it
# never has to read scripts/binaries from the user's Documents folder.
# macOS TCC blocks even root-escalated processes from arbitrary paths under
# ~/Documents, ~/Desktop, etc.; intra-bundle reads are always permitted.
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cp "$PROJECT_ROOT/bl" "$APP_PATH/Contents/Resources/bl"
chmod +x "$APP_PATH/Contents/Resources/bl"

DISLOCKER_BIN_SRC="$PROJECT_ROOT/third_party/dislocker/build/src"
DISLOCKER_BIN_DST="$APP_PATH/Contents/Resources/dislocker-bin"
mkdir -p "$DISLOCKER_BIN_DST"
for bin in dislocker-file dislocker-metadata dislocker-bek dislocker-fuse; do
    if [[ -x "$DISLOCKER_BIN_SRC/$bin" ]]; then
        cp "$DISLOCKER_BIN_SRC/$bin" "$DISLOCKER_BIN_DST/$bin"
        chmod +x "$DISLOCKER_BIN_DST/$bin"
    fi
done
# The dislocker dylib needs to come along too.
for dylib in "$DISLOCKER_BIN_SRC"/libdislocker*.dylib; do
    [[ -f "$dylib" ]] && cp "$dylib" "$DISLOCKER_BIN_DST/"
done

# ---------- F7-04: bundle libmbedcrypto so the app is self-contained ----------
# dislocker-file links against the Homebrew mbedtls@3 dylib by absolute path.
# If we don't bundle it, the app breaks on any Mac that lacks mbedtls@3.
# We copy the dylib into the bundle and rewrite dislocker-file's load command
# so it uses @executable_path-relative addressing instead.
MBEDTLS_PREFIX="$(brew --prefix mbedtls@3 2>/dev/null || true)"
if [[ -z "$MBEDTLS_PREFIX" ]]; then
    echo "error: mbedtls@3 not installed; cannot bundle libmbedcrypto." >&2
    echo "       fix: brew install mbedtls@3" >&2
    exit 1
fi

# Discover the real (versioned) install name of the dylib as it was linked.
DISLOCKER_FILE_BIN="$DISLOCKER_BIN_DST/dislocker-file"
if [[ -x "$DISLOCKER_FILE_BIN" ]]; then
    # The absolute brew path that dislocker-file currently references.
    MBEDCRYPTO_ABS="$(otool -L "$DISLOCKER_FILE_BIN" \
        | grep -E '/opt/homebrew.*libmbedcrypto' \
        | awk '{print $1}' | head -1 || true)"

    if [[ -n "$MBEDCRYPTO_ABS" && -f "$MBEDCRYPTO_ABS" ]]; then
        MBEDCRYPTO_BASENAME="$(basename "$MBEDCRYPTO_ABS")"
        BUNDLED_MBEDCRYPTO="$DISLOCKER_BIN_DST/$MBEDCRYPTO_BASENAME"

        # Copy the dylib into the bundle.
        cp "$MBEDCRYPTO_ABS" "$BUNDLED_MBEDCRYPTO"
        chmod 755 "$BUNDLED_MBEDCRYPTO"

        # Rewrite the load command in dislocker-file to point at the bundle copy.
        # @executable_path is the directory containing the binary being run,
        # which for dislocker-file is Contents/Resources/dislocker-bin/.
        NEW_RPATH="@executable_path/$MBEDCRYPTO_BASENAME"
        install_name_tool \
            -change "$MBEDCRYPTO_ABS" "$NEW_RPATH" \
            "$DISLOCKER_FILE_BIN"

        echo "Bundled mbedtls: $MBEDCRYPTO_BASENAME (rewritten from $MBEDCRYPTO_ABS)"
    else
        echo "warning: Could not detect libmbedcrypto absolute path in dislocker-file; skipping bundle." >&2
        echo "         The app may fail on machines without mbedtls@3 installed." >&2
    fi
fi

# AppIcon.icns — bundle it if generated. Use `swift gen-icon.swift` to (re)generate.
if [[ -f "$SCRIPT_DIR/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

# Info.plist — note: LSUIElement is intentionally NOT set; we want a dock
# icon and a normal window alongside the menu-bar extra.
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>BitLockerUnlock</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.bitlockerunlock</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>BitLocker Unlock</string>
    <key>CFBundleDisplayName</key>
    <string>BitLocker Unlock</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# ---------- F7-05: SHA-256 integrity manifest ----------
# Generate a manifest of every file inside the bundle so downstream consumers
# (and the verify-bundle.sh script) can detect any post-build tampering.
# The manifest itself is excluded from its own hash to keep the process
# idempotent; verify-bundle.sh skips the manifest line when re-checking.
# Paths are stored as absolute paths so verify-bundle.sh can locate them
# regardless of its working directory.
APP_ABS="$(cd "$APP_PATH" && pwd)"
MANIFEST_INSIDE="$APP_ABS/Contents/MANIFEST.sha256"
find "$APP_ABS/Contents" -type f \
    ! -name "MANIFEST.sha256" \
    -exec shasum -a 256 {} \; \
    | sort > "$MANIFEST_INSIDE"

# Also write a sibling copy alongside the .app for offline verification.
MANIFEST_OUTSIDE="$SCRIPT_DIR/BitLockerUnlock.app.MANIFEST.sha256"
cp "$MANIFEST_INSIDE" "$MANIFEST_OUTSIDE"

MANIFEST_LINES="$(wc -l < "$MANIFEST_INSIDE" | tr -d ' ')"
echo ""
echo "Built $APP_PATH"
ls -lh "$APP_ABS/Contents/MacOS/BitLockerUnlock"
echo ""
echo "SHA-256 manifest: $MANIFEST_INSIDE ($MANIFEST_LINES files)"
echo "  Top-level copy: $MANIFEST_OUTSIDE"
echo ""
echo "Run ./verify-bundle.sh after distributing the .app to confirm no tamper."
echo "Without code signing, this is the only integrity check available."
