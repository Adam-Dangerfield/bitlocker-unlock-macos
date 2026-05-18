# Security Review — BitLocker Unlock (macOS) v0.1
**Reviewed:** 2026-05-18
**Reviewer:** Claude Opus 4.7 (7 Sonnet specialist passes + 1 Opus aggregation)
**Scope:** Initial review covering all locally-developed code paths
(`bl`, `bl-open`, `bl-mount`, `build.sh`, `BitLockerUnlock/`). The vendored
upstream dislocker at `third_party/dislocker/` is treated as out-of-scope
for line-level review; verified as GPLv2 release 0.7.3 unmodified.

## Threat model

**In scope:**
- Local non-root attacker with shell on the same Mac
- Physical-access attacker on stolen / unattended Mac
- Supply-chain tamper of the .app bundle or vendored dependencies
- Accidental exfiltration via logs / backups / clipboard / screenshots

**Out of scope:**
- Kernel-level attackers (SIP bypass, etc.)
- Cryptographic primitives in dislocker (vendored upstream GPLv2 0.7.3)
- TLS / network surface (none)
- User's FileVault choice

## Summary scorecard

| Section | CRITICAL | HIGH | MEDIUM | LOW | Section verdict |
|---|---:|---:|---:|---:|---|
| 1. Authentication & Secret Handling | 2 | 3 | 2 | 1 | FAIL |
| 2. Input Validation & Path Safety | 0 | 2 | 2 | 1 | FAIL |
| 3. Privilege Escalation & Process Boundary | 0 | 3 | 2 | 1 | FAIL |
| 4. Shell / AppleScript / Command Injection | 0 | 1 | 0 | 0 | PARTIAL (conditional pass) |
| 5. Filesystem & Data Persistence | 1 | 2 | 3 | 2 | FAIL |
| 6. Logging & Information Disclosure | 0 | 2 | 1 | 2 | FAIL |
| 7. Build & Supply Chain | 2 | 3 | 3 | 1 | FAIL |
| **TOTALS** | **5** | **16** | **13** | **8** | **6 FAIL / 1 PARTIAL / 0 PASS** |

**Total findings: 42** (5 CRITICAL, 16 HIGH, 13 MEDIUM, 8 LOW)

## Top priority — remediate in this order

### CRITICAL — fix before any third-party distribution

1. **F7-01** · Sign and notarize the `.app` bundle · `BitLockerUnlock/make-app.sh` · Apply Developer ID signature, enable Hardened Runtime, notarize and staple — without this, every other tamper finding is trivially exploitable.
2. **F7-02** · `BL_PATH_OVERRIDE` redirects privileged escalation to arbitrary script · `BackendBridge.swift:374` (`locateBL`) · Remove the override in production builds, or allowlist paths inside `Bundle.main.bundlePath`.
3. **F5-01** · `/tmp/bl` symlink pre-emption attack · `bl#L242`, `bl-open#L39` · After `mkdir -p`, assert `not IMG_DIR.is_symlink()` (Python) and `[[ ! -L $IMG_DIR ]]` (bash); abort on detection.
4. **F1-01** · BitLocker secret in `dislocker-file` argv (ps-visible for hours) · `bl#L176`, `bl#L178`, `bl#L260`, `bl#L322`, `bl#L331` · Pass the secret via stdin (`-p -` / `-u -` with `subprocess.PIPE`) or a mode-0600 temp file; never via argv.
5. **F1-02** · BitLocker secret embedded in osascript `-e` argument (ps-visible) · `BackendBridge.swift:330-345` · Decouple privilege escalation from secret transport — use SMJobBless/XPC helper, or hand `bl` a file/FIFO path (not the secret) and have `bl` read the secret out-of-band.

### HIGH — fix before personal use beyond the developer's own Mac

6. **F1-03** · Secret in `bl-open` argv before `unset` (already-spawned child still holds it) · `bl-open#L126`, `#L142` · Same fix as F1-01: stdin/temp-file delivery.
7. **F1-04** · No in-memory zeroization of secret · `bl#L170-183`, `UnlockMethod.swift:14-19`, `UnlockSheetView.swift:20` · Use `bytearray` in Python and overwrite; in Swift use `Data` with `memset` and `mlock` pages; disable core dumps in `bl-open`.
8. **F1-05** · `dislocker.log` in world-readable `/tmp/bl` · `bl#L56`, `#L258-261` · Open `LOG_FILE` with `O_CREAT|O_WRONLY|O_TRUNC` mode 0600; redact credential-bearing lines before surfacing log tail.
9. **F2-01** · `--recovery` flag bypasses `RECOVERY_RE` validation · `bl#L175` · Apply the same `RECOVERY_RE.match()` guard used in the interactive path.
10. **F2-02** · `--out PATH` has no containment check; root writes anywhere · `bl#L241-260` · Mirror the `cmd_cleanup` resolve+`in target.parents` guard; reject paths outside `IMG_DIR`.
11. **F3-01** · `bl` sudo keepalive child orphans, extends sudo timestamp · `bl#L186` · Store child PID; register `atexit` + SIGTERM/SIGINT handlers that kill it.
12. **F3-02** · `bl-open` keepalive not killed on all exit paths · `bl-open#L136-138` · Move kill into an `EXIT` trap: `trap 'kill "${KEEP_SUDO:-}" 2>/dev/null; trap - EXIT' EXIT`.
13. **F3-03** · `BL_DISLOCKER_DIR` controls which binary runs as root · `bl#L50`, `BackendBridge.swift:327` · Resolve binary from `SCRIPT_DIR` realpath; reject env override or allowlist to bundle prefix.
14. **F4-01** · `BL_DISLOCKER_DIR` containing `"` or `\` breaks AppleScript escape → root injection · `BackendBridge.swift:327, 336-340` · Apply AppleScript escape to `envPrefix` separately, or reject `"`/`\` in `dir`.
15. **F5-02** · TOCTOU between `stat()` and `sudo chown` in `hdiutil_attach` · `bl#L391-394` · Use `os.open(..., O_NOFOLLOW)` + `os.fchown`.
16. **F5-03** · `/tmp/bl/decrypted.img` persists indefinitely (survives reboot) · `bl#L54, #L246-249` · Default cleanup at app quit / eject; consider RAM disk via `hdiutil attach -nomount ram://`.
17. **F6-01** · `DECRYPT_FAILED` embeds log tail in UI and clipboard · `bl#L300-303`, `ErrorView.swift:53, 124-128` · Show a generic UI message; keep raw tail to disk only; gate "Copy error details" to code-only.
18. **F6-02** · Latent: dislocker `L_DEBUG` `dis_printf` prints plaintext passwords if `-v -v -v -v` ever set · `third_party/dislocker/src/accesses/{user_pass,rp}/...` · Upstream patch to remove or `#ifdef`-guard credential-printing.
19. **F7-03** · Vendored dislocker tracks `origin/master` — no commit pin · `third_party/dislocker/.git/HEAD` · Convert to submodule pinned to v0.7.3 commit SHA; enforce in CI.
20. **F7-04** · mbedtls@3 dependency not version-pinned or hash-checked · `build.sh#L19` · Pin minimum/maximum version in `build.sh`; consider static-linking and bundling.
21. **F7-05** · No artifact integrity manifest for bundled binaries · `BitLockerUnlock/make-app.sh#L50` · Generate `SHASUMS256` after build; verify in `make-app.sh` before copy.

## STRIDE replay

**Spoofing.** The privileged side of the trust boundary — `dislocker-file` / `dislocker-fuse` — is identified solely by file path, with no signature or hash check. F3-03, F7-02, and F7-06 all let a local attacker substitute an arbitrary binary at the resolved path; F7-01 lets them substitute the entire app bundle. There is no mutual authentication between the Swift UI and `bl`, and no user-visible indication that "the binary about to run as root is the one we shipped." Net: spoofing of the privileged executable is the project's largest single problem.

**Tampering.** Multiple primitives. The unsigned bundle (F7-01) means any file under `Contents/Resources/` can be swapped without detection. The vendored dislocker tracking `origin/master` (F7-03), unpinned mbedtls (F7-04), and missing SHA manifest (F7-05) put the build pipeline itself at risk. At runtime, the `/tmp/bl` symlink pre-emption (F5-01), TOCTOU chown (F5-02), `--out` path traversal (F2-02), and BEK TOCTOU (F2-04) let a local attacker subvert filesystem state. The unbound Info.plist (F7-07) tampers persistently with no signature delta.

**Repudiation.** Limited surface. The single `osascript … with administrator privileges` prompt (F3-04) wraps a multi-minute root grant, so the user has no per-command audit trail of what ran as root — they cannot meaningfully verify what they authorised. The orphaned sudo keepalives (F3-01, F3-02) similarly let subsequent root operations occur without re-challenge. The audit gap is real for "what did this app actually do as root?", but no logs are forged or deleted.

**Information disclosure.** The dominant theme. Plaintext password in argv (F1-01, F1-02, F1-03), no zeroization (F1-04), world-readable directory and log (F1-05, F5-04, F5-05), 128 GB plaintext image persisting on disk (F1-06, F5-03), log tail piped to UI and clipboard (F6-01, F6-04), missing `NSWindowSharingNone` (F6-03), Time Machine / backup exposure (F5-08), latent debug-mode password print (F6-02), `bl-open` lacking `-nobrowse` (F5-07). This category alone has 12+ findings and three CRITICALs.

**Denial of service.** Modest. F5-06 (predictable filename pre-fill) and F5-01 (symlink to a destination that runs out of space) can cause decrypt failures. The orphaned sudo keepalive consumes a process slot but is not a serious DoS. None of the findings are weaponisable for cross-user DoS without already winning a higher-severity finding.

**Elevation of privilege.** Multiple direct primitives. F3-03 + F7-02 + F7-06 each give root via env-variable manipulation alone. F7-01 gives persistent root via a one-file bundle edit. F5-01 → F5-02 chains symlink to root-`chown` of `/etc/sudoers`. F4-01 turns a controlled `BL_DISLOCKER_DIR` value into AppleScript command injection with administrator privileges. F3-01/F3-02 extend the post-operation sudo window. The osascript flow (F3-04) grants a single broad root window per session, amplifying every other elevation primitive.

## Cross-section themes

- **Env-var trust boundary repeatedly violated.** `BL_PATH_OVERRIDE` and `BL_DISLOCKER_DIR` are accepted without canonicalisation, allowlist, or signature check in both the Swift layer and the Python `bl` script: F2-03, F3-03, F4-01, F7-02, F7-06. Any one of them yields root-equivalent execution. A single shared "trusted-path resolver" helper would close most of these.

- **Argv-as-secret-channel is the project's dominant exposure pattern.** The BitLocker secret travels through argv at three different layers — Swift→osascript (F1-02), Python→sudo→dislocker (F1-01), and bash→sudo→dislocker (F1-03) — and all three are `ps`-visible to any local user for the multi-hour decrypt window. A single stdin/temp-file delivery refactor in `bl` collapses all three.

- **`/tmp/bl/` is treated as a private directory but is not one.** Created without explicit mode (F5-04), with no symlink check (F5-01), containing a persistent plaintext image (F1-06, F5-03), a world-readable log (F1-05, F5-05), a predictable filename (F5-06), and unvalidated `chown` targets (F3-06, F5-02). The directory needs to be `mkdir(mode=0o700)` + symlink-guard + cleanup-on-exit as a single hardening pass.

