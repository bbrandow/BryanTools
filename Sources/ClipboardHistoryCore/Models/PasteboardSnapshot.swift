import Foundation

public struct CapturedClip {
    let contentHash: String
    let canonicalTextHash: String?
    let itemCount: Int
    let primaryKind: ClipPrimaryKind
    let summary: String
    let searchableText: String
    let typeIdentifiers: [String]
    let representations: [CapturedRepresentation]
    let thumbnailPNGData: Data?
    let byteCount: Int64
}

public struct CapturedRepresentation {
    let itemIndex: Int
    let typeIdentifier: String
    let data: Data

    var byteCount: Int64 {
        Int64(data.count)
    }
}
