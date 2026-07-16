import Foundation

public struct MouseMacroFloatingButtonPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct MouseMacroFloatingButtonConfiguration: Codable, Equatable, Sendable {
    public static let defaultEmoji = "📷"

    public var isVisible: Bool
    public var emoji: String
    public var position: MouseMacroFloatingButtonPosition?

    public init(
        isVisible: Bool = false,
        emoji: String = MouseMacroFloatingButtonConfiguration.defaultEmoji,
        position: MouseMacroFloatingButtonPosition? = nil
    ) {
        self.isVisible = isVisible
        self.emoji = MouseMacroEmoji.normalized(emoji) ?? Self.defaultEmoji
        self.position = position
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible
        case emoji
        case position
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        let decodedEmoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? Self.defaultEmoji
        emoji = MouseMacroEmoji.normalized(decodedEmoji) ?? Self.defaultEmoji
        position = try container.decodeIfPresent(MouseMacroFloatingButtonPosition.self, forKey: .position)
    }
}

public struct MouseMacroMapping: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var buttonNumber: Int64
    public var macroText: String
    public var floatingButton: MouseMacroFloatingButtonConfiguration

    public init(
        id: UUID = UUID(),
        buttonNumber: Int64,
        macroText: String,
        floatingButton: MouseMacroFloatingButtonConfiguration = MouseMacroFloatingButtonConfiguration()
    ) {
        self.id = id
        self.buttonNumber = buttonNumber
        self.macroText = macroText
        self.floatingButton = floatingButton
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case buttonNumber
        case macroText
        case floatingButton
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        buttonNumber = try container.decode(Int64.self, forKey: .buttonNumber)
        macroText = try container.decode(String.self, forKey: .macroText)
        floatingButton = try container.decodeIfPresent(
            MouseMacroFloatingButtonConfiguration.self,
            forKey: .floatingButton
        ) ?? MouseMacroFloatingButtonConfiguration()
    }
}

public enum MouseMacroEmoji {
    public static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1 else {
            return nil
        }

        let scalars = trimmed.unicodeScalars
        let hasEmojiPresentation = scalars.contains { $0.properties.isEmojiPresentation }
        let hasEmojiVariationSelector = scalars.contains { $0.value == 0xFE0F }
        let hasNonASCIIEmojiScalar = scalars.contains {
            $0.properties.isEmoji
                && $0.value != 0x23
                && $0.value != 0x2A
                && !(0x30...0x39).contains($0.value)
        }
        guard hasEmojiPresentation || hasEmojiVariationSelector || hasNonASCIIEmojiScalar else {
            return nil
        }
        return trimmed
    }
}