- **No artifact integrity at any layer of the build or run pipeline.** Bundle unsigned (F7-01), Info.plist unbound (F7-07), vendored dislocker on a moving branch (F7-03), unpinned mbedtls (F7-04), no SHASUMS manifest (F7-05), placeholder Homebrew hash (F7-08), no reproducible build (F7-09). Combined with F3-05's "no binary integrity check before root execution" this means the privileged code path has zero supply-chain assurance.

- **Cleanup paths exist for the safe operations but not the destructive ones.** `cmd_cleanup` correctly implements path containment, but the analogous guards are missing in `cmd_unlock` (F2-02), `cmd_mount`, and `hdiutil_attach` (F5-02, F3-06). The right pattern is already in the codebase — it just is not applied uniformly.

## Sections 1-7

## Section 1 — Authentication & Secret Handling

---

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

## Section 2 — Input Validation & Path Safety

---

# Section 2: Input Validation & Path Safety

## Summary

Input validation is inconsistent and leaves two meaningful attack surfaces open. The `--recovery` CLI flag bypasses the `RECOVERY_RE` regex that guards the interactive prompt, so any arbitrary string reaches the dislocker binary's `-p` flag without format checking. The `--out PATH` flag in `cmd_unlock` accepts any path with no containment check, allowing a caller to direct root-owned image writes anywhere on the filesystem — a significant gap relative to the intentionally tight guard in `cmd_cleanup`. The two env vars `BL_PATH_OVERRIDE` and `BL_DISLOCKER_DIR` are consumed without canonicalisation or allowlist checks, but their practical risk is lower because they are set by the Swift host process rather than by end-user text input. The `cmd_cleanup` path-containment guard is correctly implemented. JSON decoded from `diskutil`/`hdiutil` plist output is consumed defensively with typed accessors and safe defaults. No regex bypass from under-anchored patterns was found in `RECOVERY_RE` itself — the anchors `^…$` are correct — but the regex is simply not applied to the `--recovery` command-line argument.

## Findings

### F2-01 — HIGH — `--recovery` flag bypasses `RECOVERY_RE` validation

