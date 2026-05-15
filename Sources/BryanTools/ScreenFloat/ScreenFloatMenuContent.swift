import SwiftUI

struct ScreenFloatMenuContent: View {
    @ObservedObject var environment: ScreenFloatModule

    var body: some View {
        Button {
            environment.beginCapture()
        } label: {
            Label("Capture ScreenFloat (\(environment.hotKey.displayString))", systemImage: "rectangle.dashed")
        }
    }
}
