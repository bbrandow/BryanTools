import Foundation

public enum ClipPrimaryKind: String, Codable, CaseIterable {
    case text
    case richText
    case image
    case file
    case url
    case mixed
    case data

    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "URL"
        case .mixed: return "Mixed"
        case .data: return "Data"
        }
    }

    public var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .mixed: return "square.stack.3d.up"
        case .data: return "shippingbox"
        }
    }
}

public struct ClipRecord: Identifiable, Equatable, Codable {
    public let id: UUID
    public let createdAt: Date
    public let itemCount: Int
    public let contentHash: String
    public let primaryKind: ClipPrimaryKind
    public let summary: String
    public let searchableText: String
    public let typeIdentifiers: [String]
    public let byteCount: Int64
    public let thumbnailPath: String?
}

struct ClipRepresentation: Equatable, Codable {
    let itemIndex: Int
    let typeIdentifier: String
    let storagePath: String
    let byteCount: Int64
}
