#!/usr/bin/env bash
# build.sh — build the BitLocker macOS toolchain.
#
# Always builds the upstream dislocker vendored at third_party/dislocker.
#   * Without FUSE-T installed: builds dislocker-file, dislocker-metadata,
#     dislocker-bek. This is enough for Path A (decrypt-to-image workflow used
#     by ./bl-open and `./bl unlock`).
#   * With FUSE-T installed:   additionally builds dislocker-fuse, enabling
#     Path B (streaming mount used by ./bl-mount and `./bl mount`).
#
# Pass FORCE_FUSE=off|on to override auto-detection.
#
# ---------- VENDORED-COPY PIN POLICY ----------
# third_party/dislocker is a vendored snapshot pinned to the commit recorded in
# third_party/dislocker/COMMIT.txt (F7-03 remediation).  Any intentional update
# to that vendored copy requires:
#   1. cd third_party/dislocker && git pull (or cherry-pick / reset)
#   2. Manually review the diff for security-relevant changes.
#   3. Re-run:
#        SHA=$(git rev-parse HEAD)
#        DESCRIBE=$(git describe --tags --always)
#        printf 'Vendored at: %s\nTag/describe: %s\nDate pinned: %s\nReason: <your reason>\n' \
#          "$SHA" "$DESCRIBE" "$(date +%Y-%m-%d)" \
#          > COMMIT.txt
#   4. Commit COMMIT.txt together with any source changes.
# build.sh will REFUSE to build if the working-tree SHA does not match
# COMMIT.txt.  This is intentional — drift must be a conscious change.
# ----------------------------------------------

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISLOCKER_DIR="$SCRIPT_DIR/third_party/dislocker"

# ---------- F7-03: verify dislocker pin ----------
# Pin file lives OUTSIDE the submodule (so it isn't blown away by submodule
# operations). Parse the SHA out of the markdown table row.
PIN_FILE="$SCRIPT_DIR/third_party/dislocker.pin.md"
if [[ ! -f "$PIN_FILE" ]]; then
  echo "error: $PIN_FILE not found." >&2
  echo "       The dislocker submodule must have a pin file." >&2
  exit 1
fi

EXPECTED_SHA="$(grep -E '^\| \*\*Vendored at\*\*' "$PIN_FILE" \
  | grep -oE '[0-9a-f]{40}' | head -1)"
if [[ -z "$EXPECTED_SHA" ]]; then
  echo "error: Could not parse Vendored-at SHA from $PIN_FILE" >&2
  exit 1
fi

ACTUAL_SHA="$(git -C "$DISLOCKER_DIR" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$ACTUAL_SHA" ]]; then
  echo "error: Could not determine HEAD SHA for third_party/dislocker." >&2
  exit 1
fi

if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "error: Dislocker submodule SHA mismatch — refusing to build." >&2
  echo "       Expected (dislocker.pin.md): $EXPECTED_SHA" >&2
  echo "       Actual   (git HEAD):         $ACTUAL_SHA" >&2
  echo "" >&2
  echo "       If this update is intentional, see third_party/dislocker.pin.md" >&2
  echo "       for the upgrade procedure." >&2
  exit 1
fi

echo "dislocker pin OK: $ACTUAL_SHA"

# ---------- F7-09: deterministic VERSION_DBG ----------
# dislocker's CMakeLists bakes `git rev-parse --abbrev-ref HEAD` of the vendored
# tree into every binary via -DVERSION_DBG (used by dislocker.c / config.c /
# dislocker-metadata.c). On a detached HEAD that is the constant "HEAD"; on a
# named branch it is the branch name — so a binary built from the *same* pinned
# commit differs byte-for-byte depending on local checkout state.
# `git submodule update` always leaves a detached HEAD, but a manual checkout
# inside the submodule can leave a branch. Normalise it here — same commit, no
# working-tree changes — so the build is reproducible regardless of that state.
# (The other VERSION_DBG component, `git log -1 --pretty=%t`, is the pinned
# commit's tree hash and is already constant. dislocker's sources use no
# __DATE__/__TIME__ macros, so SOURCE_DATE_EPOCH is not needed.)
if git -C "$DISLOCKER_DIR" symbolic-ref -q HEAD >/dev/null 2>&1; then
  echo "normalising dislocker to detached HEAD (reproducible VERSION_DBG)"
  git -C "$DISLOCKER_DIR" checkout --detach --quiet "$ACTUAL_SHA" \
    || echo "warning: could not detach dislocker HEAD; VERSION_DBG may vary" >&2
fi

