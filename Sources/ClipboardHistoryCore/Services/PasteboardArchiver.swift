import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum PasteboardArchiver {
    public static let storedThumbnailMaxDimension: CGFloat = 1_280

    public static func capture(
        from pasteboard: NSPasteboard,
        sourceApplication: NSRunningApplication?,
        maxRepresentationBytes: Int,
        maxEventBytes: Int
    ) -> CapturedClip? {
        capture(
            from: pasteboard,
            sourceApplicationInfo: PasteboardSourceApplication(sourceApplication),
            maxRepresentationBytes: maxRepresentationBytes,
            maxEventBytes: maxEventBytes
        )
    }

    public static func capture(
        from pasteboard: NSPasteboard,
        sourceApplicationInfo sourceApplication: PasteboardSourceApplication?,
        maxRepresentationBytes: Int,
        maxEventBytes: Int
    ) -> CapturedClip? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return nil
        }
        guard !PrivacyFilter.shouldSkip(items: items, sourceApplication: sourceApplication) else {
            return nil
        }

        var representations: [CapturedRepresentation] = []
        var typeIdentifiers: [String] = []
        var seenTypes = Set<String>()
        var searchablePieces: [String] = []
        var plainTexts: [String] = []
        var richTexts: [String] = []
        var filePaths: [String] = []
        var urlStrings: [String] = []
        var imageItemIndexes = Set<Int>()
        var thumbnailData: Data?
        var totalBytes = 0

        for (itemIndex, item) in items.enumerated() {
            for type in item.types {
                let typeIdentifier = type.rawValue
                if PrivacyFilter.isMarkerType(typeIdentifier) {
                    continue
                }
                guard let data = representationData(for: item, type: type), !data.isEmpty else {
                    continue
                }
                guard data.count <= maxRepresentationBytes else {
                    continue
                }
                guard totalBytes + data.count <= maxEventBytes else {
                    continue
                }

                totalBytes += data.count
                representations.append(
                    CapturedRepresentation(
                        itemIndex: itemIndex,
                        typeIdentifier: typeIdentifier,
                        data: data
                    )
                )

                if seenTypes.insert(typeIdentifier).inserted {
                    typeIdentifiers.append(typeIdentifier)
                    if let description = UTType(typeIdentifier)?.localizedDescription {
                        searchablePieces.append(description)
                    }
                }

                extractCanonicalData(
                    item: item,
                    itemIndex: itemIndex,
                    type: type,
                    data: data,
                    plainTexts: &plainTexts,
                    richTexts: &richTexts,
                    filePaths: &filePaths,
                    urlStrings: &urlStrings,
                    imageItemIndexes: &imageItemIndexes,
                    thumbnailData: &thumbnailData,
                    searchablePieces: &searchablePieces
                )
            }
        }

        guard !representations.isEmpty else {
            return nil
        }

        let allText = (plainTexts + richTexts).map(collapseWhitespace).filter { !$0.isEmpty }
        searchablePieces.append(contentsOf: allText)
        searchablePieces.append(contentsOf: filePaths)
        searchablePieces.append(contentsOf: urlStrings)
        searchablePieces.append(contentsOf: typeIdentifiers)

        let primaryKind = inferPrimaryKind(
            plainTexts: plainTexts,
            richTexts: richTexts,
            filePaths: filePaths,
            urlStrings: urlStrings,
            imageCount: imageItemIndexes.count,
            itemCount: items.count
        )

        let summary = makeSummary(
            primaryKind: primaryKind,
            texts: allText,
            filePaths: filePaths,
            urlStrings: urlStrings,
            imageCount: imageItemIndexes.count,
            typeIdentifiers: typeIdentifiers
        )

        return CapturedClip(
            contentHash: contentHash(for: representations),
            itemCount: items.count,
            primaryKind: primaryKind,
            summary: summary,
            searchableText: unique(searchablePieces).joined(separator: " "),
            typeIdentifiers: typeIdentifiers,
            representations: representations,
            thumbnailPNGData: thumbnailData,
            byteCount: Int64(totalBytes)
        )
    }

    private static func representationData(for item: NSPasteboardItem, type: NSPasteboard.PasteboardType) -> Data? {
        if let data = item.data(forType: type) {
            return data
        }
        if let string = item.string(forType: type) {
            return Data(string.utf8)
        }
        return nil
    }

    private static func extractCanonicalData(
        item: NSPasteboardItem,
        itemIndex: Int,
        type: NSPasteboard.PasteboardType,
        data: Data,
        plainTexts: inout [String],
        richTexts: inout [String],
        filePaths: inout [String],
        urlStrings: inout [String],
        imageItemIndexes: inout Set<Int>,
        thumbnailData: inout Data?,
        searchablePieces: inout [String]
    ) {
        let typeIdentifier = type.rawValue.lowercased()

        if typeIdentifier == "public.file-url" || typeIdentifier.contains("file-url") {
            if let filePath = filePath(from: item.string(forType: type) ?? String(data: data, encoding: .utf8)) {
                filePaths.append(filePath)
                searchablePieces.append(URL(fileURLWithPath: filePath).lastPathComponent)
            }
            return
        }

        if typeIdentifier == "public.url" || typeIdentifier.hasSuffix(".url") || typeIdentifier.contains("url") {
            if let string = item.string(forType: type) ?? String(data: data, encoding: .utf8),
               let url = URL(string: string) {
                if url.isFileURL {
                    filePaths.append(url.path)
                    searchablePieces.append(url.lastPathComponent)
                } else {
                    urlStrings.append(url.absoluteString)
                    searchablePieces.append(url.host ?? url.absoluteString)
                }
            }
        }

        if typeIdentifier.contains("html") {
            if let string = attributedString(from: data, documentType: .html) {
                richTexts.append(string)
            } else if let string = item.string(forType: type) ?? String(data: data, encoding: .utf8) {
                richTexts.append(string)
            }
        } else if typeIdentifier.contains("rtf") {
            if let string = attributedString(from: data, documentType: .rtf) {
                richTexts.append(string)
            }
        } else if isPlainTextType(typeIdentifier),
                  let string = item.string(forType: type) ?? String(data: data, encoding: .utf8) {
            plainTexts.append(string)
        }

        if let image = NSImage(data: data), image.isValid {
            imageItemIndexes.insert(itemIndex)
            if thumbnailData == nil {
                thumbnailData = makeThumbnailPNG(from: image)
            }
            searchablePieces.append("image")
            searchablePieces.append("\(Int(image.size.width))x\(Int(image.size.height))")
        }
    }

    private static func isPlainTextType(_ typeIdentifier: String) -> Bool {
        typeIdentifier == NSPasteboard.PasteboardType.string.rawValue.lowercased()
            || typeIdentifier.contains("plain-text")
            || typeIdentifier.contains("utf8-plain-text")
            || typeIdentifier.contains("utf-8")
            || typeIdentifier == "nsstringpboardtype"
    }

    private static func filePath(from string: String?) -> String? {
        guard let string, !string.isEmpty else {
            return nil
        }
        if let url = URL(string: string), url.isFileURL {
            return url.path
        }
        if string.hasPrefix("/") {
            return string
        }
        return nil
    }

    private static func attributedString(from data: Data, documentType: NSAttributedString.DocumentType) -> String? {
        let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
        let string = attributed?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return string?.isEmpty == false ? string : nil
    }

    private static func inferPrimaryKind(
        plainTexts: [String],
        richTexts: [String],
        filePaths: [String],
        urlStrings: [String],
        imageCount: Int,
        itemCount: Int
    ) -> ClipPrimaryKind {
        let signals = [
            !plainTexts.isEmpty || !richTexts.isEmpty,
            !filePaths.isEmpty,
            !urlStrings.isEmpty,
            imageCount > 0
        ].filter { $0 }.count

        if signals > 1 || itemCount > 1 {
            return .mixed
        }
        if !richTexts.isEmpty {
            return .richText
        }
        if !plainTexts.isEmpty {
            return .text
        }
        if !filePaths.isEmpty {
            return .file
        }
        if !urlStrings.isEmpty {
            return .url
        }
        if imageCount > 0 {
            return .image
        }
        return .data
    }

    private static func makeSummary(
        primaryKind: ClipPrimaryKind,
        texts: [String],
        filePaths: [String],
        urlStrings: [String],
        imageCount: Int,
        typeIdentifiers: [String]
    ) -> String {
        if let text = texts.first, !text.isEmpty {
            return String(text.prefix(160))
        }
        if !filePaths.isEmpty {
            let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.filter { !$0.isEmpty }
            return "Files: " + names.prefix(3).joined(separator: ", ")
        }
        if let url = urlStrings.first {
            return url
        }
        if imageCount > 0 {
            return imageCount == 1 ? "Image" : "\(imageCount) images"
        }
        if let type = typeIdentifiers.first {
            return "\(primaryKind.displayName): \(type)"
        }
        return primaryKind.displayName
    }

    private static func contentHash(for representations: [CapturedRepresentation]) -> String {
        var hasher = SHA256()
        for representation in representations.sorted(by: { lhs, rhs in
            if lhs.itemIndex != rhs.itemIndex {
                return lhs.itemIndex < rhs.itemIndex
            }
            return lhs.typeIdentifier < rhs.typeIdentifier
        }) {
            hasher.update(data: Data("\(representation.itemIndex):\(representation.typeIdentifier):".utf8))
            hasher.update(data: representation.data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func makeThumbnailPNG(
        from image: NSImage,
        maxDimension: CGFloat = storedThumbnailMaxDimension
    ) -> Data? {
        let originalPixelSize = pixelSize(for: image)
        guard originalPixelSize.width > 0, originalPixelSize.height > 0 else {
            return nil
        }

        let scale = min(maxDimension / originalPixelSize.width, maxDimension / originalPixelSize.height, 1)
        let thumbnailPixelSize = NSSize(
            width: max(1, floor(originalPixelSize.width * scale)),
            height: max(1, floor(originalPixelSize.height * scale))
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(thumbnailPixelSize.width),
            pixelsHigh: Int(thumbnailPixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = thumbnailPixelSize
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: thumbnailPixelSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func pixelSize(for image: NSImage) -> NSSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSSize(width: cgImage.width, height: cgImage.height)
        }
        if let representation = image.representations.max(by: {
            $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
        }) {
            return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return image.size
    }

    private static func collapseWhitespace(_ string: String) -> String {
        string
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values.map(collapseWhitespace).filter({ !$0.isEmpty }) {
            if seen.insert(value).inserted {
                output.append(value)
            }
        }
        return output
    }
}
