import SwiftUI
import AppKit

/// Closes security finding **F6-03**: by default macOS allows screen-recording
/// APIs and screen-sharing software to capture an app's windows. For a tool
/// that displays a BitLocker password / recovery key, that's a real
/// exfiltration path (`ScreenCaptureKit`, third-party recorders, even
/// `screencapture -l`). Setting `sharingType = .none` removes the window
/// from those capture surfaces. Tradeoff: legitimate screen sharing
/// (e.g. demos, remote support) won't see this window either — acceptable
/// for a single-purpose credential-entry tool.
private struct WindowGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.sharingType = .none
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Closes security finding **F1-06**: Path A leaves a fully decrypted,
/// plaintext copy of the volume at `/private/tmp/bl/decrypted.img`. The eject
/// button already deletes it (when `autoCleanupOnEject` is on), but quitting
/// the app — Cmd-Q, or the menu-bar "Quit" — would otherwise leave both the
/// mounted volume and that image behind, with no app left to manage them, so
/// a later `bl unlock` could re-mount the cached plaintext with no BitLocker
/// secret. `applicationShouldTerminate` intercepts the quit and, if a volume
/// is still mounted, asks whether to eject and delete the image first.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Wired up from `BitLockerUnlockApp` once the window appears.
    weak var appState: AppState?

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let appState,
              case .mounted(let drive, _, _) = appState.state else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Eject “\(drive.name)” before quitting?"
        alert.informativeText =
            "The decrypted volume is still mounted, and a plaintext copy of it "
            + "remains at /private/tmp/bl. Eject the volume and delete that "
            + "image, or leave it mounted."
        alert.addButton(withTitle: "Eject & Quit")        // first  button
        alert.addButton(withTitle: "Quit, Keep Mounted")  // second button
        alert.addButton(withTitle: "Cancel")              // third  button

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Async eject + cleanup, then let termination proceed.
            Task { @MainActor in
                await appState.ejectAndCleanupForQuit()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertThirdButtonReturn:
            return .terminateCancel
        default:
            // "Quit, Keep Mounted" — the user's explicit choice to leave the
            // plaintext volume and image in place.
            return .terminateNow
        }
    }
}

@main
struct BitLockerUnlockApp: App {

    /// Single source-of-truth instance shared via `@EnvironmentObject`.
    @StateObject private var appState = AppState()

    /// Termination handler — see `AppDelegate` (F1-06).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("BitLocker Unlock") {
            ContentView()
                .environmentObject(appState)
                .task {
                    appState.startWatching()
                    // F1-06: let the termination handler reach app state so it
                    // can offer to eject + delete the plaintext image on quit.
                    appDelegate.appState = appState
                }
        }
        .windowResizability(.contentSize)

        // Menu bar status item — managed by BLMenuBarExtra (Chrome layer).
        // AppState is passed directly (Scene.environmentObject requires macOS 14+).
        BLMenuBarExtra(app: appState)
    }
}

/// Root view that routes the visible screen based on `AppState.state`,
/// plus chrome (preferences popover, manual-drive alert) and a
/// `.sheet` overlay for the unlock credentials modal.
///
/// Sizing matches the JSX design's 520×640 envelope (see INTERFACES.md
/// addendum, "Wave 3 changes").
struct ContentView: View {

    @EnvironmentObject var app: AppState

    /// Popover toggle for the preferences chrome. Local UI state — does not
    /// belong on `AppState`.
    @State private var showPrefs = false

    var body: some View {
        NavigationStack {
            routedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showPrefs.toggle()
                        } label: {
                            Image(systemName: "gear")
                        }
                        .help("Preferences")
                        .popover(isPresented: $showPrefs, arrowEdge: .bottom) {
                            PreferencesPopover()
                        }
                    }
                }
        }
        .frame(width: 520, height: 640)
        .background(WindowGuard())
        // Sheet overlay for the credentials modal — driven directly by the
        // .unlockSheet case.
        .sheet(isPresented: Binding(
            get: { app.state.caseTag == "unlockSheet" },
            set: { newValue in
                if !newValue && app.state.caseTag == "unlockSheet" {
                    app.dismissUnlockSheet()
                }
            }
        )) {
            UnlockSheetView()
                .environmentObject(app)
        }
        // One-shot alerts (currently only the manual-drive placeholder).
        .alert(
            "Heads up",
            isPresented: Binding(
                get: { app.alertMessage != nil },
                set: { if !$0 { app.dismissAlert() } }
            ),
            presenting: app.alertMessage
        ) { _ in
            Button("OK") { app.dismissAlert() }
        } message: { msg in
            Text(msg)
        }
    }

    /// The state-routed screen. Wrapped in an animation that only fires on
    /// case transitions (see `AppState.State.caseTag`).
    @ViewBuilder
    private var routedContent: some View {
        Group {
            switch app.state {
            case .idle:
                EmptyView()
            case .detected(let drives):
                DetectedView(drives: drives)
            case .unlockSheet(let drive):
                // The sheet is what the user actually sees; behind it we
                // continue to render the previous "detected" surface so the
                // backdrop feels right.
                DetectedView(drives: app.drives.isEmpty ? [drive] : app.drives)
            case .decrypting:
                DecryptingView()
            case .mounted:
                MountedView()
            case .error:
                ErrorView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.state.caseTag)
    }
}
