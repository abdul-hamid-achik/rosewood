import Foundation
import Testing
@testable import Rosewood

struct JSONRPCTransportTests {

    // MARK: - Content-Length Header Parsing

    @Test
    func parseContentLengthBasic() {
        let result = JSONRPCTransport.parseContentLength(from: "Content-Length: 42\r\n")
        #expect(result == 42)
    }

    @Test
    func headerParsingCaseInsensitive() {
        let result = JSONRPCTransport.parseContentLength(from: "content-length: 100\r\n")
        #expect(result == 100)
    }

    @Test
    func headerWithExtraWhitespace() {
        let result = JSONRPCTransport.parseContentLength(from: "Content-Length:  42 \r\n")
        #expect(result == 42)
    }

    @Test
    func multipleHeaderFields() {
        let header = "Content-Length: 55\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n"
        let result = JSONRPCTransport.parseContentLength(from: header)
        #expect(result == 55)
    }

    @Test
    func malformedHeaderMissingContentLength() {
        let result = JSONRPCTransport.parseContentLength(from: "Content-Type: text/plain\r\n")
        #expect(result == nil)
    }

    @Test
    func malformedHeaderNegativeLength() {
        let result = JSONRPCTransport.parseContentLength(from: "Content-Length: -1\r\n")
        #expect(result == nil)
    }

    @Test
    func malformedHeaderNonNumericLength() {
        let result = JSONRPCTransport.parseContentLength(from: "Content-Length: abc\r\n")
        #expect(result == nil)
    }

    @Test
    func headerZeroLength() {
        let result = JSONRPCTransport.parseContentLength(from: "Content-Length: 0\r\n")
        #expect(result == 0)
    }

    @Test
    func headerEmptyString() {
        let result = JSONRPCTransport.parseContentLength(from: "")
        #expect(result == nil)
    }

    // MARK: - Message Framing

