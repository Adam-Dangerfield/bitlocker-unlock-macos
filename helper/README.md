# bl-helper — privileged helper for GUI unlock

The SwiftUI app escalates via `osascript … with administrator privileges`.
That runs as root, but macOS attributes its raw-disk access to a process with
no *grantable* identity, so Full Disk Access can't be granted to it and every
in-app unlock fails with `Operation not permitted`.

This helper fixes that. It's a root `LaunchDaemon` the app talks to over a Unix
socket. Full Disk Access is granted **once** to a tiny, byte-stable stub
(`bl-helper`); the daemon it launches — and the `bl`/dislocker processes the
daemon spawns — inherit that access and can open the raw BitLocker device.

## Components

| File | Role |
|------|------|
| `bl-helper.c`        | Stable stub (the FDA-granted identity). Compiled + ad-hoc-signed by the installer; **keep it byte-stable** or you'll have to re-grant FDA. |
| `bl-helperd`         | The daemon: listens on `/usr/local/var/run/bl-helper.sock`, runs `bl <op>` as root, streams NDJSON back. |
| `com.bl.helper.plist`| `LaunchDaemon` definition (installed to `/Library/LaunchDaemons`). |
| `install-helper.sh`  | Build + install + load + reload/uninstall. |
| `bl-helper-client.py`| CLI client for testing the socket. |

## One-time setup

```bash
# 1. Build + install the helper (points it at this checkout's bl + dislocker).
./helper/install-helper.sh

# 2. Grant Full Disk Access to the stub:
#    System Settings > Privacy & Security > Full Disk Access
#    + add:  /usr/local/libexec/bl-helper   (Cmd+Shift+G to type the path)
#    toggle it ON.

# 3. Re-load so TCC honours the grant (a full bootout+bootstrap is required;
#    a plain restart is NOT enough):
./helper/install-helper.sh reload

# 4. Test (no password needed — just confirms disk access):
./helper/bl-helper-client.py probe /dev/diskNsM
#   -> {"probe":"READ_OK", ...}
```

Once `probe` returns `READ_OK`, the app's **Unlock** button works with no admin
prompts. Uninstall with `./helper/install-helper.sh uninstall`.

## Notes

- The FDA grant is keyed on the stub's code-signing hash. `bl-helper.c` is kept
  minimal precisely so it never changes; all updatable logic lives in
  `bl-helperd`, which can change freely without invalidating the grant.
- The socket is owned by the console (logged-in) user, mode `0600`.
- Recovery-key unlock isn't supported through the helper yet: dislocker reads
  the recovery password from `/dev/tty`, which a daemon has no access to. Use a
  password, or the Terminal CLI for recovery keys.