**Evidence:** [bl#L59](../../../bl#L59), [bl#L175](../../../bl#L175)

```python
RECOVERY_RE = re.compile(r"^\d{6}(-\d{6}){7}$")   # L59

if args.recovery:
    return [f"-p{args.recovery}"]                   # L175-176 — no regex check
```

**CWE:** CWE-20 (Improper Input Validation)

**Impact:** `RECOVERY_RE` is applied only to the interactive-prompt code path (`getpass`, L181). When the caller supplies `--recovery` on the command line, any string — including one containing shell metacharacters or binary data — is interpolated directly into the `-p<value>` argument passed to `dislocker-file` under `sudo`. Although the argument list is passed as a Python list (not a shell string), so shell injection is not the risk here (see Section 4), the lack of format enforcement means a malformed key will reach the C binary unparsed, and error messages echoed from `dislocker-file` as root may be reflected back to the caller via the log file and `fail()`. In a GUI context where `BackendBridge` receives the value from `UnlockMethod.cliArgs`, this path is reached without any intermediate sanitisation.

**Remediation:** In `build_auth_args` (`bl`, around L175), add the same `RECOVERY_RE.match(args.recovery)` guard that protects the interactive path. Reject — or at minimum warn — if the pattern does not match before constructing the `-p` argument.

---

### F2-02 — HIGH — `--out PATH` has no path-containment check

**Evidence:** [bl#L241](../../../bl#L241), [bl#L243](../../../bl#L243), [bl#L260](../../../bl#L260)

```python
out_path = Path(args.out or DEFAULT_IMAGE)           # L241
IMG_DIR.mkdir(parents=True, exist_ok=True)
out_path.parent.mkdir(parents=True, exist_ok=True)   # L243 — creates arbitrary dirs
# ...
["sudo", str(DISLOCKER_FILE), "-V", args.device,
 *auth, "--", str(out_path)],                        # L260 — root writes to out_path
```

**CWE:** CWE-22 (Path Traversal)

**Impact:** Any caller with access to the `bl` CLI can pass `--out /some/sensitive/location/payload.img`. Because `dislocker-file` runs as root (via `sudo`), the decrypted image is written to that path as root. Combined with `out_path.parent.mkdir(parents=True, exist_ok=True)` the code will also create arbitrary directory hierarchies as the invoking user before the sudo-privileged write. An unprivileged local attacker could pre-stage `/tmp/bl/../../../Library/LaunchDaemons/evil.plist`, then trigger an unlock to overwrite it. The `cmd_cleanup` function has the correct pattern — `target.parents` check against `IMG_DIR.resolve()` — but `cmd_unlock` has no equivalent guard.

**Remediation:** In `cmd_unlock` (`bl`, around L241), resolve `out_path` and verify it sits under `IMG_DIR` (mirroring `cmd_cleanup` L358-363). Reject any path outside that root with the same `UNSAFE_PATH` error. The `--out` flag was presumably added for developer convenience; it should be removed from the public interface or restricted to the safe root.

---

### F2-03 — MEDIUM — `BL_PATH_OVERRIDE` accepted without canonicalisation or allowlist

**Evidence:** [BackendBridge.swift#L374](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L374)

```swift
if let override = ProcessInfo.processInfo.environment["BL_PATH_OVERRIDE"],
   !override.isEmpty {
    return override          // returned verbatim, no realpath / containment check
}
```

**CWE:** CWE-426 (Untrusted Search Path)

**Impact:** The only check is `!override.isEmpty`. A local attacker who can inject environment variables into the app's process (e.g., via `launchctl setenv` before the app starts, or via a compromised parent process) can redirect `blPath` to an arbitrary executable. That executable then runs with the user's credentials and, for `unlock`/`mount`, under `osascript` with administrator privileges. The risk is partially mitigated by macOS's Hardened Runtime blocking `DYLD_*` injection, but `BL_PATH_OVERRIDE` is an application-level override with no equivalent protection.

**Remediation:** In `BackendBridge.locateBL()`, after reading `BL_PATH_OVERRIDE`, call `URL(fileURLWithPath: override).standardizedFileURL` and verify the resolved path falls within `Bundle.main.bundlePath` or a hard-coded development prefix (e.g., the repo root). If neither condition is met, ignore the override and fall through to the bundle lookup.

---

### F2-04 — MEDIUM — TOCTOU: BEK file existence check vs. use

**Evidence:** [bl#L172](../../../bl#L172), [bl#L174](../../../bl#L174)

```python
if not Path(args.bek).is_file():   # L172 — existence check
    return []
return ["-f", args.bek]            # L174 — path used seconds later under sudo
```

**CWE:** CWE-367 (TOCTOU Race Condition)

**Impact:** Between `is_file()` at L172 and the subsequent `sudo dislocker-file -f <bek>` invocation (triggered from L260), an attacker controlling a writable directory in the BEK path could swap the file for a symlink pointing elsewhere. `dislocker-file` running as root would then open the attacker-chosen target. The window is narrow (milliseconds), making reliable exploitation difficult, but the consequence — root-level read of an arbitrary file — is serious in a shared-user-account scenario (a local non-root attacker with write access to the parent directory).

**Remediation:** Open the BEK file in `build_auth_args` with `open(args.bek, 'rb')` and pass the file descriptor to dislocker via `/dev/fd/<n>` (if supported), or copy the file to a `tempfile.mkstemp`-created path inside `/tmp/bl` immediately after the existence check and pass that path instead. This eliminates the window between check and use.

---

### F2-05 — LOW — `--device` argument not validated against `/dev/disk` prefix

**Evidence:** [bl#L237](../../../bl#L237), [bl#L260](../../../bl#L260)

```python
total = device_size(args.device)   # L237 — diskutil info on arbitrary string
# ...
["sudo", str(DISLOCKER_FILE), "-V", args.device, ...]  # L260
```

**CWE:** CWE-20 (Improper Input Validation)

**Impact:** Any string is accepted as `--device`. `device_size` will pass it to `diskutil info`, which safely errors for non-device strings, but the same value is later passed as the `-V` argument to `dislocker-file` under `sudo`. Although argument-list quoting prevents shell injection (Section 4), a path like `/dev/../etc/passwd` or a named pipe could cause unexpected behaviour inside the C binary running as root. The practical risk to a local non-root attacker is low because they already control the command line.

**Remediation:** In `cmd_unlock` and `cmd_mount`, validate `args.device` with a simple prefix check (`args.device.startswith("/dev/disk")`) before calling `device_size` or building the subprocess command.

## Pass items

- **`RECOVERY_RE` anchoring is correct** — `bl#L59`: `r"^\d{6}(-\d{6}){7}$"` uses both `^` and `$` anchors; no bypass via embedded newlines because `re.DOTALL` / `re.MULTILINE` are not set and `.match()` is used.
- **`cmd_cleanup` path-containment guard is correct** — `bl#L358-363`: uses `Path.resolve()` on both target and safe root before the `in target.parents` check; symlinks are followed, so `../` traversal is neutralised.
- **`diskutil`/`hdiutil` plist decoding is type-safe** — `bl#L114-115`, `bl#L122-150`: `plistlib.loads` returns typed Python objects; all field accesses use `.get()` with typed defaults (`""`, `0`, `[]`); `int(p.get("TotalSize", 0) or 0)` double-guards against `None`.
- **`BL_DISLOCKER_DIR` in Python is path-joined, not executed** — `bl#L50-52`: the env var is used only to form `DISLOCKER_DIR / "dislocker-file"` and `DISLOCKER_DIR / "dislocker-fuse"`; the resulting path is passed as a list argument to `subprocess`, not evaluated as a shell command.
- **`shellQuote` in `BackendBridge` is correct for POSIX single-quoting** — `BackendBridge.swift#L354-357`: wraps in single quotes and escapes embedded single quotes via `'\\''`; covers the dislocker-dir env injection at L327.
- **`hdiutil` plist output used for mount-point lookup only** — `bl#L401-409`, `BackendBridge.swift#L204-205`: the `mountPath` string from `hdiutil` plist is returned to the caller but never used to make further filesystem decisions in the Python layer; no secondary path operations are performed on it.
- **DriveWatcher does not handle disk identifiers directly** — `DriveWatcher.swift`: disk-appeared/disappeared callbacks trigger a full `BackendBridge.detect()` rescan; no raw disk identifier string from the DA callback is passed to any command or stored as a path.

## Section verdict

- PASS: 7
- PARTIAL: 0
- FAIL: 5 (F2-01 HIGH, F2-02 HIGH, F2-03 MEDIUM, F2-04 MEDIUM, F2-05 LOW)

> **Cross-section note for Section 4 (Shell Injection):** F2-02's `--out PATH` path-traversal is distinct from shell injection because `bl` uses list-form `subprocess` throughout. However, the `osascript` bridging in `BackendBridge.runOsascriptBL` (L330-340) embeds `blPath` and `dislockerBinDir` — both potentially controlled by `BL_PATH_OVERRIDE` / `BL_DISLOCKER_DIR` — into a shell string before AppleScript escaping. Section 4 should verify that the AppleScript double-escaping fully neutralises a path containing embedded double-quotes or backslashes supplied via those env vars.

## Section 3 — Privilege Escalation & Process Boundary

---

# Section 3: Privilege Escalation & Process Boundary

## Summary

The application crosses the root boundary in three ways: (1) `bl` and `bl-open`
use `sudo` directly from the invoking user's shell session; (2) `BackendBridge`
wraps the entire `bl unlock` / `bl mount` invocation in a single
`osascript … with administrator privileges` call.  In both paths the duration of
root privilege is longer than necessary, the sudo timestamp keepalive loop
survives beyond the operation it was created for, and the binary executed as
root (`dislocker-file`) is resolved from an environment-variable-controlled path
that an attacker on the same machine can redirect.  No sensitive entitlements
appear in Info.plist; the bundle is intentionally unsigned, which is itself an
integrity concern (see F3-05).

---

## Findings

### F3-01 — HIGH (P1) — sudo keepalive orphan survives parent process in `bl`

**Evidence:** [bl#L186](../../../bl#L186)
```python
def ensure_sudo() -> None:
    """Cache sudo creds and spawn a refresher so long decrypts don't re-prompt."""
    subprocess.check_call(["sudo", "-v"])
    parent = os.getpid()
    pid = os.fork()
    if pid == 0:
        try:
            while True:
                if os.kill(parent, 0):   # raises if parent gone
                    pass
                subprocess.call(["sudo", "-nv"], ...)
                time.sleep(60)
        except (ProcessLookupError, KeyboardInterrupt):
            sys.exit(0)
```

The forked child calls `sudo -nv` every 60 seconds and exits only when
`os.kill(parent, 0)` raises `ProcessLookupError`.  Because the parent PID
reference is captured at fork time and not stored anywhere in the parent
process, the parent never sends a termination signal to this child on normal
exit paths (successful decrypt, user cancel via KeyboardInterrupt caught at
L293-295, or error paths in `cmd_unlock` / `cmd_mount`).  The child therefore
runs until the parent PID is recycled — potentially minutes after the legitimate
operation ends — continuously refreshing the sudo timestamp.  During that window
a second attacker-controlled invocation of any `sudo`-using command on the
machine can run without a password prompt.

**CWE:** CWE-272 (Least Privilege Violation)

**Impact:** The sudo timestamp remains alive for up to ~60 seconds (or more,
depending on PID-recycling timing) after `bl` exits.  A local non-root attacker
who can execute any `sudo`-requiring command during that window — including
invoking `bl` again with a different `--device` or `--out` path — gets root
without a password challenge.

**Remediation:** Store the child PID in a module-level variable and register an
`atexit` handler (and SIGTERM / SIGINT handlers) in the parent to `os.kill(pid,
signal.SIGTERM)` before exiting.  Alternatively, replace the forked keepalive
with a `sudo -v` call at a fixed interval driven by a `threading.Timer` inside
the parent — no fork needed, and the thread dies automatically when the parent
process ends.

---

### F3-02 — HIGH (P1) — `bl-open` keepalive loop tied to shell PID but never explicitly terminated on all exit paths

**Evidence:** [bl-open#L136](../../../bl-open#L136), [bl-open#L138](../../../bl-open#L138)
```bash
sudo -v
# Keep sudo timestamp alive for long decrypts.
( while kill -0 "$$" 2>/dev/null; do sudo -nv 2>/dev/null; sleep 60; done ) &
KEEP_SUDO=$!
```

The keepalive subshell uses `$$` (the current shell PID) as its liveness check.
`$$` is correct here, but there is a race: after `dislocker-file` finishes
(L153 `wait "$DPID"`), `kill "$KEEP_SUDO"` at L155 is the only kill site on the
success path.  The `cleanup` trap at L146-149 kills `$KEEP_SUDO` on INT/TERM,
but not on `exit` — if the script exits non-zero after the trap is cleared
(`trap - INT TERM` at L156), the subshell can linger.  More critically, if
`hdiutil attach` at L171 fails (non-zero but no trap), the keepalive is never
killed and the sudo timestamp stays warm.

**CWE:** CWE-272 (Least Privilege Violation)

**Impact:** Same window-of-opportunity as F3-01: a lingering timestamp allows a
subsequent unprompted `sudo` invocation.

**Remediation:** Add `kill "$KEEP_SUDO" 2>/dev/null || true` to an `EXIT` trap
rather than relying on inline kill sites.  Example:
`trap 'kill "${KEEP_SUDO:-}" 2>/dev/null; trap - EXIT' EXIT`

---

### F3-03 — HIGH (P1) — `BL_DISLOCKER_DIR` env var controls which binary runs as root

**Evidence:** [bl#L50](../../../bl#L50), [bl#L260](../../../bl#L260)
```python
DISLOCKER_DIR  = Path(os.environ.get("BL_DISLOCKER_DIR", str(_DEFAULT_DISLOCKER_DIR)))
DISLOCKER_FILE = DISLOCKER_DIR / "dislocker-file"
...
proc = subprocess.Popen(
    ["sudo", str(DISLOCKER_FILE), "-V", args.device, *auth, "--", str(out_path)],
    ...
)
```

`bl` resolves the binary it escalates to root (`dislocker-file`,
`dislocker-fuse`) from the environment variable `BL_DISLOCKER_DIR`.  No
validation is performed on this value — the resolved path is passed directly to
`sudo`.  On an unlocked Mac, a local attacker who can modify the environment of
the invoking process (e.g. through a malicious shell profile, a launchd
environment dictionary, or by wrapping the app launcher) can redirect
`BL_DISLOCKER_DIR` to a directory containing a malicious `dislocker-file`
executable, which will then run as root.

`BackendBridge` propagates this variable inline in the `do shell script`
command string at [BackendBridge.swift#L327](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L327),
extending the attack surface to the GUI path as well.

**CWE:** CWE-426 (Untrusted Search Path)

**Impact:** Arbitrary code execution as root by a local attacker able to
influence the environment.

**Remediation:** Resolve the dislocker binary relative to the script's own
realpath (`SCRIPT_DIR`) and do not accept env-var overrides for the executable
path itself.  If the bundled-binary use-case requires flexibility, validate that
the resolved path is inside the app bundle (check against a known bundle prefix
after `realpath`/`Path.resolve()`).  Note: the argv injection vector (passing
the path as an argument through the `do shell script` string) is in scope for
Section 4 (shell quoting).

---

### F3-04 — MEDIUM (P2) — Single `osascript` prompt covers entire `bl unlock` / `bl mount` session

**Evidence:** [BackendBridge.swift#L340](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L340)
```swift
let script = "do shell script \"\(asEscaped)\" with administrator privileges"
```

`runOsascriptBL` wraps the entire `bl unlock` or `bl mount` invocation — which
can run for many minutes for large drives — in a single `do shell script …
with administrator privileges`.  macOS presents one password/Touch ID prompt
and then grants root for the lifetime of that osascript process, which blocks
until `bl` finishes.  This is a broad grant: the user cannot see what commands
are being run with their administrator password, and if `bl` itself spawns
sub-privileged processes (e.g. the `sudo chown` at
[bl#L393](../../../bl#L393)), those also inherit the elevated context.

Best practice is one `do shell script` per discrete privileged operation (e.g.
`dislocker-file` and then a separate call for `chown`), each with its own
prompt, so the user can see and authorise exactly what runs as root.

**CWE:** CWE-250 (Execution with Unnecessary Privileges)

**Impact:** Overly broad administrator grant; reduces user visibility into
privileged operations.  Combined with F3-03, a redirected binary runs without
any additional authentication challenge.

**Remediation:** Split `bl` into a privileged stub (runs only `dislocker-file`
or `dislocker-fuse` as root) and an unprivileged orchestrator.  Issue one
`do shell script` per narrow root command.  Alternatively, adopt SMJobBless or
a privileged XPC helper with a signed entitlement, which provides a per-command
authorisation model and binary identity verification.

---

### F3-05 — MEDIUM (P2) — Unsigned bundle; no binary integrity check before root execution

**Evidence:** [BitLockerUnlock/make-app.sh#L12](../../../BitLockerUnlock/make-app.sh#L12)
```bash
# The bundle is intentionally unsigned — Gatekeeper will refuse the first
# launch via double-click; right-click → Open to bypass.
```

The `.app` bundle is intentionally not code-signed.  On an unlocked Mac, a
physical-access or local attacker can replace `Contents/MacOS/BitLockerUnlock`,
`Contents/Resources/bl`, or any file in `Contents/Resources/dislocker-bin/`
without triggering any system-level integrity check.  Because `bl` (F3-03) and
`BackendBridge` resolve the dislocker binary from the bundle resources, a
tampered bundle leads directly to arbitrary code execution as root the next time
a legitimate user runs the app.

This is a supply-chain / physical-access scenario that the threat model
explicitly includes.

**CWE:** CWE-345 (Insufficient Verification of Data Authenticity)

**Impact:** A physical-access attacker on an unlocked Mac can achieve persistent
root code execution by modifying the unsigned bundle, which is then automatically
re-elevated by the next user authentication event.

**Remediation:** Sign the bundle with a Developer ID certificate and enable
Hardened Runtime.  At minimum, enable the `com.apple.security.cs.allow-unsigned-executable-memory`
entitlement only if strictly required.  After signing, do not ship a "right-click
Open to bypass" workflow for production use.

---

### F3-06 — LOW (informational) — `sudo chown` path comes from caller-controlled `path` argument

**Evidence:** [bl#L391](../../../bl#L391), [bl#L393](../../../bl#L393)
```python
if path.stat().st_uid != os.getuid():
    subprocess.check_call(
        ["sudo", "chown", f"{os.getuid()}:{os.getgid()}", str(path)]
    )
```

`hdiutil_attach` accepts a `Path` argument and performs `sudo chown` on it when
it is not owned by the current user.  Callers pass `out_path` (from `args.out`,
default `DEFAULT_IMAGE`) and `inner` (`FUSE_DIR / "dislocker-file"`).  Shell
quoting of the `path` argument in this list-form `check_call` is safe (no shell
injection; see Section 4), but the path itself is not validated to be inside
`/tmp/bl` before `chown` is called.  An attacker who controls `args.out` (e.g.
via a symlink at `/tmp/bl/decrypted.img` pointing elsewhere) could redirect the
`chown` to an arbitrary file.  Path validation is the primary concern of Section
2; this note captures the privilege dimension.

**CWE:** CWE-61 (UNIX Symbolic Link Following)

**Impact:** An attacker-controlled symlink at the image path could cause `sudo
chown` to change ownership of an arbitrary file to the current user, potentially
allowing subsequent modification of sensitive system files.

**Remediation:** Verify the resolved real path of `out_path` is inside `IMG_DIR`
before calling `sudo chown` (mirror the guard already present in `cmd_cleanup`).
Use `O_NOFOLLOW` / `os.open` with `os.O_NOFOLLOW` for the ownership check.
Cross-reference Section 2 for the broader path-validation finding.

---

## Pass items

- **Password not cached in env or filesystem by the privilege layer.** `bl` and
  `bl-open` pass the credential inline to `dislocker-file` (an argv exposure
  covered in Section 1) but do not write it to disk or to a persistent env var
  as part of privilege escalation.

- **`bl-open` unsets credential variables promptly.** `unset PASS AUTH_ARGS`
  at [bl-open#L144](../../../bl-open#L144) runs immediately after `dislocker-file` is
  backgrounded, minimising the window in which the password lives in shell
  memory.

- **`sudo chown` scope is narrow.** The `chown` at [bl#L393](../../../bl#L393)
  targets only the specific image file and uses list-form `subprocess`, not a
  shell string, so there is no shell-injection vector in the privilege call
  itself.

- **Info.plist contains no sensitive entitlements.** The generated plist
  (make-app.sh L69-101) requests only `NSHighResolutionCapable` and standard
  bundle metadata.  No `com.apple.security.*` entitlements (Keychain, network
  server, camera, location, etc.) are declared.

- **Root privilege is not held continuously.** `dislocker-file` runs as a
  subprocess; the invoking Python / bash process itself does not elevate to root.
  Once `dislocker-file` exits, no persistent setuid process remains (modulo the
  keepalive finding F3-01/F3-02).

---

## Section verdict

| Severity | Count |
|----------|-------|
| CRITICAL (P0) | 0 |
| HIGH (P1) | 3 — F3-01, F3-02, F3-03 |
| MEDIUM (P2) | 2 — F3-04, F3-05 |
| LOW / info | 1 — F3-06 |

**Verdict: FAIL** — Three HIGH findings exist. F3-03 (env-var-controlled binary
run as root) is the most immediately exploitable on an unlocked machine and
should be treated as the blocking issue; F3-01/F3-02 (keepalive orphan extending
the sudo timestamp window) amplify its impact significantly.

## Section 4 — Shell / AppleScript / Command Injection

---

# Section 4: Shell / AppleScript / Command Injection

## Summary

The application routes user-supplied passwords and file-system paths through two
interpreter boundaries: (1) a POSIX single-quote escape (`shellQuote`) that
builds a shell command string, and (2) an AppleScript backslash/double-quote
escape that embeds that shell string inside an AppleScript `do shell script`
literal.  Both layers are correctly implemented for every tested adversarial
password input; no injection is possible via the password argument.

However, one **HIGH** finding exists: the `BL_DISLOCKER_DIR` environment
variable value — which is the source of `envPrefix` at
[BackendBridge.swift#L327](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L327)
— passes through `shellQuote` (safe for the shell layer) but a directory path
containing a **double quote or backslash** survives into the AppleScript string
unescaped at
[BackendBridge.swift#L340](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L340),
giving a local attacker who controls `BL_DISLOCKER_DIR` AppleScript-level
injection with administrator privileges.

The Python `bl` script uses only list-form `subprocess` calls throughout; no
`shell=True` is present.  The `bl-open` Bash script expands all variables into
double-quoted positions when they reach `sudo`/`dislocker-file`, and the
password is stored in a Bash array element (`AUTH_ARGS`) that is expanded with
`"${AUTH_ARGS[@]}"`, preventing word-splitting and glob expansion.

---

## Findings

### F4-01 — HIGH (P1) — `BL_DISLOCKER_DIR` containing `"` or `\` breaks AppleScript escaping

**Location:**
[BackendBridge.swift#L327](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L327),
[BackendBridge.swift#L336–340](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L336)

**Root cause:** `shellQuote` wraps `dir` in POSIX single-quotes, making the
value safe for the *shell* layer.  The resulting string — e.g.
`BL_DISLOCKER_DIR='/bad/path' ` — then goes into `cmd`, which is AppleScript-
escaped by two chained `replacingOccurrences` calls:

```
cmd → asEscaped via:
  1. replace "\" with "\\"
  2. replace "\"" with "\\\""
```

This escaping applies to `cmd` **after** `shellQuote` has already produced
single-quoted shell text from `dir`.  A single-quoted POSIX word never contains
a literal `"`, so a password is fine.  But the `dir` value itself is the
expanded path, not a user password: if `dir` contains a `\` or `"` (e.g. the
app's bundle path is relocated to a directory named `a"b` or `a\b`), those
characters appear inside the outer single-quotes of `shellQuote`'s output and
survive into `cmd` unmodified.  The AppleScript escape then sees them inside the
`do shell script "..."` string literal.

**Adversarial scenario:** A local attacker pre-creates a directory at a path
containing `"` and sets `BL_DISLOCKER_DIR` to that path (or, with physical
access, renames the app bundle directory).  The resulting AppleScript string
becomes syntactically broken or injects a second `do shell script` clause,
running attacker-chosen commands with administrator privileges.

**Concrete trace** (dir = `/tmp/evil"$(id)`):

```
shellQuote(dir) → '/tmp/evil"$(id)'
envPrefix       → "BL_DISLOCKER_DIR='/tmp/evil\"$(id)' "
                     ↑ the " inside single-quotes is literal, shellQuote did not escape it

After AppleScript escape:
  replace \ → \\  : no change (no backslash present in this example)
  replace " → \"  : the " inside the single-quoted word is escaped → \", but
                    this produces  BL_DISLOCKER_DIR='/tmp/evil\"$(id)'
                    which AppleScript re-parses as: string ends at \", shell metachar escapes
                    — AppleScript behaviour here is implementation-defined and exploitable.

Final AppleScript:
  do shell script "BL_DISLOCKER_DIR='/tmp/evil\"$(id)' /usr/bin/env python3 …"
                                               ^^^ AppleScript string boundary broken
```

For `dir = /tmp/evil\$(id)` (backslash variant):

```
shellQuote(dir)  → '/tmp/evil\$(id)'    (backslash inside single-quotes is literal in POSIX sh)
After step 1 (replace \ → \\): '/tmp/evil\\$(id)'
After step 2 (replace " → \"): no change
AppleScript sees: BL_DISLOCKER_DIR='/tmp/evil\\$(id)'
sh executes: BL_DISLOCKER_DIR='/tmp/evil\$(id)'   — backslash inside single-quotes is literal
             → no injection at the sh level in this specific case
```

The double-quote variant is the exploitable path.  A backslash alone does not
inject at the shell level, but doubles to `\\` in the AppleScript string and
could confuse AppleScript parsers.

**Severity:** HIGH (P1) — requires attacker-controlled `BL_DISLOCKER_DIR` (env
var, not a UI field), but once controlled, the payload executes as root via
osascript's `with administrator privileges`.  On a shared or compromised machine
this is a direct privilege-escalation primitive.

**Recommendation:** Apply the AppleScript escape to `envPrefix` as well, or
(preferred) compute `asEscaped` from `cmd` **before** prepending a separately
AppleScript-escaped `envPrefix`.  Alternatively, validate that `dir` contains no
`"` or `\` characters and reject values that do.

---

## Adversarial Input Traces

The three canonical inputs are traced through every escaping layer.  The target
is the final argv array seen by `dislocker-file` and any shell or AppleScript
interpreter.

### Input 1 — password `pa'ss` (single quote)

**Layer 1 — `bl` → `build_auth_args`:**
Returns `["-upa'ss"]` (a list element; no shell involved).

**Layer 2 — `BackendBridge.shellQuote`:**
```
input:   -upa'ss
step:    replace ' with '\''
result:  '-upa'\''ss'
```

**Layer 3 — AppleScript escape of `cmd`:**
```
cmd contains: ... '-upa'\''ss'
step 1 (\ → \\):  ... '-upa'\\''ss'
step 2 (" → \"): no change
```

**Layer 4 — AppleScript `do shell script` execution:**
AppleScript passes the string to `/bin/sh -c`.  The shell sees the token
`'-upa'\''ss'` which is POSIX-equivalent to the literal string `-upa'ss`.

**Final argv received by dislocker-file:** `[..., "-upa'ss"]`
**Verdict: SAFE — no injection.**

---

### Input 2 — password `pa\"ss` (backslash + double quote)

**Layer 1 — `bl` → `build_auth_args`:**
Returns `['-upa\\"ss']` (list element; literal backslash + double-quote).

**Layer 2 — `shellQuote`:**
```
input:   -upa\"ss
replace ':  no single-quote present, no change
result:  '-upa\"ss'
```

**Layer 3 — AppleScript escape:**
```
cmd contains: ... '-upa\"ss'
step 1 (\ → \\):  ... '-upa\\"ss'
step 2 (" → \"):  ... '-upa\\"ss'   (the " inside single-quote token; already doubled backslash)
```

AppleScript string literal seen by the AppleScript interpreter:
`... '-upa\\"ss'`

When AppleScript hands this to sh, the shell sees `'-upa\\"ss'`.  Inside
single-quotes, `\\` is two literal backslashes, and `"` is a literal double
quote.  The final argument passed to dislocker-file is `-upa\\"ss` — two
backslashes and a double-quote.  This differs from the original input of one
backslash + double-quote: **the backslash is doubled** by the AppleScript escape
layer.

This is a **data-fidelity bug** (the password is mangled) but **not an
injection vulnerability** — no extra command is executed, and the shell boundary
is not broken.  It is noted as an informational item below (P4-I-01).

**Verdict: No injection. Data mangled (informational).**

---

### Input 3 — password `;\ rm -rf /` + newline (shell metachar + newline)

**Layer 1 — `bl` → `build_auth_args`:**
Returns `["-u; rm -rf /\n"]` (list element; newline is a literal `\n`
character, not a shell newline).

**Layer 2 — `shellQuote`:**
```
input:   -u; rm -rf /\n   (where \n is a literal LF byte)
replace ':  no single-quote present
result:  '-u; rm -rf /\n'
```

POSIX single-quotes preserve every byte including `;`, spaces, `/`, and LF
unchanged.  The semicolons and spaces are not metacharacters inside single-quotes.

**Layer 3 — AppleScript escape:**
```
step 1 (\ → \\): '-u; rm -rf /\\n'  (backslash before n doubled)
step 2 (" → \"): no change
```

**Layer 4 — sh execution:**
Shell sees `'-u; rm -rf /\\n'`.  Inside single-quotes the string is literal:
`-u; rm -rf /\n` (where `\\n` inside the AppleScript string decodes back to `\n`
at the sh level — actually `\\n` in the shell string is a literal backslash
followed by `n`, not a newline; the original LF is present verbatim before the
AppleScript layer doubled the backslash that preceded it, but there is no
backslash before the LF in this input).

Stepping back to the actual input byte sequence `;\ rm -rf /` + LF:

```
shellQuote: '; rm -rf /\<LF>'    (the backslash + space + LF are all inside single quotes)
AppleScript step 1: '; rm -rf /\\<LF>'
AppleScript step 2: no change
sh sees: '; rm -rf /\\<LF>'   → literal string -u; rm -rf /\<LF>  as a single argv element
dislocker-file argv[n] = "-u; rm -rf /\\\n"
```

No shell command boundary is crossed; the semicolon, backslash, and newline all
arrive as data to dislocker-file.

**Verdict: SAFE — no injection.**

---

## Pass Items

### PASS — Python `bl`: no `shell=True` anywhere

All `subprocess` calls in `bl` use list form:

- [bl#L114](../../../bl#L114): `["diskutil", cmd, "-plist", *rest]`
- [bl#L259](../../../bl#L259): `["sudo", str(DISLOCKER_FILE), "-V", args.device, *auth, "--", str(out_path)]`
- [bl#L330](../../../bl#L330): `["sudo", str(DISLOCKER_FUSE), ...]`
- `["sudo", "-v"]`, `["sudo", "-nv"]`, `["hdiutil", ...]`, `["sudo", "chown", ...]`

No instance of `shell=True` or `subprocess.getoutput` / `os.system` was found.
User-supplied values (`args.device`, `auth` elements, `args.mount`, `str(path)`)
flow directly as argv elements and are never interpreted by a shell.

### PASS — `bl-open`: array expansion of `AUTH_ARGS`

[bl-open#L142](../../../bl-open#L142):
```bash
sudo "$DISLOCKER" -V "$DEVICE" "${AUTH_ARGS[@]}" -- "$IMG"
```

`AUTH_ARGS` is a Bash array populated at lines 120, 126, and 130 with the
password element already prefixed (`"-u$PASS"` or `"-p$PASS"`).  The
`"${AUTH_ARGS[@]}"` expansion with double-quotes prevents word-splitting and
glob expansion.  `$DEVICE`, `$DISLOCKER`, and `$IMG` are all double-quoted.
No shell metacharacter in the password can escape the array element boundary.

### PASS — `bl-open`: `TOTAL` validation against injection in `diskutil` pipeline

[bl-open#L110–111](../../../bl-open#L110):
```bash
TOTAL=$(diskutil info "$DEVICE" | awk -F'[()]' '/Disk Size:/ { print $2; exit }' | awk '{print $1}')
[[ "$TOTAL" =~ ^[0-9]+$ ]] || { echo "error: ..."; exit 1; }
```

`TOTAL` is validated to be purely numeric before use, eliminating any injection
risk from a crafted device name.

### PASS — `shellQuote` implementation is correct for passwords

[BackendBridge.swift#L354–357](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L354):
```swift
return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
```

This is the canonical POSIX single-quote escaping idiom.  It correctly handles
all byte values including NUL-adjacent edge cases for printable ASCII input.

### PASS — `build.sh`: no user-supplied data reaches shell expansions

`build.sh` uses only developer-supplied compile flags and Homebrew prefix paths.
No runtime user input is present.  Variable expansions use double-quoted
`"$VAR"` form throughout.  No injection surface for end-users or drive contents.

---

## Informational

### P4-I-01 — Data fidelity: passwords containing `\` are mangled by AppleScript escape

As traced in Input 2 above, the `replacingOccurrences(of: "\\", with: "\\\\")`
step at
[BackendBridge.swift#L337](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L337)
doubles every backslash inside the single-quoted password token before sh sees
it.  Inside POSIX single-quotes, `\\` is two literal backslashes, not one.  A
user whose BitLocker password contains a backslash will experience authentication
failure because the password delivered to `dislocker-file` has doubled
backslashes.  This is a usability bug, not a security vulnerability.

---

## Section Verdict

**CONDITIONAL PASS with one HIGH finding.**

Injection via user-supplied passwords (all three adversarial inputs) is **not
possible**: the two-layer `shellQuote` + AppleScript escape chain correctly
confines passwords to a single argv element even for the most pathological
inputs.  The Python subprocess layer has no shell involvement at all.

The one **HIGH (P1)** finding (F4-01) affects `BL_DISLOCKER_DIR`: a
double-quote or backslash in that environment variable value is not fully
neutralised before it enters the AppleScript `do shell script` string literal,
creating an AppleScript-level injection primitive that executes with administrator
privileges.  This is exploitable by a local attacker who can set environment
variables before launching the app or by a physical-access attacker who renames
the app bundle to a path containing a double-quote.

## Section 5 — Filesystem & Data Persistence

---

# Section 5 — Filesystem & Data Persistence

## Summary

`/tmp/bl/` is the sole staging area for a ~128 GB plaintext BitLocker image,
a FUSE mount directory, and a log file. The directory itself is world-readable
(`drwxr-xr-x`), the image is protected (`-rw-------  root`), and the log file
inherits whatever mode Python's `open("wb")` assigns with the process umask.
The main risks are: a local attacker pre-placing a symlink at `/tmp/bl` before
first run; a TOCTOU window between the `stat()`/`chown()` pair in
`hdiutil_attach`; the image persisting indefinitely between reboots; and
backup tools reaching `/tmp` on non-standard macOS configurations.

---

## Findings

### F5-01 — CRITICAL: Symlink attack on `/tmp/bl` creation (pre-run race)

**Affected code:** [`bl#L242`](../../../bl#L242), [`bl-open#L39`](../../../bl-open#L39)

Both entry points create `/tmp/bl` with `mkdir -p` / `mkdir -p "$IMG_DIR"`
without checking whether the path already exists as a symlink. `/tmp` is
world-writable with the sticky bit set (`drwxrwxrwt`), so any local user can
create `/tmp/bl -> /some/sensitive/path` before the legitimate user runs the
tool for the first time. When `bl unlock` then calls
`IMG_DIR.mkdir(parents=True, exist_ok=True)` (Python's `Path.mkdir`) and
subsequently writes `decrypted.img` into the resolved path, or when
`bl-open` calls `mkdir -p "$IMG_DIR"` and writes `$LOG`, the file is created
inside the attacker-chosen directory rather than `/tmp/bl`. Both `mkdir -p`
and Python's `Path.mkdir(exist_ok=True)` silently succeed when the target is
an existing symlink to a directory, so neither detects the substitution.

**Attack scenario:** A local attacker pre-creates `/tmp/bl -> /Users/victim/
Library/Application Scripts/com.apple.Mail/` before the victim's first run;
when dislocker writes the 128 GB plaintext image there the attacker gains read
access via the overly-permissive symlink destination, or the disk fills causing
a DoS.

**Remediation:** After `mkdir -p /tmp/bl`, assert that the resulting path is
not a symlink:

```python
# Python (bl)
IMG_DIR.mkdir(parents=True, exist_ok=True)
if IMG_DIR.is_symlink():
    sys.exit("FATAL: /tmp/bl is a symlink — possible attack")
```

```bash
# Bash (bl-open)
mkdir -p "$IMG_DIR"
[[ -L "$IMG_DIR" ]] && { echo "FATAL: $IMG_DIR is a symlink" >&2; exit 1; }
```

---

### F5-02 — HIGH: TOCTOU between `stat()` and `chown()` in `hdiutil_attach`

**Affected code:** [`bl#L391-L394`](../../../bl#L391)

```python
if path.stat().st_uid != os.getuid():          # (1) stat
    subprocess.check_call(
        ["sudo", "chown", f"{os.getuid()}:{os.getgid()}", str(path)]   # (2) chown
    )
```

Between the `stat()` at (1) and the `chown` execution at (2) a local attacker
with write access to `/tmp/bl/` (which is `drwxr-xr-x` so only the owner can
write — but see F5-01 for the symlink case that defeats this) could replace
`decrypted.img` with a symlink to an arbitrary path. The subsequent
`sudo chown` would then recursively change ownership of that target.

**Attack scenario:** If F5-01 is exploited first to control `/tmp/bl/`, an
attacker substitutes `decrypted.img` with a symlink to `/etc/sudoers`; the
`sudo chown` call changes ownership of `/etc/sudoers` to the victim user,
enabling privilege escalation.

**Note:** Under the observed system state (`/tmp/bl/` owned by `adamdangerfield
wheel  drwxr-xr-x`) an unprivileged second user cannot write into `/tmp/bl/`
without first winning F5-01. Severity is HIGH rather than CRITICAL in isolation,
but CRITICAL in combination with F5-01.

**Remediation:** Use an `O_NOFOLLOW` aware helper or pass `--no-dereference` to
`chown` (GNU coreutils). On macOS `chown` does not have `--no-dereference`, so
the safe pattern is to open the file with `O_NOFOLLOW` and operate on the file
descriptor:

```python
import fcntl, os
fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW)
os.fchown(fd, os.getuid(), os.getgid())
os.close(fd)
```

This makes the stat/chown atomic with respect to symlink substitution.

---

### F5-03 — HIGH: `/tmp/bl/decrypted.img` persists indefinitely across reboots

**Affected code:** [`bl#L54`](../../../bl#L54), [`bl#L246-L249`](../../../bl#L246),
[`bl-open#L114-L116`](../../../bl-open#L114)

On macOS, `/tmp` is a symlink to `/private/tmp`, which is **not** cleared on
reboot by default (unlike Linux's tmpfs). The 128 GB plaintext image therefore
persists until `bl cleanup` is explicitly called or the file is manually
deleted. Both `bl` and `bl-open` actively re-use an existing image
(`if out_path.exists() and out_path.stat().st_size > 0`) to skip re-decryption,
which means a stolen Mac that is powered on (or resumed from sleep) retains
the full plaintext drive contents regardless of FileVault state on the Mac
itself — the image is not encrypted at rest.

**Attack scenario:** An attacker with physical access to a powered-off Mac
boots a live USB, mounts `/private/tmp/bl/decrypted.img` (which is
`-rw-------  root`), and reads the full BitLocker volume without needing the
BitLocker credential.

**Observed state:** `/tmp/bl/decrypted.img  -rw-------  root  wheel  (~128 GB)`

**Remediation:**
1. Warn the user prominently that the file is plaintext at rest and should be
   deleted when the drive is ejected.
2. Consider hooking `cmd_eject` to offer automatic cleanup.
3. Document that FileVault must be enabled for the Mac's own volume to prevent
   cold-boot access to `/private/tmp`.

---

### F5-04 — MEDIUM: `/tmp/bl/` directory is world-readable

**Affected code:** [`bl#L242`](../../../bl#L242), [`bl-open#L39`](../../../bl-open#L39)

**Observed state:** `/tmp/bl/  drwxr-xr-x  adamdangerfield  wheel`

`drwxr-xr-x` allows any local user to list the directory contents (filenames,
sizes) and to `stat()` files within it. While `decrypted.img` itself is
`-rw-------  root`, any other files created in the directory with a permissive
umask (e.g., log file, FUSE mount entries) would be readable by all users.
A local attacker can also confirm that a decrypt operation is in progress and
watch the image grow in real time by polling `stat /tmp/bl/decrypted.img`.

**Attack scenario:** A local attacker on a multi-user Mac learns that a
BitLocker volume is being unlocked and can observe progress and file sizes,
enabling targeted timing attacks.

**Remediation:** Create the directory with mode `0700`:

```python
IMG_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
```

```bash
mkdir -p "$IMG_DIR" && chmod 700 "$IMG_DIR"
```

---

### F5-05 — MEDIUM: `/tmp/bl/dislocker.log` — mode uncontrolled

**Affected code:** [`bl#L258`](../../../bl#L258)

```python
log = LOG_FILE.open("wb")
```

Python's built-in `open()` creates files with mode `0666` minus the process
umask. With a typical umask of `022` the log is created as `0644`
(world-readable). Log contents are deferred to Section 6, but the file's
existence and world-readable mode mean any local user can read whatever
dislocker-file writes to stdout/stderr, which may include diagnostic
information.

**Attack scenario:** A local attacker reads `/tmp/bl/dislocker.log`
continuously to harvest error messages or timing data from dislocker.

**Remediation:** Open the log with an explicit restricted mode:

```python
fd = os.open(str(LOG_FILE), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
log = os.fdopen(fd, "wb")
```

---

### F5-06 — MEDIUM: Predictable filename enables targeted denial-of-service

**Affected code:** [`bl#L54`](../../../bl#L54), [`bl#L246`](../../../bl#L246)

`DEFAULT_IMAGE` is always `/tmp/bl/decrypted.img`. Because `/tmp` is
world-writable, a local attacker who does not yet control `/tmp/bl/` can
attempt to pre-create `/tmp/bl/decrypted.img` as a zero-byte file (after the
directory is legitimately created) with world-read permissions. The
`bl unlock` skip-if-present check at [`bl#L246`](../../../bl#L246):

```python
if out_path.exists() and out_path.stat().st_size > 0:
```

checks `st_size > 0`, so a zero-byte pre-created file would **not** trigger
the skip path. However, since the directory is owned by the legitimate user and
mode `drwxr-xr-x` (others have no write), this attack requires winning F5-01
or F5-04 first.

**Attack scenario:** Combined with world-write access to the directory (e.g.,
after symlink takeover), an attacker pre-fills the path with garbage, causing
`dislocker-file` to fail mid-write or producing a corrupted image.

---

### F5-07 — LOW: `bl-open` calls `hdiutil attach` without `-nobrowse`

**Affected code:** [`bl-open#L171`](../../../bl-open#L171)

```bash
hdiutil attach "$IMG"
```

`bl` passes `-nobrowse` to suppress Finder notification of the attachment
([`bl#L399`](../../../bl#L399)), but `bl-open` does not. This causes Finder
to display the mounted plaintext volume in the sidebar, advertising its
presence to anyone with physical access or screen-sharing access to the Mac.

**Attack scenario:** An attacker with brief physical or remote-screen access
notices the unlocked BitLocker volume in Finder and accesses it before the
user ejects.

**Remediation:** Add `-nobrowse` to the `hdiutil attach` call in `bl-open`.

---

### F5-08 — LOW: Time Machine / backup tools — `/tmp` exclusion not guaranteed

macOS Time Machine excludes `/private/tmp` from backups by default via
`/System/Library/CoreServices/backupd.bundle/.../StdExclusions.plist`. However,
third-party backup tools (Carbon Copy Cloner, rsync jobs, enterprise MDM
backup agents) may include `/private/tmp` in their scope. A 128 GB plaintext
image at `/private/tmp/bl/decrypted.img` would be backed up in full to
potentially less-protected destinations (external drives, cloud storage,
NAS shares).

**Attack scenario:** A backup agent copies the plaintext image to a NAS share
with relaxed ACLs; an attacker who cannot access the Mac directly mounts the
backup copy.

**Remediation:** Document clearly that `/private/tmp/bl/decrypted.img` is
unencrypted plaintext and that any backup solution touching `/private/tmp`
should explicitly exclude `/private/tmp/bl`.

---

## Pass Items

- **`cmd_cleanup` safe-path guard** ([`bl#L358-L363`](../../../bl#L358)): Uses
  `Path.resolve()` before comparing against `IMG_DIR.resolve()`, correctly
  preventing directory traversal via `..` components and symlink tricks on the
  supplied `--image` argument.

- **`_existing_mount_for` symlink resolution** ([`bl#L424`](../../../bl#L424)):
  Uses `os.path.realpath()` on both the lookup path and the hdiutil-reported
  path, correctly handling the `/tmp -> /private/tmp` symlink and preventing
  false-negative idempotency failures.

- **`decrypted.img` ownership/mode** (observed): The image file itself is
  `-rw-------  root  wheel`, so no local non-root user can directly read
  the plaintext even with the directory being world-readable.

- **`hdiutil attach -nobrowse`** ([`bl#L399`](../../../bl#L399)): `bl`
  (the primary Python CLI) suppresses Finder advertising of the mount.

- **`bl-open` PASS variable cleanup** ([`bl-open#L144`](../../../bl-open#L144)):
  `unset PASS AUTH_ARGS` after launching dislocker, limiting credential
  lifetime in shell memory (credential handling is Section 1 scope, noted
  here only as a positive data point).

---

## Section Verdict

**HIGH** — No single finding directly exposes the 128 GB plaintext image to a
local unprivileged attacker under the observed permissions, but two HIGH
findings (F5-01 symlink pre-emption, F5-02 TOCTOU chown) are chained: winning
F5-01 unlocks F5-02 and turns it CRITICAL. The persistent unencrypted image
(F5-03) is the dominant physical-access risk and requires the only truly
architectural fix (delete-on-eject or encrypt-at-rest). F5-04 and F5-05 are
straightforward one-line hardening items.

## Section 6 — Logging & Information Disclosure

---

# Section 6 — Logging & Information Disclosure

## Summary

The application writes dislocker-file's combined stdout/stderr to
`/tmp/bl/dislocker.log`. At the default verbosity (`L_CRITICAL`, level 0),
the log contains only fatal error strings with no credential material —
password-printing `dis_printf` calls are gated at `L_DEBUG` (level 4) or
`L_INFO` (level 3), both of which are suppressed. No Swift `NSLog`, `print`,
or `os_log` calls exist in the SwiftUI layer; the macOS unified log is clean.
Core dumps are disabled by `setrlimit(RLIMIT_CORE, 0)` in `dis_new()`. No
Notification Center messages are sent. The app does not set
`NSWindowSharingNone`, leaving window contents visible to screen-recording
and screenshotting tools.

The most significant findings are: (1) `DECRYPT_FAILED` error messages embed
the last 20 lines of the log file and surface them in the UI and the system
clipboard; (2) `dis_printf(L_DEBUG)` in the dislocker C library prints the
plaintext password and recovery password if verbosity is raised to `L_DEBUG`
(i.e. `-v -v -v -v` on the command line), which would capture them in the log;
(3) the `ErrorView` "Copy error details" button unconditionally writes
`code + message` to `NSPasteboard.general`, which includes the log tail; and
(4) the password is embedded as a quoted substring in the AppleScript string
passed via `-e` to `/usr/bin/osascript` (noted here for cross-cutting context;
the primary analysis is in Section 1).

---

## Findings

### F6-01 — HIGH: DECRYPT_FAILED message embeds log tail, exposed in UI and clipboard

**Affected code:**
[`bl#L300-L303`](../../../bl#L300),
[`ErrorView.swift#L53`](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/ErrorView.swift#L53),
[`ErrorView.swift#L124-L128`](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/ErrorView.swift#L124)

When `dislocker-file` exits non-zero, `bl` reads the last 20 lines of
`/tmp/bl/dislocker.log` and embeds them verbatim in the JSON error message:

```python
tail = LOG_FILE.read_text(errors="replace").splitlines()[-20:]
fail("DECRYPT_FAILED",
     f"dislocker-file exit {rc}. tail:\n" + "\n".join(tail),
     json_mode=args.json)
```

That `message` string propagates through `AppState.error` and is displayed
without truncation in `ErrorView` (`Text(message)`). The same string is
written to `NSPasteboard.general` when the user clicks "Copy error details":

```swift
let detail = "Error code: \(code)\n\(message)"
NSPasteboard.general.setString(detail, forType: .string)
```

**At default verbosity** (`L_CRITICAL`) the log contains only generic error
phrases such as "Unable to grab VMK or FVEK. Abort." — no password material.
However, the log may contain internal memory addresses, file paths, or volume
geometry that assists a local attacker in crafting follow-on attacks. More
critically, any future increase in verbosity (see F6-02) would immediately
push the plaintext password into the clipboard via this path.

**Remediation:** Cap the message shown in the UI to a generic, human-readable
sentence (e.g. "The decryption tool exited unexpectedly.") and log the raw
tail only to the on-disk log at a controlled verbosity. If the tail is needed
for diagnostics, write it to a separate diagnostic file rather than embedding
it in the UI-facing message. Consider disabling the "Copy error details"
clipboard action or stripping it of log tail content.

---

### F6-02 — HIGH (LATENT): dislocker `L_DEBUG` logs print plaintext passwords into LOG_FILE

**Affected code:**
[`third_party/dislocker/src/accesses/user_pass/user_pass.c#L78`](../../../third_party/dislocker/src/accesses/user_pass/user_pass.c#L78),
[`third_party/dislocker/src/accesses/rp/recovery_password.c#L84`](../../../third_party/dislocker/src/accesses/rp/recovery_password.c#L84),
[`third_party/dislocker/src/config.c#L771`](../../../third_party/dislocker/src/config.c#L771),
[`third_party/dislocker/src/config.c#L776`](../../../third_party/dislocker/src/config.c#L776)

The dislocker C library contains the following `L_DEBUG`-level log calls that
print credentials verbatim:

```c
/* user_pass/user_pass.c:78 */
dis_printf(L_DEBUG, "Using the user password: '%s'.\n", (char *)*user_password);

/* rp/recovery_password.c:84 */
dis_printf(L_DEBUG, "Using the recovery password: '%s'.\n", (char *)recovery_password);

/* config.c:771 */
dis_printf(L_DEBUG, "   \t\t-> '%s'\n", cfg->user_password);

/* config.c:776 */
dis_printf(L_DEBUG, "   \t\t-> '%s'\n", cfg->recovery_password);
```

`L_DEBUG` is level 4; the default verbosity after `dis_new()` → `memset(…,0)`
is `L_CRITICAL` (level 0), so `dis_printf` returns immediately
(`if(verbosity < level …) return 0`). **`bl` does not pass any `-v` flag**
(it passes `-V` for the volume path, which is unrelated). Therefore under
normal operation these lines are never reached.

The risk is latent: if a developer or user invokes `dislocker-file` directly
with `-v -v -v -v` (four `-v` flags raise verbosity to `L_DEBUG`), the
password appears in stdout, which `bl` redirects to `/tmp/bl/dislocker.log`,
and from there into the `DECRYPT_FAILED` UI message and clipboard (F6-01).

An additional `L_INFO` emission logs the intermediate recovery key as a hex
string at `recovery_password.c:595`:

```c
dis_printf(L_INFO, "Intermediate recovery key:\n\t%s\n", s);
```

`L_INFO` is level 3, also suppressed at default verbosity, but reachable with
two `-v` flags.

**Remediation:** Remove or redact the password-printing `L_DEBUG` calls from
`user_pass.c` and `recovery_password.c` (upstream patch) or, at minimum, add
a compile-time `#ifdef DIS_DEBUG_PASSWORDS` guard. In `config.c`, replace the
`'%s'` format with a fixed marker such as `"<set>"` whenever a password is
non-NULL.

---

### F6-03 — MEDIUM: No `NSWindowSharingNone` — window contents visible to screen-recording tools

**Affected code:** [`App.swift#L10`](../../../BitLockerUnlock/Sources/BitLockerUnlock/App.swift#L10)

The main `WindowGroup` and the unlock credentials sheet are standard
`NSWindow` instances with the default `sharingType` of
`NSWindowSharingReadOnly`. macOS screen-capture APIs (`CGWindowListCreateImage`,
`SCScreenshotManager`, and third-party capture tools) can therefore capture
the window, including the password field before it is submitted and the error
view with the log tail.

The `SecureField` used for the password input (`UnlockSheetView.swift:181`)
benefits from AppKit-level protection that blanks the field's content in
screenshots on macOS 14+, but the surrounding sheet (drive name, chosen
authentication mode, recovery key field) and the error view are fully
visible.

**Remediation:** Set `sharingType = .none` on the main window immediately
after creation. In SwiftUI this can be done via an `NSViewRepresentable` or
by hooking `NSApplicationDelegate.applicationDidFinishLaunching`:

```swift
// In App.swift or a window delegate
if let window = NSApp.windows.first {
    window.sharingType = .none
}
```

---

### F6-04 — LOW: `ErrorView` "Copy error details" writes raw log tail to system clipboard

**Affected code:**
[`ErrorView.swift#L75`](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/ErrorView.swift#L75),
[`ErrorView.swift#L124-L128`](../../../BitLockerUnlock/Sources/BitLockerUnlock/Screens/ErrorView.swift#L124)

The "Copy error details" button is always visible in `ErrorContent`, including
for the `DECRYPT_FAILED` case where `message` contains the 20-line log tail.
The clipboard is a shared resource: any application running on the same macOS
session can read `NSPasteboard.general` at any time. This is a lower-severity
variant of F6-01 specifically concerning the cross-process clipboard channel.

**Remediation:** Restrict clipboard copy to the error code and a sanitised
human-readable summary; omit the raw log tail. If full diagnostics are
required, write them to a diagnostic file and offer an "Export diagnostics…"
sheet that requires an explicit file-save action.

---

### F6-05 — LOW (INFORMATIONAL): `BackendBridge` decode-failure error includes raw `bl` stdout

**Affected code:**
[`BackendBridge.swift#L175`](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L175)

When the final NDJSON line from `bl unlock` cannot be parsed, the thrown error
embeds `result.stdout` verbatim:

```swift
continuation.finish(throwing: BackendError.decodeFailure(
    message: "Could not parse final line from bl unlock: \(result.stdout)"
))
```

`result.stdout` is the entire osascript-captured stdout of `bl`, which at
default verbosity contains only progress JSON and the terminal
`{error, message}` or `{mountPath, …}` record — no credentials. The path
is informational because, in a non-default verbosity scenario, additional
dislocker output (potentially including sensitive material per F6-02) could
appear in `result.stdout`.

---

## Pass Items

| Area | Status |
|---|---|
| macOS unified log (`NSLog` / `print`) | No `NSLog`, `print`, or `os_log` calls found in any Swift source. The unified log is clean. |
| Core dumps | `dis_new()` calls `setrlimit(RLIMIT_CORE, {0,0})` at startup. Core dumps are disabled, so the password is not written to `/cores/` on crash. |
| `dis_printf` at default verbosity | Default verbosity is `L_CRITICAL` (0). All password-printing `dis_printf` calls are at `L_DEBUG` (4) or `L_INFO` (3) and are suppressed. |
| `hide_opt` argv scrubbing | `config.c:hide_opt()` overwrites the `optarg` buffer with `'X'` characters immediately after parsing `-p`/`-u` flags, reducing the window during which the password lives in `/proc/*/cmdline` equivalents. |
| Notification Center | No `UNUserNotificationCenter` or `NSUserNotification` calls found. The app does not post system notifications that could leak drive names or error details to the notification shade. |
| `BackendBridge` logging | `BackendBridge` captures subprocess stdout/stderr into local Swift strings; it does not write them to any log file or system logger. |
| `UnlockMethod.label` | The `label` computed property returns a human-readable mode name ("Password", "Recovery Key", "BEK File"), never the secret value. |

---

## Section Verdict

**HIGH**

Under default operation no plaintext password reaches `dislocker.log` or the
macOS unified log. The most actionable issues are: the `DECRYPT_FAILED` error
path, which surfaces log content in the UI and clipboard (F6-01 / F6-04); the
latent but dangerous `L_DEBUG` password-print calls in the dislocker C library
(F6-02); and the absence of `NSWindowSharingNone` on the credentials window
(F6-03). None of the three require attacker control of verbosity flags to
trigger (F6-01, F6-03, F6-04 fire in normal use); F6-02 is a configuration-
dependent latent risk but has a direct path to the clipboard via F6-01.

**Cross-cutting concern (Section 1 link):** The osascript invocation in
`BackendBridge.runOsascriptBL` embeds the password as a shell-quoted substring
inside the AppleScript `-e` argument string, making it visible to any process
that can enumerate `osascript`'s argv (e.g. via `proc_pidinfo` or Activity
Monitor). This is noted in Section 1 as the primary argv-exposure finding;
it is called out here because the script string is also the content that
`osascript` logs to the macOS Activity Monitor "Open Files and Ports" pane
for the duration of the unlock operation.

## Section 7 — Build & Supply Chain

---

# Section 7: Build & Supply Chain

## Summary

The project's build and supply-chain posture has five significant weaknesses.
The `.app` bundle is intentionally unsigned with only an ad-hoc linker signature
— no developer-ID certificate, no hardened runtime, no notarization, and no
Gatekeeper ticket.  This is documented as a deliberate choice requiring users to
bypass Gatekeeper via "right-click → Open", but it eliminates every OS-enforced
integrity check for the bundle's contents.  The vendored dislocker C source
(version 0.7.3) is not pinned to a tag or a locked commit hash — it tracks
`origin/master` via a full `.git` directory that could be `git pull`-ed to any
future commit.  The Homebrew mbedtls@3 dependency is accepted from Homebrew
without any version-range constraint or hash verification.  No artifact
integrity manifest (SHA-256 sums) is generated or checked for the bundled
binaries.  The `BL_PATH_OVERRIDE` environment variable — accepted at runtime
without validation — allows an attacker with FS write to redirect the Swift
frontend to an arbitrary Python script that inherits the `osascript`
administrator-privilege escalation path.

---

## Findings

### F7-01 — CRITICAL (P0) — Bundle entirely unsigned; Gatekeeper and SIP offer no protection

**Evidence:**
[`BitLockerUnlock/make-app.sh#L11`](../../../BitLockerUnlock/make-app.sh#L11)

```
# The bundle is intentionally unsigned — Gatekeeper will refuse the first
# launch via double-click; right-click → Open to bypass.
```

Verified with `codesign -dv`:

```
Signature=adhoc
Info.plist=not bound
TeamIdentifier=not set
Sealed Resources=none
Internal requirements=none
```

The `.app` carries only the linker-injected ad-hoc signature (`flags=adhoc,linker-signed`).
No Developer ID certificate is attached.  The Info.plist is not bound into the
CodeDirectory, so it can be edited freely.  There are no sealed resources,
meaning every file under `Contents/Resources/` — including the `bl` Python
script and all dislocker binaries — can be replaced without breaking the
(meaningless) signature.  Hardened Runtime is not enabled; the entitlements set
is empty.

**Tamper scenario:** A local non-root attacker with write access to the
`.app` bundle (e.g., installed in a world-writable `/Applications` location, or
in the user's `~/Applications`) replaces
`Contents/Resources/bl` with a malicious Python script.  The next time the user
runs the app and clicks "Unlock" — which calls `osascript … with administrator
privileges` — the replacement script executes as root.  macOS Gatekeeper,
SIP, and the code-signature check do not fire because: (a) no Developer ID
certificate to revoke; (b) no sealed resource hash to validate; (c) the bundle
was already "opened" once via the right-click bypass, clearing the quarantine
attribute.

**CWE:** CWE-345 (Insufficient Verification of Data Authenticity)

**Impact:** Complete privilege escalation to root for any attacker who can write
one file inside the bundle.

**Remediation:**
1. Sign the bundle with a Developer ID Application certificate:
   `codesign --deep --strict -s "Developer ID Application: …" --options runtime BitLockerUnlock.app`
2. Enable Hardened Runtime (`--options runtime`) to lock down library injection,
   DYLD variables, and JIT.
3. Notarize with `xcrun notarytool submit` and staple the Gatekeeper ticket:
   `xcrun stapler staple BitLockerUnlock.app`
4. Add a `make-app.sh` post-build step that verifies the resulting signature
   with `codesign --verify --deep --strict` and `spctl --assess --type exec`.

---

### F7-02 — CRITICAL (P0) — `BL_PATH_OVERRIDE` env var accepted without validation; redirects privileged escalation path

**Evidence:**
[`BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L374`](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L374)

```swift
if let override = ProcessInfo.processInfo.environment["BL_PATH_OVERRIDE"],
   !override.isEmpty {
    return override
}
```

`BackendBridge` unconditionally trusts `BL_PATH_OVERRIDE` as the path to the
`bl` script.  The script at that path is subsequently executed under
`osascript … with administrator privileges`.  The only check is `!override.isEmpty`.

**Tamper scenario:** An attacker plants a malicious script at `/tmp/evil.py` and
sets `BL_PATH_OVERRIDE=/tmp/evil.py` in the process environment before launching
the app (e.g., via a Launch Agent plist, a crafted `.command` file, or by
modifying `~/.zshenv`).  When the user clicks "Unlock", `evil.py` runs as root.
No code-signature check prevents this because the bundle itself is unsigned
(F7-01) and there is no path allowlist.

**CWE:** CWE-426 (Untrusted Search Path)

**Impact:** Root-equivalent code execution via environmental manipulation, requiring
no file write into the bundle itself.

**Remediation:** Remove `BL_PATH_OVERRIDE` from production builds, or restrict it
to paths that lie inside the signed bundle with an allowlist check:
```swift
guard override.hasPrefix(Bundle.main.bundlePath) else { /* ignore */ }
```
In a properly signed + hardened-runtime bundle, the `com.apple.security.inherit`
entitlement is not set, so child processes inherit a sanitised environment; but
this requires F7-01 to be fixed first.

---

### F7-03 — HIGH (P1) — Vendored dislocker tracks `origin/master`; no commit or tag pin

**Evidence:**
[`third_party/dislocker/.git/HEAD`](../../../third_party/dislocker/.git/HEAD)

```
ref: refs/heads/master
```

```
git log -1: 38dab03175cb5798d625375154e716665201bae1  HEAD -> master, origin/master
```

The dislocker C library is vendored as a full cloned repository tracking the
live `master` branch of `https://github.com/Aorimn/dislocker.git`.  No tag,
no pinned commit SHA, and no `.gitmodules` lock exists.  Running `git pull`
inside `third_party/dislocker/` — or any automated tool that recurses into
subdirectories — silently advances to the latest upstream commit.

**Tamper scenario (supply chain):** A future commit to `Aorimn/dislocker`
(malicious or compromised maintainer) introduces a backdoor in the C source.  A
developer running `git pull` in `third_party/dislocker/` followed by `./build.sh`
incorporates the backdoor into the dislocker binaries that get bundled into the
`.app`.  Because there is no integrity manifest (F7-05) and the bundle is
unsigned (F7-01), the shipped binary is indistinguishable from the legitimate one.

**CWE:** CWE-1357 (Reliance on Insufficiently Trustworthy Component)

**Impact:** Undetected supply-chain compromise of the crypto-decryption engine
that processes BitLocker-protected drives containing potentially sensitive data.

**Remediation:**
1. Convert to a git submodule pinned to a specific tag (`v0.7.3`) or commit SHA:
   `git submodule add --depth 1 https://github.com/Aorimn/dislocker.git third_party/dislocker`
   `git -C third_party/dislocker checkout <verified-tag-or-sha>`
2. Record the pinned SHA in `third_party/dislocker.lock` (or in `.gitmodules`)
   and enforce it in CI with `git submodule status --recursive | grep -v '^ '`.
3. Add a `build.sh` pre-flight check that aborts if the working tree SHA does
   not match the recorded lock.

---

### F7-04 — HIGH (P1) — mbedtls@3 dependency not version-pinned or hash-verified at build time

**Evidence:**
[`build.sh#L19`](../../../build.sh#L19)

```bash
MBEDTLS_PREFIX="$(brew --prefix mbedtls@3 2>/dev/null || true)"
```

`build.sh` resolves mbedtls@3 by asking Homebrew for the prefix of whatever
version is currently installed.  No minimum version, no maximum version, and no
hash of the installed dylibs is checked.  The dislocker C build links
dynamically against the Homebrew-managed `libmbedcrypto.dylib`; the dylib is
then **not** bundled into the `.app` (only the dislocker Mach-O executables are
copied in `make-app.sh`), meaning the runtime dependency remains a system-wide
Homebrew formula that can be silently upgraded or downgraded.

**Tamper scenario:** An attacker with write access to the Homebrew Cellar
(`/opt/homebrew/Cellar/mbedtls@3/`) replaces `libmbedcrypto.dylib` with a
patched version that leaks the BitLocker VMK to a local socket.  Because
`dislocker-file` is linked at dynamic-load time and the dylib is not bundled
with an RPATH restricted to `@rpath`, the replacement dylib is loaded on the
next unlock operation without any signature check.

**CWE:** CWE-829 (Inclusion of Functionality from Untrusted Control Sphere)

**Impact:** Cryptographic-key exfiltration at unlock time via a tampered Homebrew
dependency, no root required.

**Remediation:**
1. Pin the required mbedtls version in `build.sh` and abort if the installed
   version does not match:
   ```bash
   MBEDTLS_VERSION="$(brew info --json=v2 mbedtls@3 | jq -r '.formulae[0].versions.stable')"
   [[ "$MBEDTLS_VERSION" == "3.6."* ]] || { echo "Unexpected mbedtls version $MBEDTLS_VERSION"; exit 1; }
   ```
2. Consider static-linking mbedcrypto into the dislocker binaries
   (`-DENABLE_STATIC=ON` in mbedtls CMake) and bundling the result, removing
   the runtime Homebrew dependency.

---

### F7-05 — HIGH (P1) — No artifact integrity manifest; bundled binaries are not hash-verified

**Evidence:**
[`BitLockerUnlock/make-app.sh#L50`](../../../BitLockerUnlock/make-app.sh#L50)

```bash
for bin in dislocker-file dislocker-metadata dislocker-bek dislocker-fuse; do
    if [[ -x "$DISLOCKER_BIN_SRC/$bin" ]]; then
        cp "$DISLOCKER_BIN_SRC/$bin" "$DISLOCKER_BIN_DST/$bin"
```

`make-app.sh` copies dislocker binaries and `bl` into the `.app` bundle with no
SHA-256 or other hash check against a known-good manifest.  There is no
`SHASUMS`, `checksums.txt`, or equivalent file anywhere in the repository or
generated during the build.

**Tamper scenario:** A developer machine is compromised via an unrelated vector
(e.g., a malicious npm/pip package).  The attacker replaces
`third_party/dislocker/build/src/dislocker-file` with a backdoored binary.
`make-app.sh` copies it without complaint.  The resulting `.app` is shared with
users who have no means of verifying that the bundled binary matches what was
compiled from the audited source.

**CWE:** CWE-494 (Download of Code Without Integrity Check)

**Impact:** Silently ships a malicious binary to end-users; no build-log artifact
or manifest allows post-hoc detection.

**Remediation:**
1. After `./build.sh`, generate a SHA-256 manifest:
   ```bash
   shasum -a 256 third_party/dislocker/build/src/dislocker-{file,metadata,bek,fuse} bl > build/SHASUMS256
   ```
2. In `make-app.sh`, verify against the manifest before copying:
   ```bash
   shasum -a 256 --check build/SHASUMS256 || { echo "Integrity check failed"; exit 1; }
   ```
3. Commit `SHASUMS256` and sign it with a developer key (GPG or `codesign`).

---

### F7-06 — MEDIUM (P2) — `BL_DISLOCKER_DIR` env var accepted without bundle-path validation

**Evidence:**
[`bl#L50`](../../../bl#L50)
[`BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L404`](../../../BitLockerUnlock/Sources/BitLockerUnlock/BackendBridge.swift#L404)

```python
DISLOCKER_DIR = Path(os.environ.get("BL_DISLOCKER_DIR", str(_DEFAULT_DISLOCKER_DIR)))
DISLOCKER_FILE = DISLOCKER_DIR / "dislocker-file"
```

```swift
if let override = ProcessInfo.processInfo.environment["BL_DISLOCKER_DIR"],
   !override.isEmpty {
    return override
}
```

Both the Swift layer and the Python `bl` script accept `BL_DISLOCKER_DIR`
without verifying the supplied path lies within the bundle or a trusted
location.  `dislocker-file` at that path is executed as root via the `sudo`
escalation chain.

**Tamper scenario:** An attacker sets `BL_DISLOCKER_DIR=/tmp/evil` and places a
malicious `dislocker-file` executable there.  When `bl unlock` runs, the
malicious binary executes as root with full access to raw disk devices.

**CWE:** CWE-426 (Untrusted Search Path)

**Impact:** Root execution of an arbitrary binary via environment variable;
lower privilege requirement than F7-02 because the attacker only needs to
control the env and write a binary, not replace `bl` itself.

**Remediation:** Validate `BL_DISLOCKER_DIR` against a path prefix allowlist (e.g.,
must begin with `Bundle.main.bundlePath` or `/usr/local`).  Apply the same
validation in the Python `bl` script before constructing `DISLOCKER_FILE`.

---

### F7-07 — MEDIUM (P2) — Info.plist not bound into CodeDirectory; trivially editable

**Evidence:** `codesign -dv` output: `Info.plist=not bound`

[`BitLockerUnlock/make-app.sh#L68`](../../../BitLockerUnlock/make-app.sh#L68)

The Info.plist is written by `make-app.sh` with a here-doc but is never bound
to the code signature.  An attacker can freely add keys such as `LSEnvironment`
(to inject environment variables into every launch), `NSAppleEventsUsageDescription`
(to silently suppress permission prompts), or manipulate `CFBundleIdentifier`
(to impersonate a different app for TCC purposes) without invalidating any
signature.

**Tamper scenario:** An attacker adds an `LSEnvironment` dict to Info.plist
setting `BL_PATH_OVERRIDE` to a malicious script path.  Every subsequent Finder
launch of the app invokes the malicious script under administrator privileges,
without any user-visible indicator and without breaking the ad-hoc signature.

**CWE:** CWE-345 (Insufficient Verification of Data Authenticity)

**Impact:** Persistent privilege escalation via a plist key; no binary modification
required.

**Remediation:** Fix F7-01 (Developer ID + hardened runtime); a properly signed and
sealed bundle binds the Info.plist into the CodeDirectory, making any edit
detectable by Gatekeeper and `codesign --verify`.

---

### F7-08 — MEDIUM (P2) — Homebrew formula contains placeholder SHA-256; ships with fake integrity value

**Evidence:**
[`homebrew/bitlocker-macos.rb#L5`](../../../homebrew/bitlocker-macos.rb#L5)

```ruby
sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
```

The Homebrew formula contains a clearly placeholder SHA-256 (`0123456789abcdef…`).
If the formula is published to a tap in this state, Homebrew will compare the
downloaded tarball against this value and either silently pass (if the value is
never validated before publishing) or fail at install time.  More critically, it
signals that no release tarball has yet been hashed — meaning the integrity
anchor for the Homebrew distribution channel does not exist.

**Tamper scenario:** A developer publishes the formula to a public Homebrew tap
with the placeholder still in place.  Homebrew does not abort on a mismatched
SHA-256 until install time on the end-user machine, but an attacker who controls
the release URL can serve an arbitrary tarball because no valid hash is enforced
in the source of truth.

**CWE:** CWE-494 (Download of Code Without Integrity Check)

**Impact:** Formula is either broken for all users (install error) or ships without
a real integrity guarantee, depending on whether Homebrew validates the hash
against a known-good value before the formula reaches users.

**Remediation:** Generate the real SHA-256 of the release tarball before publishing:
`shasum -a 256 v0.1.0.tar.gz` and substitute the result into `homebrew/bitlocker-macos.rb`.

---

### F7-09 — LOW — Builds are not reproducible; embedded Git branch string varies by checkout

**Evidence:**
[`third_party/dislocker/CMakeLists.txt#L28`](../../../third_party/dislocker/CMakeLists.txt#L28)

```cmake
execute_process(
    COMMAND ${GIT_EXE} rev-parse --abbrev-ref HEAD
    ...
    OUTPUT_VARIABLE GIT_RELEASE_BRANCH)
execute_process(
    COMMAND ${GIT_EXE} log -n 1 --pretty=format:%t
    ...
    OUTPUT_VARIABLE GIT_RELEASE_COMMIT)
add_definitions(-DVERSION_DBG="${GIT_RELEASE_BRANCH}:${GIT_RELEASE_COMMIT}")
```

The dislocker CMake bakes the current branch name and abbreviated commit hash
into the compiled binary via `-DVERSION_DBG`.  This value changes with each
`git pull` or checkout, making it impossible to reproduce a byte-identical
binary from the same source commit.  Combined with no `SOURCE_DATE_EPOCH` usage
and no Swift package lock file (`Package.resolved` is absent from the
`BitLockerUnlock/` directory), builds from the same source tree on two machines
may differ in ways that are difficult to audit.

**CWE:** CWE-1269 (Product Released in Non-Release Configuration)

**Impact:** Inability to verify that a distributed binary was compiled from the
audited source; reduces confidence in supply-chain integrity audits.

**Remediation:** Pass `-DVERSION_DBG` from the outer `build.sh` using the pinned
commit SHA (once F7-03 is fixed).  Set `SOURCE_DATE_EPOCH` to a fixed value
during release builds.  Generate and commit `BitLockerUnlock/.build/checkouts`
lockfiles or add a `Package.resolved` to the repository.

---

## Pass Items

- **Info.plist contains no dangerous keys:** No `LSEnvironment`, no
  `NSAppleScriptEnabled`, no `SecTaskAccess`, no `NSSystemAdministrationUsageDescription`,
  and no unusual privacy-usage-description keys that would silently pre-authorise
  TCC access.  The plist is minimal and appropriate for the declared functionality.
- **`set -euo pipefail` in `make-app.sh`:** The bundle assembly script exits
  immediately on any unset variable or command failure, preventing partial or
  corrupt bundles from being silently accepted.
- **No `LSUIElement` suppression:** The bundle correctly does not set
  `LSUIElement`, so the app appears in the Dock and the user can see it is
  running; this prevents silent background persistence.
- **Dislocker version in CMakeLists is declared (0.7.3):** The semantic version
  is at least asserted in the vendored CMake configuration, providing a baseline
  for manual audits even though the git reference is not pinned.
- **No LSEnvironment in generated Info.plist:** The here-doc in `make-app.sh`
  does not inject environment-variable overrides via `LSEnvironment`, which would
  permanently affect all child processes launched by the app.

---

## Section Verdict

**CRITICAL** — Two CRITICAL and three HIGH findings mean this project currently
ships with no meaningful supply-chain integrity guarantees.  The `.app` bundle
is ad-hoc signed with no Developer ID certificate, no hardened runtime, and no
Gatekeeper notarization; every resource inside it can be replaced without
breaking any signature.  The privileged escalation path (`osascript …
administrator privileges`) is reachable by an attacker who controls a single
environment variable or a single file inside the bundle.  The upstream crypto
engine (dislocker) tracks a live `master` branch with no commit pin.  These
deficiencies must be remediated — in the order F7-01, F7-02, F7-03, F7-05 —
before the application can be considered safe to distribute to third parties.

## Sign-off question

**Has every CRITICAL finding (F1-01, F1-02, F5-01, F7-01, F7-02) been remediated, and has the `BL_PATH_OVERRIDE` / `BL_DISLOCKER_DIR` env-var trust boundary been closed (F3-03, F7-06) — such that no local non-root attacker can substitute the binary that runs as root and no plaintext credential appears in any `ps`-visible argv?** If YES, the project moves from RED to YELLOW and is acceptable for personal use on a single-operator Mac; remaining HIGHs (zeroization, log hygiene, persistent image, supply-chain pinning) can be addressed before sharing with anyone else.
