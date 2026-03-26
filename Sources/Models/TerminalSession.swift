import Foundation

enum TerminalSessionType: Equatable {
    case local(shell: String)
    case dockerExec(containerId: String, user: String? = nil)
    case dockerComposeExec(projectPath: URL, service: String, user: String? = nil)

    var defaultTitle: String {
        switch self {
        case .local(let shell):
            return URL(fileURLWithPath: shell).deletingPathExtension().lastPathComponent
        case .dockerExec(let containerId, _):
            return "docker: \(containerId.prefix(12))"
        case .dockerComposeExec(_, let service, _):
            return "compose: \(service)"
        }
    }

    var displayName: String {
        switch self {
        case .local(let shell):
            return "Local (\(URL(fileURLWithPath: shell).lastPathComponent))"
        case .dockerExec(let containerId, _):
            return "Docker Exec (\(containerId.prefix(12)))"
        case .dockerComposeExec(_, let service, _):
            return "Compose: \(service)"
        }
    }

    var iconName: String {
        switch self {
        case .local: return "terminal"
        case .dockerExec: return "container"
        case .dockerComposeExec: return "doc.text.fill"
        }
    }
}

struct TerminalSession: Identifiable, Equatable {
    let id: UUID
    let type: TerminalSessionType
    let createdAt: Date

    var title: String
    var isActive: Bool = true
    var processId: Int32?

    init(type: TerminalSessionType, title: String? = nil) {
        self.id = UUID()
        self.type = type
        self.title = title ?? type.defaultTitle
        self.createdAt = Date()
    }

    var displayName: String {
        title
    }

    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id
    }
}