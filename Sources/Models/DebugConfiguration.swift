import Foundation

struct DebugConfiguration: Codable, Equatable, Identifiable {
    let name: String
    let adapter: String
    let program: String
    let cwd: String?
    let args: [String]
    let preLaunchTask: String?
    let stopOnEntry: Bool

    var id: String {
        name
    }

    func resolvedProgramURL(relativeTo projectRoot: URL) -> URL {
        resolveURL(for: program, relativeTo: projectRoot)
    }

    func resolvedWorkingDirectoryURL(relativeTo projectRoot: URL) -> URL {
        guard let cwd, !cwd.isEmpty else { return projectRoot }
        return resolveURL(for: cwd, relativeTo: projectRoot)
    }

    private func resolveURL(for path: String, relativeTo projectRoot: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return projectRoot.appendingPathComponent(path).standardizedFileURL
    }
}

struct DebugProjectConfiguration: Equatable {
    var defaultConfiguration: String?
    var configurations: [DebugConfiguration]

    static let empty = DebugProjectConfiguration(defaultConfiguration: nil, configurations: [])
}

struct DebugConsoleEntry: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case info
        case success
        case warning
        case error
    }

    let id: UUID
    let kind: Kind
    let message: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.timestamp = timestamp
    }
}
