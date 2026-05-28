import Foundation

struct MouseMacroMapping: Codable, Equatable, Identifiable {
    let id: UUID
    var buttonNumber: Int64
    var macroText: String

    init(id: UUID = UUID(), buttonNumber: Int64, macroText: String) {
        self.id = id
        self.buttonNumber = buttonNumber
        self.macroText = macroText
    }
}
