import Foundation

// MARK: - Transport Errors

enum JSONRPCTransportError: Error, Equatable {
    case missingContentLength
    case invalidContentLength(String)
    case processNotRunning
    case encodingFailed
    case connectionClosed
}

// MARK: - Transport Protocol (for testability)

protocol JSONRPCTransportProtocol: Sendable {
    func send(_ data: Data) throws
    var messages: AsyncStream<Data> { get }
    func close()
}

// MARK: - JSON-RPC Transport

/// Handles JSON-RPC 2.0 communication over stdio (stdin/stdout pipes of a child process).
/// Messages are framed with `Content-Length: N\r\n\r\n` headers per the LSP specification.
final class JSONRPCTransport: JSONRPCTransportProtocol, @unchecked Sendable {
    /// Maximum allowed body size for a single JSON-RPC message (256 MB).
    static let maxBodySize = 256 * 1024 * 1024
    /// Maximum allowed header size before giving up (64 KB).
    static let maxHeaderSize = 64 * 1024

    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let readQueue: DispatchQueue
    private let stderrQueue: DispatchQueue
    private let writeQueue: DispatchQueue
    private var continuation: AsyncStream<Data>.Continuation?
    private let _messages: AsyncStream<Data>
    private var isClosed = false

    var messages: AsyncStream<Data> { _messages }

    init(process: Process, stdinPipe: Pipe, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.readQueue = DispatchQueue(label: "rosewood.lsp.transport.read", qos: .utility)
        self.stderrQueue = DispatchQueue(label: "rosewood.lsp.transport.stderr", qos: .utility)
        self.writeQueue = DispatchQueue(label: "rosewood.lsp.transport.write", qos: .utility)

        var captured: AsyncStream<Data>.Continuation?
        _messages = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured

        startReadLoop()
        startErrorDrainLoop()
    }

    func send(_ data: Data) throws {
        guard process.isRunning else { throw JSONRPCTransportError.processNotRunning }
        guard !isClosed else { throw JSONRPCTransportError.connectionClosed }

        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            throw JSONRPCTransportError.encodingFailed
        }

        writeQueue.async { [stdinPipe] in
            let handle = stdinPipe.fileHandleForWriting
            // Use the throwing variant so a pipe closed by a dying LSP process
            // surfaces as a Swift error instead of an unhandled NSException.
            do {
                try handle.write(contentsOf: headerData)
                try handle.write(contentsOf: data)
            } catch {
                // Process likely terminated; readMessages will detect EOF and finish.
            }
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        continuation?.finish()
        continuation = nil
    }

    private func startReadLoop() {
        readQueue.async { [weak self] in
            self?.readMessages()
        }
    }

    private func startErrorDrainLoop() {
        stderrQueue.async { [weak self] in
            self?.drainErrorOutput()
        }
    }

    private func readMessages() {
        let handle = stdoutPipe.fileHandleForReading

        while !isClosed {
            guard let contentLength = readContentLength(from: handle) else {
                break
            }

            guard contentLength > 0 else { continue }

            // Reject messages that exceed the maximum allowed body size to prevent
            // unbounded memory allocation from a malicious or misbehaving server.
            guard contentLength <= Self.maxBodySize else {
                break
            }

            var bodyData = Data()
            while bodyData.count < contentLength {
                let remaining = contentLength - bodyData.count
                // `read(upToCount:)` throws Swift errors on closed pipe;
                // `readData(ofLength:)` raises an Obj-C exception that crashes the process.
                guard let chunk = try? handle.read(upToCount: remaining), !chunk.isEmpty else {
                    break
                }
                bodyData.append(chunk)
            }

            guard bodyData.count == contentLength else { break }

            continuation?.yield(bodyData)
        }

        continuation?.finish()
    }

    private func drainErrorOutput() {
        let handle = stderrPipe.fileHandleForReading

        while !isClosed {
            guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else {
                break
            }
        }
    }

