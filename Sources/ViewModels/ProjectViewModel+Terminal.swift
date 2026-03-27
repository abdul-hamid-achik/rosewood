import Foundation

extension ProjectViewModel {
    
    // MARK: - Terminal Service Reference
    
    private var terminalService: TerminalService {
        TerminalService.shared
    }

    private func syncTerminalSessions() {
        terminalSessions = terminalService.sessions
        currentTerminalSessionId = terminalService.currentSessionId
    }
    
    // MARK: - Terminal Actions
    
    func toggleTerminalPanel() {
        if bottomPanel == .terminal {
            bottomPanel = nil
        } else {
            if terminalSessions.isEmpty {
                createTerminalSession()
            }
            bottomPanel = .terminal
        }
    }
    
    func createTerminalSession(type: TerminalSessionType? = nil) {
        let sessionType = type ?? .local(shell: configService.settings.docker.terminalShell)
        _ = terminalService.createSession(type: sessionType)
        syncTerminalSessions()
    }

    func selectTerminalSession(_ id: UUID) {
        terminalService.selectSession(id)
        syncTerminalSessions()
    }

    func closeTerminalSession(_ id: UUID) {
        terminalService.closeSession(id)
        syncTerminalSessions()
    }
    
    func closeCurrentTerminalSession() {
        guard let id = currentTerminalSessionId else { return }
        closeTerminalSession(id)
    }
    
    // MARK: - Quick Terminal Actions
    
    func openLocalTerminal() {
        createTerminalSession(type: .local(shell: configService.settings.docker.terminalShell))
        bottomPanel = .terminal
    }
    
    func openDockerTerminal(in container: DockerContainer) {
        createTerminalSession(type: .dockerExec(containerId: container.id))
        bottomPanel = .terminal
    }
    
    func openComposeTerminal(projectPath: URL, service: String) {
        createTerminalSession(type: .dockerComposeExec(projectPath: projectPath, service: service))
        bottomPanel = .terminal
    }
}
