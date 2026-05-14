import SwiftUI

struct QuickTaskMenuContent: View {
    @ObservedObject var environment: QuickTaskModule

    var body: some View {
        Button {
            environment.showQuickTask()
        } label: {
            Label("Open QuickTask (\(environment.hotKey.displayString))", systemImage: "command")
        }
    }
}
