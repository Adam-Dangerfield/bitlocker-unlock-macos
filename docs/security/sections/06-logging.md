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
