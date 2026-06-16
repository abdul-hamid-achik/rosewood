import Foundation

enum DebugSessionEvent: Equatable, Sendable {
    case output(DebugConsoleEntry.Kind, String)
    case state(DebugSessionState)
    case stopped(filePath: String?, line: Int?, reason: String)
    case callStack([DAPStackFrame])
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
    func resume() async
    func stepOver() async
    func stepInto() async
    func stepOut() async
    func pause() async
    func scopes(frameId: Int) async -> [DAPScope]
    func variables(reference: Int) async -> [DAPVariable]
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

    // Execution control. The DAPClient transitions to .running (emitting .running, which maps to
    // .state(.running)) so we don't optimistically emit it here; failures surface as a console warning.
    func resume() async {
        guard let activeClient else { return }
        do { try await activeClient.resume() } catch {
            eventHandler?(.output(.warning, "Could not continue: \(error.localizedDescription)"))
        }
    }

    func stepOver() async {
        guard let activeClient else { return }
        do { try await activeClient.stepOver() } catch {
            eventHandler?(.output(.warning, "Could not step over: \(error.localizedDescription)"))
        }
    }

    func stepInto() async {
        guard let activeClient else { return }
        do { try await activeClient.stepInto() } catch {
            eventHandler?(.output(.warning, "Could not step into: \(error.localizedDescription)"))
        }
    }

    func stepOut() async {
        guard let activeClient else { return }
        do { try await activeClient.stepOut() } catch {
            eventHandler?(.output(.warning, "Could not step out: \(error.localizedDescription)"))
        }
    }

    func pause() async {
        guard let activeClient else { return }
        do { try await activeClient.pause() } catch {
            eventHandler?(.output(.warning, "Could not pause: \(error.localizedDescription)"))
        }
    }

    func scopes(frameId: Int) async -> [DAPScope] {
        guard let activeClient else { return [] }
        return await activeClient.scopes(frameId: frameId)
    }

    func variables(reference: Int) async -> [DAPVariable] {
        guard let activeClient else { return [] }
        return await activeClient.variables(reference: reference)
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
        case .callStack(let frames):
            eventHandler?(.callStack(frames))
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
            let result: ProcessRunnerResult
            do {
                result = try ProcessRunner.run(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: ["-lc", command],
                    currentDirectoryURL: workingDirectory,
                    timeout: 600.0
                )
            } catch {
                throw DebugSessionServiceError.preLaunchTaskFailed(
                    "Failed to start preLaunchTask: \(error.localizedDescription)"
                )
            }

            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.terminationStatus != 0 {
                let message = stderr.isEmpty ? "preLaunchTask failed with exit code \(result.terminationStatus)." : stderr
                throw DebugSessionServiceError.preLaunchTaskFailed(message)
            }
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
    private(set) var resumeCallCount: Int = 0
    private(set) var stepOverCallCount: Int = 0
    private(set) var stepIntoCallCount: Int = 0
    private(set) var stepOutCallCount: Int = 0
    private(set) var pauseCallCount: Int = 0
    var nextScopes: [DAPScope] = []
    var nextVariables: [Int: [DAPVariable]] = [:]
    private(set) var scopesCalls: [Int] = []
    private(set) var variablesCalls: [Int] = []

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

    func resume() async { resumeCallCount += 1 }
    func stepOver() async { stepOverCallCount += 1 }
    func stepInto() async { stepIntoCallCount += 1 }
    func stepOut() async { stepOutCallCount += 1 }
    func pause() async { pauseCallCount += 1 }
    func scopes(frameId: Int) async -> [DAPScope] {
        scopesCalls.append(frameId)
        return nextScopes
    }
    func variables(reference: Int) async -> [DAPVariable] {
        variablesCalls.append(reference)
        return nextVariables[reference] ?? []
    }
}
