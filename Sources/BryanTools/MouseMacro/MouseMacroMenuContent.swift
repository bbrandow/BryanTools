import SwiftUI

struct MouseMacroMenuContent: View {
    @ObservedObject var environment: MouseMacroModule

    var body: some View {
        Button {
            if let mapping = environment.mappings.first {
                environment.triggerMacro(mapping)
            }
        } label: {
            Label("Trigger MouseMacro", systemImage: environment.systemImage)
        }
        .disabled(environment.mappings.isEmpty)
    }
}
