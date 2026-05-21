import Foundation
import Darwin

/// Thin Swift wrapper around the `./bl` Python CLI sitting in the project root.
///
/// Privilege model
/// ---------------
/// * `detect`, `eject`, `cleanup` are root-free → run `./bl` directly.
/// * `unlock`, `mount` need root → invoked via `osascript`'s
///   `do shell script ... with administrator privileges`, which yields a
///   native macOS Touch ID / password prompt.
///
/// Why osascript (not SMJobBless / a helper tool)?
///   - Zero setup, no codesigning gymnastics required for this milestone.
///   - The cost: `osascript` blocks until the wrapped command finishes; we
///     cannot tail its stdout for progress. For `unlock` we work around this
///     by polling `/tmp/bl/decrypted.img`'s file size on a 500ms timer to
///     synthesize `UnlockEvent.progress(...)` while the osascript task runs.
///
/// `bl` path resolution
/// --------------------
/// In release builds the bundled `bl` script at `Contents/Resources/bl` is
/// used exclusively. In DEBUG builds only, `BL_PATH_OVERRIDE` can redirect
/// to a development copy. See `Self.locateBL()` and the F7-02 security note
/// therein.
///
/// Secret transport
/// ----------------
/// BitLocker secrets (passwords, recovery keys) are NEVER placed in argv or
/// shell command strings. Instead, BackendBridge writes the secret to a
/// temporary file (mode 0600, O_EXCL) and passes `--secret-file <path>
/// --secret-type <tag>` to `bl`. The temp file is deleted in a `defer` block
/// after `osascript` returns (bl also deletes it — defence in depth).
public final class BackendBridge: @unchecked Sendable {

    public static let shared = BackendBridge()

    // MARK: Init / config -----------------------------------------------------

    /// Absolute path to the `bl` Python script.
    public let blPath: String

    /// Absolute path to the directory containing dislocker-file, libdislocker.dylib,
    /// etc. When the app is bundled, this points at `…/Contents/Resources/dislocker-bin`
    /// and is passed to `bl` via the `BL_DISLOCKER_DIR` env var. `nil` means the
    /// Python side's default path lookup applies (dev/source-tree usage).
    public let dislockerBinDir: String?

    /// Where `bl unlock` writes its decrypted image (also used for progress
    /// polling). Matches the Python side's `DEFAULT_IMAGE`.
    public let defaultImagePath: String = "/tmp/bl/decrypted.img"

    public init(blPath: String? = nil, dislockerBinDir: String? = nil) {
        self.blPath = blPath ?? Self.locateBL()
        self.dislockerBinDir = dislockerBinDir ?? Self.locateDislockerBinDir()
    }

    // MARK: Public API --------------------------------------------------------

