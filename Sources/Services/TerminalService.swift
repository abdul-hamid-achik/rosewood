import Foundation

@MainActor
final class TerminalService: ObservableObject {
    static let shared = TerminalService()

    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var currentSessionId: UUID?

    private init() {}

    // MARK: - Session Management

    func createSession(type: TerminalSessionType, workingDirectory: URL? = nil) -> TerminalSession {
        let session = TerminalSession(type: type, workingDirectory: workingDirectory)
        sessions.append(session)
        setCurrentSession(id: session.id)
        return session
    }

    func selectSession(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        setCurrentSession(id: id)
    }

    func closeSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        // Kill the PTY/process exactly when the session closes (a no-op if none was spawned),
        // BEFORE dropping the metadata.
        TerminalProcessController.shared.terminate(id)
        sessions.remove(at: index)

        if currentSessionId == id {
            setCurrentSession(id: sessions.last?.id)
        } else {
            updateSessionActivity()
        }
    }

    func currentSession() -> TerminalSession? {
        guard let id = currentSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    private func setCurrentSession(id: UUID?) {
        currentSessionId = id
        updateSessionActivity()
    }

    private func updateSessionActivity() {
        for index in sessions.indices {
            sessions[index].isActive = sessions[index].id == currentSessionId
        }
    }
}