    private func readContentLength(from handle: FileHandle) -> Int? {
        var headerString = ""
        var foundEnd = false

        while !foundEnd && !isClosed {
            guard let byte = try? handle.read(upToCount: 1),
                  !byte.isEmpty,
                  let char = String(data: byte, encoding: .utf8) else {
                return nil
            }
            headerString.append(char)

            // Guard against unbounded header growth from a malicious or misbehaving server.
            if headerString.count > Self.maxHeaderSize {
                return nil
            }

            if headerString.hasSuffix("\r\n\r\n") {
                foundEnd = true
            }
        }

        guard foundEnd else { return nil }
        return parseContentLength(from: headerString)
    }

    static func parseContentLength(from header: String) -> Int? {
        let lines = header.split(separator: "\r\n", omittingEmptySubsequences: true)
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            if key == "content-length" {
                let valueStr = parts[1].trimmingCharacters(in: .whitespaces)
                guard let length = Int(valueStr), length >= 0 else { return nil }
                return length
            }
        }
        return nil
    }
}

private extension JSONRPCTransport {
    func parseContentLength(from header: String) -> Int? {
        Self.parseContentLength(from: header)
    }
}

// MARK: - Message Framing Utilities

enum JSONRPCFraming {
    /// Wraps a JSON body with Content-Length header framing.
    static func frame(_ data: Data) -> Data {
        let header = "Content-Length: \(data.count)\r\n\r\n"
        var framed = header.data(using: .utf8) ?? Data()
        framed.append(data)
        return framed
    }

    /// Parses a Content-Length framed message from raw data.
    /// Returns the parsed body data and the number of bytes consumed, or nil if incomplete.
    static func parse(_ data: Data) -> (body: Data, consumed: Int)? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }

        guard let headerEnd = string.range(of: "\r\n\r\n") else { return nil }

        let headerPortion = String(string[string.startIndex..<headerEnd.lowerBound])
        guard let contentLength = JSONRPCTransport.parseContentLength(from: headerPortion + "\r\n") else {
            return nil
        }

        let actualHeaderByteCount = data.startIndex + headerPortion.utf8.count + 4 // +4 for \r\n\r\n

        let totalNeeded = actualHeaderByteCount + contentLength
        guard data.count >= totalNeeded else { return nil }

        let bodyStart = actualHeaderByteCount
        let body = data[bodyStart..<(bodyStart + contentLength)]
        return (Data(body), totalNeeded)
    }
}

// MARK: - Mock Transport (for testing)

final class MockJSONRPCTransport: JSONRPCTransportProtocol, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let _messages: AsyncStream<Data>
    private(set) var sentMessages: [Data] = []
    private let lock = NSLock()
    private var isClosed = false

    var messages: AsyncStream<Data> { _messages }

    init() {
        var captured: AsyncStream<Data>.Continuation?
        _messages = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    func send(_ data: Data) throws {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            throw JSONRPCTransportError.connectionClosed
        }
        sentMessages.append(data)
        lock.unlock()
    }

    func close() {
        lock.lock()
        isClosed = true
        continuation?.finish()
        continuation = nil
        lock.unlock()
    }

    /// Simulate receiving a message from the server.
    func receive(_ data: Data) {
        continuation?.yield(data)
    }

    /// Simulate receiving a JSON-RPC response.
    func receiveResponse(id: Int, result: Any?) {
        let response: [String: Any?] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        if let data = try? JSONSerialization.data(withJSONObject: response as Any) {
            receive(data)
        }
    }

    /// Simulate receiving a JSON-RPC notification.
    func receiveNotification(method: String, params: Any?) {
        var notification: [String: Any?] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params { notification["params"] = params }
        if let data = try? JSONSerialization.data(withJSONObject: notification as Any) {
            receive(data)
        }
    }

    /// Get the last sent message decoded as a JSON dictionary.
    func lastSentJSON() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard let last = sentMessages.last else { return nil }
        return try? JSONSerialization.jsonObject(with: last) as? [String: Any]
    }

    /// Get all sent messages decoded as JSON dictionaries.
    func allSentJSON() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return sentMessages.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