    /// `./bl detect --json` — no root required.
    public func detect() async throws -> [Drive] {
        let result = try await runProcess(
            executable: "/usr/bin/env",
            args: ["python3", blPath, "detect", "--json"],
            extraEnv: blEnv()
        )
        guard result.exitCode == 0 else {
            throw BackendError.cliFailure(
                code: "detect_failed",
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        let data = Data(result.stdout.utf8)
        do {
            return try JSONDecoder().decode([Drive].self, from: data)
        } catch {
            throw BackendError.decodeFailure(
                message: "Could not decode `bl detect` JSON: \(error.localizedDescription)"
            )
        }
    }

    /// `./bl unlock --device DEV ... --json`
    ///
    /// Streams `UnlockEvent` values. `bl unlock` runs UNPRIVILEGED (F3-04) and
    /// itself elevates only its `_priv-decrypt` helper for the one root step
    /// (dislocker reading the raw device). We capture bl's stdout as one blob
    /// and poll the output image every 500ms to emit `.progress` events.
    ///
    /// SECURITY (F1-02): The secret is written to a 0600 temp file and passed
    /// via `--secret-file`; it is never placed in argv or a shell command string.
    public func unlock(
        device: String,
        method: UnlockMethod
    ) -> AsyncThrowingStream<UnlockEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [self] in
                let imagePath = self.defaultImagePath

                // Capture starting size so the poller doesn't think a stale
                // image is fresh progress.
                let startSize = self.fileSize(at: imagePath) ?? 0

                // Write the secret to a temp file (0600, O_EXCL) before
                // spawning osascript. The file URL is passed to bl, not the
                // secret bytes.
                let secretFileResult = Self.writeSecretFile(for: method)
                let secretFileURL: URL?
                let secretArgs: [String]
                switch secretFileResult {
                case .bek(let bekPath):
                    // BEK: pass the user's .BEK file path directly; no temp file.
                    secretFileURL = nil
                    secretArgs = ["--bek", bekPath]
                case .tempFile(let url, let tag):
                    secretFileURL = url
                    secretArgs = ["--secret-file", url.path, "--secret-type", tag]
                case .failure(let msg):
                    continuation.finish(throwing: BackendError.spawnFailure(message: msg))
                    return
                }

                // Ensure the temp file is deleted after osascript returns,
                // regardless of success or failure.
                defer {
                    if let url = secretFileURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                }

                // F3-04: run `bl unlock` UNPRIVILEGED in parallel with the
                // progress poller. bl is now an orchestrator that internally
                // elevates only its `_priv-decrypt` helper (one osascript admin
                // prompt) for the dislocker step. BL_ELEVATE pins bl to the GUI
                // auth dialog rather than a (here unanswerable) terminal sudo.
                let runTask = Task.detached { () -> (exit: Int32, stdout: String, stderr: String) in
                    var env = self.blEnv()
                    env["BL_ELEVATE"] = "osascript"
                    do {
                        let r = try await self.runProcess(
                            executable: "/usr/bin/env",
                            args: ["python3", self.blPath, "unlock", "--device", device]
                                + secretArgs + ["--json"],
                            extraEnv: env
                        )
                        return (r.exitCode, r.stdout, r.stderr)
                    } catch {
                        return (-1, "", "spawn error: \(error.localizedDescription)")
                    }
                }

                // Progress poller. Emits .progress periodically until the
                // privileged task completes.
                let pollTask = Task.detached {
                    var lastSize: Int64 = startSize
                    let pollStart = Date()
                    var lastSampleAt = pollStart
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if Task.isCancelled { break }
                        guard let size = self.fileSize(at: imagePath) else { continue }
                        let now = Date()
                        let dt = max(now.timeIntervalSince(lastSampleAt), 0.001)
                        let delta = max(size - lastSize, 0)
                        let rate = Int64(Double(delta) / dt)
                        lastSize = size
                        lastSampleAt = now

                        // We don't know totalBytes from the poller. Report
                        // bytesDone with bytesTotal=0 and progress=0; the
                        // final mounted event ends the stream. UI may treat
                        // bytesTotal==0 as indeterminate.
                        continuation.yield(.progress(
                            progress: 0,
                            bytesDone: size,
                            bytesTotal: 0,
                            ratePerSec: rate,
                            etaSec: nil
                        ))
                    }
                }

                // Wait for the privileged task to finish, then stop polling.
                let result = await runTask.value
                pollTask.cancel()

                // Parse the *last* JSON line out of stdout. `osascript -e ...`
                // returns the underlying program's stdout verbatim, but with
                // CRs in lieu of LFs in some macOS versions — normalise.
                let normalised = result.stdout.replacingOccurrences(of: "\r", with: "\n")
                let lines = normalised
                    .split(whereSeparator: { $0 == "\n" })
                    .map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                // Forward any intermediate progress NDJSON lines we did get
                // (we may catch a few in human-mode fallbacks).
                for line in lines.dropLast() {
                    if let evt = Self.decodeStreamLine(line) {
                        continuation.yield(evt)
                    }
                }

                if result.exit != 0 && lines.isEmpty {
                    continuation.finish(throwing: BackendError.cliFailure(
                        code: "unlock_failed",
                        message: result.stderr.isEmpty
                            ? "osascript exited \(result.exit)"
                            : result.stderr
                    ))
                    return
                }

                // Decode the terminal line: either {mountPath,imagePath} or {error,message}.
                if let last = lines.last, let finalEvent = Self.decodeFinalLine(last) {
                    switch finalEvent {
                    case .mounted, .failed:
                        continuation.yield(finalEvent)
                        continuation.finish()
                    case .progress:
                        continuation.finish(throwing: BackendError.decodeFailure(
                            message: "bl unlock ended on a progress line; expected terminal event"
                        ))
                    }
                } else {
                    continuation.finish(throwing: BackendError.decodeFailure(
                        message: "Could not parse final line from bl unlock: \(result.stdout)"
                    ))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// `./bl mount --device DEV ... --json` — root required, returns mountPath.
    ///
    /// SECURITY (F1-02): The secret is written to a 0600 temp file and passed
    /// via `--secret-file`; it is never placed in argv or the shell command string.
    public func mount(device: String, method: UnlockMethod) async throws -> String {
        // Write the secret to a temp file (0600, O_EXCL) before spawning osascript.
        let secretFileResult = Self.writeSecretFile(for: method)
        let secretFileURL: URL?
        let secretArgs: [String]
        switch secretFileResult {
        case .bek(let bekPath):
            secretFileURL = nil
            secretArgs = ["--bek", bekPath]
        case .tempFile(let url, let tag):
            secretFileURL = url
            secretArgs = ["--secret-file", url.path, "--secret-type", tag]
        case .failure(let msg):
            throw BackendError.spawnFailure(message: msg)
        }

        defer {
            if let url = secretFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let result = await runOsascriptBL(
            subcommand: "mount",
            extraArgs: ["--device", device] + secretArgs + ["--json"]
        )
        guard result.exit == 0 else {
            throw BackendError.cliFailure(
                code: "mount_failed",
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).last else {
            throw BackendError.decodeFailure(message: "Empty mount output")
        }
        let data = Data(String(last).utf8)
        if let payload = try? JSONDecoder().decode(MountPayload.self, from: data),
           let path = payload.mountPath {
            return path
        }
        if let err = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            throw BackendError.cliFailure(code: err.error, message: err.message)
        }
        throw BackendError.decodeFailure(message: "Could not parse mount output: \(trimmed)")
    }

    /// `./bl eject --mount PATH --json` — no root required.
    public func eject(mountPath: String) async throws {
        let result = try await runProcess(
            executable: "/usr/bin/env",
            args: ["python3", blPath, "eject", "--mount", mountPath, "--json"],
            extraEnv: blEnv()
        )
        guard result.exitCode == 0 else {
            throw BackendError.cliFailure(
                code: "eject_failed",
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
    }

    /// `./bl cleanup --image PATH --json` — no root required.
    public func cleanup(imagePath: String) async throws {
        let result = try await runProcess(
            executable: "/usr/bin/env",
            args: ["python3", blPath, "cleanup", "--image", imagePath, "--json"],
            extraEnv: blEnv()
        )
        guard result.exitCode == 0 else {
            throw BackendError.cliFailure(
                code: "cleanup_failed",
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
    }

    // MARK: Errors ------------------------------------------------------------

    public enum BackendError: Error, LocalizedError {
        case cliFailure(code: String, message: String)
        case decodeFailure(message: String)
        case spawnFailure(message: String)

        public var errorDescription: String? {
            switch self {
            case .cliFailure(let code, let message):
                return "\(code): \(message)"
            case .decodeFailure(let message):
                return "Could not parse bl output: \(message)"
            case .spawnFailure(let message):
                return "Could not launch process: \(message)"
            }
        }
    }

    // MARK: Internals ---------------------------------------------------------

    /// Result of a non-privileged child process run.
    private struct RunResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Run a process directly (no osascript). Captures stdout/stderr.
    private func runProcess(
        executable: String,
        args: [String],
        extraEnv: [String: String] = [:]
    ) async throws -> RunResult {
        try await withCheckedThrowingContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args
            if !extraEnv.isEmpty {
                var env = ProcessInfo.processInfo.environment
                for (k, v) in extraEnv { env[k] = v }
                proc.environment = env
            }
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError  = errPipe

            proc.terminationHandler = { p in
                let out = String(data: (try? outPipe.fileHandleForReading.readToEnd()) ?? Data(),
                                 encoding: .utf8) ?? ""
                let err = String(data: (try? errPipe.fileHandleForReading.readToEnd()) ?? Data(),
                                 encoding: .utf8) ?? ""
                continuation.resume(returning: RunResult(
                    exitCode: p.terminationStatus,
                    stdout: out,
                    stderr: err
                ))
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: BackendError.spawnFailure(
                    message: error.localizedDescription
                ))
            }
        }
    }

    /// Builds and runs an osascript invocation of `./bl <subcommand> <args...>`.
    /// Returns the inner program's stdout/stderr as captured by osascript.
    ///
    /// SECURITY (F1-02, F4-01):
    ///   - `extraArgs` must NOT contain raw secret material; secrets travel via
    ///     --secret-file (a temp-file path). The caller (unlock/mount) is
    ///     responsible for ensuring this.
    ///   - BL_DISLOCKER_DIR is validated against a character allowlist before
    ///     being embedded in the shell command string. Any value containing
    ///     shell/AppleScript metacharacters (', ", \, newline, NUL) is rejected
    ///     and the env var is omitted, falling back to bl's default path lookup.
    private func runOsascriptBL(
        subcommand: String,
        extraArgs: [String]
    ) async -> (exit: Int32, stdout: String, stderr: String) {
        // Embed BL_DISLOCKER_DIR as an inline env assignment because osascript's
        // `do shell script` doesn't expose Swift's process environment.
        // SECURITY (F4-01): Reject dir values that contain characters that
        // cannot be safely embedded in a shell+AppleScript string, even after
        // single-quoting. A double-quote inside a single-quoted POSIX word still
        // survives as a literal " into the AppleScript `do shell script "..."`,
        // breaking the AppleScript string boundary. Belt-and-braces: reject any
        // of the five problematic chars outright rather than trying to escape them.
        var envPrefix = ""
        if let dir = dislockerBinDir {
            if Self.isSafeForShellEmbed(dir) {
                envPrefix = "BL_DISLOCKER_DIR=\(Self.shellQuote(dir)) "
            } else {
                NSLog("[BackendBridge] BL_DISLOCKER_DIR contains unsafe characters — " +
                      "omitting env var and falling back to bl default path lookup")
            }
        }

        let cmd = envPrefix + (["/usr/bin/env", "python3", blPath, subcommand] + extraArgs)
            .map(Self.shellQuote)
            .joined(separator: " ")

        // osascript escaping: backslashes and double quotes inside AppleScript
        // string literals must be doubled-up.
        let asEscaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(asEscaped)\" with administrator privileges"

        do {
            let result = try await runProcess(
                executable: "/usr/bin/osascript",
                args: ["-e", script]
            )
            return (result.exitCode, result.stdout, result.stderr)
        } catch {
            return (-1, "", "spawn error: \(error.localizedDescription)")
        }
    }

    /// POSIX single-quote a shell argument.
    private static func shellQuote(_ s: String) -> String {
        // Wrap in single quotes, escaping any embedded single quotes.
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Returns true iff `s` contains none of the characters that cannot be
    /// safely embedded in a shell command string that is subsequently wrapped
    /// in an AppleScript `do shell script "..."` literal.
    ///
    /// SECURITY (F4-01): A single-quote (`'`) terminates the POSIX single-quoted
    /// word. A double-quote (`"`) breaks the AppleScript string boundary even
    /// after single-quoting (the `"` literal survives into the AppleScript layer).
    /// A backslash (`\`) can confuse the AppleScript escape step. Newline and NUL
    /// can truncate the shell command or AppleScript string.
    private static func isSafeForShellEmbed(_ s: String) -> Bool {
        let forbidden: [Character] = ["'", "\"", "\\", "\n", "\r", "\0"]
        return !s.contains(where: { forbidden.contains($0) })
    }

    // MARK: Secret file transport ------------------------------------------------

    /// Result of `writeSecretFile(for:)`.
    private enum SecretFileResult {
        /// A temp file was created at `url` with the secret encoded as UTF-8.
        /// `tag` is the `--secret-type` value ("password" or "recovery").
        case tempFile(url: URL, tag: String)
        /// BEK case — the user's own .BEK file path; no temp file created.
        case bek(path: String)
        /// Failed to create or write the temp file.
        case failure(message: String)
    }

    /// Write the BitLocker secret to a temporary file with mode 0600 (O_EXCL).
    ///
    /// SECURITY (F1-02): This is the sole mechanism by which secrets leave the
    /// Swift process and reach `bl`. The secret is NEVER placed in argv, shell
    /// command strings, environment variables, or AppleScript strings.
    ///
    /// Protocol used by Agent P (bl Python receiver):
    ///   - File name: `bl-secret-<UUID>` in NSTemporaryDirectory().
    ///   - Open flags: O_WRONLY | O_CREAT | O_EXCL (no TOCTOU race).
    ///   - Mode: 0o600 (owner read/write only, set atomically via open(2)).
    ///   - Content: UTF-8 bytes of the secret, no trailing newline.
    ///   - bl reads the file, then deletes it. BackendBridge also deletes it
    ///     in a defer block after osascript returns (defence in depth).
    private static func writeSecretFile(for method: UnlockMethod) -> SecretFileResult {
        // BEK: the user's .BEK file is the credential; no temp file needed.
        if let bekPath = method.bekPath {
            return .bek(path: bekPath)
        }

        guard let tag = method.typeTag, let secret = method.rawSecret else {
            return .failure(message: "UnlockMethod has no secret (unexpected case)")
        }

        let tmpDir = NSTemporaryDirectory()
        let fileName = "bl-secret-\(UUID().uuidString)"
        let url = URL(fileURLWithPath: tmpDir).appendingPathComponent(fileName)
        let path = url.path

        // Open with O_EXCL so we fail (rather than silently truncate) if the
        // file somehow already exists — prevents TOCTOU attacks on /tmp.
        let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            return .failure(message: "Could not create secret temp file at \(path): errno \(errno)")
        }

        // Write secret bytes (UTF-8, no trailing newline).
        var writeError: String? = nil
        if let data = secret.data(using: .utf8) {
            let written = data.withUnsafeBytes { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return Darwin.write(fd, base, ptr.count)
            }
            if written != data.count {
                writeError = "Short write to secret temp file: wrote \(written)/\(data.count)"
            }
        } else {
            writeError = "Could not UTF-8 encode secret"
        }

        Darwin.close(fd)

        if let err = writeError {
            try? FileManager.default.removeItem(at: url)
            return .failure(message: err)
        }

        return .tempFile(url: url, tag: tag)
    }

    /// `stat -f %z PATH` equivalent via FileManager.
    private func fileSize(at path: String) -> Int64? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value
    }

    /// Locate the `bl` script. Resolution order:
    ///   1. (DEBUG only) BL_PATH_OVERRIDE env var.
    ///   2. Bundled inside the .app at `Contents/Resources/bl` (production path —
    ///      mandatory because macOS TCC blocks reading scripts elsewhere under
    ///      ~/Documents even when escalated to root via osascript).
    ///   3. Walk up from the executable URL looking for a `bl` sibling (dev path
    ///      for `swift run` from the package dir).
    ///   4. Hard-coded dev path inside this repo (last resort).
    ///
    /// SECURITY (F7-02): BL_PATH_OVERRIDE is gated to DEBUG builds only.
    ///   In release builds this env var is completely ignored. A local attacker
    ///   who can set environment variables before the app launches would otherwise
    ///   be able to redirect the privileged `osascript … with administrator
    ///   privileges` invocation to an arbitrary script, achieving root code
    ///   execution without modifying any file inside the bundle.
    private static func locateBL() -> String {
        #if DEBUG
        // Development override — not available in release builds (see F7-02).
        if let override = ProcessInfo.processInfo.environment["BL_PATH_OVERRIDE"],
           !override.isEmpty {
            return override
        }
        #endif

        // Bundled inside .app
        if let bundled = Bundle.main.url(forResource: "bl", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }

        // Walk up from the executable (dev).
        var url = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = url.appendingPathComponent("bl")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
            url.deleteLastPathComponent()
        }

        // Last resort — the known dev location.
        return "/Users/adamdangerfield/Documents/VS Code Projects/Dislocker/bl"
    }

    /// Locate the dislocker binary dir. Resolution order:
    ///   1. BL_DISLOCKER_DIR env var — validated (see security note below).
    ///   2. Bundled at `Contents/Resources/dislocker-bin`.
    ///   3. `nil` — let the Python side use its default search.
    ///
    /// SECURITY (F3-03, F7-06): BL_DISLOCKER_DIR is validated before use.
    ///   The resolved real path must lie inside Bundle.main.bundleURL, and the
    ///   raw string must not contain shell/AppleScript metacharacters. On
    ///   rejection the env var is silently ignored and the bundled path is used.
    ///   Threat: a local attacker who controls this env var can redirect
    ///   `dislocker-file` (run as root) to a malicious binary. Restricting to
    ///   the bundle prevents this for any attacker who cannot also write files
    ///   inside the bundle.
    private static func locateDislockerBinDir() -> String? {
        if let override = ProcessInfo.processInfo.environment["BL_DISLOCKER_DIR"],
           !override.isEmpty {
            // Reject values containing shell / AppleScript metacharacters
            // (belt-and-braces against F4-01 / F3-03).
            guard isSafeForShellEmbed(override) else {
                NSLog("[BackendBridge] BL_DISLOCKER_DIR rejected: contains unsafe characters")
                // Fall through to bundled path.
                return locateDislockerBinDirBundled()
            }

            // Reject values that resolve outside the app bundle (F3-03 / F7-06).
            let overrideURL = URL(fileURLWithPath: override)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let bundleURL = Bundle.main.bundleURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let bundlePath = bundleURL.path
            guard overrideURL.path.hasPrefix(bundlePath + "/") ||
                  overrideURL.path == bundlePath else {
                NSLog("[BackendBridge] BL_DISLOCKER_DIR rejected: resolved path is outside " +
                      "the app bundle (override=%@, bundle=%@)", overrideURL.path, bundlePath)
                // Fall through to bundled path.
                return locateDislockerBinDirBundled()
            }

            return override
        }
        return locateDislockerBinDirBundled()
    }

    /// Returns the bundled dislocker-bin dir, or nil to let bl use its default.
    private static func locateDislockerBinDirBundled() -> String? {
        if let bundleRes = Bundle.main.resourceURL {
            let candidate = bundleRes.appendingPathComponent("dislocker-bin")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
               isDir.boolValue {
                return candidate.path
            }
        }
        return nil
    }

    /// Build the env-var overlay we pass to every `bl` invocation.
    private func blEnv() -> [String: String] {
        var env: [String: String] = [:]
        if let dir = dislockerBinDir {
            env["BL_DISLOCKER_DIR"] = dir
        }
        return env
    }

    // MARK: NDJSON decoding ---------------------------------------------------

    private struct ProgressPayload: Decodable {
        let progress: Double?
        let bytesDone: Int64?
        let bytesTotal: Int64?
        let ratePerSec: Int64?
        let etaSec: Int?
    }
    private struct MountPayload: Decodable {
        let mountPath: String?
        let imagePath: String?
    }
    private struct ErrorPayload: Decodable {
        let error: String
        let message: String
    }

    /// Decode a non-terminal NDJSON line (a progress update).
    static func decodeStreamLine(_ line: String) -> UnlockEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        if let p = try? JSONDecoder().decode(ProgressPayload.self, from: data),
           p.bytesDone != nil || p.progress != nil {
            return .progress(
                progress: p.progress ?? 0,
                bytesDone: p.bytesDone ?? 0,
                bytesTotal: p.bytesTotal ?? 0,
                ratePerSec: p.ratePerSec ?? 0,
                etaSec: p.etaSec
            )
        }
        return nil
    }

    /// Decode the final NDJSON line (mounted or failed).
    static func decodeFinalLine(_ line: String) -> UnlockEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        if let m = try? JSONDecoder().decode(MountPayload.self, from: data),
           let mountPath = m.mountPath {
            return .mounted(mountPath: mountPath, imagePath: m.imagePath)
        }
        if let e = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            return .failed(code: e.error, message: e.message)
        }
        // Tolerate the case where the final line is itself a progress line.
        return decodeStreamLine(line)
    }
}
