import Foundation

enum DebugSessionEvent: Equatable, Sendable {
    case output(DebugConsoleEntry.Kind, String)
    case state(DebugSessionState)
    case stopped(filePath: String?, line: Int?, reason: String)
    case terminated
}

struct DebugSessionStartResult: Equatable {
    let adapterPath: String
    let programPath: String
    let workingDirectoryPath: String
    let executedPreLaunchTask: Bool
}

enum DebugSessionServiceError: LocalizedError, Equatable {
    case missingProjectRoot
    case unsupportedAdapter(String)
    case missingProgram(String)
    case preLaunchTaskFailed(String)
    case adapterUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingProjectRoot:
            return "Open a folder before starting the debugger."
        case .unsupportedAdapter(let adapter):
            return "The adapter \"\(adapter)\" is not supported yet."
        case .missingProgram(let path):
            return "The configured program does not exist at \(path)."
        case .preLaunchTaskFailed(let message):
            return message
        case .adapterUnavailable(let message):
            return message
        }
    }
}

@MainActor
protocol DebugSessionServiceProtocol: AnyObject {
    func setEventHandler(_ handler: @escaping @Sendable (DebugSessionEvent) -> Void)
    func start(
        configuration: DebugConfiguration,
        projectRoot: URL?,
        breakpoints: [Breakpoint]
    ) async throws -> DebugSessionStartResult
    func updateBreakpoints(_ breakpoints: [Breakpoint], projectRoot: URL?) async
    func stop() async
}

final class DebugSessionService: DebugSessionServiceProtocol {
    static let shared = DebugSessionService()

    private let adapterLocator: DAPAdapterLocator
    private var clientFactory: (String, URL) throws -> DAPClient
    private var activeClient: DAPClient?
    private var eventHandler: (@Sendable (DebugSessionEvent) -> Void)?
    private var activeProjectRoot: URL?

    init(
        adapterLocator: DAPAdapterLocator = DAPAdapterLocator(),
        clientFactory: @escaping (String, URL) throws -> DAPClient = { adapterPath, workingDirectory in
            try DAPClient.spawn(adapterPath: adapterPath, workingDirectory: workingDirectory)
        }
    ) {
        self.adapterLocator = adapterLocator
        self.clientFactory = clientFactory
    }

    func setEventHandler(_ handler: @escaping @Sendable (DebugSessionEvent) -> Void) {
        eventHandler = handler
    }

    func start(
        configuration: DebugConfiguration,
        projectRoot: URL?,
        breakpoints: [Breakpoint]
    ) async throws -> DebugSessionStartResult {
        guard let projectRoot else {
            throw DebugSessionServiceError.missingProjectRoot
        }

        await stop()
        eventHandler?(.state(.starting))

        let prepared = try await prepare(
            configuration: configuration,
            projectRoot: projectRoot
        )

        let client: DAPClient
        switch configuration.adapter.lowercased() {
        case "lldb":
            client = try clientFactory(
                prepared.adapterPath,
                URL(fileURLWithPath: prepared.workingDirectoryPath)
            )
        default:
            throw DebugSessionServiceError.unsupportedAdapter(configuration.adapter)
        }

        await client.setOnEvent { [weak self] event in
            Task { @MainActor in
                self?.handleClientEvent(event)
            }
        }

        activeProjectRoot = projectRoot
        activeClient = client

        eventHandler?(.output(.info, "Starting \(configuration.name)..."))
        try await client.startSession(
            projectRoot: projectRoot,
            configuration: configuration,
            breakpoints: breakpoints
        )

        eventHandler?(.state(.running))
        eventHandler?(.output(.success, "Debug session started."))
        return DebugSessionStartResult(
            adapterPath: prepared.adapterPath,
            programPath: prepared.programPath,
            workingDirectoryPath: prepared.workingDirectoryPath,
            executedPreLaunchTask: prepared.executedPreLaunchTask
        )
    }

    func updateBreakpoints(_ breakpoints: [Breakpoint], projectRoot: URL?) async {
        guard activeProjectRoot == projectRoot, let activeClient else { return }
        do {
            try await activeClient.updateBreakpoints(breakpoints)
            eventHandler?(.output(.info, "Updated \(breakpoints.count) breakpoint\(breakpoints.count == 1 ? "" : "s")."))
        } catch {
            eventHandler?(.output(.warning, "Could not update breakpoints: \(error.localizedDescription)"))
        }
    }

