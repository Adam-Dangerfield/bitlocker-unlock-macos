# BitLocker on macOS

Open BitLocker-encrypted USB drives on macOS, including BitLocker To Go (exFAT-personality) volumes. CLI + SwiftUI app, both backed by the well-tested [dislocker](https://github.com/Aorimn/dislocker) crypto core.

## Clone

```bash
git clone --recurse-submodules https://github.com/Adam-Dangerfield/bitlocker-unlock-macos.git
cd bitlocker-unlock-macos
```

The `--recurse-submodules` flag is required — `third_party/dislocker` is a submodule pinned to a specific upstream SHA (see [third_party/dislocker.pin.md](third_party/dislocker.pin.md)). If you forgot the flag: `git submodule update --init`.

## Quick start — SwiftUI app

```bash
brew install cmake pkg-config mbedtls@3
./build.sh                                 # builds dislocker
cd BitLockerUnlock
swift build -c release
./make-app.sh                              # produces BitLockerUnlock.app + integrity manifest
open BitLockerUnlock.app                   # right-click → Open the first time (unsigned)
```

Plug in your BitLocker USB and the app auto-detects it via DiskArbitration. Click **Unlock**, enter your password or 48-digit recovery key, approve the macOS admin prompt (Touch ID or password), wait for decrypt, the volume mounts in Finder.

## Quick start — CLI (no app)

```bash
brew install cmake pkg-config mbedtls@3
./build.sh
./bl-open                                  # prompts for secret, decrypts, mounts
```

`./bl-open` auto-detects the drive (defaults to `/dev/disk7s1` if no arg), prompts for your secret, decrypts to `/tmp/bl/decrypted.img`, and mounts via `hdiutil`. Re-running skips the decrypt if the cached image exists.

## Path B — streaming mount (no full image)

Requires [FUSE-T](https://www.fuse-t.org/) (userspace FUSE — no kernel extension):

```bash
brew install --cask fuse-t                 # one-time; needs sudo + System Settings approval
./build.sh                                 # auto-detects FUSE-T, rebuilds with WITH_FUSE=ON
./bl-mount                                 # streams without materialising a 128 GB image
```

Path B is preferable when disk space is tight or you only need a few files. Path A is preferable when you want a portable plaintext image.

## Layout

```
.
├── bl                          # Python control-plane CLI (detect/unlock/mount/eject/cleanup)
├── bl-open                     # User-facing Path A wrapper (bash)
├── bl-mount                    # User-facing Path B wrapper (bash; requires FUSE-T build)
├── build.sh                    # Builds the dislocker submodule with FUSE-T auto-detection
├── CMakeLists.txt              # Drives the in-progress macOS-native rewrite under src/
├── BitLockerUnlock/            # SwiftUI app (SwiftPM project + make-app.sh bundler)
├── MacOS Bit Locker/           # React/JSX design canvas (input to the SwiftUI port)
├── third_party/
│   └── dislocker/              # Git submodule — Aorimn/dislocker @ 38dab03 (see .pin.md)
├── src/                        # Scaffolding for the future macOS-native binary (Milestone 3)
├── docs/
│   └── security/               # Security review + remediation backlog
└── tests/                      # Stub
```

## `bl` — the control-plane CLI

`bl` exposes the entire workflow as subcommands with `--json` output, designed to back the SwiftUI app and any future GUI:

```bash
./bl detect [--json]                      # → [{device, name, sizeBytes, isBitLocker, isLocked, mountPoint, filesystem}]
./bl unlock --device DEV --secret-file PATH --secret-type {password|recovery|bek} [--out PATH] [--json]
                                          # → streams {progress, bytesDone, bytesTotal, ratePerSec, etaSec}
                                          #   then {mountPath, imagePath}
./bl mount  --device DEV --secret-file PATH --secret-type T [--json]   # FUSE-T streaming
./bl eject   --mount PATH [--json]
./bl cleanup --image PATH [--json]        # safeguarded to /tmp/bl only
```

The `--secret-file PATH --secret-type T` protocol routes the BitLocker secret through a 0600 temp file (auto-deleted after read) so it never appears in process argv. Direct `--password` / `--recovery` flags still work for interactive CLI use but emit a deprecation warning — the secret would otherwise be visible via `ps aux`.

## Dependencies

| Package         | Why                                                | Install                              |
| --------------- | -------------------------------------------------- | ------------------------------------ |
| `cmake`         | Build dislocker                                    | `brew install cmake`                 |
| `pkg-config`    | CMake helper                                       | `brew install pkg-config`            |
| `mbedtls@3`     | Crypto. **Must be v3** — v4 is incompatible.       | `brew install mbedtls@3`             |
| `fuse-t` (cask) | Path B only. Userspace FUSE; no kext.              | `brew install --cask fuse-t`         |
| Python 3        | The `bl` control-plane CLI. Ships with macOS.      | —                                    |
| Swift 5.9+      | SwiftUI app. Ships with Xcode / Command Line Tools.| `xcode-select --install`             |

## Bundle integrity

`make-app.sh` writes a SHA-256 manifest at `BitLockerUnlock/BitLockerUnlock.app/Contents/MANIFEST.sha256` and a sibling top-level copy. Run `./BitLockerUnlock/verify-bundle.sh` after distributing the `.app` to confirm no post-build tamper. **The app is intentionally unsigned** — Gatekeeper refuses the first launch via double-click; right-click → Open to bypass. This is the only integrity check available without code signing.

## Security

A full security review lives at [docs/security/SECURITY_REVIEW_2026-05-18.md](docs/security/SECURITY_REVIEW_2026-05-18.md). All CRITICAL and HIGH findings except code-signing have been remediated; the remediation history is preserved in git. The remaining backlog (MEDIUM/LOW) is tracked as open issues. Threat model is single-user macOS; do not use this for distribution to others without a signed build.

### Plaintext image on disk

Path A (`bl-open`, `bl unlock`, the app's default flow) writes a **fully decrypted, unencrypted** copy of the volume to `/private/tmp/bl/decrypted.img`. Treat that file as sensitive as the drive itself:

- **Delete it when done** — `./bl cleanup --image /private/tmp/bl/decrypted.img`, the app's auto-cleanup-on-eject, or plain `rm`.
- **Backups:** macOS Time Machine already excludes `/private/tmp`, but third-party backup tools (Carbon Copy Cloner, `rsync` jobs, MDM backup agents) may not. Explicitly exclude `/private/tmp/bl` from any such tool — otherwise the plaintext image is copied to the backup destination, which may be less protected than the Mac.
- For a **no-plaintext-on-disk** posture, use Path B (FUSE-T streaming) — it never materialises the image.

## License

GPLv2. See [LICENSE](LICENSE).

This project links against [Aorimn/dislocker](https://github.com/Aorimn/dislocker) (GPLv2), which makes the combined work GPLv2. dislocker is unmodified upstream source pinned via submodule to [SHA `38dab03`](third_party/dislocker.pin.md).

## Roadmap

- **Milestone 1 (done):** Vendor dislocker, build for macOS, wrap with `bl-open`.
- **Milestone 2 (done):** `bl` JSON CLI, FUSE-T streaming, SwiftUI app with DiskArbitration auto-detection.
- **Milestone 3 (planned):** Replace the bash/Python wrappers with a single native binary linked directly against `libdislocker.dylib` (scaffolding under [src/](src/)).
- **Milestone 4 (planned):** Code signing + notarization for distribution.
