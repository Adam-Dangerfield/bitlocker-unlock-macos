import SwiftUI
import AppKit

/// Preferences popover presented from the menu-bar chrome.
///
/// All settings are backed by `@AppStorage` — changes persist
/// immediately with no Save button required.
///
/// Integration note: Wave 3 will attach this view via `.popover` or
/// similar inside `BLMenuBarExtra`. This file is self-contained.
struct PreferencesPopover: View {

    // MARK: - Persisted preferences

    @AppStorage("imageCacheLocation")  var cachePath: String = "/tmp/bl"
    @AppStorage("defaultUnlockMethod") var defaultMethod: String = "password"
    @AppStorage("alwaysReDecrypt")      var alwaysReDecrypt: Bool = false
    /// F5-03 mitigation: delete the plaintext decrypted image on eject.
    /// Default ON so the safe behaviour is the out-of-box behaviour.
    @AppStorage("autoCleanupOnEject")  var autoCleanupOnEject: Bool = true

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            Text("Preferences")
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
                .padding(.bottom, 8)

            Divider()

            // ── Image cache location ─────────────────────────────────
            PrefsRow(label: "Image cache location") {
                HStack(spacing: 6) {
                    TextField("Path", text: $cachePath)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 100)

                    Button("Choose…") {
                        chooseCacheDirectory()
                    }
                    .font(.system(.caption))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // ── Default unlock method ────────────────────────────────
            PrefsRow(label: "Default unlock method") {
                Picker("", selection: $defaultMethod) {
                    Text("Password").tag("password")
                    Text("Recovery").tag("recovery")
                    Text("BEK").tag("bek")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 160)
            }

            Divider()

            // ── Always re-decrypt ────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                PrefsRow(label: "Always re-decrypt") {
                    Toggle("", isOn: $alwaysReDecrypt)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Text("Skip cache; always run full decrypt. Slow.")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            Divider()

            // ── Auto-delete plaintext image on eject ──────────────────
            VStack(alignment: .leading, spacing: 4) {
                PrefsRow(label: "Auto-delete plaintext image on eject") {
                    Toggle("", isOn: $autoCleanupOnEject)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Text("Delete the cached decrypted image whenever the volume is ejected. Recommended — leaving plaintext on disk defeats BitLocker if your Mac is lost or stolen.")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - Helpers

    /// Opens an `NSOpenPanel` restricted to directory selection and
    /// writes the chosen path back into `cachePath`.
    private func chooseCacheDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a folder for the BitLocker image cache."

        if panel.runModal() == .OK, let url = panel.url {
            cachePath = url.path
        }
    }
}

// MARK: - PrefsRow helper

/// A horizontally-laid-out label + trailing control pair used for each
/// preference row, matching the JSX `Row` component style.
private struct PrefsRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(.body))
                .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

struct PreferencesPopover_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesPopover()
            .frame(width: 360, height: 280)
    }
}
