import AppKit
import BryanToolsShared

final class ShotFloatImageView: NSView, NSTextFieldDelegate {
    static let topBarHeight: CGFloat = 40
    private static let toolbarMinimumWidth: CGFloat = 380

    let image: NSImage
    var onClose: (() -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?

    private enum Tool: Int { case move, draw, erase }
    private let sourceImage: CGImage?
    private var zoom: CGFloat
    private var document = ImageMarkupDocument()
    private var tool = Tool.move
    private var draftStroke: ImageMarkupStroke?
    private var eraserLocation: CGPoint?
    private var imageTrackingArea: NSTrackingArea?
    private var strokeWidth = ImageMarkupStroke.defaultWidth
    private var copyTask: Task<Void, Never>?
    private static let eraserCursor = NSCursor(
        image: NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true },
        hotSpot: .zero
    )

    private let toolbar = NSStackView()
    private let toolSelector = ShotFloatSegmentedControl()
    private let widthField = NSTextField(string: "\(Int(ImageMarkupStroke.defaultWidth))")
    private let colorWell = ShotFloatColorWell()
    private let arrowButton = ShotFloatToolbarButton()
    private let undoButton = ShotFloatToolbarButton()
    private let redoButton = ShotFloatToolbarButton()
    private let copyButton = ShotFloatToolbarButton()
    private let closeButton = ShotFloatToolbarButton()

