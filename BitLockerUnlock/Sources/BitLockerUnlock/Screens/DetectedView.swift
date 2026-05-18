import SwiftUI

// MARK: - Helpers

private extension Int64 {
    /// Converts a byte count to a human-readable string, e.g. "128.3 GB".
    var humanisedBytes: String {
        let value = Double(self)
        let units: [(divisor: Double, suffix: String)] = [
            (1_000_000_000_000, "TB"),
            (1_000_000_000,     "GB"),
            (1_000_000,         "MB"),
            (1_000,             "KB"),
        ]
        for (divisor, suffix) in units {
            if value >= divisor {
                let rounded = value / divisor
                // One decimal place, but drop trailing ".0"
                let formatted = rounded.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f %@", rounded, suffix)
                    : String(format: "%.1f %@", rounded, suffix)
                return formatted
            }
        }
        return "\(self) B"
    }
}

// MARK: - Drive card

private struct DriveCard: View {
    let drive: Drive
    let onUnlock: () -> Void

    var body: some View {
        Button(action: onUnlock) {
            HStack(spacing: 16) {
                // Drive icon
                Image(systemName: "externaldrive.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 32, weight: .light))
                    .frame(width: 40)

                // Drive info
                VStack(alignment: .leading, spacing: 4) {
                    Text(drive.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(drive.device)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(drive.sizeBytes.humanisedBytes)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                            Text(drive.isLocked ? "Locked — BitLocker" : "BitLocker")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DetectedView

struct DetectedView: View {
    @EnvironmentObject var app: AppState
    let drives: [Drive]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Section header
            Text(drives.count == 1 ? "Detected drive" : "Detected drives")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.bottom, 10)

            // Drive list
            VStack(spacing: 8) {
                ForEach(drives) { drive in
                    DriveCard(drive: drive) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            app.openUnlockSheet(for: drive)
                        }
                    }
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: 8) {
                // Primary action — only shown for single-drive case to avoid
                // ambiguity; multi-drive taps the card row instead.
                if drives.count == 1, let drive = drives.first {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            app.openUnlockSheet(for: drive)
                        }
                    } label: {
                        Label("Unlock", systemImage: "lock.open.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                }

                // Secondary action — Wave 3 wired to AppState.promptForManualDrive().
                Button {
                    app.promptForManualDrive()
                } label: {
                    Text("Pick a different drive")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 472)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Preview

struct DetectedView_Previews: PreviewProvider {
    static let singleDrive = Drive(
        device: "/dev/disk4s2",
        name: "Kingston DataTraveler",
        sizeBytes: 128_035_676_160,   // ~128.0 GB
        isBitLocker: true,
        isLocked: true,
        mountPoint: "",
        filesystem: "BitLocker",
        bus: "USB"
    )

    static let multiDrives = [
        singleDrive,
        Drive(
            device: "/dev/disk5s1",
            name: "WD Passport",
            sizeBytes: 1_000_204_886_016,   // ~1.0 TB
            isBitLocker: true,
            isLocked: true,
            mountPoint: "",
            filesystem: "BitLocker",
            bus: "USB"
        ),
    ]

    static var previews: some View {
        Group {
            DetectedView(drives: [singleDrive])
                .environmentObject(AppState())
                .frame(width: 472, height: 580)
                .previewDisplayName("Single drive")

            DetectedView(drives: multiDrives)
                .environmentObject(AppState())
                .frame(width: 472, height: 580)
                .previewDisplayName("Multi-drive")
        }
    }
}
