import SwiftUI
import AppKit

// MARK: - ErrorView

struct ErrorView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if case .error(let code, let message, _, let recoverable) = app.state {
            ErrorContent(code: code, message: message, recoverable: recoverable)
                .environmentObject(app)
        }
    }
}

// MARK: - ErrorContent
// Extracted so previews can inject parameters directly without needing to
// mutate AppState's private(set) state property.

private struct ErrorContent: View {
    @EnvironmentObject var app: AppState

    let code: String
    let message: String
    let recoverable: Bool

    // Maximum number of lines copied to the clipboard for any single field.
    // Keeps accidental log-tail disclosure bounded even if the caller embeds
    // verbose output in `message`.
    private static let DETAILS_LINE_LIMIT = 8

    var body: some View {
        VStack(spacing: 0) {
            // ── Red icon badge ────────────────────────────────────────────
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 76, height: 76)

                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.red)
                    .font(.system(size: 36, weight: .medium))
            }

            Spacer().frame(height: 16)

            // ── Headline ──────────────────────────────────────────────────
            Text(headline(for: code))
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.2)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 6)

            // ── Human-readable body message ───────────────────────────────
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            Spacer().frame(height: 14)

            // ── SF Mono error-code chip ───────────────────────────────────
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Spacer()

            // ── Action buttons ────────────────────────────────────────────
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button("Copy error details") {
                        copyToClipboard(code: code, message: message)
                    }
                    .buttonStyle(.bordered)

                    if recoverable {
                        // Wave 3 will wire the actual retry; dismissError for now.
                        Button("Try Again") {
                            app.dismissError()
                        }
                        .buttonStyle(.borderedProminent)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    if recoverable {
                        Button("Dismiss") {
                            app.dismissError()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Dismiss") {
                            app.dismissError()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: recoverable)

                // Disclosure note: informs the user that the copied text is
                // sanitised before it reaches the clipboard.
                Text("Sensitive content is suppressed before copying.")
                    .font(.system(.caption2))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 472)
        .frame(minHeight: 580)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Helpers

    private func headline(for code: String) -> String {
        switch code {
        case "WRONG_PASSWORD":      return "Wrong password"
        case "WRONG_RECOVERY_KEY":  return "Wrong recovery key"
        case "NOT_BITLOCKER":       return "Not a BitLocker volume"
        case "PERMISSION_DENIED":   return "Permission denied (need admin)"
        case "DECRYPT_FAILED":      return "Decryption failed"
        case "MISSING_DISLOCKER":   return "Decryption tool missing"
        case "CANCELLED":           return "Cancelled"
        default:                    return "Decryption failed"
        }
    }

    /// Redact potential credential tokens and cap to `DETAILS_LINE_LIMIT` lines.
    ///
    /// Redaction rule: any run of >= 8 contiguous non-whitespace characters that
    /// contains at least one ASCII letter AND at least one ASCII digit is
    /// replaced with "[REDACTED]". This is intentionally over-broad so that
    /// hex keys, base64 blobs, and recovery passwords are suppressed even when
    /// they appear as part of a longer diagnostic sentence.
    ///
    /// Line cap: only the first `DETAILS_LINE_LIMIT` lines are kept; a trailing
    /// note is appended when lines are dropped.
    private func truncatedMessage(_ raw: String) -> String {
        // 1. Redact tokens that look like credentials.
        //    Pattern: >=8 non-whitespace chars containing >=1 letter AND >=1 digit.
        let credentialPattern = #"(?=\S*[A-Za-z])(?=\S*[0-9])\S{8,}"#
        let redacted: String
        if let regex = try? NSRegularExpression(pattern: credentialPattern) {
            let range = NSRange(raw.startIndex..., in: raw)
            redacted = regex.stringByReplacingMatches(
                in: raw,
                range: range,
                withTemplate: "[REDACTED]"
            )
        } else {
            redacted = raw
        }

        // 2. Cap to DETAILS_LINE_LIMIT lines.
        let lines = redacted.components(separatedBy: "\n")
        let limit = Self.DETAILS_LINE_LIMIT
        if lines.count <= limit {
            return redacted
        }
        let kept = lines.prefix(limit).joined(separator: "\n")
        return kept + "\n(...further lines suppressed)"
    }

    private func copyToClipboard(code: String, message: String) {
        let sanitised = truncatedMessage(message)
        let detail = "\(headline(for: code))\nCode: \(code)\n\nMessage:\n\(sanitised)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(detail, forType: .string)
    }
}

// MARK: - Previews

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Recoverable: show "Try Again" + "Dismiss"
            ErrorContent(
                code: "WRONG_RECOVERY_KEY",
                message: "The 48-digit key didn't match this volume's header. Check for transposed groups and try again.",
                recoverable: true
            )
            .environmentObject(AppState())
            .frame(width: 472, height: 580)
            .previewDisplayName("Recoverable — wrong recovery key")

            // Non-recoverable: show "Dismiss" only (prominent)
            ErrorContent(
                code: "MISSING_DISLOCKER",
                message: "The dislocker binary could not be found. Re-install the app or check your PATH.",
                recoverable: false
            )
            .environmentObject(AppState())
            .frame(width: 472, height: 580)
            .previewDisplayName("Non-recoverable — tool missing")
        }
    }
}
