import Foundation
import Testing
@testable import Rosewood

struct DAPClientTests {
    @Test
    func startSessionSendsLaunchSequenceAndBreakpoints() async throws {
        let transport = MockDAPClientTransport()
        let client = DAPClient(transport: transport)
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = DebugConfiguration(
            name: "Debug App",
            adapter: "lldb",
            program: "App",
            cwd: ".",
            args: ["--flag"],
            preLaunchTask: nil,
            stopOnEntry: false
        )
        let breakpoints = [
            Breakpoint(filePath: projectRoot.appendingPathComponent("Sources/App.swift").path, line: 8),
            Breakpoint(filePath: projectRoot.appendingPathComponent("Sources/App.swift").path, line: 12)
        ]

        let startTask = Task {
            try await client.startSession(
                projectRoot: projectRoot,
                configuration: configuration,
                breakpoints: breakpoints
            )
        }

        let initializeRequest = try await waitForSentCommand("initialize", transport: transport)
        transport.receiveResponse(
            requestID: initializeRequest.requestID,
            body: ["supportsConfigurationDoneRequest": true]
        )

        let launchRequest = try await waitForSentCommand("launch", transport: transport)
        let launchArguments = try #require(launchRequest.json["arguments"] as? [String: Any])
        #expect(launchArguments["program"] as? String == projectRoot.appendingPathComponent("App").path)
        #expect(launchArguments["args"] as? [String] == ["--flag"])
        transport.receiveResponse(requestID: launchRequest.requestID, body: nil)
        transport.receiveEvent(name: "initialized")

        let setBreakpointsRequest = try await waitForSentCommand("setBreakpoints", transport: transport)
        let arguments = try #require(setBreakpointsRequest.json["arguments"] as? [String: Any])
        let source = try #require(arguments["source"] as? [String: Any])
        let sourceBreakpoints = try #require(arguments["breakpoints"] as? [[String: Any]])
        #expect(source["path"] as? String == breakpoints[0].filePath)
        #expect(sourceBreakpoints.compactMap { $0["line"] as? Int } == [8, 12])
        transport.receiveResponse(requestID: setBreakpointsRequest.requestID, body: ["breakpoints": [] as [Any]])

        let configurationDoneRequest = try await waitForSentCommand("configurationDone", transport: transport)
        transport.receiveResponse(requestID: configurationDoneRequest.requestID, body: nil)

        try await startTask.value

        let state = await client.state
        #expect(state == .running)
    }

    @Test
    func initializedEventBeforeLaunchResponseDoesNotDeadlockSessionStart() async throws {
        let transport = MockDAPClientTransport()
        let client = DAPClient(transport: transport)
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = DebugConfiguration(
            name: "Debug App",
            adapter: "lldb",
            program: "App",
            cwd: ".",
            args: [],
            preLaunchTask: nil,
            stopOnEntry: false
        )

        let startTask = Task {
            try await client.startSession(
                projectRoot: projectRoot,
                configuration: configuration,
                breakpoints: []
            )
        }

        let initializeRequest = try await waitForSentCommand("initialize", transport: transport)
        transport.receiveResponse(
            requestID: initializeRequest.requestID,
            body: ["supportsConfigurationDoneRequest": true]
        )

        let launchRequest = try await waitForSentCommand("launch", transport: transport)
        transport.receiveEvent(name: "initialized")
        transport.receiveResponse(requestID: launchRequest.requestID, body: nil)

        let configurationDoneRequest = try await waitForSentCommand("configurationDone", transport: transport)
        transport.receiveResponse(requestID: configurationDoneRequest.requestID, body: nil)

        try await startTask.value

        let commands = transport.allSentJSON().compactMap { $0["command"] as? String }
        #expect(commands == ["initialize", "launch", "configurationDone"])
    }

