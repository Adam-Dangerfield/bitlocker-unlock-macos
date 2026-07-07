# Changelog

## Unreleased — 2026-07-07

### Added — unlock from the GUI without Terminal (privileged helper)

The SwiftUI app previously escalated with `osascript … with administrator
privileges`. That command runs as root, but macOS attributes its raw-disk
access to a helper with no *grantable* identity, so Full Disk Access could
never be granted to it — every in-app unlock failed with
`Operation not permitted`. Fixed with a proper privileged helper:

- **`helper/`** — a root `LaunchDaemon`:
  - `bl-helper.c` — a tiny, byte-stable stub that holds the Full Disk Access
    grant (TCC keys the grant on its code-signing hash, so keeping it fixed
    means you grant FDA only once) and supervises the daemon.
  - `bl-helperd` — the daemon: listens on a Unix socket and runs `bl <op>` as
    root; because it descends from the FDA-granted stub, the `bl`/dislocker
    processes it spawns can open raw BitLocker devices.
  - `install-helper.sh` — installs the stub + daemon + `LaunchDaemon`, then
    (after you grant FDA to `/usr/local/libexec/bl-helper`) `reload`s it.
  - `bl-helper-client.py` — CLI client for testing the socket.
  - See `helper/README.md` for the one-time setup.
- **`BitLockerUnlock/…/HelperClient.swift`** — Unix-socket client. The app's
  **Unlock** and **Eject** now drive the helper when it's installed, so the
  whole flow works from the GUI with **no admin/auth prompts**. Falls back to
  the legacy osascript path when the helper isn't installed.

### Added — write support (Path B, read-write mount)

- `bl mount --rw` and `./bl-mount --rw` — read-write streaming mount (no
  128 GB image). Writes are re-encrypted back to the drive live.
- Filesystem-aware mounting (`bl` `_detect_fs`): **exFAT/FAT** volumes mount
  **read-write natively** via `hdiutil`; **NTFS** uses `ntfs-3g` (built against
  FUSE-T) when `--rw` is requested, read-only otherwise.
- `hdiutil_attach` now attaches with `-imagekey diskimage-class=CRawDiskImage`
  so a raw decrypted filesystem mounts instead of failing "image not
  recognised" (this also fixes Path A image mounting).

### Fixed

- **In-app unlock crashed with `dislocker-file exit -6`** — the bundled
  `dislocker-file` couldn't load `libdislocker.0.7.dylib`: its only rpath
  pointed at the absolute `~/Documents` build dir, which the app's sandbox
  blocks at runtime, so dyld aborted (SIGABRT). `make-app.sh` now adds
  `@executable_path` to the bundled dislocker binaries' rpath, drops the stale
  build-dir rpath, and re-signs them.
- **Password was never delivered (hang) once disk access worked** — `bl` fed
  the secret over a pty that stalled when there was no controlling terminal.
  Switched to a plain stdin pipe (dislocker reads the user password from
  stdin); the secret still never appears on argv.
- **`/tmp/bl` ownership lockout** — a root (app) run left `/tmp/bl` root-owned,
  locking out every later user-context run (CLI + Finder). `bl` and `bl-open`
  now hand `/tmp/bl` and the decrypted image to the real login user.
- **`bl-open` password/recovery path broken** — it passed `bl`-only
  `--secret-file`/`--secret-type` flags to `dislocker-file`, which rejects
  them. Rewritten to delegate to `bl unlock` (secure secret transport, every
  auth type).
- **Redundant/harmful `sudo` when already root** — `bl` no longer wraps
  dislocker/ntfs-3g/umount in `sudo` when euid is 0; doing so reset TCC's
  responsible process to `sudo` and lost the helper's Full Disk Access.

### Changed

- The app now surfaces a specific, actionable **"Can't access the drive"**
  alert (`NEEDS_DISK_ACCESS`, with an "Open Full Disk Access Settings" button)
  instead of an opaque `dislocker-file exit -N`. `bl` classifies the
  `Operation not permitted` failure and `BackendBridge` recovers the real error
  code even when osascript wraps it.
