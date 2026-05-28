import SwiftUI

struct MouseMacroSettingsView: View {
    @ObservedObject var environment: MouseMacroModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MouseMacro")
                .font(.system(size: 22, weight: .semibold))

            Text("Map an extra mouse button that macOS exposes, then run a key command sequence such as cmd+shift+ctrl+4.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
