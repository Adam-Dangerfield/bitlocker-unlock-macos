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
