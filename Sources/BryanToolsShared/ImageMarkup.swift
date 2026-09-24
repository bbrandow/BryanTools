import AppKit

/// Points and widths are in source-image pixels, with a bottom-left origin.
public struct ImageMarkupStroke: Equatable {
    public static let defaultWidth: CGFloat = 8
    public static let eraserWidthMultiplier: CGFloat = 4

    public let id: UUID
    public var points: [CGPoint]
    public let width: CGFloat
    public let color: NSColor
    public let hasArrow: Bool
    public let isEraser: Bool

    public init(points: [CGPoint], width: CGFloat, color: NSColor, hasArrow: Bool = false) {
        self.init(points: points, width: Self.brushWidth(width), color: color, hasArrow: hasArrow, isEraser: false)
    }

    private init(points: [CGPoint], width: CGFloat, color: NSColor, hasArrow: Bool, isEraser: Bool) {
        self.id = UUID()
        self.points = points
        self.width = width
        self.color = color.usingColorSpace(.sRGB) ?? .systemRed
        self.hasArrow = hasArrow
        self.isEraser = isEraser
    }

    public static func eraser(points: [CGPoint], brushWidth: CGFloat) -> Self {
        Self(points: points, width: Self.brushWidth(brushWidth) * eraserWidthMultiplier, color: .clear, hasArrow: false, isEraser: true)
    }

    private static func brushWidth(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(100, max(1, value)) : defaultWidth
    }

    public var arrowPoints: [CGPoint] {
        guard hasArrow, let tip = points.last,
              let previous = points.dropLast().reversed().first(where: {
                  hypot(tip.x - $0.x, tip.y - $0.y) >= max(1, width)
              }) else { return [] }
        let angle = atan2(tip.y - previous.y, tip.x - previous.x)
        let length = max(10, width * 4)
        let spread = CGFloat.pi / 6
        return [
            CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)),
            tip,
            CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread))
        ]
    }

}

public struct ImageMarkupDocument {
    public private(set) var strokes: [ImageMarkupStroke] = []
    private var undoStates: [[ImageMarkupStroke]] = []
    private var redoStates: [[ImageMarkupStroke]] = []
    private static let historyLimit = 100

    public init() {}

    public var canUndo: Bool { !undoStates.isEmpty }
    public var canRedo: Bool { !redoStates.isEmpty }

    public mutating func add(_ stroke: ImageMarkupStroke) {
        guard !stroke.points.isEmpty else { return }
        replaceStrokes(strokes + [stroke])
    }

    /// Commit a whole drawing/erasing gesture as a single undoable edit.
    private mutating func replaceStrokes(_ newStrokes: [ImageMarkupStroke]) {
        guard strokes != newStrokes else { return }
        undoStates.append(strokes)
        if undoStates.count > Self.historyLimit { undoStates.removeFirst() }
        redoStates.removeAll()
        strokes = newStrokes
    }

    public mutating func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(strokes)
        strokes = previous
    }

    public mutating func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(strokes)
        strokes = next
    }
}

public enum ImageMarkupRenderer {
    public static func sourceImage(from image: NSImage) -> CGImage? {
        // Preserve Retina pixels rather than rasterizing at NSImage's point size.
        image.representations.compactMap { ($0 as? NSBitmapImageRep)?.cgImage }
            .max { $0.width * $0.height < $1.width * $1.height }
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    public static func draw(_ strokes: [ImageMarkupStroke], in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        // Clear eraser pixels inside the markup layer, never the source image.
        context.setBlendMode(.normal)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            context.setBlendMode(stroke.isEraser ? .clear : .normal)
            context.setStrokeColor(stroke.color.cgColor)
            context.setFillColor(stroke.color.cgColor)
            context.setLineWidth(stroke.width)
            if stroke.points.count == 1, let point = stroke.points.first {
                context.fillEllipse(in: CGRect(x: point.x - stroke.width / 2, y: point.y - stroke.width / 2,
                                              width: stroke.width, height: stroke.width))
            } else {
                drawPath(stroke.points, in: context)
            }
            drawPath(stroke.arrowPoints, in: context)
        }
    }

    public static func pngData(image: CGImage, strokes: [ImageMarkupStroke]) -> Data? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        draw(strokes, in: context)
        guard let result = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])
    }

    private static func drawPath(_ points: [CGPoint], in context: CGContext) {
        guard points.count > 1, let first = points.first else { return }
        context.beginPath()
        context.move(to: first)
        for point in points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }
}
