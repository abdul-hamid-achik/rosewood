import Foundation

enum DAPAdapterLocatorError: LocalizedError, Equatable {
    case adapterNotFound
    case adapterNotExecutable(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .adapterNotFound:
            return "Unable to locate lldb-dap via xcrun."
        case .adapterNotExecutable(let path):
            return "Found lldb-dap at \(path), but it is not executable."
        case .commandFailed(let message):
            return message
        }
    }
}

struct DAPPreflightResult: Equatable {
    let adapterPath: String
}

final class DAPAdapterLocator {
    func preflightLLDBDAP() throws -> DAPPreflightResult {
        let adapterPath = try locateLLDBDAP()
        guard FileManager.default.isExecutableFile(atPath: adapterPath) else {
            throw DAPAdapterLocatorError.adapterNotExecutable(adapterPath)
        }
        return DAPPreflightResult(adapterPath: adapterPath)
    }

    func locateLLDBDAP() throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "lldb-dap"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw DAPAdapterLocatorError.commandFailed("Failed to launch xcrun: \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0, !stdout.isEmpty else {
            if !stderr.isEmpty {
                throw DAPAdapterLocatorError.commandFailed(stderr)
            }
            throw DAPAdapterLocatorError.adapterNotFound
        }

        return stdout
    }
}

enum DAPClientError: LocalizedError, Equatable {
    case adapterNotReady
    case requestFailed(message: String)
    case invalidResponse
    case sessionTerminated
    case timedOutWaitingForInitialization

    var errorDescription: String? {
        switch self {
        case .adapterNotReady:
            return "The debug adapter is not ready."
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return "The debug adapter returned an invalid response."
        case .sessionTerminated:
            return "The debug session terminated unexpectedly."
        case .timedOutWaitingForInitialization:
            return "Timed out waiting for the debug adapter to finish initialization."
        }
    }
}