    @Test
    func frameMessage() {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"test"}"#.data(using: .utf8)!
        let framed = JSONRPCFraming.frame(body)
        let expected = "Content-Length: \(body.count)\r\n\r\n\(String(data: body, encoding: .utf8)!)"
        #expect(String(data: framed, encoding: .utf8) == expected)
    }

    @Test
    func frameEmptyBody() {
        let body = Data()
        let framed = JSONRPCFraming.frame(body)
        #expect(String(data: framed, encoding: .utf8) == "Content-Length: 0\r\n\r\n")
    }

    // MARK: - Message Parsing

    @Test
    func parseSimpleMessage() {
        let body = #"{"jsonrpc":"2.0","id":1,"result":null}"#
        let framed = "Content-Length: \(body.utf8.count)\r\n\r\n\(body)".data(using: .utf8)!
        let result = JSONRPCFraming.parse(framed)
        #expect(result != nil)
        #expect(String(data: result!.body, encoding: .utf8) == body)
        #expect(result!.consumed == framed.count)
    }

    @Test
    func parseNotification() {
        let body = #"{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///test.swift","diagnostics":[]}}"#
        let framed = "Content-Length: \(body.utf8.count)\r\n\r\n\(body)".data(using: .utf8)!
        let result = JSONRPCFraming.parse(framed)
        #expect(result != nil)
        let json = try? JSONSerialization.jsonObject(with: result!.body) as? [String: Any]
        #expect(json?["method"] as? String == "textDocument/publishDiagnostics")
    }

    @Test
    func parseResponseWithError() {
        let body = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid Request"}}"#
        let framed = "Content-Length: \(body.utf8.count)\r\n\r\n\(body)".data(using: .utf8)!
        let result = JSONRPCFraming.parse(framed)
        #expect(result != nil)
        let response = try? LSPEncoder.decode(JSONRPCResponse.self, from: result!.body)
        #expect(response?.error?.code == -32600)
    }

    @Test
    func parseMultipleMessagesInSequence() {
        let body1 = #"{"jsonrpc":"2.0","id":1,"result":null}"#
        let body2 = #"{"jsonrpc":"2.0","id":2,"result":42}"#
        let msg1 = "Content-Length: \(body1.utf8.count)\r\n\r\n\(body1)"
        let msg2 = "Content-Length: \(body2.utf8.count)\r\n\r\n\(body2)"
        let combined = (msg1 + msg2).data(using: .utf8)!

        // Parse first message
        let result1 = JSONRPCFraming.parse(combined)
        #expect(result1 != nil)
        #expect(String(data: result1!.body, encoding: .utf8) == body1)

        // Parse second message from remaining data
        let remaining = combined[result1!.consumed...]
        let result2 = JSONRPCFraming.parse(Data(remaining))
        #expect(result2 != nil)
        #expect(String(data: result2!.body, encoding: .utf8) == body2)
    }

    @Test
    func parseIncompleteMessage() {
        // Header present but body truncated
        let body = #"{"jsonrpc":"2.0","id":1,"result":null}"#
        let header = "Content-Length: \(body.utf8.count)\r\n\r\n"
        let truncated = header + String(body.prefix(10))
        let result = JSONRPCFraming.parse(truncated.data(using: .utf8)!)
        #expect(result == nil)
    }

    @Test
    func parseHeaderOnly() {
        // Header without separator
        let result = JSONRPCFraming.parse("Content-Length: 42".data(using: .utf8)!)
        #expect(result == nil)
    }

    @Test
    func parseLargeMessage() {
        // 1MB JSON payload
        let largeValue = String(repeating: "x", count: 1_000_000)
        let body = #"{"data":"\#(largeValue)"}"#
        let framed = "Content-Length: \(body.utf8.count)\r\n\r\n\(body)".data(using: .utf8)!
        let result = JSONRPCFraming.parse(framed)
        #expect(result != nil)
        #expect(result!.body.count == body.utf8.count)
    }

    @Test
    func parseUTF8MultibyteInBody() {
        let body = #"{"message":"Hello 世界 🌍"}"#
        let bodyData = body.data(using: .utf8)!
        // Content-Length is byte count, not character count
        let framed = "Content-Length: \(bodyData.count)\r\n\r\n".data(using: .utf8)! + bodyData
        let result = JSONRPCFraming.parse(framed)
        #expect(result != nil)
        #expect(String(data: result!.body, encoding: .utf8) == body)
    }

    @Test
    func parseWithMultipleHeaders() {
        let body = #"{"jsonrpc":"2.0","id":1}"#
        let framed = "Content-Length: \(body.utf8.count)\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n\(body)".data(using: .utf8)!
        let result = JSONRPCFraming.parse(framed)
        #expect(result != nil)
        #expect(String(data: result!.body, encoding: .utf8) == body)
    }

    // MARK: - Request Encoding

    @Test
    func encodeRequest() throws {
        let request = JSONRPCRequest(id: 1, method: "initialize")
        let data = try LSPEncoder.encode(request)
        let framed = JSONRPCFraming.frame(data)
        let framedStr = String(data: framed, encoding: .utf8)!
        #expect(framedStr.hasPrefix("Content-Length:"))
        #expect(framedStr.contains("\r\n\r\n"))
    }

    @Test
    func encodeNotification() throws {
        let notification = JSONRPCNotification(method: "initialized")
        let data = try LSPEncoder.encode(notification)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["jsonrpc"] as? String == "2.0")
        #expect(json?["method"] as? String == "initialized")
        #expect(json?["id"] == nil) // notifications have no id
    }

    @Test
    func encodeRequestWithParams() throws {
        let request = JSONRPCRequest(
            id: 1,
            method: "textDocument/completion",
            params: AnyCodable([
                "textDocument": ["uri": "file:///test.swift"],
                "position": ["line": 5, "character": 10]
            ] as [String: Any])
        )
        let data = try LSPEncoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let params = json?["params"] as? [String: Any]
        let textDoc = params?["textDocument"] as? [String: Any]
        #expect(textDoc?["uri"] as? String == "file:///test.swift")
    }

    // MARK: - Round Trip

    @Test
    func requestEncodeDecodeRoundTrip() throws {
        let original = JSONRPCRequest(id: 42, method: "textDocument/hover", params: AnyCodable("test"))
        let data = try LSPEncoder.encode(original)
        let decoded = try LSPEncoder.decode(JSONRPCRequest.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.method == original.method)
        #expect(decoded.jsonrpc == "2.0")
    }

    @Test
    func requestIdCorrelation() throws {
        let request = JSONRPCRequest(id: 99, method: "test")
        let requestData = try LSPEncoder.encode(request)
        let requestJSON = try JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        let requestId = requestJSON?["id"] as? Int

        let responseJSON: [String: Any] = ["jsonrpc": "2.0", "id": requestId!, "result": "ok"]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = try LSPEncoder.decode(JSONRPCResponse.self, from: responseData)

        #expect(response.id == request.id)
    }

    // MARK: - Mock Transport

    @Test
    func mockTransportSendRecords() throws {
        let mock = MockJSONRPCTransport()
        let data = "test".data(using: .utf8)!
        try mock.send(data)
        #expect(mock.sentMessages.count == 1)
        #expect(mock.sentMessages[0] == data)
    }

    @Test
    func mockTransportReceiveYieldsMessage() async throws {
        let mock = MockJSONRPCTransport()
        let expected = #"{"jsonrpc":"2.0","id":1,"result":null}"#.data(using: .utf8)!

        Task {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            mock.receive(expected)
            mock.close()
        }

        var received: [Data] = []
        for await message in mock.messages {
            received.append(message)
        }
        #expect(received.count == 1)
        #expect(received[0] == expected)
    }

    @Test
    func mockTransportCloseStopsSend() {
        let mock = MockJSONRPCTransport()
        mock.close()
        #expect(throws: JSONRPCTransportError.connectionClosed) {
            try mock.send("test".data(using: .utf8)!)
        }
    }

    @Test
    func mockTransportReceiveResponse() async throws {
        let mock = MockJSONRPCTransport()

        Task {
            try? await Task.sleep(nanoseconds: 10_000_000)
            mock.receiveResponse(id: 1, result: ["capabilities": [:] as [String: Any]])
            mock.close()
        }

        var received: [Data] = []
        for await message in mock.messages {
            received.append(message)
        }

        #expect(received.count == 1)
        let json = try JSONSerialization.jsonObject(with: received[0]) as? [String: Any]
        #expect(json?["id"] as? Int == 1)
    }

    @Test
    func mockTransportReceiveNotification() async throws {
        let mock = MockJSONRPCTransport()

        Task {
            try? await Task.sleep(nanoseconds: 10_000_000)
            mock.receiveNotification(method: "textDocument/publishDiagnostics", params: ["uri": "file:///test.swift", "diagnostics": [] as [Any]])
            mock.close()
        }

        var received: [Data] = []
        for await message in mock.messages {
            received.append(message)
        }

        #expect(received.count == 1)
        let json = try JSONSerialization.jsonObject(with: received[0]) as? [String: Any]
        #expect(json?["method"] as? String == "textDocument/publishDiagnostics")
    }

    @Test
    func mockTransportLastSentJSON() throws {
        let mock = MockJSONRPCTransport()
        let request = JSONRPCRequest(id: 1, method: "test")
        try mock.send(LSPEncoder.encode(request))
        let json = mock.lastSentJSON()
        #expect(json?["method"] as? String == "test")
    }

    @Test
    func mockTransportAllSentJSON() throws {
        let mock = MockJSONRPCTransport()
        try mock.send(LSPEncoder.encode(JSONRPCRequest(id: 1, method: "first")))
        try mock.send(LSPEncoder.encode(JSONRPCRequest(id: 2, method: "second")))
        let all = mock.allSentJSON()
        #expect(all.count == 2)
        #expect(all[0]["method"] as? String == "first")
        #expect(all[1]["method"] as? String == "second")
    }
}