# ---------- F7-04: mbedtls@3 (required) — version must be v3.x ----------
MBEDTLS_PREFIX="$(brew --prefix mbedtls@3 2>/dev/null || true)"
if [[ -z "$MBEDTLS_PREFIX" ]]; then
  echo "error: mbedtls@3 not installed."                                    >&2
  echo "       fix: brew install mbedtls@3"                                 >&2
  echo "       (mbedtls 4.x is incompatible with dislocker — must be v3.)"  >&2
  exit 1
fi

# Assert the installed library is genuinely v3.x, not v4+ or a stale install.
# We inspect the dylib's install_name via otool; the current version field
# reports the actual library version baked in at link time.
MBEDCRYPTO_DYLIB="$MBEDTLS_PREFIX/lib/libmbedcrypto.dylib"
if [[ ! -f "$MBEDCRYPTO_DYLIB" ]]; then
  echo "error: $MBEDCRYPTO_DYLIB not found — mbedtls@3 install may be broken." >&2
  echo "       fix: brew reinstall mbedtls@3" >&2
  exit 1
fi

MBEDTLS_VERSION="$(otool -L "$MBEDCRYPTO_DYLIB" 2>/dev/null \
  | grep -Eo '3\.[0-9]+\.[0-9]+' | head -1 || true)"

if [[ -z "$MBEDTLS_VERSION" ]]; then
  echo "error: Could not determine mbedtls version from $MBEDCRYPTO_DYLIB" >&2
  echo "       Expected a v3.x.y dylib; got unexpected output from otool." >&2
  echo "       fix: brew reinstall mbedtls@3" >&2
  exit 1
fi

MBEDTLS_MAJOR="${MBEDTLS_VERSION%%.*}"
if [[ "$MBEDTLS_MAJOR" != "3" ]]; then
  echo "error: mbedtls major version is $MBEDTLS_MAJOR (found $MBEDTLS_VERSION); need v3." >&2
  echo "       fix: brew install mbedtls@3  (do NOT use the default mbedtls formula)" >&2
  exit 1
fi

echo "mbedtls@3 OK: v$MBEDTLS_VERSION at $MBEDTLS_PREFIX"

# ---------- FUSE-T detection (optional, enables Path B) ----------
WITH_FUSE="${FORCE_FUSE:-}"
FUSET_PREFIX=""

if [[ -z "$WITH_FUSE" || "$WITH_FUSE" == "auto" ]]; then
  WITH_FUSE=OFF
  for candidate in \
      "$(brew --prefix fuse-t 2>/dev/null || true)" \
      /Library/Frameworks/fuse-t.framework \
      /usr/local \
      /opt/homebrew; do
    [[ -z "$candidate" ]] && continue
    if [[ -f "$candidate/include/fuse/fuse.h" || -f "$candidate/include/fuse.h" ]]; then
      FUSET_PREFIX="$candidate"
      WITH_FUSE=ON
      break
    fi
  done
fi

PREFIX_PATH="$MBEDTLS_PREFIX"
[[ -n "$FUSET_PREFIX" ]] && PREFIX_PATH="$PREFIX_PATH;$FUSET_PREFIX"

# ---------- configure + build ----------
mkdir -p "$DISLOCKER_DIR/build"
cd "$DISLOCKER_DIR/build"
rm -f CMakeCache.txt
cmake .. \
  -DWITH_FUSE="$WITH_FUSE" \
  -DWITH_RUBY=OFF \
  -DCMAKE_PREFIX_PATH="$PREFIX_PATH" \
  > /tmp/bl-cmake.log 2>&1 \
  || { echo "cmake configure failed. See /tmp/bl-cmake.log"; tail -20 /tmp/bl-cmake.log; exit 1; }

cmake --build . -j \
  > /tmp/bl-build.log 2>&1 \
  || { echo "build failed. See /tmp/bl-build.log"; tail -30 /tmp/bl-build.log; exit 1; }

echo ""
echo "Built binaries (third_party/dislocker/build/src/):"
for b in dislocker-file dislocker-metadata dislocker-bek dislocker-fuse; do
  [[ -x "src/$b" ]] && echo "  ✓ $b"
done

echo ""
echo "Ready commands:"
echo "  ./bl-open                  Path A: decrypt USB to image and mount (default flow)"
echo "  ./bl detect --json         List candidate BitLocker drives"
echo "  ./bl unlock --device DEV   Programmatic Path A with JSON progress events"
if [[ "$WITH_FUSE" == "ON" ]]; then
  echo "  ./bl-mount                 Path B: FUSE-T streaming mount (no 128 GB image)"
  echo "  ./bl mount --device DEV    Programmatic Path B"
else
  echo ""
  echo "Path B (FUSE-T streaming) not enabled. To turn it on:"
  echo "  1. brew install --cask fuse-t   # needs sudo + System Settings approval"
  echo "  2. ./build.sh                   # auto-detects and rebuilds with WITH_FUSE=ON"
fi
