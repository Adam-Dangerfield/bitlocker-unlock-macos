import SwiftUI
import AppKit

/// A `Scene` that owns the macOS menu bar status item for BitLocker Unlock.
///
/// Add to the `App.body` alongside the `WindowGroup`, passing the shared
/// `AppState` directly (avoids the macOS 14-only `Scene.environmentObject`):
/// ```swift
/// BLMenuBarExtra(app: appState)
/// ```
struct BLMenuBarExtra: Scene {

    /// Injected from `App.swift`; must be the same instance passed to
    /// `WindowGroup` so all Scenes share one source of truth.
    var app: AppState

    // MARK: - Icon

    /// SF Symbol name that represents the current `AppState.State`.
    private var systemImage: String {
        switch app.state {
        case .idle:
            return "externaldrive"
        case .detected:
            return "externaldrive.badge.questionmark"
        case .unlockSheet:
            return "externaldrive.badge.questionmark"
        case .decrypting:
            return "externaldrive.badge.timemachine"
        case .mounted:
            return "externaldrive.badge.checkmark"
        case .error:
            return "externaldrive.badge.xmark"
        }
    }

    // MARK: - Scene body

    var body: some Scene {
        MenuBarExtra(content: {
            BLMenuBarContent()
                .environmentObject(app)
        }, label: {
            Image(systemName: systemImage)
                .accessibilityLabel("BitLocker Unlock")
        })
    }
}

// MARK: - Menu content

/// The dropdown content rendered inside the `MenuBarExtra`.
private struct BLMenuBarContent: View {

    @EnvironmentObject var app: AppState

    var body: some View {
        statusItems
        Divider()
        bottomItems
    }

    // MARK: State-driven items

    @ViewBuilder
    private var statusItems: some View {
        switch app.state {

        case .idle:
            Text("No drive plugged in")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .disabled(true)

        case .detected(let drives):
            if drives.isEmpty {
                Text("No BitLocker drives detected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .disabled(true)
            } else {
                ForEach(drives) { drive in
                    Button("Unlock \(drive.name)") {
                        app.openUnlockSheet(for: drive)
                    }
                    .font(.system(size: 13))
                }
            }

        case .unlockSheet(let drive):
            Text("Unlocking \(drive.name)…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .disabled(true)

        case .decrypting(let drive, let progress, let etaSec, _):
            VStack(alignment: .leading, spacing: 4) {
                Text("Decrypting \(drive.name)")
                    .font(.system(size: 13))
                if progress > 0 {
                    let pct = Int(progress * 100)
                    if let eta = etaSec {
                        Text("\(pct)% · ~\(etaString(eta))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(pct)%")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Starting…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(true)

            Button("Cancel") {
                app.cancelUnlock()
            }
            .font(.system(size: 13))

        case .mounted(let drive, let mountPath, _):
            Button("Open \(mountPath)") {
                NSWorkspace.shared.open(URL(fileURLWithPath: mountPath))
            }
            .font(.system(size: 13))

            Button("Eject \(drive.name)") {
                Task { await app.ejectMounted() }
            }
            .font(.system(size: 13))

        case .error(_, let message, _, let recoverable):
            Text(message.isEmpty ? "An error occurred" : message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .disabled(true)

            if recoverable {
                Button("Try Again") {
                    app.dismissError()
                }
                .font(.system(size: 13))
            } else {
                Button("Dismiss") {
                    app.dismissError()
                }
                .font(.system(size: 13))
            }
        }
    }

    // MARK: Bottom items (always shown)

    @ViewBuilder
    private var bottomItems: some View {
        Button("Quit") {
            NSApp.terminate(nil)
        }
        .font(.system(size: 13))
        .keyboardShortcut("q")
    }

    // MARK: Helpers

    private func etaString(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m)m \(s)s"
    }
}