actor DAPClient {
    enum State: Equatable, Sendable {
        case starting
        case ready
        case running
        case paused
        case terminated
        case failed(String)
    }

    private let transport: JSONRPCTransportProtocol
    private var process: Process?
    private var nextRequestId: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
    private var messageLoopTask: Task<Void, Never>?
    private var initializedContinuation: CheckedContinuation<Void, Error>?
    private var didReceiveInitializedEvent = false
    private var configuredBreakpointFiles: Set<String> = []

    private(set) var state: State = .starting
    private(set) var capabilities: DAPCapabilities?
    private(set) var onEvent: (@Sendable (DAPClientEvent) -> Void)?

    init(transport: JSONRPCTransportProtocol, process: Process? = nil) {
        self.transport = transport
        self.process = process
    }

    func setOnEvent(_ callback: @escaping @Sendable (DAPClientEvent) -> Void) {
        self.onEvent = callback
    }

    static func spawn(adapterPath: String, workingDirectory: URL) throws -> DAPClient {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adapterPath)
        process.currentDirectoryURL = workingDirectory

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let transport = JSONRPCTransport(
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        return DAPClient(transport: transport, process: process)
    }

    func startSession(
        projectRoot: URL,
        configuration: DebugConfiguration,
        breakpoints: [Breakpoint]
    ) async throws {
        startMessageLoop()

        let initializeResponse = try await sendRequest(
            "initialize",
            params: DAPInitializeRequestArguments(
                adapterID: "lldb",
                clientID: "rosewood",
                clientName: "Rosewood",
                locale: nil,
                linesStartAt1: true,
                columnsStartAt1: true,
                pathFormat: "path",
                supportsVariableType: true,
                supportsRunInTerminalRequest: false
            )
        )
        let initializeBody = try JSONDecoder().decode(DAPInitializeResponseBody.self, from: initializeResponse)
        capabilities = DAPCapabilities(
            supportsConfigurationDoneRequest: initializeBody.supportsConfigurationDoneRequest
        )
        state = .ready

        let launchArguments = DAPLaunchRequestArguments(
            name: configuration.name,
            type: configuration.adapter,
            request: "launch",
            program: configuration.resolvedProgramURL(relativeTo: projectRoot).path,
            cwd: configuration.resolvedWorkingDirectoryURL(relativeTo: projectRoot).path,
            args: configuration.args,
            stopOnEntry: configuration.stopOnEntry
        )

        _ = try await sendRequest("launch", params: launchArguments)

        try await waitForInitializedEvent()
        try await updateBreakpoints(breakpoints)

        if capabilities?.supportsConfigurationDoneRequest != false {
            _ = try await sendRequest("configurationDone", params: DAPConfigurationDoneArguments())
        }

        state = .running
        onEvent?(.running)
    }

    func updateBreakpoints(_ breakpoints: [Breakpoint]) async throws {
        let grouped = Dictionary(grouping: breakpoints.filter(\.isEnabled), by: \.filePath)
        let currentFiles = Set(grouped.keys)
        let filesToClear = configuredBreakpointFiles.subtracting(currentFiles)

        for filePath in filesToClear {
            _ = try await sendRequest(
                "setBreakpoints",
                params: DAPSetBreakpointsArguments(
                    source: DAPSource(name: URL(fileURLWithPath: filePath).lastPathComponent, path: filePath),
                    breakpoints: [],
                    sourceModified: false
                )
            )
        }

        for (filePath, fileBreakpoints) in grouped {
            _ = try await sendRequest(
                "setBreakpoints",
                params: DAPSetBreakpointsArguments(
                    source: DAPSource(name: URL(fileURLWithPath: filePath).lastPathComponent, path: filePath),
                    breakpoints: fileBreakpoints.sorted(by: { $0.line < $1.line }).map {
                        DAPSourceBreakpoint(line: $0.line)
                    },
                    sourceModified: false
                )
            )
        }

        configuredBreakpointFiles = currentFiles
    }

    func disconnect() async {
        state = .terminated
        _ = try? await sendRequest(
            "disconnect",
            params: DAPDisconnectArguments(restart: false, terminateDebuggee: true)
        )
        messageLoopTask?.cancel()
        transport.close()
        if let process, process.isRunning {
            process.terminate()
        }
        onEvent?(.terminated)
    }

    private func startMessageLoop() {
        messageLoopTask?.cancel()
        messageLoopTask = Task { [weak self] in
            guard let self else { return }
            for await data in self.transport.messages {
                await self.handleMessage(data)
            }
            await self.handleTransportClosed()
        }
    }

    private func handleMessage(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let responseType = json["type"] as? String, responseType == "response",
           let requestID = json["request_seq"] as? Int {
            if let continuation = pendingRequests.removeValue(forKey: requestID) {
                if let success = json["success"] as? Bool, success == false {
                    let message = json["message"] as? String ?? "Unknown DAP error."
                    continuation.resume(throwing: DAPClientError.requestFailed(message: message))
                    return
                }
                if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown DAP error."
                    continuation.resume(throwing: DAPClientError.requestFailed(message: message))
                } else if let result = json["body"] ?? json["result"] {
                    if let resultData = try? JSONValueCodec.data(from: result) {
                        continuation.resume(returning: resultData)
                    } else {
                        continuation.resume(throwing: DAPClientError.invalidResponse)
                    }
                } else {
                    continuation.resume(returning: Data("null".utf8))
                }
            }
            return
        }

        guard let method = json["event"] as? String else { return }
        await handleEvent(method: method, body: json["body"])
    }

    private func handleEvent(method: String, body: Any?) async {
        switch method {
        case "initialized":
            didReceiveInitializedEvent = true
            initializedContinuation?.resume()
            initializedContinuation = nil
        case "output":
            if let bodyData = try? JSONValueCodec.data(from: body),
               let eventBody = try? JSONDecoder().decode(DAPOutputEventBody.self, from: bodyData) {
                onEvent?(.output(eventBody.output))
            }
        case "continued":
            state = .running
            onEvent?(.running)
        case "stopped":
            state = .paused
            Task { [weak self] in
                await self?.handleStoppedEvent(body)
            }
        case "terminated", "exited":
            state = .terminated
            onEvent?(.terminated)
        default:
            break
        }
    }

    private func handleStoppedEvent(_ body: Any?) async {
        guard let bodyData = try? JSONValueCodec.data(from: body),
              let eventBody = try? JSONDecoder().decode(DAPStoppedEventBody.self, from: bodyData) else {
            onEvent?(.stopped(filePath: nil, line: nil, reason: "stopped"))
            return
        }

        let topFrame = await fetchTopFrame(threadId: eventBody.threadId)
        onEvent?(
            .stopped(
                filePath: topFrame?.source?.path,
                line: topFrame?.line,
                reason: eventBody.description ?? eventBody.text ?? eventBody.reason
            )
        )
    }

    private func fetchTopFrame(threadId: Int?) async -> DAPStackFrame? {
        let resolvedThreadId: Int
        if let threadId {
            resolvedThreadId = threadId
        } else {
            guard let threadsData = try? await sendRequest("threads", params: Optional<String>.none),
                  let threads = try? JSONDecoder().decode(DAPThreadsResponseBody.self, from: threadsData).threads,
                  let firstThread = threads.first else {
                return nil
            }
            resolvedThreadId = firstThread.id
        }

        guard let stackData = try? await sendRequest(
            "stackTrace",
            params: DAPStackTraceArguments(threadId: resolvedThreadId, startFrame: 0, levels: 1)
        ),
        let response = try? JSONDecoder().decode(DAPStackTraceResponseBody.self, from: stackData) else {
            return nil
        }

        return response.stackFrames.first
    }

    private func waitForInitializedEvent(timeoutNanoseconds: UInt64 = 5_000_000_000) async throws {
        if didReceiveInitializedEvent {
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                try await withCheckedThrowingContinuation { continuation in
                    Task { await self?.storeInitializedContinuation(continuation) }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw DAPClientError.timedOutWaitingForInitialization
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func storeInitializedContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        if didReceiveInitializedEvent {
            continuation.resume()
            return
        }
        initializedContinuation = continuation
    }

    private func handleTransportClosed() {
        if case .terminated = state { return }
        state = .terminated
        initializedContinuation?.resume(throwing: DAPClientError.sessionTerminated)
        initializedContinuation = nil
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: DAPClientError.sessionTerminated)
        }
        pendingRequests.removeAll()
        onEvent?(.terminated)
    }

    private func sendRequest<P: Encodable>(_ method: String, params: P?) async throws -> Data {
        let id = nextRequestId
        nextRequestId += 1

        var jsonDict: [String: Any] = [
            "seq": id,
            "type": "request",
            "command": method
        ]

        if let params {
            jsonDict["arguments"] = try JSONValueCodec.object(from: params)
        }

        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            do {
                try transport.send(data)
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }
}

