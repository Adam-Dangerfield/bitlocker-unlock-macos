# Section 1: Authentication & Secret Handling

## Summary

The BitLocker secret (password or 48-digit recovery key) is exposed in the process argument list at every layer of the stack: as a `--password` / `--recovery` CLI flag to `bl`, embedded verbatim inside the AppleScript string passed via `osascript -e`, and finally as a `-u` / `-p` flag concatenated directly onto `dislocker-file`'s argv — all of which are visible to any local user via `ps aux` for the full duration of the decrypt operation (potentially hours). The bash wrapper `bl-open` partially mitigates this by `unset`ing the shell variable after spawning the child, but the secret is already in the child's argv at that point. No zeroization occurs in the Python path, no kernel memory locking (`mlock`) is used anywhere, and a "Remember for this session" UI toggle is rendered but never wired to any storage or logic. On the positive side, the UI correctly uses `SecureField` for password entry and `UnlockMethod.label` is careful never to include secret material in log-safe strings.

## Findings

### F1-01 — CRITICAL — BitLocker secret exposed in `dislocker-file` argv (ps-visible)

**Evidence:** [bl#L176](../../../bl#L176), [bl#L178](../../../bl#L178), [bl#L260](../../../bl#L260)

```python
def build_auth_args(args) -> list[str]:
    if args.recovery:
        return [f"-p{args.recovery}"]
    if args.password is not None:
        return [f"-u{args.password}"]
    ...
proc = subprocess.Popen(
    ["sudo", str(DISLOCKER_FILE), "-V", args.device, *auth, "--", str(out_path)],
```

**CWE:** CWE-214 (Invocation of Process Using Visible Sensitive Information)

**Impact:** The plaintext password or recovery key is concatenated directly onto the argv of the `dislocker-file` subprocess (e.g. `-umysecret`). On macOS, `/proc` is absent but `ps aux` and the `sysctl` KERN_PROCARGS2 interface are available to all local users without any privilege. Any process running as the same user — or any user if the default `kern.ps_showallprocs` sysctl is enabled — can read the full argv and extract the BitLocker credential. Because `dislocker-file` decrypts at roughly 100–200 MB/s for a 1 TB drive, the window of exposure can be 1–3 hours. The same vulnerability exists in `cmd_mount` via [bl#L322](../../../bl#L322) and [bl#L331](../../../bl#L331).

**Remediation:** Pass the secret out-of-band via a pipe or a temporary file with mode 0600. `dislocker-file` supports `-p -` (read from stdin) for the recovery key and `-u -` for the user password; use `stdin=subprocess.PIPE` and `proc.stdin.write(secret.encode()); proc.stdin.close()`. If `dislocker-file` does not support stdin, write the secret to a `tempfile.NamedTemporaryFile(mode='w', delete=False)` with `os.chmod(fd, 0o600)` immediately after creation, pass `-f <tmpfile>` to dislocker, and unlink it once the process has opened it (within 1–2 seconds). Either approach removes the secret from the argv namespace entirely.

---

### F1-02 — CRITICAL — BitLocker secret embedded in osascript `-e` argument (ps-visible)

**Evidence:** [BackendBridge.swift#L330](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L330), [BackendBridge.swift#L340](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L340), [BackendBridge.swift#L345](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L345)

```swift
let cmd = envPrefix + (["/usr/bin/env", "python3", blPath, subcommand] + extraArgs)
    .map(Self.shellQuote).joined(separator: " ")
let asEscaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"")
let script = "do shell script \"\(asEscaped)\" with administrator privileges"
// ...
args: ["-e", script]
```

**CWE:** CWE-214 (Invocation of Process Using Visible Sensitive Information)

**Impact:** `method.cliArgs` (from `UnlockMethod.swift#L16`) returns `["--password", "<plaintext>"]` or `["--recovery", "<plaintext>"]`. These values flow into `extraArgs`, are shell-quoted and joined into a single command string, and then that string is passed as the `-e` argument to `/usr/bin/osascript`. The full AppleScript — containing the plaintext credential — therefore appears in osascript's argv entry, visible to `ps aux` from the moment the Swift process spawns osascript until osascript exits (same multi-hour window as F1-01). The secret is also transiently present in the Swift `String` objects `cmd`, `asEscaped`, and `script` in the process heap without any zeroization.

**Remediation:** Decouple privilege escalation from secret transport. Two options: (a) Use `SMJobBless` or an XPC helper that receives the secret over a local UNIX-domain socket with appropriate entitlements, never embedding it in any argv. (b) If osascript remains, write the secret to a named pipe or temp file before escalation, pass only the file path (not the secret) in the argv, and have `bl` read from the pipe/file — the file should be unlinked before `dislocker-file` is spawned. This also resolves F1-01 simultaneously. See also Section 4 (injection) for the related AppleScript injection risk of embedding user input in the `-e` string.

---

### F1-03 — HIGH — BitLocker secret in `bl-open` argv window before `unset`

**Evidence:** [bl-open#L126](../../../bl-open#L126), [bl-open#L129](../../../bl-open#L129), [bl-open#L142](../../../bl-open#L142), [bl-open#L144](../../../bl-open#L144)

```bash
AUTH_ARGS=("-p$PASS")   # or "-u$PASS"
sudo "$DISLOCKER" -V "$DEVICE" "${AUTH_ARGS[@]}" -- "$IMG" >"$LOG" 2>&1 &
DPID=$!
unset PASS AUTH_ARGS
```

**CWE:** CWE-214 (Invocation of Process Using Visible Sensitive Information)

**Impact:** `bl-open` correctly uses `read -rsp` (no echo, no history) and `unset`s `$PASS` and `$AUTH_ARGS` after forking the child. However, `unset` only removes the variable from the shell's environment; the child process (`dislocker-file`) has already inherited its argv at fork time and those values remain in the child's address space and in the kernel's process table. The `unset` at line 144 cannot retract the secret from the already-spawned child's argv. The entire decode window (up to hours) remains exposed. This is a lesser instance of F1-01 but originates from a different entry path.

**Remediation:** Same as F1-01: use stdin or a temp file to deliver the secret to `dislocker-file`, never via argv expansion.

---

### F1-04 — HIGH — No in-memory zeroization of secret after use

**Evidence:** [bl#L170](../../../bl#L170)–[bl#L183](../../../bl#L183), [UnlockMethod.swift#L14](../../../BitLockerUnlock/Sources/BitLockerUnlock/Models/UnlockMethod.swift#L14)–[UnlockMethod.swift#L19](../../../BitLockerUnlock/Sources/BitLockerUnlock/Models/UnlockMethod.swift#L19), [UnlockSheetView.swift#L20](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/UnlockSheetView.swift#L20)

```python
def build_auth_args(args) -> list[str]:
    ...
    return [f"-u{args.password}"]   # secret lives in list until GC
```

**CWE:** CWE-316 (Cleartext Storage of Sensitive Information in Memory)

**Impact:** In Python, strings are immutable and reference-counted; there is no way to zero the underlying buffer before the GC reclaims it. In Swift, `String` values bound in `UnlockMethod.password(String)` and in `passwordText: String` (`UnlockSheetView.swift:20`) similarly have no guaranteed zeroization. If the process crashes (core dump), is suspended (hibernation/swap), or if a local attacker dumps the process memory via `task_for_pid`, the cleartext secret may be recoverable from memory pages. The risk is elevated because macOS allows the decrypted image to persist at `/tmp/bl/decrypted.img` across reboots (see F1-06) and the process lives for the entire decrypt window.

**Remediation:** For the Swift layer, store the password in a `SecKeyCreateWithData`-backed buffer or use `Data` with explicit zeroing via `withUnsafeMutableBytes { memset($0.baseAddress, 0, $0.count) }` before the variable is released. Mark the `UnlockMethod` enum storage as `@_sensitive` or pin pages with `mlock`. For Python, use a `bytearray` (mutable) for the secret, overwrite it with zeros immediately after building `auth`, and avoid creating intermediate `str` copies. Also add `ulimit -c 0` in `bl-open` to disable core dumps for the decrypt process.

---

### F1-05 — HIGH — dislocker.log written to world-readable `/tmp/bl` directory

**Evidence:** [bl#L56](../../../bl#L56), [bl#L258](../../../bl#L258)–[bl#L261](../../../bl#L261), [bl#L300](../../../bl#L300)–[bl#L302](../../../bl#L302)

```python
LOG_FILE = IMG_DIR / "dislocker.log"   # /tmp/bl/dislocker.log
log = LOG_FILE.open("wb")
proc = subprocess.Popen(
    ["sudo", str(DISLOCKER_FILE), "-V", args.device, *auth, "--", str(out_path)],
    stdout=log, stderr=subprocess.STDOUT,
)
# On failure:
tail = LOG_FILE.read_text(errors="replace").splitlines()[-20:]
fail("DECRYPT_FAILED", f"dislocker-file exit {rc}. tail:\n" + "\n".join(tail), ...)
```

**CWE:** CWE-532 (Insertion of Sensitive Information into Log File)

**Impact:** `/tmp/bl` is created with `mkdir(parents=True, exist_ok=True)` using no explicit mode, so it inherits the process umask (typically 022), making it world-executable and group-readable. `dislocker-file`'s stdout/stderr (which may include diagnostic lines echoing the credential flags, internal state, or error messages containing partial key material) is written as root to `dislocker.log` in this directory. When decryption fails, the last 20 lines of the log are included verbatim in the error message propagated back through JSON to the Swift UI and potentially to `os_log`. Additionally, if Time Machine or another backup agent is active, `/tmp/bl/dislocker.log` may be snapshotted while the secret is present. Note: `/tmp/bl` is a symlink to `/private/tmp/bl` on macOS; Time Machine excludes `/private/tmp` by default, but a non-default backup configuration could include it.

**Remediation:** Create `IMG_DIR` with mode `0o700` explicitly: `IMG_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)`. Open `LOG_FILE` with `O_CREAT | O_WRONLY | O_TRUNC` and mode `0600` before passing to the subprocess. Truncate and delete the log immediately after a successful or failed run — do not leave it on disk between sessions. Strip or redact any credential-bearing lines before including log tail in error messages.

---

### F1-06 — MEDIUM — Decrypted image persists indefinitely at `/tmp/bl/decrypted.img`

**Evidence:** [bl#L246](../../../bl#L246)–[bl#L249](../../../bl#L249), [BackendBridge.swift#L42](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L42)

```python
if out_path.exists() and out_path.stat().st_size > 0:
    mount_path = hdiutil_attach(out_path)
    emit({"mountPath": mount_path}, json_mode=args.json)
    return 0
```

**CWE:** CWE-922 (Insecure Storage of Sensitive Information)

**Impact:** The decrypted plaintext image is intentionally cached at `/tmp/bl/decrypted.img` to avoid re-decrypting on the next mount. On macOS, `/private/tmp` survives reboots (it is cleaned only on boot-time `periodic daily`). A physical-access attacker who obtains the Mac after a session (screen-locked or stolen) can mount the pre-existing image without needing the BitLocker password — bypassing the entire authentication flow. The image is root-owned with mode 0600 at time of writing (observed from a live session), so a local non-root attacker cannot read it directly, but root escalation (e.g. via a sudo misconfiguration) would give full access.

**Remediation:** Prompt the user to eject and delete the image at app quit. Expose a clear "Eject and delete image" affordance and make it the default action. Optionally, register a `SIGTERM`/`applicationWillTerminate` handler that ejects and unlinks `/tmp/bl/decrypted.img` automatically. For the strongest posture, use an in-memory RAM disk (`hdiutil attach -nomount ram://...`) rather than a `/tmp` file, so the plaintext disappears on reboot or unmount.

---

### F1-07 — MEDIUM — `emit()` called with undeclared `stream=True` kwarg (latent crash)

**Evidence:** [bl#L291](../../../bl#L291), [bl#L307](../../../bl#L307)

```python
emit({...}, json_mode=args.json, stream=True)
```

**CWE:** CWE-755 (Improper Handling of Exceptional Conditions)

**Impact:** `emit()` is defined at [bl#L67](../../../bl#L67) with the signature `def emit(obj: dict, *, json_mode: bool) -> None` — it does not accept a `stream` keyword argument. Calling `emit(..., stream=True)` will raise `TypeError: emit() got an unexpected keyword argument 'stream'` at runtime. This means progress reporting during `cmd_unlock` (and the final 100% paint) will crash the Python process with an unhandled exception rather than fail gracefully. An attacker who triggers a decrypt attempt can observe an abnormal exit code but cannot exploit this directly; however the crash means the JSON error path is bypassed and the UI may hang waiting for osascript to return. The secret has already been passed to `dislocker-file` by this point, so exposure from F1-01 is not worsened, but reliability is impacted.

**Remediation:** Add `stream: bool = False` to `emit()`'s signature (or remove the `stream=True` call sites). Add a test that calls `cmd_unlock` in dry-run mode to exercise the progress path.

---

### F1-08 — LOW — "Remember for this session" toggle is a UI stub with no backing store

**Evidence:** [UnlockSheetView.swift#L24](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/UnlockSheetView.swift#L24)–[UnlockSheetView.swift#L25](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/UnlockSheetView.swift#L25), [UnlockSheetView.swift#L136](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/UnlockSheetView.swift#L136)–[UnlockSheetView.swift#L139](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/UnlockSheetView.swift#L139)

```swift
// UI-only session-remember toggle
@State private var rememberSession: Bool = false
// ...
Toggle(isOn: $rememberSession) {
    Text("Remember for this session")
```

**CWE:** CWE-671 (Lack of Administrator Control over Security)

**Impact:** The toggle is rendered and is user-interactable, but `rememberSession` is never read by `handleUnlock()` or passed to `AppState.attemptUnlock()`. If a future developer wires it to a Keychain store without a security review, this becomes a credential-storage risk. At present the risk is low — the toggle does nothing — but the misleading UI could cause a user to believe their credential is being remembered (and stored securely) when it is not, or vice versa.

**Remediation:** Either implement the Keychain-backed session credential store (use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecAttrAccessControl` with `.userPresence`) or remove the toggle until the feature is ready. Add a code comment making the stub status explicit and adding a `TODO` with a ticket reference.

---

## Pass items

- **SecureField for password entry** — [UnlockSheetView.swift#L181](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/UnlockSheetView.swift#L181) uses `SecureField`, preventing the password from appearing in the autocomplete / accessibility tree and masking characters on screen.
- **`UnlockMethod.label` never leaks secrets** — [UnlockMethod.swift#L23](../../../BitLockerUnlock/Sources/BitLockerUnlock/Models/UnlockMethod.swift#L23)–[UnlockMethod.swift#L27](../../../BitLockerUnlock/Sources/BitLockerUnlock/Models/UnlockMethod.swift#L27) returns only `"Password"`, `"Recovery Key"`, or `"BEK File"` — never the credential value. Safe for logging.
- **Shell-quoting applied before osascript embedding** — [BackendBridge.swift#L354](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L354)–[BackendBridge.swift#L357](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L357) uses POSIX single-quote wrapping with internal single-quote escaping. This prevents shell word-splitting but does not prevent argv exposure (see F1-02; shell injection is Section 4's scope).
- **`bl-open` uses `read -rsp`** — [bl-open#L123](../../../bl-open#L123) reads the password with echo suppressed and no shell history recording (`read -s`), reducing shoulder-surfing and `~/.bash_history` leakage.
- **`bl-open` unsets `$PASS` and `$AUTH_ARGS`** — [bl-open#L144](../../../bl-open#L144) removes the variables from the bash environment after forking the child. Insufficient to protect the child's argv (see F1-03), but limits env-variable inspection of the parent process.
- **Decrypted image written root-owned, mode 0600** — confirmed at runtime; the plaintext image is not world-readable to non-root local users.
- **No credentials logged via Swift logging APIs** — a search of `BackendBridge.swift` and `AppState.swift` found no `os_log`, `NSLog`, or `print` statements that include `method.cliArgs` or the raw credential value.
- **`BackendBridge.runProcess` inherits the process environment only when `extraEnv` is non-empty** — [BackendBridge.swift#L282](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L282)–[BackendBridge.swift#L285](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L285) avoids leaking unrelated environment variables into child processes when no overlay is needed.

## Section verdict

- PASS items: 7
- PARTIAL items: 0
- FAIL items: 8 (2 × CRITICAL, 2 × HIGH, 2 × MEDIUM, 2 × LOW/MEDIUM)
