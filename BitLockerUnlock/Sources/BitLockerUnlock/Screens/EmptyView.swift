import SwiftUI

struct EmptyView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            // Centre stack
            VStack(spacing: 0) {
                Image(systemName: "externaldrive.badge.questionmark")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 72, weight: .light))
                    .opacity(0.92)

                Spacer().frame(height: 24)

                Text("Plug in a BitLocker drive")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 6)

                Text("We'll detect it automatically.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 56)

            // Footer link — Wave 3 wired this to AppState.promptForManualDrive().
            Button("Pick a drive manually\u{2026}") {
                app.promptForManualDrive()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .font(.caption)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct EmptyView_Previews: PreviewProvider {
    static var previews: some View {
        EmptyView()
            .environmentObject(AppState())
            .frame(width: 472, height: 580)
    }
}