final class MockDAPClientTransport: JSONRPCTransportProtocol, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    private(set) var sentMessages: [Data] = []
    let _messages: AsyncStream<Data>

    var messages: AsyncStream<Data> { _messages }

    init() {
        var captured: AsyncStream<Data>.Continuation?
        _messages = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func send(_ data: Data) throws {
        sentMessages.append(data)
    }

    func close() {
        continuation?.finish()
        continuation = nil
    }

    func receive(_ data: Data) {
        continuation?.yield(data)
    }

    func lastSentJSON() -> [String: Any]? {
        guard let last = sentMessages.last else { return nil }
        return try? JSONSerialization.jsonObject(with: last) as? [String: Any]
    }

    func allSentJSON() -> [[String: Any]] {
        sentMessages.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func receiveResponse(requestID: Int, body: Any?) {
        var response: [String: Any] = [
            "seq": requestID + 1000,
            "type": "response",
            "request_seq": requestID,
            "success": true,
            "command": ""
        ]
        if let body {
            response["body"] = body
        }
        if let data = try? JSONSerialization.data(withJSONObject: response) {
            receive(data)
        }
    }

    func receiveEvent(name: String, body: Any? = nil) {
        var event: [String: Any] = [
            "seq": Int.random(in: 1...10_000),
            "type": "event",
            "event": name
        ]
        if let body {
            event["body"] = body
        }
        if let data = try? JSONSerialization.data(withJSONObject: event) {
            receive(data)
        }
    }
}
