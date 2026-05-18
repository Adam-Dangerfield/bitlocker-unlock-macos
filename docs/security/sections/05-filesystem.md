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
