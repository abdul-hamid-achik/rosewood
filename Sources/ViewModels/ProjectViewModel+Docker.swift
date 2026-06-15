import Foundation
import SwiftUI

extension ProjectViewModel {
    // Docker state/actions now live on `dockerModel` (DockerModel). These two methods stay on
    // the core view model because they mutate shared chrome state (bottomPanel) and the terminal.

    // MARK: - Terminal Integration

    func openTerminalInContainer(_ container: DockerContainer) {
        createTerminalSession(type: .dockerExec(containerId: container.id))
        bottomPanel = .terminal
    }

    // MARK: - Log Viewing

    func showContainerLogs(_ container: DockerContainer) {
        dockerModel.selectedContainer = container
        bottomPanel = .dockerLogs
    }
}
