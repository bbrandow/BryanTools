import SwiftUI

struct ColorPickerMenuContent: View {
    @ObservedObject var environment: ColorPickerModule

    var body: some View {
        Button {
            environment.beginPicking()
        } label: {
            Label("Pick Color (\(environment.hotKey.displayString))", systemImage: "eyedropper")
        }

        if let lastHexColor = environment.lastHexColor {
            Button {
                environment.copyLastColor()
            } label: {
                Label("Copy \(lastHexColor)", systemImage: "doc.on.doc")
            }
        }
    }
}