    @Test
    func stoppedEventResolvesTopFrameLocation() async throws {
        let transport = MockDAPClientTransport()
        let client = DAPClient(transport: transport)
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pausedFile = projectRoot.appendingPathComponent("Sources/Paused.swift")
        let configuration = DebugConfiguration(
            name: "Debug App",
            adapter: "lldb",
            program: "App",
            cwd: ".",
            args: [],
            preLaunchTask: nil,
            stopOnEntry: false
        )

        let recorder = DAPClientEventRecorder()
        await client.setOnEvent { event in
            recorder.record(event)
        }

        let startTask = Task {
            try await client.startSession(
                projectRoot: projectRoot,
                configuration: configuration,
                breakpoints: []
            )
        }

        let initializeRequest = try await waitForSentCommand("initialize", transport: transport)
        transport.receiveResponse(
            requestID: initializeRequest.requestID,
            body: ["supportsConfigurationDoneRequest": true]
        )

        let launchRequest = try await waitForSentCommand("launch", transport: transport)
        transport.receiveResponse(requestID: launchRequest.requestID, body: nil)
        transport.receiveEvent(name: "initialized")

        let configurationDoneRequest = try await waitForSentCommand("configurationDone", transport: transport)
        transport.receiveResponse(requestID: configurationDoneRequest.requestID, body: nil)
        try await startTask.value

        transport.receiveEvent(
            name: "stopped",
            body: [
                "reason": "breakpoint",
                "description": "Paused on breakpoint",
                "threadId": 7
            ]
        )

        let stackTraceRequest = try await waitForSentCommand("stackTrace", transport: transport)
        let stackTraceArguments = try #require(stackTraceRequest.json["arguments"] as? [String: Any])
        #expect(stackTraceArguments["threadId"] as? Int == 7)
        transport.receiveResponse(
            requestID: stackTraceRequest.requestID,
            body: [
                "stackFrames": [[
                    "id": 11,
                    "name": "main",
                    "line": 14,
                    "column": 1,
                    "source": [
                        "name": "Paused.swift",
                        "path": pausedFile.path
                    ]
                ]],
                "totalFrames": 1
            ]
        )

        try await waitUntil {
            recorder.lastStoppedEvent != nil
        }

        let stoppedEvent = try #require(recorder.lastStoppedEvent)
        if case let .stopped(filePath, line, reason) = stoppedEvent {
            #expect(filePath == pausedFile.path)
            #expect(line == 14)
            #expect(reason == "Paused on breakpoint")
        } else {
            Issue.record("Expected a stopped event, received \(String(describing: stoppedEvent))")
        }

        let state = await client.state
        #expect(state == .paused)
    }

