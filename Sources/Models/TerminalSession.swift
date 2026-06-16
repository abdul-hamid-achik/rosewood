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
    /// The working directory captured at creation time, so a later project-folder switch does not
    /// change an already-spawned terminal's cwd. Nil falls back to the home directory at launch.
    let workingDirectory: URL?

    var title: String
    var isActive: Bool = true
    var processId: Int32?

    init(type: TerminalSessionType, title: String? = nil, workingDirectory: URL? = nil) {
        self.id = UUID()
        self.type = type
        self.title = title ?? type.defaultTitle
        self.createdAt = Date()
        self.workingDirectory = workingDirectory
    }

    var displayName: String {
        title
    }

    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.isActive == rhs.isActive
            && lhs.processId == rhs.processId
            && lhs.type == rhs.type
            && lhs.workingDirectory == rhs.workingDirectory
    }
}
