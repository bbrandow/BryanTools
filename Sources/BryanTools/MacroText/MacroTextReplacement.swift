import Foundation

struct MacroTextReplacement: Codable, Equatable, Identifiable {
    let id: UUID
    var command: String
    var replacement: String

    init(id: UUID = UUID(), command: String, replacement: String) {
        self.id = id
        self.command = command
        self.replacement = replacement
    }
}
