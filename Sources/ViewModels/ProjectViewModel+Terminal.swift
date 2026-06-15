import Foundation

extension ProjectViewModel {
    // Terminal session state/management now lives on `terminalModel` (TerminalModel).
    // These methods stay on the core view model because they mutate shared chrome (bottomPanel);
    // they delegate the session work to terminalModel.

    func toggleTerminalPanel() {
        if bottomPanel == .terminal {
            bottomPanel = nil
        } else {
            if terminalModel.terminalSessions.isEmpty {
                terminalModel.createTerminalSession()
            }
            bottomPanel = .terminal
        }
    }

    // MARK: - Quick Terminal Actions

    func openLocalTerminal() {
        terminalModel.createTerminalSession(type: .local(shell: configService.settings.docker.terminalShell))
        bottomPanel = .terminal
    }

    func openDockerTerminal(in container: DockerContainer) {
        terminalModel.createTerminalSession(type: .dockerExec(containerId: container.id))
        bottomPanel = .terminal
    }

    func openComposeTerminal(projectPath: URL, service: String) {
        terminalModel.createTerminalSession(type: .dockerComposeExec(projectPath: projectPath, service: service))
        bottomPanel = .terminal
    }
}
