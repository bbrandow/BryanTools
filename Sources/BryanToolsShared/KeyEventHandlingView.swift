import AppKit
import SwiftUI

public struct KeyEventHandlingView: NSViewRepresentable {
    public var handler: (NSEvent) -> Bool

    public init(handler: @escaping (NSEvent) -> Bool) {
        self.handler = handler
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view] event in
            guard let window = view?.window,
                  (event.window ?? NSApp.keyWindow) === window else {
                return event
            }
            return context.coordinator.handler(event) ? nil : event
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    public final class Coordinator {
        var handler: (NSEvent) -> Bool
        var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        deinit {
            removeMonitor()
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
