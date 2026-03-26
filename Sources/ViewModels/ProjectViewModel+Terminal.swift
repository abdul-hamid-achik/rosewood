import Foundation

extension ProjectViewModel {
    
    // MARK: - Terminal Service Reference
    
    private var terminalService: TerminalService {
        TerminalService.shared
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
        let session = TerminalService.shared.createSession(type: sessionType)
        terminalSessions = terminalService.sessions
        currentTerminalSessionId = session.id
    }
    
    func selectTerminalSession(_ id: UUID) {
        TerminalService.shared.selectSession(id)
        currentTerminalSessionId = id
    }
    
    func closeTerminalSession(_ id: UUID) {
        TerminalService.shared.closeSession(id)
        terminalSessions = terminalService.sessions
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