    @Test
    func stoppedEmitsFullCallStack() async throws {
        let transport = MockDAPClientTransport()
        let recorder = DAPClientEventRecorder()
        let client = DAPClient(transport: transport)
        await client.setOnEvent { recorder.record($0) }
        try await performDAPHandshake(client: client, transport: transport)

        transport.receiveEvent(name: "stopped", body: ["reason": "breakpoint", "threadId": 7])
        let stackRequest = try await waitForSentCommand("stackTrace", transport: transport)
        transport.receiveResponse(
            requestID: stackRequest.requestID,
            body: [
                "stackFrames": [
                    ["id": 1, "name": "inner", "line": 5, "column": 1, "source": ["name": "A.swift", "path": "/tmp/A.swift"]],
                    ["id": 2, "name": "middle", "line": 12, "column": 1, "source": ["name": "B.swift", "path": "/tmp/B.swift"]],
                    ["id": 3, "name": "main", "line": 20, "column": 1, "source": ["name": "C.swift", "path": "/tmp/C.swift"]]
                ],
                "totalFrames": 3
            ]
        )

        try await waitUntil { recorder.lastCallStackFrames != nil }
        let frames = try #require(recorder.lastCallStackFrames)
        #expect(frames.count == 3)
        #expect(frames.map(\.name) == ["inner", "middle", "main"])
        // The .stopped event maps to the top (first) frame.
        if case let .stopped(filePath, line, _) = try #require(recorder.lastStoppedEvent) {
            #expect(filePath == "/tmp/A.swift")
            #expect(line == 5)
        } else {
            Issue.record("expected a stopped event")
        }
    }

    @Test
    func resumeSendsContinueWithStoppedThread() async throws {
        let transport = MockDAPClientTransport()
        let recorder = DAPClientEventRecorder()
        let client = try await startPausedDAPClient(threadId: 7, transport: transport, recorder: recorder)

        let task = Task { try await client.resume() }
        let req = try await waitForSentCommand("continue", transport: transport)
        #expect((req.json["arguments"] as? [String: Any])?["threadId"] as? Int == 7)
        transport.receiveResponse(requestID: req.requestID, body: nil)
        try await task.value
    }

    @Test
    func stepOverSendsNextWithStoppedThread() async throws {
        let transport = MockDAPClientTransport()
        let recorder = DAPClientEventRecorder()
        let client = try await startPausedDAPClient(threadId: 7, transport: transport, recorder: recorder)

        let task = Task { try await client.stepOver() }
        let req = try await waitForSentCommand("next", transport: transport)
        #expect((req.json["arguments"] as? [String: Any])?["threadId"] as? Int == 7)
        transport.receiveResponse(requestID: req.requestID, body: nil)
        try await task.value
    }

    @Test
    func stepIntoSendsStepInWithStoppedThread() async throws {
        let transport = MockDAPClientTransport()
        let recorder = DAPClientEventRecorder()
        let client = try await startPausedDAPClient(threadId: 7, transport: transport, recorder: recorder)

        let task = Task { try await client.stepInto() }
        let req = try await waitForSentCommand("stepIn", transport: transport)
        #expect((req.json["arguments"] as? [String: Any])?["threadId"] as? Int == 7)
        transport.receiveResponse(requestID: req.requestID, body: nil)
        try await task.value
    }

    @Test
    func stepOutSendsStepOutWithStoppedThread() async throws {
        let transport = MockDAPClientTransport()
        let recorder = DAPClientEventRecorder()
        let client = try await startPausedDAPClient(threadId: 7, transport: transport, recorder: recorder)

        let task = Task { try await client.stepOut() }
        let req = try await waitForSentCommand("stepOut", transport: transport)
        #expect((req.json["arguments"] as? [String: Any])?["threadId"] as? Int == 7)
        transport.receiveResponse(requestID: req.requestID, body: nil)
        try await task.value
    }

    @Test
    func pauseSendsPauseWithThread() async throws {
        let transport = MockDAPClientTransport()
        let recorder = DAPClientEventRecorder()
        let client = try await startPausedDAPClient(threadId: 7, transport: transport, recorder: recorder)

        let task = Task { try await client.pause() }
        let req = try await waitForSentCommand("pause", transport: transport)
        #expect((req.json["arguments"] as? [String: Any])?["threadId"] as? Int == 7)
        transport.receiveResponse(requestID: req.requestID, body: nil)
        try await task.value
    }

    @Test
    func staleStoppedIsDroppedAfterContinued() async throws {
        // Race guard: a deferred "stopped" handler whose stackTrace resolves AFTER a "continued"
        // event must not re-pause the UI. The generation token should drop the stale emit.
        let transport = MockDAPClientTransport()
        let recorder = DAPClientEventRecorder()
        let client = DAPClient(transport: transport)
        await client.setOnEvent { recorder.record($0) }
        try await performDAPHandshake(client: client, transport: transport)

        // stop#1 arrives; capture its stackTrace request but DON'T answer it yet.
        transport.receiveEvent(name: "stopped", body: ["reason": "breakpoint", "threadId": 7])
        let staleStack = try await waitForSentCommand("stackTrace", transport: transport)

        // A "continued" supersedes the pending stop (bumps the stop generation).
        transport.receiveEvent(name: "continued", body: ["threadId": 7])
        var sawRunning = false
        for _ in 0..<300 {
            if await client.state == .running { sawRunning = true; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(sawRunning)

        // Now answer the stale stackTrace out of order: the handler must drop its emit.
        transport.receiveResponse(
            requestID: staleStack.requestID,
            body: [
                "stackFrames": [[
                    "id": 1, "name": "main", "line": 99, "column": 1,
                    "source": ["name": "Stale.swift", "path": "/tmp/Stale.swift"]
                ]],
                "totalFrames": 1
            ]
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(recorder.lastStoppedEvent == nil)
        let state = await client.state
        #expect(state == .running)
    }
}

private struct SentDAPRequest {
    let requestID: Int
    let json: [String: Any]
}

private final class DAPClientEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DAPClientEvent] = []

    var lastStoppedEvent: DAPClientEvent? {
        lock.lock()
        defer { lock.unlock() }
        return events.last {
            if case .stopped = $0 {
                return true
            }
            return false
        }
    }

    var lastCallStackFrames: [DAPStackFrame]? {
        lock.lock()
        defer { lock.unlock() }
        for event in events.reversed() {
            if case .callStack(let frames) = event {
                return frames
            }
        }
        return nil
    }

    func record(_ event: DAPClientEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }
}

