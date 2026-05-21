import SwiftUI

struct ShotFloatMenuContent: View {
    @ObservedObject var environment: ShotFloatModule

    var body: some View {
        Button {
            environment.beginCapture()
        } label: {
            Label("Capture ShotFloat (\(environment.hotKey.displayString))", systemImage: "rectangle.dashed")
        }
    }
}
