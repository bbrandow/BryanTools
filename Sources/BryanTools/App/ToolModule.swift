import BryanToolsShared
import SwiftUI

@MainActor
protocol ToolModule: AnyObject {
    var id: ToolIdentifier { get }
    var displayName: String { get }
    var systemImage: String { get }

    func start()
    func stop()
    func menuContent() -> AnyView
    func settingsView() -> AnyView
}
