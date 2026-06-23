import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class VehicleMotionCuesModule: NSObject, ObservableObject, ToolModule {
    static let shared = VehicleMotionCuesModule(controller: SystemVehicleMotionCuesController())

    let id = ToolIdentifier.vehicleMotionCues
    let displayName = ToolIdentifier.vehicleMotionCues.displayName
    let systemImage = "car.side"

    @Published private(set) var snapshot = VehicleMotionCuesSnapshot(isSupported: true, isEnabled: false, isActive: false)
    @Published var lastErrorMessage: String?

    private let controller: SystemVehicleMotionCuesController
    private var isRunning = false

    private init(controller: SystemVehicleMotionCuesController) {
        self.controller = controller
        super.init()
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        refresh(reconcileRuntime: true)
    }

    func stop() {
        isRunning = false
    }

    func menuContent() -> AnyView {
        AnyView(EmptyView())
    }

    func settingsView() -> AnyView {
        AnyView(EmptyView())
    }

    func refresh() {
        refresh(reconcileRuntime: false)
    }

    func toggleEnabled() {
        do {
            snapshot = try controller.toggleEnabled()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refresh(reconcileRuntime: Bool) {
        do {
            snapshot = try controller.snapshot(reconcileActiveState: reconcileRuntime)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
