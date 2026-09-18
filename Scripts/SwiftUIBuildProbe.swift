import SwiftUI

// Type-check the property wrapper/macro and its generated binding before building the app.
struct BryanToolsSwiftUIBuildProbe: View {
    @State private var value = ""

    var body: some View {
        TextField("Probe", text: $value)
    }
}
