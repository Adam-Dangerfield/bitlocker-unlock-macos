# Full Repository Code Review — 2026-07-07

**Repo:** BitLocker-on-macOS (dislocker wrapper — CLI + SwiftUI app + privileged helper)
**Branch reviewed:** `fix/ci-cmake-build`
**Method:** Four parallel reviewers (Python CLI, privileged helper, SwiftUI app, build/scripts/hygiene). Highest-severity findings were re-verified directly against source (and the vendored dislocker submodule) before inclusion.

---

## TL;DR

The project is unusually security-conscious in intent — F-tagged mitigations, out-of-band secret transport, symlink/TOCTOU guards, submodule pinning — but several of those mitigations are **incomplete or broken in practice**, and the safety net around them is largely illusory. The most consequential problems:

1. **The root helper executes user-writable code** (`bl` and dislocker binaries live in the user's `~/Documents` checkout), turning any user-level compromise into root. This defeats the entire privilege-separation design.
2. **Recovery-key unlock is broken outright** — dislocker reads recovery passwords from `/dev/tty`, not the stdin pipe `bl` now writes to. Every recovery-key unlock hangs or fails.
3. **CI has never run a test.** `enable_testing()` is in the wrong CMake scope, so `ctest` finds nothing and exits 0 — and the one test that exists *fails* when actually run.
4. **The unprivileged CLI path crashes after a full decrypt** because the `sudo chown /dev/fd/<fd>` fix can't work across the sudo/close_fds boundary.
5. **The screen-capture password protection misses the password sheet** — the one window where the secret is actually typed remains capturable.

The GUI/root-helper happy path was clearly tested; the plain-CLI path and the failure paths were not re-verified after recent refactors.

---

## Critical

### C1 — Root helper executes user-writable code → local privilege escalation
**Files:** [helper/bl-helperd:61,81-84](helper/bl-helperd#L61), [helper/install-helper.sh:61](helper/install-helper.sh#L61)

The root LaunchDaemon reads `BL_PATH` / `BL_DISLOCKER_DIR` from `/usr/local/etc/bl-helper.conf` and runs them as root: `["/usr/bin/python3", bl, op, "--json", ...]`. The installer sets `BL_PATH=$PROJECT/bl`, i.e. the `bl` script **inside the user's `~/Documents` checkout**. Verified: `bl` is `-rwxr-xr-x <user>:staff` — writable by the unprivileged owner.

**Attack:** any process running as the console user overwrites `./bl` (or drops a malicious `dislocker-file` / `libdislocker.dylib` into the dislocker build dir), then sends any request to the helper socket → arbitrary code as root with Full Disk Access. No exploit of the wire protocol is needed; this alone makes the privilege boundary meaningless.

**Fix:** copy `bl` and the dislocker binaries to a root-owned location at install time (as is already done for `bl-helperd` itself), and verify root ownership before exec.

### C2 — Recovery-key unlock never delivers the key to dislocker
**Files:** [bl:785-807](bl#L785), [bl:826-827](bl#L826); submodule `recovery_password.c:411-418`, `xstdio.c:124-131`

`bl` writes the secret to dislocker's **stdin pipe** and passes a bare `-p`. Verified against the submodule: for `-p`, dislocker calls `prompt_rp()` → `get_input_fd()` → `open("/dev/tty")` — it does **not** read stdin. Only the user-password path (`-u`) reads stdin.

**Failure:** `bl unlock ... --secret-type recovery` (what `bl-open`/`bl-mount` generate for recovery keys). Under the GUI helper (no controlling tty) `open("/dev/tty")` fails → unlock fails every time. From a terminal, dislocker prompts on the real tty while the written secret sits unread → spins at 0% forever. The module docstring, `_DEPRECATION_EPILOG`, and code comments still claim a pty is used (see M-DOC).

### C3 — Unprivileged CLI unlock crashes after a full decrypt (`sudo chown /dev/fd/<fd>` can't work)
**File:** [bl:736-738](bl#L736) (`_safe_chown_to_self`)

`subprocess.check_call` defaults to `close_fds=True`, and `sudo` additionally does `closefrom()`, so `/dev/fd/<fd>` (resolved against the *caller's* descriptor table) doesn't exist in the child. Confirmed empirically by the reviewer (`Bad file descriptor`).

**Failure:** `./bl-open <disk>` unprivileged → dislocker (via sudo) writes a root-owned image → after hours of decryption, `_safe_chown_to_self` → uncaught `CalledProcessError` traceback; nothing mounts. Reruns hit the same crash on the skip-path attach. The `euid==0` (GUI) branch masks this in app testing.

---

## High

### H1 — CI test step is a green no-op, and the one real test fails
**Files:** [CMakeLists.txt:63](CMakeLists.txt#L63), [tests/CMakeLists.txt:1](tests/CMakeLists.txt#L1), [.github/workflows/ci.yml:25-28](.github/workflows/ci.yml#L25), `src/bitlocker-crypto/bitlocker_crypto.c:14-43`

`enable_testing()` is called only in the `tests/` subdirectory, so CMake writes `CTestTestfile.cmake` under `build/tests/` but not at the build root where CI runs `ctest`. Empirically verified: `ctest` from the build root prints `No tests were found!!!` and **exits 0**. Every CI run to date has "passed tests" without running one. Worse, when the test *is* run directly it **fails** (`aes_decrypt` never calls `EVP_CIPHER_CTX_set_padding(ctx, 0)`, so PKCS#7 padding is enforced on raw sector data). Fixing H1 turns CI red until the padding bug is fixed too.

**Fix:** `enable_testing()` / `include(CTest)` in the root `CMakeLists.txt`; add `--no-tests=error` to the CI `ctest` call; set padding off in `aes_decrypt`.

### H2 — Helper stream EOF without a terminal event strands the UI in `.decrypting`
**Files:** [AppState.swift:137-149](BitLockerUnlock/Sources/BitLockerUnlock/AppState.swift#L137), [HelperClient.swift:59-68](BitLockerUnlock/Sources/BitLockerUnlock/HelperClient.swift#L59)

`HelperClient.mountStream` calls `continuation.finish()` on socket EOF even when no `.mounted`/`.failed` line was received (helper crash, daemon restart, dropped last line). `attemptUnlock`'s `for try await` then completes with no `catch` and no state transition → the spinner stays up forever until the user guesses to Cancel.

### H3 — `runProcess` never drains pipes until exit → deadlock hangs the app
**File:** [BackendBridge.swift:388-403](BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L388)

Verified: stdout/stderr are read (`readToEnd()`) only inside `terminationHandler`. If a child fills the ~64KB pipe buffer it blocks on `write(2)` and never exits → the handler never fires → the continuation never resumes. A long unlock emitting many NDJSON progress lines (or verbose dislocker stderr) can cross that threshold and hang at "Decrypting…" with a root process still running. No timeout anywhere. **Fix:** attach `readabilityHandler`s or read on background threads concurrently.

### H4 — Failed eject/cleanup discards `.mounted` context → orphaned volume + plaintext image
**Files:** [AppState.swift:179-203](BitLockerUnlock/Sources/BitLockerUnlock/AppState.swift#L179), [ErrorView.swift:99-103](BitLockerUnlock/Sources/BitLockerUnlock/Screens/ErrorView.swift#L99)

On eject/cleanup error the state goes to `.error(..., drive: nil)`, dropping `mountPath`/`imagePath`. "Try Again" is just a dismiss. The still-mounted decrypted volume and the plaintext `/tmp/bl/decrypted.img` then have no in-app path to clean up, and `ejectAndCleanupForQuit` no longer fires (state isn't `.mounted`). Scenario: eject fails (Finder has a file open) → user dismisses → plaintext image persists.

### H5 — Screen-capture exclusion misses the password sheet window
**Files:** [App.swift:134-147](BitLockerUnlock/Sources/BitLockerUnlock/App.swift#L134), [UnlockSheetView.swift:188](BitLockerUnlock/Sources/BitLockerUnlock/Screens/UnlockSheetView.swift#L188)

`sharingType = .none` (F6-03) is applied only to the main window. SwiftUI `.sheet` content is hosted in a *separate* NSWindow that keeps the default `sharingType`, so `UnlockSheetView` — the SecureField and the fully visible 48-digit recovery-key TextField — stays capturable by ScreenCaptureKit/`screencapture -l`, defeating the mitigation exactly where the secret is typed. **Fix:** apply the guard to the sheet's own window.

### H6 — Multiple `bl` subprocess calls raise uncaught exceptions, breaking the JSON contract
**Files:** [bl:627](bl#L627), [bl:1212-1215](bl#L1212), [bl:302](bl#L302), [bl:719](bl#L719)

`SudoKeepalive.__enter__`'s `sudo -v`, `hdiutil_attach`'s `check_output`, `diskutil_plist`, and `_safe_chown_to_self`'s re-raise can all throw raw exceptions in `--json` mode, producing a Python traceback on stderr and **no** `{"error": ...}` record — which the SwiftUI parser can't handle.

### H7 — No caller authentication on the helper socket; world-writable fallback + bind→chmod TOCTOU
**File:** [helper/bl-helperd:163-171](helper/bl-helperd#L163)

The daemon never checks peer credentials (no `getpeereid`/`LOCAL_PEERCRED`); it trusts the socket file mode alone. Two gaps: (a) the socket is created by `bind()` and only chmod'd afterward — a window at umask-default perms; (b) if `chown`/`chmod` raises, it falls back to **0666**, letting *any* local user drive the root helper. Combined with C1, that is root RCE. **Fix:** verify the connecting peer's uid.

### H8 — `eject` mount path is unvalidated → root unmount of an arbitrary path
**Files:** [helper/bl-helperd:72-73](helper/bl-helperd#L72), [bl:1145-1162](bl#L1145)

Unlike `device` (regex-checked) and `cleanup` (IMG_DIR-guarded), the eject `mount` value is passed straight to root `hdiutil detach` / `umount`. A caller sending `{"op":"eject","mount":"/"}` (or any other user's mountpoint) gets the root helper to force-unmount it — DoS / data-integrity damage. **Fix:** allowlist/contain the mount path.

### H9 — Partial image from a failed/cancelled decrypt is silently attached as valid
**Files:** [bl:916-919](bl#L916), [bl:982-995](bl#L982)

The skip-if-present check only tests `exists() and st_size > 0`, and a cancelled/failed decrypt never deletes the partial `out_path`. Next `bl unlock` skips decryption and hands the corrupt image to `hdiutil attach` → mounts garbage or throws uncaught. Compounded by M-DEVICE (skip check ignores `--device`, so a stale image from a *different* drive is mounted and reported as success).

### H10 — Menu-bar icon never updates (unobserved dependency)
**File:** [BLMenuBarExtra.swift:15](BitLockerUnlock/Sources/BitLockerUnlock/Chrome/BLMenuBarExtra.swift#L15)

`var app: AppState` is a plain property, not `@ObservedObject`, so the status-item `systemImage` never re-evaluates — the icon stays `externaldrive` across all state transitions. The dropdown updates (it uses `@EnvironmentObject`), which masks the bug.

---

## Medium

### M-EXEC-USER — Root helper is single-threaded with no timeouts → trivial DoS
[helper/bl-helperd:80-90,175-186](helper/bl-helperd#L80). Blocking `readline()`/`read(n)` with no socket timeout, serviced inline in the accept loop. A client that connects and never sends a newline wedges the helper for all users; unbounded header `readline()` also allows memory growth.

### M-CHOWN-KILL — `proc.terminate()` on the root sudo child raises `PermissionError`
[bl:956-958](bl#L956), [bl:1114](bl#L1114). The Popen pid is the root `sudo` front-end; `kill(2)` from the unprivileged parent returns `EPERM`. Ctrl-C during an unprivileged decrypt → `PermissionError` (not `KeyboardInterrupt`) → uncaught traceback, and root dislocker keeps writing. Same for the FUSE-timeout path.

### M-DEVICE — Skip/ready checks ignore `--device`, mounting stale data from a different drive
[bl:916-919](bl#L916), [bl:1108-1112](bl#L1108). `unlock --device /dev/disk5s1` after a prior unlock of `/dev/disk4s1` finds the cached image and mounts disk4's plaintext while reporting success for disk5.

### M-QUIT — Cmd-Q during `.decrypting` exits silently, leaking a root decrypt + growing plaintext
[App.swift:40-43](BitLockerUnlock/Sources/BitLockerUnlock/App.swift#L40). `applicationShouldTerminate` only intercepts `.mounted`. Quitting mid-decrypt lets the privileged child run to completion, writing the full plaintext image to `/tmp/bl` — the exact F1-06 scenario the delegate exists to prevent.

### M-CANCEL — Cancel doesn't stop the privileged work, and the confirmation text lies
[AppState.swift:138-160](BitLockerUnlock/Sources/BitLockerUnlock/AppState.swift#L138), [DecryptingView.swift:173](BitLockerUnlock/Sources/BitLockerUnlock/Screens/DecryptingView.swift#L173). Cancel only cancels the reader task; the daemon/osascript keeps decrypting and later mounts silently. A late in-flight event can also "resurrect" cancelled state (the `Task.isCancelled` check precedes the `await consume`). The dialog's "The decryption process will be stopped" is factually wrong.

### M-BLOCKIO — Blocking POSIX `read`/`write` in `Task.detached` starves the cooperative pool
[HelperClient.swift:146-167](BitLockerUnlock/Sources/BitLockerUnlock/HelperClient.swift#L146). Cancellation is a no-op while blocked in `read(2)`; a hung daemon permanently consumes a cooperative executor thread. A few hung attempts can starve the pool.

### M-MBEDTLS — Bundle self-containment (F7-04) covers only one of five binaries; Intel-only
[make-app.sh:95-123](BitLockerUnlock/make-app.sh#L95). Verified via `otool -L`: `libdislocker.*.dylib`, `dislocker-fuse`, etc. still hard-link `/opt/homebrew/opt/mbedtls@3/...`, and `@rpath/libfuse3.4.dylib` isn't bundled. On a Mac without Homebrew mbedtls@3, `dislocker-fuse` (the helper's preferred Path B binary) dies at dyld load. The `otool` grep also only matches `/opt/homebrew`, so it silently no-ops on Intel (`/usr/local`).

### M-MANIFEST — `verify-bundle.sh` can never verify a relocated bundle
[make-app.sh:183-189](BitLockerUnlock/make-app.sh#L183). The manifest bakes **absolute** paths; `verify-bundle.sh` diffs whole lines against the bundle's current absolute paths. Copying the `.app` anywhere (the exact "after distributing" case it targets) yields a guaranteed false "integrity check FAILED". **Fix:** store bundle-relative paths.

### M-CLEANUP-STALE — Successful cleanup leaves stale `imagePath` in `.mounted`
[AppState.swift:191-203](BitLockerUnlock/Sources/BitLockerUnlock/AppState.swift#L191). After deleting the image the state still shows the "Cached plaintext image" warning and Delete button; pressing it re-runs `bl cleanup` on a missing file → spurious `cleanup_failed` (→ H4 context loss).

### M-BUILD-SH — `build.sh` lacks `set -e`; unchecked `cd` before destructive `rm`; predictable `/tmp` logs
[build.sh:150-161](build.sh#L150). `set -uo pipefail` only. If `mkdir`/`cd` fails, the script continues in the caller's cwd and `rm -f CMakeCache.txt` there, then configures cmake in the wrong dir. Logs to fixed `/tmp/bl-cmake.log` / `/tmp/bl-build.log` (symlink-clobber / multi-user collision). Use `cd ... || exit`, `mktemp`.

### M-CI-COVERAGE — CI builds only stub scaffolding, never the shipping product
[.github/workflows/ci.yml](.github/workflows/ci.yml). No `submodules: true`, never runs `build.sh`, never installs mbedtls@3, never `swift build`s the app, no ShellCheck, no lint of the ~1900-line `bl`. A broken `build.sh` or `bl` merges green. `--config Release` on a Makefile generator with no `CMAKE_BUILD_TYPE` is a silent no-op. CI also triggers only on `main`, so branch commits (like this one) get zero CI until a PR is opened.

### M-DISLOCKER-FAIL — `_dislocker_failure` misclassifies errors
[bl:861](bl#L861). Matching bare `"Failed to open"` in the log tail turns a BEK/metadata open error into a "needs Full Disk Access" message; a wrong-password failure matches nothing and surfaces as a bare exit code.

### M-SECRET-SHORT — Helper doesn't verify it read `n` secret bytes
[helper/bl-helperd:127](helper/bl-helperd#L127). A client that sends a short secret then closes yields a silently-truncated secret written to the temp file → wrong-password behavior with no error.

### M-DOC — Stale secret-transport documentation is itself security-relevant
[bl:40-42](bl#L40), [bl:764-784](bl#L764), [bl:1277](bl#L1277), [bl-open:12](bl-open#L12). Docstrings/comments still promise "delivered over a pty"; the `use_pty` parameter is accepted and ignored. This stale guarantee is the direct reason C2 went unnoticed. Also "zero our copy of the secret" comments are false — Python `bytes` are immutable; `secret.value = None` drops a reference, it doesn't wipe memory.

---

## Low

- **L-DISK7 — `bl-open` hardcodes `/dev/disk7s1` and the README claims auto-detection.** [bl-open:41](bl-open#L41) does no detection (that logic lives only in `bl-mount`), yet [README.md:35](README.md#L35) says it auto-detects. Wrong-device decrypt runs as root. Reuse `bl detect` or make the arg mandatory.
- **L-SECRET-DISK — Plaintext secret transiently on disk as root.** [helper/bl-helperd:128-131](helper/bl-helperd#L128) — atomic `mkstemp` 0600, unlinked in `finally`, mirrors bl's F1-01 design, but could survive a crash between write and unlink.
- **L-ERR-RAW — Backend error `message` rendered unredacted on screen** ([ErrorView.swift:58](BitLockerUnlock/Sources/BitLockerUnlock/Screens/ErrorView.swift#L58), [BLMenuBarExtra.swift:136](BitLockerUnlock/Sources/BitLockerUnlock/Chrome/BLMenuBarExtra.swift#L136)) — redaction applies only to the clipboard path. Defence-in-depth gap; secrets never enter argv.
- **L-JSON-ESC — Helper builds JSON via `%`/f-string interpolation** ([helper/bl-helperd:94,116-117](helper/bl-helperd#L94)) — a message with `"`/`\`/newline yields malformed JSON.
- **L-DETECT-SWALLOW — `DriveWatcher` coerces any `detect` failure to an empty list** ([DriveWatcher.swift:140-145](BitLockerUnlock/Sources/BitLockerUnlock/DriveWatcher.swift#L140)) — a locked drive shows "Plug in a BitLocker drive" with no error.
- **L-HARDPATH — Release-build `bl` fallback resolves to a hardcoded home path** ([BackendBridge.swift:610](BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L610)) — `/Users/<user>/...` (and the wrong dir name `Dislocker`).
- **L-EJECT-OK — `cmd_eject` reports success for a never-mounted target** ([bl:1147-1165](bl#L1147)).
- **L-CLEANUP-DIR — `cmd_cleanup` unhandled `IsADirectoryError`/`PermissionError`** ([bl:1177](bl#L1177)).
- **L-DEADCODE — `BackendBridge.mount(device:method:)` is dead code** ([BackendBridge.swift:261-306](BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L261)); `bl:1137` `writable` expression is always false; `bl:599` `_assert_no_verbose` has a vacuous condition; secret prompt happens before the skip-if-present check ([bl:888](bl#L888) vs [bl:916](bl#L916)).
- **L-SUBMODULE-DIRTY — Perpetual `? third_party/dislocker`** is the submodule's own untracked `build/` dir (the parent `.gitignore` can't reach it). Add `ignore = untracked` to `.gitmodules`. Pinning itself is consistent across gitlink / `dislocker.pin.md` / README.
- **L-PIN-DOC — `build.sh` header documents a `COMMIT.txt` pin file that doesn't exist** ([build.sh:14-27](build.sh#L14)) — the code actually reads `third_party/dislocker.pin.md`.
- **L-ZIP — `MacOS Bit Locker.zip` (tracked) duplicates the tracked `MacOS Bit Locker/` dir.** Otherwise hygiene is clean (`.DS_Store`, `__pycache__`, `build/` are untracked+ignored).
- **L-CRYPTO-STUBS — `bitlocker_crypto.c` stubs return success while doing nothing** (`derive_key`, `decrypt_volume_header`, `apply_elephant_diffuser` return 0 and write nothing); XTS path selects a 32-byte-key cipher with no key-length param (OOB read risk); `macos_fuse.c` ignores `volume_path` and stores literals in `char *` argv.
- **L-DRIVEWATCHER-LIFECYCLE — Thread body holds a strong `self`** so `deinit`-driven `stop()` is dead code; `stop()`/`start()` race the worker thread ([DriveWatcher.swift:61-120](BitLockerUnlock/Sources/BitLockerUnlock/DriveWatcher.swift#L61)). Low impact (app-lifetime singleton).
- **L-INSTALL-SET-E — `install-helper.sh` lacks `set -e`** — a failed `sudo cp` of the daemon doesn't abort before `launchctl bootstrap`.
- **L-KEEPALIVE — sudo keepalive backstop (30 min) is shorter than documented decrypt times ("hours").**

---

## What's sound (verified OK)

- Device names are anchored-regex validated (`^/dev/disk\d+(s\d+)*$`) on the helper's unlock/mount/probe paths — blocks traversal there.
- All privileged subprocess calls use list argv (no shell) — no command injection via request fields.
- Secret transport from the GUI never places secrets in argv, env, or the AppleScript string; the legacy osascript path validates `BL_DISLOCKER_DIR` against a metacharacter allowlist and bundle containment.
- `bl-open` / `bl-mount` secret handling is correct: `mktemp` + `chmod 600`, passed by path, `unset PASS`, EXIT/INT/TERM traps remove the file and run `sudo -k`.
- `cmd_cleanup` deletions are contained to `IMG_DIR` (keep this invariant if `bl` changes — the helper relies on it, see H8 notes).
- Submodule pin is internally consistent and enforced by `build.sh`.
- The single-`@MainActor`-enum state machine is a clean, appropriate design; the code is exceptionally well-annotated.

---

## Recommended priority order

1. **C1** — stop root from executing user-writable code (root-owned install of `bl` + binaries, ownership check before exec). Highest leverage.
2. **C2** — fix recovery-key transport (use `-p -` reading stdin, or write to the tty dislocker actually reads), and fix the stale docs (M-DOC) that hid it.
3. **H1** — move `enable_testing()` to root CMake + `--no-tests=error`, then fix the `aes_decrypt` padding bug (H1 second half).
4. **C3 / H6 / M-CHOWN-KILL** — make the unprivileged CLI path actually work (chown across sudo, uncaught exceptions, terminate root child).
5. **H3 / H2 / H4** — fix the Swift IO/state failure paths (pipe drain, EOF-without-terminal-event, `.mounted` context loss).
6. **H5 / H7 / H8** — close the remaining privilege/secret gaps (sheet-window capture, peer-uid check, eject path validation).
7. **M-CI-COVERAGE** — make CI build and lint the real product so the above can't regress silently.
