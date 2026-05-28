import Foundation

public enum QuickTaskCommandLine {
    public static func commandText(fromPrefixedQuery query: String) -> String? {
        guard query.first == ">" else {
            return nil
        }

        var command = query.dropFirst()
        if command.first == " " {
            command = command.dropFirst()
        }
        return String(command)
    }
}
