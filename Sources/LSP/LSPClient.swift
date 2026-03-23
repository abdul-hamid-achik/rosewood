import Foundation

// MARK: - LSP Client Errors

enum LSPClientError: Error {
    case serverNotReady
    case requestFailed(code: Int, message: String)
    case invalidResponse
    case serverCrashed
    case shutdownInProgress
}

// MARK: - LSP Client

actor LSPClient {
    enum State: Sendable {
        case starting
        case ready
        case shutdown
        case failed(String)
    }

    let language: String
    let serverConfig: LSPServerConfig

    private let rootURI: String
    private let transport: JSONRPCTransportProtocol
    private var process: Process?
    private var nextRequestId: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
    private var messageLoopTask: Task<Void, Never>?

    private(set) var state: State = .starting
    private(set) var serverCapabilities: ServerCapabilities?

    private(set) var onDiagnostics: (@Sendable (String, [LSPDiagnostic]) -> Void)?
    private(set) var onStateChange: (@Sendable (State) -> Void)?

    func setOnDiagnostics(_ callback: @escaping @Sendable (String, [LSPDiagnostic]) -> Void) {
        self.onDiagnostics = callback
    }

    func setOnStateChange(_ callback: @escaping @Sendable (State) -> Void) {
        self.onStateChange = callback
    }

    // MARK: - Initialization

    init(
        language: String,
        serverConfig: LSPServerConfig,
        rootURI: String,
        transport: JSONRPCTransportProtocol,
        process: Process? = nil
    ) {
        self.language = language
        self.serverConfig = serverConfig
        self.rootURI = rootURI
        self.transport = transport
        self.process = process
    }

    /// Create a client by spawning the language server process.
    static func spawn(
        language: String,
        serverConfig: LSPServerConfig,
        serverPath: String,
        rootURI: String
    ) throws -> LSPClient {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = serverConfig.arguments

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin", "\(NSHomeDirectory())/.cargo/bin"]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        process.environment = env

        // Set working directory to project root if possible
        if let rootURL = URL(string: rootURI), rootURL.isFileURL {
            process.currentDirectoryURL = rootURL
        }

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

        return LSPClient(
            language: language,
            serverConfig: serverConfig,
            rootURI: rootURI,
            transport: transport,
            process: process
        )
    }

    // MARK: - Lifecycle

    func start() async throws {
        startMessageLoop()

        // Send initialize request
        let params = InitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            clientInfo: ClientInfo(name: "Rosewood", version: "0.1.0"),
            rootUri: rootURI,
            capabilities: ClientCapabilities(
                textDocument: TextDocumentClientCapabilities(
                    completion: CompletionClientCapabilities(
                        completionItem: CompletionItemClientCapabilities(
                            snippetSupport: false,
                            documentationFormat: ["plaintext", "markdown"]
                        )
                    ),
                    hover: HoverClientCapabilities(contentFormat: ["plaintext", "markdown"]),
                    references: ReferencesClientCapabilities(dynamicRegistration: false),
                    publishDiagnostics: PublishDiagnosticsClientCapabilities(relatedInformation: true)
                )
            )
        )

        let responseData = try await sendRequest("initialize", params: params)
        let result = try LSPEncoder.decode(InitializeResult.self, from: responseData)
        serverCapabilities = result.capabilities

        // Send initialized notification
        sendNotification("initialized", params: nil as String?)

        state = .ready
        onStateChange?(.ready)
    }

    func shutdown() async {
        guard case .ready = state else { return }
        state = .shutdown
        onStateChange?(.shutdown)

        // Send shutdown request (ignore errors)
        _ = try? await sendRequest("shutdown", params: nil as String?)

        // Send exit notification
        sendNotification("exit", params: nil as String?)

        // Give the server a moment to exit, then force terminate
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        messageLoopTask?.cancel()
        transport.close()

        if let process, process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Document Lifecycle

    func didOpenDocument(uri: String, languageId: String, version: Int, text: String) {
        guard case .ready = state else { return }
        let params = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(uri: uri, languageId: languageId, version: version, text: text)
        )
        sendNotification("textDocument/didOpen", params: params)
    }

    func didChangeDocument(uri: String, version: Int, text: String) {
        guard case .ready = state else { return }
        let params = DidChangeTextDocumentParams(
            textDocument: VersionedTextDocumentIdentifier(uri: uri, version: version),
            contentChanges: [TextDocumentContentChangeEvent(text: text)]
        )
        sendNotification("textDocument/didChange", params: params)
    }

    func didSaveDocument(uri: String) {
        guard case .ready = state else { return }
        let params = DidSaveTextDocumentParams(
            textDocument: TextDocumentIdentifier(uri: uri)
        )
        sendNotification("textDocument/didSave", params: params)
    }

    func didCloseDocument(uri: String) {
        guard case .ready = state else { return }
        let params = DidCloseTextDocumentParams(
            textDocument: TextDocumentIdentifier(uri: uri)
        )
        sendNotification("textDocument/didClose", params: params)
    }

    // MARK: - Feature Requests

    func completion(uri: String, position: LSPPosition) async throws -> CompletionList {
        guard case .ready = state else { throw LSPClientError.serverNotReady }
        guard serverCapabilities?.supportsCompletion == true else {
            return CompletionList(isIncomplete: false, items: [])
        }

        let params = CompletionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: position,
            context: nil
        )

        let responseData = try await sendRequest("textDocument/completion", params: params)

        // Response can be CompletionList or [CompletionItem]
        if let list = try? LSPEncoder.decode(CompletionList.self, from: responseData) {
            return list
        }
        if let items = try? LSPEncoder.decode([CompletionItem].self, from: responseData) {
            return CompletionList(isIncomplete: false, items: items)
        }
        return CompletionList(isIncomplete: false, items: [])
    }

    func hover(uri: String, position: LSPPosition) async throws -> HoverResult? {
        guard case .ready = state else { throw LSPClientError.serverNotReady }
        guard serverCapabilities?.supportsHover == true else { return nil }

        let params = HoverParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: position
        )

        let responseData = try await sendRequest("textDocument/hover", params: params)

        // Check for null result
        if let json = try? JSONSerialization.jsonObject(with: responseData), json is NSNull {
            return nil
        }

        return try? LSPEncoder.decode(HoverResult.self, from: responseData)
    }

    func definition(uri: String, position: LSPPosition) async throws -> [LSPLocation] {
        guard case .ready = state else { throw LSPClientError.serverNotReady }
        guard serverCapabilities?.supportsDefinition == true else { return [] }

        let params = DefinitionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: position
        )

        let responseData = try await sendRequest("textDocument/definition", params: params)

        // Response can be Location, [Location], or null
        if let json = try? JSONSerialization.jsonObject(with: responseData), json is NSNull {
            return []
        }
        if let locations = try? LSPEncoder.decode([LSPLocation].self, from: responseData) {
            return locations
        }
        if let location = try? LSPEncoder.decode(LSPLocation.self, from: responseData) {
            return [location]
        }
        return []
    }

    func references(uri: String, position: LSPPosition, includeDeclaration: Bool) async throws -> [LSPLocation] {
        guard case .ready = state else { throw LSPClientError.serverNotReady }
        guard serverCapabilities?.supportsReferences == true else { return [] }

        let params = ReferenceParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: position,
            context: ReferenceContext(includeDeclaration: includeDeclaration)
        )

        let responseData = try await sendRequest("textDocument/references", params: params)

        if let json = try? JSONSerialization.jsonObject(with: responseData), json is NSNull {
            return []
        }
        return (try? LSPEncoder.decode([LSPLocation].self, from: responseData)) ?? []
    }

    // MARK: - Message Loop

    private func startMessageLoop() {
        messageLoopTask = Task { [weak self] in
            guard let self else { return }
            let transport = self.transport
            for await data in transport.messages {
                await self.handleMessage(data)
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let id = json["id"] as? Int {
            // Response to a request
            if let continuation = pendingRequests.removeValue(forKey: id) {
                if let error = json["error"] as? [String: Any] {
                    let code = error["code"] as? Int ?? -1
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: LSPClientError.requestFailed(code: code, message: message))
                } else if let result = json["result"] {
                    if let resultData = try? JSONValueCodec.data(from: result) {
                        continuation.resume(returning: resultData)
                    } else {
                        // null result
                        let nullData = "null".data(using: .utf8) ?? Data()
                        continuation.resume(returning: nullData)
                    }
                } else {
                    let nullData = "null".data(using: .utf8) ?? Data()
                    continuation.resume(returning: nullData)
                }
            }
        } else if let method = json["method"] as? String {
            // Server notification
            handleNotification(method: method, params: json["params"])
        }
    }

    private func handleNotification(method: String, params: Any?) {
        switch method {
        case "textDocument/publishDiagnostics":
            guard let params,
                  let paramsData = try? JSONSerialization.data(withJSONObject: params),
                  let diagnosticsParams = try? LSPEncoder.decode(PublishDiagnosticsParams.self, from: paramsData) else {
                return
            }
            onDiagnostics?(diagnosticsParams.uri, diagnosticsParams.diagnostics)
        default:
            break
        }
    }

    // MARK: - Transport

    private func sendRequest<P: Encodable>(_ method: String, params: P?) async throws -> Data {
        let id = nextRequestId
        nextRequestId += 1

        var jsonDict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]

        if let params {
            if let paramsObj = try? JSONValueCodec.object(from: params) {
                jsonDict["params"] = paramsObj
            }
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

    private func sendNotification<P: Encodable>(_ method: String, params: P?) {
        var jsonDict: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]

        if let params {
            if let paramsObj = try? JSONValueCodec.object(from: params) {
                jsonDict["params"] = paramsObj
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: jsonDict) else { return }
        try? transport.send(data)
    }
}
