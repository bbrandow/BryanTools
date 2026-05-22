import CoreGraphics
import Foundation

public struct ScreenOCRRecognizedLine: Equatable {
    public let text: String
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public enum ScreenOCRTextFormatter {
    public static func text(from lines: [ScreenOCRRecognizedLine]) -> String {
        lines
            .map { line in
                ScreenOCRRecognizedLine(
                    text: line.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    boundingBox: line.boundingBox
                )
            }
            .filter { !$0.text.isEmpty }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .map(\.text)
            .joined(separator: "\n")
    }
}