private func performDAPHandshake(client: DAPClient, transport: MockDAPClientTransport) async throws {
    let configuration = DebugConfiguration(
        name: "Debug App",
        adapter: "lldb",
        program: "App",
        cwd: ".",
        args: [],
        preLaunchTask: nil,
        stopOnEntry: false
    )
    let startTask = Task {
        try await client.startSession(
            projectRoot: FileManager.default.temporaryDirectory,
            configuration: configuration,
            breakpoints: []
        )
    }
    let initializeRequest = try await waitForSentCommand("initialize", transport: transport)
    transport.receiveResponse(requestID: initializeRequest.requestID, body: ["supportsConfigurationDoneRequest": true])
    let launchRequest = try await waitForSentCommand("launch", transport: transport)
    transport.receiveResponse(requestID: launchRequest.requestID, body: nil)
    transport.receiveEvent(name: "initialized")
    let configurationDoneRequest = try await waitForSentCommand("configurationDone", transport: transport)
    transport.receiveResponse(requestID: configurationDoneRequest.requestID, body: nil)
    try await startTask.value
}

/// Drives a client through the handshake and a breakpoint stop on `threadId`, leaving it paused
/// (so execution-control methods target that thread).
private func startPausedDAPClient(
    threadId: Int,
    transport: MockDAPClientTransport,
    recorder: DAPClientEventRecorder
) async throws -> DAPClient {
    let client = DAPClient(transport: transport)
    await client.setOnEvent { recorder.record($0) }
    try await performDAPHandshake(client: client, transport: transport)

    transport.receiveEvent(name: "stopped", body: ["reason": "breakpoint", "threadId": threadId])
    let stackTraceRequest = try await waitForSentCommand("stackTrace", transport: transport)
    transport.receiveResponse(
        requestID: stackTraceRequest.requestID,
        body: [
            "stackFrames": [[
                "id": 1, "name": "main", "line": 10, "column": 1,
                "source": ["name": "Frame.swift", "path": "/tmp/Frame.swift"]
            ]],
            "totalFrames": 1
        ]
    )
    try await waitUntil { recorder.lastStoppedEvent != nil }
    return client
}

private func waitForSentCommand(
    _ command: String,
    transport: MockDAPClientTransport,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    stepNanoseconds: UInt64 = 10_000_000
) async throws -> SentDAPRequest {
    let iterations = Int(timeoutNanoseconds / stepNanoseconds)
    for _ in 0..<iterations {
        if let json = transport.allSentJSON().first(where: { $0["command"] as? String == command }),
           let requestID = json["seq"] as? Int {
            return SentDAPRequest(requestID: requestID, json: json)
        }
        try await Task.sleep(nanoseconds: stepNanoseconds)
    }

    Issue.record("Timed out waiting for DAP command: \(command)")
    throw DAPClientError.timedOutWaitingForInitialization
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    stepNanoseconds: UInt64 = 10_000_000,
    condition: @escaping () -> Bool
) async throws {
    let iterations = Int(timeoutNanoseconds / stepNanoseconds)
    for _ in 0..<iterations {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: stepNanoseconds)
    }

    Issue.record("Timed out waiting for condition")
}
