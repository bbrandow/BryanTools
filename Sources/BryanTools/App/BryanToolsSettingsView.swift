import SwiftUI

struct BryanToolsSettingsView: View {
    @ObservedObject var environment: BryanToolsEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Bryan Tools")
                    .font(.system(size: 22, weight: .semibold))

                environment.clipboardHistory.settingsView()

                environment.colorPicker.settingsView()

                environment.macroText.settingsView()

                environment.quickTask.settingsView()

                environment.screenFloat.settingsView()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 680, height: 640, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

}
