import Foundation
import AppKit
import Combine

@MainActor
final class TerminalService: ObservableObject {
    static let shared = TerminalService()
    
    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var currentSessionId: UUID?
    
    private let configService: ConfigurationService
    
    private init() {
        configService = ConfigurationService.shared
    }
    
    // MARK: - Session Management
    
    func createSession(type: TerminalSessionType) -> TerminalSession {
        let session = TerminalSession(type: type)
        sessions.append(session)
        
        if currentSessionId == nil {
            currentSessionId = session.id
        }
        
        return session
    }
    
    func selectSession(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentSessionId = id
    }
    
    func closeSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        
        sessions.remove(at: index)
        
        if currentSessionId == id {
            currentSessionId = sessions.last?.id
        }
    }
    
    func currentSession() -> TerminalSession? {
        guard let id = currentSessionId else { return nil }
        return sessions.first { $0.id == id }
    }
}