    func stop() async {
        guard let activeClient else { return }
        eventHandler?(.state(.stopping))
        await activeClient.disconnect()
        self.activeClient = nil
        activeProjectRoot = nil
        eventHandler?(.state(.idle))
    }

    private func handleClientEvent(_ event: DAPClientEvent) {
        switch event {
        case .output(let output):
            let trimmed = output.trimmingCharacters(in: .newlines)
            guard !trimmed.isEmpty else { return }
            eventHandler?(.output(.info, trimmed))
        case .running:
            eventHandler?(.state(.running))
        case let .stopped(filePath, line, reason):
            eventHandler?(.state(.paused))
            eventHandler?(.stopped(filePath: filePath, line: line, reason: reason))
        case .terminated:
            activeClient = nil
            activeProjectRoot = nil
            eventHandler?(.terminated)
            eventHandler?(.state(.idle))
        }
    }

    private func prepare(
        configuration: DebugConfiguration,
        projectRoot: URL
    ) async throws -> DebugSessionStartResult {
        let workingDirectory = configuration.resolvedWorkingDirectoryURL(relativeTo: projectRoot)
        let programURL = configuration.resolvedProgramURL(relativeTo: projectRoot)

        var executedPreLaunchTask = false
        if let preLaunchTask = configuration.preLaunchTask?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preLaunchTask.isEmpty {
            executedPreLaunchTask = true
            eventHandler?(.output(.info, "Running preLaunchTask..."))
            try await runShellCommand(preLaunchTask, in: workingDirectory)
        }

        guard FileManager.default.fileExists(atPath: programURL.path) else {
            throw DebugSessionServiceError.missingProgram(programURL.path)
        }

        let adapterPath: String
        switch configuration.adapter.lowercased() {
        case "lldb":
            do {
                adapterPath = try adapterLocator.preflightLLDBDAP().adapterPath
            } catch {
                throw DebugSessionServiceError.adapterUnavailable(error.localizedDescription)
            }
        default:
            throw DebugSessionServiceError.unsupportedAdapter(configuration.adapter)
        }

        return DebugSessionStartResult(
            adapterPath: adapterPath,
            programPath: programURL.path,
            workingDirectoryPath: workingDirectory.path,
            executedPreLaunchTask: executedPreLaunchTask
        )
    }

    private func runShellCommand(_ command: String, in workingDirectory: URL) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                throw DebugSessionServiceError.preLaunchTaskFailed(
                    "Failed to start preLaunchTask: \(error.localizedDescription)"
                )
            }

            process.waitUntilExit()

            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus != 0 {
                let message = stderr.isEmpty ? "preLaunchTask failed with exit code \(process.terminationStatus)." : stderr
                throw DebugSessionServiceError.preLaunchTaskFailed(message)
            }

            _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }
}

@MainActor
final class MockDebugSessionService: DebugSessionServiceProtocol {
    var nextStartResult: Result<DebugSessionStartResult, Error> = .failure(DebugSessionServiceError.missingProjectRoot)
    private(set) var eventHandler: ((DebugSessionEvent) -> Void)?
    private(set) var startCalls: [(configuration: DebugConfiguration, projectRoot: URL?, breakpoints: [Breakpoint])] = []
    private(set) var updateBreakpointCalls: [[Breakpoint]] = []
    private(set) var stopCallCount: Int = 0

    func setEventHandler(_ handler: @escaping @Sendable (DebugSessionEvent) -> Void) {
        eventHandler = handler
    }

    func start(
        configuration: DebugConfiguration,
        projectRoot: URL?,
        breakpoints: [Breakpoint]
    ) async throws -> DebugSessionStartResult {
        startCalls.append((configuration, projectRoot, breakpoints))
        switch nextStartResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    func updateBreakpoints(_ breakpoints: [Breakpoint], projectRoot: URL?) async {
        updateBreakpointCalls.append(breakpoints)
    }

    func stop() async {
        stopCallCount += 1
    }
}
