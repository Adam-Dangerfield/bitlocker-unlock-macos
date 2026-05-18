import SwiftUI

struct MountedView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if case .mounted(let drive, let mountPath, let imagePath) = app.state {
            MountedContent(drive: drive, mountPath: mountPath, imagePath: imagePath)
                .environmentObject(app)
        }
    }
}

// MARK: - Plaintext image warning badge

/// A visible security notice shown whenever a plaintext cached image is present
/// on disk. Addresses F5-03: the image persists at rest and is unencrypted.
private struct PlaintextImageWarning: View {
    let sizeString: String
    @AppStorage("autoCleanupOnEject") private var autoCleanupOnEject: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.orange)
                .font(.system(size: 15, weight: .medium))

            VStack(alignment: .leading, spacing: 2) {
                Text("Cached plaintext image: \(sizeString) on disk.")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(Color.orange)

                Text(autoCleanupOnEject
                     ? "Eject will auto-delete."
                     : "Enable \"Auto-delete on eject\" in Preferences to remove automatically.")
                    .font(.system(.caption2))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Private content view

private struct MountedContent: View {
    let drive: Drive
    let mountPath: String
    let imagePath: String?

    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ── Top: success badge + headline + mount path ───────────────────
            VStack(spacing: 0) {
                // Green success circle badge
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 76, height: 76)

                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.green)
                        .font(.system(size: 44, weight: .regular))
                }

                Spacer().frame(height: 16)

                // Drive name headline
                Text(drive.name)
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                Spacer().frame(height: 4)

                Text("Mounted and ready")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer().frame(height: 14)

                // Mount path in SF Mono
                Text(mountPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 36)
            .padding(.horizontal, 24)

            Spacer()

            // ── F5-03 warning: plaintext image present on disk ───────────────
            if imagePath != nil {
                PlaintextImageWarning(sizeString: freedSizeString)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            // ── Bottom: action buttons ───────────────────────────────────────
            VStack(spacing: 8) {
                // Primary: Open in Finder
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mountPath))
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // Secondary: Eject
                Button {
                    Task { await app.ejectMounted() }
                } label: {
                    Label("Eject", systemImage: "eject")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)

            // Tertiary: Delete cached image (only when imagePath is set)
            if imagePath != nil {
                Button {
                    Task { await app.cleanupCachedImage() }
                } label: {
                    Text("Delete cached image (frees \(freedSizeString))")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 12)
            }

            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: imagePath != nil)
    }

    // MARK: - Helpers

    /// Humanise `drive.sizeBytes` into a user-friendly string (e.g. "128 GB").
    private var freedSizeString: String {
        let bytes = drive.sizeBytes
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 {
            let hasDecimal = gb.truncatingRemainder(dividingBy: 1) > 0.05
            return hasDecimal
                ? String(format: "%.1f GB", gb)
                : String(format: "%.0f GB", gb)
        }
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Preview

struct MountedView_Previews: PreviewProvider {
    static var previews: some View {
        let drive128 = Drive(
            device: "/dev/disk4s2",
            name: "Kingston DataTraveler",
            sizeBytes: 128_000_000_000,
            isBitLocker: true,
            isLocked: false,
            mountPoint: "/Volumes/MY_USB",
            filesystem: "BitLocker",
            bus: "USB"
        )

        let drive32 = Drive(
            device: "/dev/disk4s2",
            name: "Kingston DataTraveler",
            sizeBytes: 32_010_928_128,
            isBitLocker: true,
            isLocked: false,
            mountPoint: "/Volumes/MY_USB",
            filesystem: "BitLocker",
            bus: "USB"
        )

        Group {
            MountedContent(
                drive: drive128,
                mountPath: "/Volumes/MY_USB",
                imagePath: "/tmp/bl/decrypted.img"
            )
            .environmentObject(AppState())
            .frame(width: 472, height: 580)
            .previewDisplayName("Mounted — with image (128 GB)")

            MountedContent(
                drive: drive32,
                mountPath: "/Volumes/MY_USB",
                imagePath: nil
            )
            .environmentObject(AppState())
            .frame(width: 472, height: 580)
            .previewDisplayName("Mounted — no image (FUSE-T)")
        }
    }
}
