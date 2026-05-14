import SwiftUI

struct MacroTextMenuContent: View {
    @ObservedObject var environment: MacroTextModule

    var body: some View {
        Button {
            environment.showConfig()
        } label: {
            Label("Configure MacroText (\(environment.hotKey.displayString))", systemImage: "text.badge.plus")
        }

        if let lastExpansion = environment.lastExpansion {
            Label(lastExpansion, systemImage: "text.cursor")
        } else {
            Label("\(environment.replacements.count) replacements", systemImage: "list.bullet")
        }
    }
}
