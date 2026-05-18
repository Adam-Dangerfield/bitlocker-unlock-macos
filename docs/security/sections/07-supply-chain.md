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
