import Foundation

struct DAPInitializeRequestArguments: Codable, Sendable {
    let adapterID: String
    let clientID: String?
    let clientName: String?
    let locale: String?
    let linesStartAt1: Bool
    let columnsStartAt1: Bool
    let pathFormat: String
    let supportsVariableType: Bool?
    let supportsRunInTerminalRequest: Bool?
}

struct DAPCapabilities: Codable, Sendable {
    let supportsConfigurationDoneRequest: Bool?
}

struct DAPInitializeResponseBody: Codable, Sendable {
    let supportsConfigurationDoneRequest: Bool?
}

struct DAPLaunchRequestArguments: Codable, Sendable {
    let name: String
    let type: String
    let request: String
    let program: String
    let cwd: String?
    let args: [String]
    let stopOnEntry: Bool
}

struct DAPSource: Codable, Equatable, Sendable {
    let name: String?
    let path: String?
}

struct DAPSourceBreakpoint: Codable, Equatable, Sendable {
    let line: Int
}

struct DAPSetBreakpointsArguments: Codable, Sendable {
    let source: DAPSource
    let breakpoints: [DAPSourceBreakpoint]
    let sourceModified: Bool?
}

struct DAPConfigurationDoneArguments: Codable, Sendable {}

struct DAPDisconnectArguments: Codable, Sendable {
    let restart: Bool?
    let terminateDebuggee: Bool?
}

struct DAPStoppedEventBody: Codable, Sendable {
    let reason: String
    let threadId: Int?
    let description: String?
    let text: String?
}

struct DAPContinuedEventBody: Codable, Sendable {
    let threadId: Int?
    let allThreadsContinued: Bool?
}

struct DAPOutputEventBody: Codable, Sendable {
    let category: String?
    let output: String
}

struct DAPThreadsResponseBody: Codable, Sendable {
    let threads: [DAPThread]
}

struct DAPThread: Codable, Sendable {
    let id: Int
    let name: String
}

struct DAPStackTraceArguments: Codable, Sendable {
    let threadId: Int
    let startFrame: Int?
    let levels: Int?
}

// Execution-control request arguments. Each takes the thread to act on; optional DAP fields
// (singleThread, granularity) are omitted and default to whole-process, statement granularity.
struct DAPContinueArguments: Codable, Sendable {
    let threadId: Int
}

struct DAPNextArguments: Codable, Sendable {
    let threadId: Int
}

struct DAPStepInArguments: Codable, Sendable {
    let threadId: Int
}

struct DAPStepOutArguments: Codable, Sendable {
    let threadId: Int
}

struct DAPPauseArguments: Codable, Sendable {
    let threadId: Int
}

struct DAPStackTraceResponseBody: Codable, Sendable {
    let stackFrames: [DAPStackFrame]
    let totalFrames: Int?
}

struct DAPStackFrame: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let line: Int
    let column: Int
    let source: DAPSource?
}

struct DAPScopesArguments: Codable, Sendable {
    let frameId: Int
}

struct DAPScopesResponseBody: Codable, Sendable {
    let scopes: [DAPScope]
}

struct DAPScope: Codable, Equatable, Sendable {
    let name: String
    let variablesReference: Int
    let expensive: Bool?
}

struct DAPVariablesArguments: Codable, Sendable {
    let variablesReference: Int
}

struct DAPVariablesResponseBody: Codable, Sendable {
    let variables: [DAPVariable]
}

struct DAPVariable: Codable, Equatable, Sendable {
    let name: String
    let value: String
    let type: String?
    let variablesReference: Int   // > 0 == expandable (has children)
}

enum DAPClientEvent: Equatable, Sendable {
    case output(String)
    case running
    case stopped(filePath: String?, line: Int?, reason: String)
    case callStack([DAPStackFrame])
    case terminated
}
