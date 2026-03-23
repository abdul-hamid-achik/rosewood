import Foundation
import Testing
@testable import Rosewood

struct LSPClientTests {

    private func makeClient(transport: MockJSONRPCTransport = MockJSONRPCTransport()) -> LSPClient {
        let config = LSPServerConfig(
            languageId: "swift",
            command: "sourcekit-lsp",
            discoveryMethod: .xcrun(tool: "sourcekit-lsp")
        )
        return LSPClient(
            language: "swift",
            serverConfig: config,
            rootURI: "file:///test/project",
            transport: transport
        )
    }

    private func makeInitializeResult() -> [String: Any] {
        [
            "capabilities": [
                "textDocumentSync": 1,
                "completionProvider": ["triggerCharacters": ["."], "resolveProvider": true],
                "hoverProvider": true,
                "definitionProvider": true,
                "referencesProvider": true
            ] as [String: Any]
        ]
    }

    // MARK: - Initialization

    @Test
    func initializeHandshake() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        // Simulate server responding to initialize request
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            // The first sent message should be the initialize request
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }

        try await client.start()
        let state = await client.state
        #expect(state == .ready)
    }

    @Test
    func initializeWithCapabilities() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }

        try await client.start()
        let capabilities = await client.serverCapabilities
        #expect(capabilities?.supportsCompletion == true)
        #expect(capabilities?.supportsHover == true)
        #expect(capabilities?.supportsDefinition == true)
    }

    @Test
    func initializeSendsCorrectParams() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }

        try await client.start()

        let allSent = transport.allSentJSON()
        // First message should be initialize request
        #expect(allSent.count >= 1)
        let initRequest = allSent[0]
        #expect(initRequest["method"] as? String == "initialize")
        #expect(initRequest["id"] != nil)

        let params = initRequest["params"] as? [String: Any]
        #expect(params?["rootUri"] as? String == "file:///test/project")

        let clientInfo = params?["clientInfo"] as? [String: Any]
        #expect(clientInfo?["name"] as? String == "Rosewood")
    }

    @Test
    func initializeSendsInitializedNotification() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }

        try await client.start()

        // Wait a bit for the initialized notification to be sent
        try? await Task.sleep(nanoseconds: 50_000_000)

        let allSent = transport.allSentJSON()
        let initializedNotification = allSent.first { ($0["method"] as? String) == "initialized" }
        #expect(initializedNotification != nil)
        #expect(initializedNotification?["id"] == nil) // notifications have no id
    }

    // MARK: - Document Lifecycle

    @Test
    func didOpenDocument() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        await client.didOpenDocument(
            uri: "file:///test.swift",
            languageId: "swift",
            version: 0,
            text: "import Foundation"
        )

        try? await Task.sleep(nanoseconds: 20_000_000)
        let allSent = transport.allSentJSON()
        let didOpen = allSent.first { ($0["method"] as? String) == "textDocument/didOpen" }
        #expect(didOpen != nil)

        let params = didOpen?["params"] as? [String: Any]
        let textDoc = params?["textDocument"] as? [String: Any]
        #expect(textDoc?["uri"] as? String == "file:///test.swift")
        #expect(textDoc?["languageId"] as? String == "swift")
        #expect(textDoc?["version"] as? Int == 0)
        #expect(textDoc?["text"] as? String == "import Foundation")
    }

    @Test
    func didChangeDocument() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        await client.didChangeDocument(
            uri: "file:///test.swift",
            version: 1,
            text: "import Foundation\nlet x = 1"
        )

        try? await Task.sleep(nanoseconds: 20_000_000)
        let allSent = transport.allSentJSON()
        let didChange = allSent.first { ($0["method"] as? String) == "textDocument/didChange" }
        #expect(didChange != nil)

        let params = didChange?["params"] as? [String: Any]
        let textDoc = params?["textDocument"] as? [String: Any]
        #expect(textDoc?["version"] as? Int == 1)
    }

    @Test
    func didCloseDocument() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        await client.didCloseDocument(uri: "file:///test.swift")

        try? await Task.sleep(nanoseconds: 20_000_000)
        let allSent = transport.allSentJSON()
        let didClose = allSent.first { ($0["method"] as? String) == "textDocument/didClose" }
        #expect(didClose != nil)
    }

    @Test
    func didSaveDocument() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        await client.didSaveDocument(uri: "file:///test.swift")

        try? await Task.sleep(nanoseconds: 20_000_000)
        let allSent = transport.allSentJSON()
        let didSave = allSent.first { ($0["method"] as? String) == "textDocument/didSave" }
        #expect(didSave != nil)
    }

    // MARK: - Completion

    @Test
    func completionRequest() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        // Initialize
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        // Set up completion response
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let completionReq = allSent.last(where: { ($0["method"] as? String) == "textDocument/completion" }),
               let id = completionReq["id"] as? Int {
                let result: [String: Any] = [
                    "isIncomplete": false,
                    "items": [
                        ["label": "append", "kind": 2] as [String: Any],
                        ["label": "count", "kind": 10] as [String: Any]
                    ]
                ]
                transport.receiveResponse(id: id, result: result)
            }
        }

        let completionList = try await client.completion(
            uri: "file:///test.swift",
            position: LSPPosition(line: 5, character: 10)
        )
        #expect(completionList.items.count == 2)
        #expect(completionList.items[0].label == "append")
    }

    @Test
    func completionRequestEmptyResult() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "textDocument/completion" }),
               let id = req["id"] as? Int {
                transport.receiveResponse(id: id, result: ["isIncomplete": false, "items": [] as [Any]] as [String: Any])
            }
        }

        let completionList = try await client.completion(
            uri: "file:///test.swift",
            position: LSPPosition(line: 0, character: 0)
        )
        #expect(completionList.items.isEmpty)
    }

    // MARK: - Hover

    @Test
    func hoverRequest() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "textDocument/hover" }),
               let id = req["id"] as? Int {
                transport.receiveResponse(id: id, result: ["contents": "func hello() -> String"] as [String: Any])
            }
        }

        let result = try await client.hover(
            uri: "file:///test.swift",
            position: LSPPosition(line: 3, character: 5)
        )
        #expect(result != nil)
        #expect(result?.contentsString == "func hello() -> String")
    }

    @Test
    func hoverRequestNoResult() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "textDocument/hover" }),
               let id = req["id"] as? Int {
                transport.receiveResponse(id: id, result: nil)
            }
        }

        let result = try await client.hover(
            uri: "file:///test.swift",
            position: LSPPosition(line: 0, character: 0)
        )
        #expect(result == nil)
    }

    // MARK: - Definition

    @Test
    func definitionRequest() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "textDocument/definition" }),
               let id = req["id"] as? Int {
                let result: [String: Any] = [
                    "uri": "file:///other.swift",
                    "range": [
                        "start": ["line": 10, "character": 4],
                        "end": ["line": 10, "character": 20]
                    ] as [String: Any]
                ]
                transport.receiveResponse(id: id, result: result)
            }
        }

        let locations = try await client.definition(
            uri: "file:///test.swift",
            position: LSPPosition(line: 5, character: 10)
        )
        #expect(locations.count == 1)
        #expect(locations[0].uri == "file:///other.swift")
        #expect(locations[0].range.start.line == 10)
    }

    @Test
    func definitionRequestNoResult() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "textDocument/definition" }),
               let id = req["id"] as? Int {
                transport.receiveResponse(id: id, result: nil)
            }
        }

        let locations = try await client.definition(
            uri: "file:///test.swift",
            position: LSPPosition(line: 0, character: 0)
        )
        #expect(locations.isEmpty)
    }

    // MARK: - References

    @Test
    func referencesRequest() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "textDocument/references" }),
               let id = req["id"] as? Int {
                let result: [[String: Any]] = [
                    [
                        "uri": "file:///other.swift",
                        "range": [
                            "start": ["line": 10, "character": 4],
                            "end": ["line": 10, "character": 20]
                        ] as [String: Any]
                    ]
                ]
                transport.receiveResponse(id: id, result: result)
            }
        }

        let locations = try await client.references(
            uri: "file:///test.swift",
            position: LSPPosition(line: 5, character: 10),
            includeDeclaration: false
        )
        #expect(locations.count == 1)
        #expect(locations[0].uri == "file:///other.swift")
        #expect(locations[0].range.start.line == 10)
    }

    @Test
    func referencesRequestNoResult() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "textDocument/references" }),
               let id = req["id"] as? Int {
                transport.receiveResponse(id: id, result: nil)
            }
        }

        let locations = try await client.references(
            uri: "file:///test.swift",
            position: LSPPosition(line: 0, character: 0),
            includeDeclaration: false
        )
        #expect(locations.isEmpty)
    }

    // MARK: - Diagnostics Notification

    @Test
    func diagnosticsNotification() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        var receivedDiagnostics: (String, [LSPDiagnostic])?

        await client.setOnDiagnostics { uri, diagnostics in
            receivedDiagnostics = (uri, diagnostics)
        }

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        // Simulate server pushing diagnostics
        transport.receiveNotification(
            method: "textDocument/publishDiagnostics",
            params: [
                "uri": "file:///test.swift",
                "diagnostics": [
                    [
                        "range": ["start": ["line": 1, "character": 0], "end": ["line": 1, "character": 5]] as [String: Any],
                        "severity": 1,
                        "message": "cannot find 'foo' in scope"
                    ] as [String: Any]
                ]
            ] as [String: Any]
        )

        // Wait for processing
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        #expect(receivedDiagnostics?.0 == "file:///test.swift")
        #expect(receivedDiagnostics?.1.count == 1)
        #expect(receivedDiagnostics?.1[0].message == "cannot find 'foo' in scope")
        #expect(receivedDiagnostics?.1[0].severity == .error)
    }

    @Test
    func diagnosticsCleared() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        var latestDiagnostics: [LSPDiagnostic]?
        await client.setOnDiagnostics { _, diagnostics in
            latestDiagnostics = diagnostics
        }

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        // Send empty diagnostics
        transport.receiveNotification(
            method: "textDocument/publishDiagnostics",
            params: ["uri": "file:///test.swift", "diagnostics": [] as [Any]] as [String: Any]
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(latestDiagnostics?.isEmpty == true)
    }

    // MARK: - Request ID

    @Test
    func requestIdIncrementing() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        // Initialize with ID 1
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                #expect(id == 1) // First request should be ID 1
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()
    }

    // MARK: - Server Error Response

    @Test
    func serverErrorResponse() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        // Initialize
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        // Send error for completion request
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "textDocument/completion" }),
               let id = req["id"] as? Int {
                let errorResponse: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": ["code": -32600, "message": "Invalid Request"] as [String: Any]
                ]
                if let data = try? JSONSerialization.data(withJSONObject: errorResponse) {
                    transport.receive(data)
                }
            }
        }

        do {
            _ = try await client.completion(
                uri: "file:///test.swift",
                position: LSPPosition(line: 0, character: 0)
            )
            Issue.record("Expected error to be thrown")
        } catch {
            if case LSPClientError.requestFailed(let code, let message) = error {
                #expect(code == -32600)
                #expect(message == "Invalid Request")
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - State

    @Test
    func stateTransitions() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        let state1 = await client.state
        #expect(state1 == .starting)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        let state2 = await client.state
        #expect(state2 == .ready)
    }

    @Test
    func stateOnShutdown() async throws {
        let transport = MockJSONRPCTransport()
        let client = makeClient(transport: transport)

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let json = transport.lastSentJSON(), let id = json["id"] as? Int {
                transport.receiveResponse(id: id, result: makeInitializeResult())
            }
        }
        try await client.start()

        // Respond to shutdown request
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let allSent = transport.allSentJSON()
            if let req = allSent.last(where: { ($0["method"] as? String) == "shutdown" }),
               let id = req["id"] as? Int {
                transport.receiveResponse(id: id, result: nil)
            }
        }

        await client.shutdown()
        let state = await client.state
        #expect(state == .shutdown)
    }

    // MARK: - Not Ready State

    @Test
    func completionWhenNotReady() async {
        let client = makeClient()
        do {
            _ = try await client.completion(
                uri: "file:///test.swift",
                position: LSPPosition(line: 0, character: 0)
            )
            Issue.record("Expected serverNotReady error")
        } catch {
            #expect(error is LSPClientError)
        }
    }

    @Test
    func hoverWhenNotReady() async {
        let client = makeClient()
        do {
            _ = try await client.hover(
                uri: "file:///test.swift",
                position: LSPPosition(line: 0, character: 0)
            )
            Issue.record("Expected serverNotReady error")
        } catch {
            #expect(error is LSPClientError)
        }
    }

    @Test
    func definitionWhenNotReady() async {
        let client = makeClient()
        do {
            _ = try await client.definition(
                uri: "file:///test.swift",
                position: LSPPosition(line: 0, character: 0)
            )
            Issue.record("Expected serverNotReady error")
        } catch {
            #expect(error is LSPClientError)
        }
    }
}

// MARK: - LSPClient State Equatable

extension LSPClient.State: Equatable {
    public static func == (lhs: LSPClient.State, rhs: LSPClient.State) -> Bool {
        switch (lhs, rhs) {
        case (.starting, .starting): return true
        case (.ready, .ready): return true
        case (.shutdown, .shutdown): return true
        case (.failed(let l), .failed(let r)): return l == r
        default: return false
        }
    }
}
