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
