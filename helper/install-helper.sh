#!/usr/bin/env bash
# install-helper.sh — install the BitLockerUnlock privileged helper.
#
# Builds the stable `bl-helper` stub, installs it + the daemon + a LaunchDaemon,
# and points them at this checkout's `bl` + dislocker build. Uses sudo.
#
# After running, GRANT Full Disk Access to /usr/local/libexec/bl-helper in
# System Settings, then re-run this with `reload` (a full bootout+bootstrap is
# required for TCC to honour the new grant).
#
# Usage:
#   ./helper/install-helper.sh            # build + install + load
#   ./helper/install-helper.sh reload     # bootout + bootstrap (after FDA grant)
#   ./helper/install-helper.sh uninstall  # remove everything
set -uo pipefail

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HELPER_DIR/.." && pwd)"
LABEL="com.bl.helper"
PLIST_DST="/Library/LaunchDaemons/$LABEL.plist"
STUB_DST="/usr/local/libexec/bl-helper"
DAEMON_DST="/usr/local/libexec/bl-helperd"
CONF_DST="/usr/local/etc/bl-helper.conf"

reload_daemon() {
  sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
  sleep 1
  sudo launchctl bootstrap system "$PLIST_DST"
  echo "reloaded $LABEL"
}

case "${1:-install}" in
  uninstall)
    sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
    sudo rm -f "$PLIST_DST" "$STUB_DST" "$DAEMON_DST" "$CONF_DST"
    sudo rm -f /usr/local/var/run/bl-helper.sock
    echo "uninstalled $LABEL"
    exit 0
    ;;
  reload)
    reload_daemon
    exit 0
    ;;
esac

# ---- build the stable stub (ad-hoc signed; keep it byte-stable) ----
clang -O2 -o "$HELPER_DIR/bl-helper" "$HELPER_DIR/bl-helper.c" || { echo "compile failed" >&2; exit 1; }
codesign --force --sign - "$HELPER_DIR/bl-helper"
echo "built + signed bl-helper stub"

# ---- install files ----
sudo mkdir -p /usr/local/libexec /usr/local/etc /usr/local/var/run
sudo cp "$HELPER_DIR/bl-helper" "$STUB_DST"
sudo cp "$HELPER_DIR/bl-helperd" "$DAEMON_DST"
sudo chmod 755 "$STUB_DST" "$DAEMON_DST"
sudo chown root:wheel "$STUB_DST" "$DAEMON_DST"

# Point the helper at this checkout (Full Disk Access lets it read ~/Documents).
sudo tee "$CONF_DST" >/dev/null <<EOF
# BitLockerUnlock helper config — written by install-helper.sh
BL_PATH=$PROJECT/bl
BL_DISLOCKER_DIR=$PROJECT/third_party/dislocker/build/src
BL_NTFS3G=/usr/local/bin/ntfs-3g
EOF
sudo chmod 644 "$CONF_DST"

sudo cp "$HELPER_DIR/com.bl.helper.plist" "$PLIST_DST"
sudo chown root:wheel "$PLIST_DST"
sudo chmod 644 "$PLIST_DST"

reload_daemon
echo
echo "Installed. NEXT:"
echo "  1. System Settings > Privacy & Security > Full Disk Access"
echo "     + add:  $STUB_DST"
echo "  2. ./helper/install-helper.sh reload"
echo "  3. Test:  ./helper/bl-helper-client.py detect"
