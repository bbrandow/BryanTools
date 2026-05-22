import BryanToolsShared
import SwiftUI

struct DiskSpaceMonitorSettingsView: View {
    @ObservedObject var environment: DiskSpaceMonitorModule
    @State private var warningThresholdText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Disk Space Monitor")
                .font(.system(size: 22, weight: .semibold))

            settingsSection("Menu Bar") {
                Toggle(
                    "Show Disk Space in Menu Bar",
                    isOn: Binding(
                        get: { environment.isEnabled },
                        set: { environment.updateEnabled($0) }
                    )
                )
            }

            settingsSection("Warnings") {
                settingsRow("Warning Below") {
                    HStack(spacing: 8) {
                        TextField("50", text: $warningThresholdText)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 74)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(commitWarningThresholdText)

                        Text("GB")
                            .foregroundStyle(.secondary)

                        Stepper("", value: warningThresholdBinding, in: DiskSpaceMonitorPreferences.minimumWarningThresholdGB...DiskSpaceMonitorPreferences.maximumWarningThresholdGB)
                            .labelsHidden()
                    }
                }
            }

            if let message = environment.lastErrorMessage {
                settingsSection("Last Error") {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            syncWarningThresholdText()
        }
        .onChange(of: environment.warningThresholdGB) { _, _ in
            syncWarningThresholdText()
        }
    }

    private var warningThresholdBinding: Binding<Int> {
        Binding(
            get: { environment.warningThresholdGB },
            set: { value in
                environment.updateWarningThresholdGB(value)
                warningThresholdText = "\(environment.warningThresholdGB)"
            }
        )
    }

    private func commitWarningThresholdText() {
        let filtered = warningThresholdText.filter(\.isNumber)
        if let value = Int(filtered) {
            environment.updateWarningThresholdGB(value)
        }
        syncWarningThresholdText()
    }

    private func syncWarningThresholdText() {
        warningThresholdText = "\(environment.warningThresholdGB)"
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            content()
        }
    }
}
