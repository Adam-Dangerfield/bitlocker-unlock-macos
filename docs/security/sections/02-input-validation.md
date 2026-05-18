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
