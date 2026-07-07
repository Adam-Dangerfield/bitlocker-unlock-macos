import Foundation

/// Client for the privileged `bl-helper` daemon (see helper/).
///
/// The daemon runs as root with Full Disk Access (granted once to the stable
/// `bl-helper` stub), which is the access the app's own osascript path can never
/// obtain — macOS gates raw disk reads behind Full Disk Access, and attributes
/// the osascript-escalated command to a helper with no grantable identity.
///
/// Protocol: connect to the Unix socket, send one JSON header line, then (for
/// unlock/mount) the raw secret bytes; the daemon streams `bl <op> --json`
/// NDJSON back. We reuse BackendBridge's decoders to turn those into
/// `UnlockEvent`s, so the existing AppState flow is unchanged.
enum HelperClient {
    static let socketPath = "/usr/local/var/run/bl-helper.sock"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    /// Unlock + mount `device` via the helper (Path B: streaming FUSE mount,
    /// read-write when the volume is exFAT/FAT). Streams `.progress` /
    /// `.mounted` / `.failed` events.
    static func mountStream(device: String, method: UnlockMethod)
        -> AsyncThrowingStream<UnlockEvent, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                var fd: Int32 = -1
                do {
                    fd = try connect()

                    var req: [String: Any] = ["op": "mount", "device": device]
                    var secret = Data()
                    if let bek = method.bekPath {
                        _ = bek
                        throw BackendBridge.BackendError.cliFailure(
                            code: "UNSUPPORTED",
                            message: "BEK-file unlock through the helper isn't wired up yet — use a password or recovery key."
                        )
                    }
                    guard let tag = method.typeTag, let raw = method.rawSecret else {
                        throw BackendBridge.BackendError.spawnFailure(message: "no secret to send")
                    }
                    secret = Data(raw.utf8)
                    req["secretType"] = tag
                    req["secretLen"] = secret.count

                    var header = try JSONSerialization.data(withJSONObject: req)
                    header.append(0x0a)  // newline-terminated header line
                    try writeAll(fd, header)
                    if !secret.isEmpty { try writeAll(fd, secret) }

                    // Read NDJSON, split on newlines, decode each line.
                    var buf = Data()
                    while true {
                        if Task.isCancelled { break }
                        let chunk = try readSome(fd, 4096)
                        if chunk.isEmpty { break }  // EOF
                        buf.append(chunk)
                        while let nl = buf.firstIndex(of: 0x0a) {
                            let lineData = buf.subdata(in: buf.startIndex..<nl)
                            buf.removeSubrange(buf.startIndex...nl)
                            emit(lineData, to: continuation)
                        }
                    }
                    if !buf.isEmpty { emit(buf, to: continuation) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                if fd >= 0 { Darwin.close(fd) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Eject a helper-mounted volume: tears down the hdiutil/ntfs-3g mount AND
    /// the underlying dislocker-fuse layer, as root — so no admin/auth prompt.
    static func eject(mount: String) async throws {
        try await Task.detached {
            let fd = try connect()
            defer { Darwin.close(fd) }
            var header = try JSONSerialization.data(
                withJSONObject: ["op": "eject", "mount": mount])
            header.append(0x0a)
            try writeAll(fd, header)
            var buf = Data()
            while true {
                let chunk = try readSome(fd, 4096)
                if chunk.isEmpty { break }
                buf.append(chunk)
            }
            let text = String(data: buf, encoding: .utf8) ?? ""
            if text.contains("\"error\"") {
                throw BackendBridge.BackendError.cliFailure(
                    code: "eject_failed",
                    message: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }.value
    }

    private static func emit(_ lineData: Data,
                             to continuation: AsyncThrowingStream<UnlockEvent, Error>.Continuation) {
        guard let line = String(data: lineData, encoding: .utf8),
              !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let evt = BackendBridge.decodeFinalLine(line) {
            continuation.yield(evt)
        }
    }

    // MARK: - POSIX Unix-domain socket plumbing

    private static func connect() throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw BackendBridge.BackendError.spawnFailure(message: "socket() failed (errno \(errno))")
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)  // 104 on macOS
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: cap) {
                    _ = strncpy($0, src, cap - 1)
                }
            }
        }
        let rc = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let e = errno
            Darwin.close(fd)
            throw BackendBridge.BackendError.cliFailure(
                code: "HELPER_UNREACHABLE",
                message: "Can't reach the BitLockerUnlock helper (errno \(e)). Install it with helper/install-helper.sh and grant it Full Disk Access."
            )
        }
        return fd
    }

    private static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var off = 0
            while off < data.count {
                let n = Darwin.write(fd, base + off, data.count - off)
                if n <= 0 {
                    throw BackendBridge.BackendError.spawnFailure(message: "socket write failed (errno \(errno))")
                }
                off += n
            }
        }
    }

    private static func readSome(_ fd: Int32, _ cap: Int) throws -> Data {
        var tmp = [UInt8](repeating: 0, count: cap)
        let n = Darwin.read(fd, &tmp, cap)
        if n < 0 {
            throw BackendBridge.BackendError.spawnFailure(message: "socket read failed (errno \(errno))")
        }
        return n > 0 ? Data(tmp[0..<n]) : Data()
    }
}
