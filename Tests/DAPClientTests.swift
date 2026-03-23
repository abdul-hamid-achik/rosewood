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

    func record(_ event: DAPClientEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }
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
