import Foundation

/// Owns terminal-session state, extracted from ProjectViewModel so terminal session changes
/// only re-render the terminal panel rather than every view observing the app-wide view model.
/// Injected as its own @EnvironmentObject. Methods that toggle the bottom panel stay on
/// ProjectViewModel (shared chrome) and delegate session work here.
@MainActor
final class TerminalModel: ObservableObject {
    @Published var terminalSessions: [TerminalSession] = []
    @Published var currentTerminalSessionId: UUID?

    private let configService: ConfigurationService

    init(configService: ConfigurationService) {
        self.configService = configService
    }

    private var terminalService: TerminalService {
        TerminalService.shared
    }

    private func syncTerminalSessions() {
        terminalSessions = terminalService.sessions
        currentTerminalSessionId = terminalService.currentSessionId
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
}
