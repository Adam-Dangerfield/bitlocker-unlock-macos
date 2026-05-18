import SwiftUI
import AppKit

// MARK: - UnlockSheetView

struct UnlockSheetView: View {
    @EnvironmentObject var app: AppState

    // MARK: Input-mode picker
    private enum InputMode: String, CaseIterable, Identifiable {
        case password  = "Password"
        case recovery  = "Recovery Key"
        case bek       = "BEK File"
        var id: Self { self }
    }

    @State private var mode: InputMode = .password

    // Per-mode field state
    @State private var passwordText:  String = ""
    @State private var recoveryRaw:   String = ""   // digits only, max 48
    @State private var bekURL:        URL?   = nil

    // UI-only session-remember toggle
    @State private var rememberSession: Bool = false

    // MARK: Derived helpers

    /// Recovery key formatted as "######-######-…" with dashes every 6 digits.
    private var recoveryFormatted: String {
        let digits = recoveryRaw.prefix(48)
        var result = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && i % 6 == 0 { result += "-" }
            result.append(ch)
        }
        return result
    }

    /// True when the current mode has sufficient input to attempt unlock.
    private var canUnlock: Bool {
        switch mode {
        case .password: return !passwordText.isEmpty
        case .recovery: return recoveryRaw.count == 48
        case .bek:      return bekURL != nil
        }
    }

    /// Drive extracted from app state (present only in .unlockSheet).
    private var drive: Drive? {
        if case .unlockSheet(let d) = app.state { return d }
        return nil
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // Backdrop — matches the JS `t.backdrop` semi-transparent overlay.
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                sheetCard
                    .frame(width: 400)
                    // Attach from top, leaving room for the drive-list behind.
                    .padding(.top, 0)
                Spacer()
            }
        }
        .frame(width: 472, height: 580)
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    // MARK: Sheet card

    @ViewBuilder
    private var sheetCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Drive header ─────────────────────────────────────────────
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "externaldrive.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 36))

                VStack(alignment: .leading, spacing: 2) {
                    if let drive {
                        Text("Unlock \"\(drive.name)\"")
                            .font(.system(size: 14, weight: .semibold))
                        Text(formatSize(drive.sizeBytes))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Unlock Drive")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Choose how to authenticate this BitLocker volume.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 16)

            // ── Mode picker ──────────────────────────────────────────────
            Picker("", selection: $mode) {
                ForEach(InputMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // ── Input area ───────────────────────────────────────────────
            Group {
                switch mode {
                case .password:
                    passwordSection
                case .recovery:
                    recoverySection
                case .bek:
                    bekSection
                }
            }
            .padding(.top, 14)
            .animation(.easeInOut(duration: 0.2), value: mode)

            // ── Divider + checkbox ───────────────────────────────────────
            Divider()
                .padding(.top, 16)
                .padding(.bottom, 12)

            Toggle(isOn: $rememberSession) {
                Text("Remember for this session")
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)

            // ── Buttons ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    app.dismissUnlockSheet()
                }
                .keyboardShortcut(.cancelAction)

                Button("Unlock") {
                    handleUnlock()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canUnlock)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 4)
        )
        // Flat top edge (sheet drops from window chrome)
        .mask(
            VStack(spacing: 0) {
                Rectangle()                         // top corners stay square
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
            }
        )
    }

    // MARK: Input sections

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password")
                .font(.system(size: 12, weight: .medium))
            SecureField("Enter password", text: $passwordText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery key")
                .font(.system(size: 12, weight: .medium))

            TextField("", text: Binding(
                get: { recoveryFormatted },
                set: { newValue in
                    // Strip everything that isn't a digit, cap at 48
                    let digits = newValue.filter(\.isNumber)
                    recoveryRaw = String(digits.prefix(48))
                }
            ))
            .font(.system(size: 13, design: .monospaced))
            .textFieldStyle(.roundedBorder)

            Text("48 digits in 8 groups of 6 · auto-formatted as you type")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var bekSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Key file")
                .font(.system(size: 12, weight: .medium))

            HStack(spacing: 8) {
                Button("Choose file\u{2026}") {
                    pickBEKFile()
                }

                if let url = bekURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No file selected")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Actions

    private func pickBEKFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a BEK file"
        panel.allowedContentTypes = []           // set via extension below
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a BitLocker External Key (.bek) file"
        // Restrict to .bek extension — UTType for .bek is not registered,
        // so we gate via a delegate-free extension filter approach: allow all
        // files but filter to .bek in the filename. NSOpenPanel doesn't have
        // a built-in UTType for .bek, so we accept all and validate.
        panel.allowsOtherFileTypes = true        // user sees all; we validate
        if panel.runModal() == .OK, let url = panel.url {
            if url.pathExtension.lowercased() == "bek" {
                bekURL = url
            }
            // If extension doesn't match we silently ignore — user must re-pick.
        }
    }

    private func handleUnlock() {
        let method: UnlockMethod
        switch mode {
        case .password:
            method = .password(passwordText)
        case .recovery:
            // Pass the raw digits; strip any dashes to be safe
            let clean = recoveryFormatted.filter(\.isNumber)
            method = .recovery(clean)
        case .bek:
            guard let url = bekURL else { return }
            method = .bek(url)
        }
        Task { await app.attemptUnlock(method: method) }
    }

    // MARK: Helpers

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

struct UnlockSheetView_Previews: PreviewProvider {
    private static func makeState() -> AppState {
        let s = AppState()
        let drive = Drive(
            device: "/dev/disk4s2",
            name: "Kingston DataTraveler",
            sizeBytes: 32_010_928_128,
            isBitLocker: true,
            isLocked: true,
            mountPoint: "",
            filesystem: "BitLocker",
            bus: "USB"
        )
        s.openUnlockSheet(for: drive)
        return s
    }

    static var previews: some View {
        UnlockSheetView()
            .environmentObject(makeState())
            .frame(width: 472, height: 580)
            .previewDisplayName("Password mode")
    }
}
