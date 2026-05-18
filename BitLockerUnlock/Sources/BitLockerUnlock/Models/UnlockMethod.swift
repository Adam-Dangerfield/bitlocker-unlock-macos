import Foundation

/// Credential the user supplies to `./bl unlock` / `./bl mount`.
///
/// Maps 1:1 onto the secret-file transport protocol:
///   `--secret-file PATH --secret-type password|recovery` | `--bek FILE`
///
/// SECURITY: `cliArgs` has been removed. Secrets are NEVER placed in argv.
/// BackendBridge writes the secret to a 0600 temp file and passes
/// `--secret-file <path>` instead. For BEK the user's own .BEK path
/// is passed directly as `--bek <path>` (no secret materialised here).
public enum UnlockMethod: Sendable, Hashable {
    case password(String)
    case recovery(String)
    case bek(URL)

    /// The `--secret-type` tag understood by `bl` on the receiver side.
    /// Returns nil for `.bek` because no secret-file is created in that case.
    public var typeTag: String? {
        switch self {
        case .password: return "password"
        case .recovery: return "recovery"
        case .bek:      return nil
        }
    }

    /// The raw secret string for `.password` / `.recovery`.
    /// Returns nil for `.bek` (no in-process secret string; only a file URL).
    /// SECURITY: never log, print, or embed this value in a command string.
    public var rawSecret: String? {
        switch self {
        case .password(let p): return p
        case .recovery(let r): return r
        case .bek:             return nil
        }
    }

    /// For the `.bek` case: the path to the user's pre-existing .BEK file.
    /// Passed as `--bek <path>` on the command line (the file is the user's
    /// own credential, not material we generated).
    public var bekPath: String? {
        guard case .bek(let url) = self else { return nil }
        return url.path
    }

    /// Human label for UI / logs (never includes secret material).
    public var label: String {
        switch self {
        case .password:  return "Password"
        case .recovery:  return "Recovery Key"
        case .bek:       return "BEK File"
        }
    }
}
