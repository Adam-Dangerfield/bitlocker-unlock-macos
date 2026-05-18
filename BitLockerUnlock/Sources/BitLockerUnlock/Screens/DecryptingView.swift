import SwiftUI

// MARK: - Public screen view

/// Active while `app.state == .decrypting(...)`. Renders EmptyView otherwise.
struct DecryptingView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        guard case .decrypting(let drive, let progress, let etaSec, let ratePerSec) = app.state else {
            return AnyView(SwiftUI.EmptyView())
        }
        return AnyView(
            DecryptingContent(
                drive: drive,
                progress: progress,
                etaSec: etaSec,
                ratePerSec: ratePerSec,
                onCancel: { app.cancelUnlock() }
            )
        )
    }
}

// MARK: - Content view (state-value driven; previews instantiate this directly)

private struct DecryptingContent: View {
    let drive: Drive
    let progress: Double       // 0…1
    let etaSec: Int?
    let ratePerSec: Int64
    let onCancel: () -> Void

    @State private var showCancelConfirm = false

    // §6 display-mode logic
    private var isDeterminate: Bool { progress > 0 }
    private var isIndeterminateWithRate: Bool { !isDeterminate && ratePerSec > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Drive card ─────────────────────────────────────────────────
            HStack(spacing: 14) {
                Image(systemName: "externaldrive.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 32, weight: .regular))

                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name.isEmpty ? drive.device : drive.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Text(isDeterminate || isIndeterminateWithRate ? "Decrypting\u{2026}" : "Preparing\u{2026}")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: isDeterminate)
                }

                Spacer()

                if isDeterminate {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(progress * 100))")
                            .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        Text("%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
                    )
            )

            Spacer().frame(height: 22)

            // ── Progress bar / spinner ─────────────────────────────────────
            Group {
                if isDeterminate {
                    // Determinate — no animation wrapper; let value update naturally
                    ProgressView(value: progress)
                        .tint(Color.accentColor)
                } else {
                    // Indeterminate (with or without throughput) — continuous spinner
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                }
            }

            Spacer().frame(height: 10)

            // ── Stats line ─────────────────────────────────────────────────
            // Layout: "X GB of Y GB · ~Nm Ns remaining · Z MB/s"
            // Hidden entirely when fully indeterminate with no rate.
            if isDeterminate || isIndeterminateWithRate {
                HStack(spacing: 0) {
                    // Left: bytes done / total (determinate) or "Calculating…"
                    if isDeterminate {
                        Text(bytesLabel(progress: progress, sizeBytes: drive.sizeBytes))
                            .monospacedDigit()
                    } else {
                        Text("Calculating\u{2026}")
                    }

                    Spacer()

                    // Centre: ETA
                    if let etaSec {
                        Text("~\(etaLabel(etaSec)) remaining")
                            .monospacedDigit()
                    } else if isDeterminate {
                        Text("\u{2014}")   // em dash
                    }

                    // Right: throughput in SF Mono
                    if ratePerSec > 0 {
                        Spacer()
                        Text(rateLabel(ratePerSec))
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            // ── Disclosure footer ──────────────────────────────────────────
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Text("Decrypting to ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("/tmp/bl/decrypted.img")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 16)

            // ── Cancel button ──────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Cancel") {
                    showCancelConfirm = true
                }
                .confirmationDialog(
                    "Cancel decryption?",
                    isPresented: $showCancelConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Cancel Decryption", role: .destructive) {
                        onCancel()
                    }
                    Button("Keep Going", role: .cancel) { }
                } message: {
                    Text("The decryption process will be stopped. You can restart it later.")
                }
            }
        }
        .padding(24)
        .frame(width: 472)
    }

    // MARK: Formatters

    private func bytesLabel(progress: Double, sizeBytes: Int64) -> String {
        let done = Int64(Double(sizeBytes) * progress)
        return "\(formatBytes(done)) of \(formatBytes(sizeBytes))"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return "\(bytes) B"
    }

    private func etaLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "\u{2014}" }
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private func rateLabel(_ bytesPerSec: Int64) -> String {
        let mb = Double(bytesPerSec) / 1_048_576
        return String(format: "%.0f MB/s", mb)
    }
}

// MARK: - Previews
// Previews drive DecryptingContent directly to avoid needing to mutate
// AppState.state (which is private(set)).

private let previewDrive = Drive(
    device: "/dev/disk4s2",
    name: "Kingston DataTraveler",
    sizeBytes: 137_438_953_472,   // 128 GB
    isBitLocker: true,
    isLocked: true,
    mountPoint: "",
    filesystem: "BitLocker",
    bus: "USB"
)

struct DecryptingView_Previews: PreviewProvider {
    static var previews: some View {
        // Requested by spec: progress 0.42, etaSec 720, ratePerSec 80 MB/s
        DecryptingContent(
            drive: previewDrive,
            progress: 0.42,
            etaSec: 720,
            ratePerSec: 80_000_000,
            onCancel: {}
        )
        .frame(width: 472, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .previewDisplayName("Determinate 42%")

        // §6 indeterminate-with-throughput: progress == 0 && ratePerSec > 0
        DecryptingContent(
            drive: previewDrive,
            progress: 0,
            etaSec: nil,
            ratePerSec: 80_000_000,
            onCancel: {}
        )
        .frame(width: 472, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .previewDisplayName("Indeterminate + throughput")

        // Fully indeterminate ("Preparing…")
        DecryptingContent(
            drive: previewDrive,
            progress: 0,
            etaSec: nil,
            ratePerSec: 0,
            onCancel: {}
        )
        .frame(width: 472, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .previewDisplayName("Preparing (fully indeterminate)")
    }
}
