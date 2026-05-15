import AppKit
import CoreGraphics
import Foundation

struct ColorPickerSample {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}

enum ColorPickerCaptureError: Error, LocalizedError {
    case screenUnavailable
    case captureFailed
    case pixelUnavailable

    var errorDescription: String? {
        switch self {
        case .screenUnavailable:
            return "No screen is available for color picking."
        case .captureFailed:
            return "Unable to capture the screen for color picking."
        case .pixelUnavailable:
            return "Unable to read the selected pixel."
        }
    }
}

struct ColorPickerScreenCapture {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let image: CGImage

    static func ensurePermission(promptIfNeeded: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        guard promptIfNeeded else {
            return false
        }
        return CGRequestScreenCaptureAccess()
    }

    static func captureScreens() throws -> [ColorPickerScreenCapture] {
        let captures = NSScreen.screens.compactMap { screen -> ColorPickerScreenCapture? in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let image = CGDisplayCreateImage(displayID) else {
                return nil
            }
            return ColorPickerScreenCapture(
                screen: screen,
                displayID: displayID,
                frame: screen.frame,
                image: image
            )
        }

        guard !NSScreen.screens.isEmpty else {
            throw ColorPickerCaptureError.screenUnavailable
        }
        guard !captures.isEmpty else {
            throw ColorPickerCaptureError.captureFailed
        }
        return captures
    }

    func contains(globalPoint: CGPoint) -> Bool {
        frame.contains(globalPoint)
    }

    func imagePoint(for globalPoint: CGPoint) -> CGPoint? {
        guard contains(globalPoint: globalPoint) else {
            return nil
        }

        let localX = globalPoint.x - frame.minX
        let localYFromBottom = globalPoint.y - frame.minY
        let xScale = CGFloat(image.width) / frame.width
        let yScale = CGFloat(image.height) / frame.height
        let x = min(max(localX * xScale, 0), CGFloat(image.width - 1))
        let y = min(max((frame.height - localYFromBottom) * yScale, 0), CGFloat(image.height - 1))
        return CGPoint(x: x, y: y)
    }

    func sample(at globalPoint: CGPoint) -> ColorPickerSample? {
        guard let imagePoint = imagePoint(for: globalPoint),
              let cropped = image.cropping(to: CGRect(
                x: floor(imagePoint.x),
                y: floor(imagePoint.y),
                width: 1,
                height: 1
              )) else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return ColorPickerSample(red: pixel[0], green: pixel[1], blue: pixel[2])
    }

    func cropRect(centeredAt globalPoint: CGPoint, diameterPoints: CGFloat, magnification: CGFloat) -> CGRect? {
        guard let imagePoint = imagePoint(for: globalPoint) else {
            return nil
        }

        let sourceDiameterPoints = diameterPoints / magnification
        let xScale = CGFloat(image.width) / frame.width
        let yScale = CGFloat(image.height) / frame.height
        let width = max(1, sourceDiameterPoints * xScale)
        let height = max(1, sourceDiameterPoints * yScale)
        let rect = CGRect(
            x: imagePoint.x - width / 2,
            y: imagePoint.y - height / 2,
            width: width,
            height: height
        )
        return rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    func imageRect(forGlobalRect globalRect: CGRect) -> CGRect? {
        let selection = globalRect.standardized.intersection(frame)
        guard !selection.isNull,
              selection.width > 0,
              selection.height > 0 else {
            return nil
        }

        let xScale = CGFloat(image.width) / frame.width
        let yScale = CGFloat(image.height) / frame.height
        let x = (selection.minX - frame.minX) * xScale
        let y = (frame.maxY - selection.maxY) * yScale
        let rect = CGRect(
            x: floor(x),
            y: floor(y),
            width: ceil(selection.width * xScale),
            height: ceil(selection.height * yScale)
        )
        return rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    func croppedImage(forGlobalRect globalRect: CGRect) -> CGImage? {
        guard let imageRect = imageRect(forGlobalRect: globalRect) else {
            return nil
        }
        return image.cropping(to: imageRect)
    }
}
