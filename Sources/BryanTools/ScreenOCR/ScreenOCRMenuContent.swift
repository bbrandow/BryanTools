import SwiftUI

struct ScreenOCRMenuContent: View {
    @ObservedObject var environment: ScreenOCRModule

    var body: some View {
        Button {
            environment.beginCapture()
        } label: {
            Label("Capture Text (\(environment.hotKey.displayString))", systemImage: "text.viewfinder")
        }
        .disabled(environment.isRecognizing)
    }
}
