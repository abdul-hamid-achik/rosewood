import Foundation

enum DockerContainerStatus: String, Codable {
    case running = "running"
    case paused = "paused"
    case exited = "exited"
    case created = "created"
    case dead = "dead"
    case removing = "removing"
    case restarting = "restarting"

    var icon: String {
        switch self {
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .exited, .created: return "stop.circle"
        case .dead: return "xmark.circle.fill"
        case .removing: return "arrow.triangle.2.circlepath"
        case .restarting: return "arrow.triangle.2.circlepath"
        }
    }

    var displayText: String {
        switch self {
        case .running: return "Running"
        case .paused: return "Paused"
        case .exited: return "Exited"
        case .created: return "Created"
        case .dead: return "Dead"
        case .removing: return "Removing"
        case .restarting: return "Restarting"
        }
    }
}

struct DockerPort: Hashable, Codable {
    let containerPort: Int
    let hostPort: Int?
    let protocolType: String

    var display: String {
        if let hostPort = hostPort {
            return "\(hostPort):\(containerPort)"
        }
        return "\(containerPort)"
    }
}

struct DockerContainer: Identifiable, Hashable, Codable {
    let id: String
    let names: [String]
    let image: String
    let imageId: String
    let status: DockerContainerStatus
    let state: String
    let ports: [DockerPort]
    let created: Date
    let labels: [String: String]

    var displayName: String {
        names.first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? shortId
    }

    var shortId: String { String(id.prefix(12)) }

    var isComposeService: Bool {
        labels["com.docker.compose.project"] != nil
    }

    var composeProject: String? {
        labels["com.docker.compose.project"]
    }

    var composeService: String? {
        labels["com.docker.compose.service"]
    }
}

struct DockerImage: Identifiable, Hashable, Codable {
    let id: String
    let repoTags: [String]
    let size: Int64
    let created: Date
    let labels: [String: String]

    var displayName: String {
        if let tag = repoTags.first, tag != "<none>:<none>" {
            return tag
        }
        return shortId
    }

    var shortId: String {
        String(id.replacingOccurrences(of: "sha256:", with: "").prefix(12))
    }

    var sizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct DockerVolume: Identifiable, Hashable, Codable {
    let name: String
    let driver: String
    let mountpoint: String
    let scope: String

    var id: String { name }
}

struct DockerComposeProject: Identifiable, Hashable {
    let id: String
    let name: String
    let configPath: URL
    let workingDirectory: URL
    let configFileName: String
    var services: [DockerComposeService]

    var runningCount: Int {
        services.filter { $0.state == .running }.count
    }

    var totalServices: Int {
        services.count
    }
}

struct DockerComposeService: Identifiable, Hashable {
    let id: String
    let name: String
    let containerId: String?
    let state: DockerContainerStatus
    let ports: [DockerPort]

    init(name: String, state: DockerContainerStatus = .created, ports: [DockerPort] = []) {
        self.id = name
        self.name = name
        self.containerId = nil
        self.state = state
        self.ports = ports
    }

    init(from container: DockerContainer) {
        self.id = container.composeService ?? container.names.first ?? container.id
        self.name = container.composeService ?? container.displayName
        self.containerId = container.id
        self.state = container.status
        self.ports = container.ports
    }
}

enum DockerConnectionState: Equatable {
    case connected
    case connecting
    case reconnecting(timeLeft: Int, attempt: Int)
    case disconnected(error: String)
    case notInstalled

    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reconnecting(let timeLeft, let attempt):
            return "Reconnecting in \(timeLeft)s (attempt \(attempt))"
        case .disconnected(let error): return "Disconnected: \(error)"
        case .notInstalled: return "Docker not installed"
        }
    }
}

struct LogLine: Identifiable, Hashable {
    let id: UUID
    let text: String
    let timestamp: Date
    let stream: LogStream

    init(text: String, stream: LogStream = .stdout) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.stream = stream
    }
}

enum LogStream: String, Codable {
    case stdout
    case stderr
}