    init(image: NSImage, zoom: CGFloat) {
        self.image = image
        self.sourceImage = ImageMarkupRenderer.sourceImage(from: image)
        self.zoom = zoom
        super.init(frame: NSRect(origin: .zero, size: Self.contentSize(for: image, zoom: zoom)))
        configureToolbar()
        setAccessibilityLabel("Floating screenshot")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func dispose() {
        copyTask?.cancel()
        copyTask = nil
        colorWell.deactivate()
    }

    private var pixelSize: CGSize {
        guard let sourceImage else { return Self.validImageSize(image) }
        return CGSize(width: sourceImage.width, height: sourceImage.height)
    }

    private var imageRect: CGRect {
        let size = Self.validImageSize(image)
        let width = size.width * zoom
        return CGRect(x: (bounds.width - width) / 2, y: 0, width: width, height: size.height * zoom)
    }

    private var visibleStrokes: [ImageMarkupStroke] {
        if let draftStroke { return document.strokes + [draftStroke] }
        return document.strokes
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: imageRect)
        if let sourceImage {
            context.interpolationQuality = .high
            context.draw(sourceImage, in: imageRect)
        } else {
            image.draw(in: imageRect)
        }
        context.translateBy(x: imageRect.minX, y: imageRect.minY)
        context.scaleBy(x: imageRect.width / pixelSize.width, y: imageRect.height / pixelSize.height)
        ImageMarkupRenderer.draw(visibleStrokes, in: context)
        context.restoreGState()
        drawEraserPreview(in: context)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - Self.topBarHeight, width: bounds.width, height: 1).fill()
    }

    override func resetCursorRects() {
        let cursor: NSCursor = tool == .move ? .openHand : tool == .erase ? Self.eraserCursor : .crosshair
        addCursorRect(imageRect, cursor: cursor)
    }

    override func updateTrackingAreas() {
        if let imageTrackingArea { removeTrackingArea(imageTrackingArea) }
        let area = NSTrackingArea(rect: imageRect, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        imageTrackingArea = area
        super.updateTrackingAreas()
        updateEraserLocation()
    }

    override func mouseMoved(with event: NSEvent) {
        eraserLocation = convert(event.locationInWindow, from: nil)
        if tool == .erase { needsDisplay = true }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        eraserLocation = nil
        if tool == .erase { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        guard imageRect.contains(location), tool != .move else {
            window?.performDrag(with: event)
            return
        }
        let point = imagePoint(for: event)
        if tool == .draw {
            draftStroke = ImageMarkupStroke(points: [point], width: strokeWidth, color: colorWell.color,
                                            hasArrow: arrowButton.state == .on)
        } else {
            draftStroke = .eraser(points: [point], brushWidth: strokeWidth)
            eraserLocation = location
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(for: event)
        if let last = draftStroke?.points.last {
            if hypot(point.x - last.x, point.y - last.y) >= 0.5 {
                draftStroke?.points.append(point)
            }
        }
        if tool == .erase { eraserLocation = convert(event.locationInWindow, from: nil) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if draftStroke != nil { mouseDragged(with: event) }
        finishGesture()
    }

    override func scrollWheel(with event: NSEvent) {
        guard draftStroke == nil else { return }
        let direction = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        guard direction != 0 else { return }
        let size = Self.validImageSize(image)
        let longestSide = max(size.width, size.height)
        zoom = min(max(zoom * (direction > 0 ? 1.08 : 0.925), 120 / longestSide), 2_400 / longestSide)
        onZoomChange?(zoom)
        updateEraserLocation()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Leave text-field copy/undo to its field editor.
        guard window?.firstResponder === self,
              event.modifierFlags.intersection([.command, .control, .option]) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z":
            if event.modifierFlags.contains(.shift) { redoMarkup() } else { undoMarkup() }
            return true
        case "c": copyImage(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    static func contentSize(for image: NSImage, zoom: CGFloat) -> NSSize {
        let size = validImageSize(image)
        return NSSize(width: max(toolbarMinimumWidth, size.width * zoom),
                      height: max(1, size.height * zoom) + topBarHeight)
    }

    static func validImageSize(_ image: NSImage) -> NSSize {
        let size = image.size
        return size.width > 0 && size.height > 0 ? size : NSSize(width: 320, height: 240)
    }

    private func imagePoint(for event: NSEvent) -> CGPoint {
        let location = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: (location.x - imageRect.minX) * pixelSize.width / imageRect.width,
            y: (location.y - imageRect.minY) * pixelSize.height / imageRect.height
        )
    }

    private func updateEraserLocation() {
        if let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            eraserLocation = imageRect.contains(point) ? point : nil
        } else {
            eraserLocation = nil
        }
        needsDisplay = true
    }

    private func drawEraserPreview(in context: CGContext) {
        guard tool == .erase, let eraserLocation else { return }
        let diameter = strokeWidth * ImageMarkupStroke.eraserWidthMultiplier
        let size = CGSize(width: diameter * imageRect.width / pixelSize.width,
                          height: diameter * imageRect.height / pixelSize.height)
        let rect = CGRect(x: eraserLocation.x - size.width / 2, y: eraserLocation.y - size.height / 2,
                          width: size.width, height: size.height)
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: imageRect)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: rect)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: rect)
    }

    private func finishGesture() {
        if let draftStroke { document.add(draftStroke) }
        draftStroke = nil
        updateHistoryButtons()
        needsDisplay = true
    }

    private func configureToolbar() {
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 4
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            toolbar.heightAnchor.constraint(equalToConstant: 28)
        ])

        toolSelector.segmentCount = 3
        toolSelector.trackingMode = .selectOne
        toolSelector.segmentStyle = .rounded
        toolSelector.controlSize = .small
        for (index, entry) in [("hand.raised", "Move window"), ("pencil.tip", "Draw"), ("eraser", "Erase markup (4x the brush width)")].enumerated() {
            toolSelector.setImage(NSImage(systemSymbolName: entry.0, accessibilityDescription: entry.1), forSegment: index)
            toolSelector.setToolTip(entry.1, forSegment: index)
            toolSelector.setWidth(26, forSegment: index)
        }
        toolSelector.selectedSegment = tool.rawValue
        toolSelector.target = self
        toolSelector.action = #selector(changeTool)
        toolbar.addArrangedSubview(toolSelector)

        widthField.alignment = .right
        widthField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        widthField.controlSize = .small
        widthField.toolTip = "Stroke width in original-image pixels (1-100)"
        widthField.setAccessibilityLabel("Stroke width in pixels")
        widthField.target = self
        widthField.action = #selector(changeWidth)
        widthField.delegate = self
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 100
        widthField.formatter = formatter
        addControl(widthField, width: 40)
        let pixelsLabel = NSTextField(labelWithString: "px")
        pixelsLabel.font = .systemFont(ofSize: 11)
        pixelsLabel.textColor = .secondaryLabelColor
        addControl(pixelsLabel, width: 14, height: 16)

        colorWell.color = .systemRed
        colorWell.colorWellStyle = .minimal
        colorWell.toolTip = "Markup color"
        colorWell.setAccessibilityLabel("Markup color")
        addControl(colorWell, width: 28)
        configureButton(arrowButton, symbol: "arrow.up.right", label: "Arrow at end of stroke", action: #selector(toggleArrow))
        arrowButton.setButtonType(.pushOnPushOff)
        configureButton(undoButton, symbol: "arrow.uturn.backward", label: "Undo markup (Command-Z)", action: #selector(undoMarkup))
        configureButton(redoButton, symbol: "arrow.uturn.forward", label: "Redo markup (Shift-Command-Z)", action: #selector(redoMarkup))
        configureButton(copyButton, symbol: "doc.on.doc", label: "Copy image as PNG (Command-C)", action: #selector(copyImage))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(spacer)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true
        configureButton(closeButton, symbol: "xmark", label: "Close floating image", action: #selector(closeImage))
        updateHistoryButtons()
    }

    private func addControl(_ control: NSView, width: CGFloat, height: CGFloat = 24) {
        toolbar.addArrangedSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: width).isActive = true
        control.heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    private func configureButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = action
        addControl(button, width: 28)
    }

    private func updateHistoryButtons() {
        undoButton.isEnabled = document.canUndo
        redoButton.isEnabled = document.canRedo
        copyButton.isEnabled = sourceImage != nil && copyTask == nil
    }

    @objc private func changeTool() {
        finishGesture()
        tool = Tool(rawValue: toolSelector.selectedSegment) ?? .move
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        updateEraserLocation()
    }

    @objc private func toggleArrow() {
        toolSelector.selectedSegment = Tool.draw.rawValue
        changeTool()
    }

    @objc private func changeWidth() {
        let value = widthField.doubleValue
        if value.isFinite, (1...100).contains(value) { strokeWidth = CGFloat(value.rounded()) }
        widthField.integerValue = Int(strokeWidth)
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) { changeWidth() }

    @objc private func undoMarkup() {
        finishGesture()
        document.undo()
        updateHistoryButtons()
        needsDisplay = true
    }

    @objc private func redoMarkup() {
        finishGesture()
        document.redo()
        updateHistoryButtons()
        needsDisplay = true
    }

    @objc private func closeImage() { onClose?() }

    @objc private func copyImage() {
        guard let sourceImage, copyTask == nil else { return }
        finishGesture()
        let strokes = document.strokes
        copyButton.isEnabled = false
        copyTask = Task { [weak self] in
            let data = await Task.detached(priority: .userInitiated) {
                ImageMarkupRenderer.pngData(image: sourceImage, strokes: strokes)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.copyTask = nil
            self.updateHistoryButtons()
            guard let data else {
                self.copyFailed()
                return
            }
            let item = NSPasteboardItem()
            guard item.setData(data, forType: .png) else {
                self.copyFailed()
                return
            }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([item]) else {
                self.copyFailed()
                return
            }
            self.copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied PNG")
            self.copyButton.toolTip = "Copied PNG"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy image as PNG")
                self?.copyButton.toolTip = "Copy image as PNG (Command-C)"
            }
        }
    }

    private func copyFailed() {
        copyButton.toolTip = "Unable to copy PNG. Click to retry."
        NSSound.beep()
    }
}

// Toolbar actions must also work on the first click when another app has focus.
private final class ShotFloatToolbarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ShotFloatSegmentedControl: NSSegmentedControl {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ShotFloatColorWell: NSColorWell {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
