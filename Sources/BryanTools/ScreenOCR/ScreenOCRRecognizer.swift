import AppKit
import BryanToolsShared
import Foundation
import Vision

enum ScreenOCRError: Error, LocalizedError {
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "No text was recognized in the selected area."
        }
    }
}

enum ScreenOCRRecognizer {
    static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation -> ScreenOCRRecognizedLine? in
            guard let text = observation.topCandidates(1).first?.string else {
                return nil
            }
            return ScreenOCRRecognizedLine(text: text, boundingBox: observation.boundingBox)
        }

        let text = ScreenOCRTextFormatter.text(from: lines)
        guard !text.isEmpty else {
            throw ScreenOCRError.noTextFound
        }
        return text
    }
}
