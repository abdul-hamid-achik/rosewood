import Foundation
import Testing
@testable import Rosewood

struct LSPTypesTests {

    // MARK: - LSPPosition

    @Test
    func lspPositionCoding() throws {
        let position = LSPPosition(line: 5, character: 10)
        let data = try LSPEncoder.encode(position)
        let decoded = try LSPEncoder.decode(LSPPosition.self, from: data)
        #expect(decoded == position)
    }

    @Test
    func lspPositionZeroIndexed() throws {
        let json = #"{"line":0,"character":0}"#.data(using: .utf8)!
        let position = try LSPEncoder.decode(LSPPosition.self, from: json)
        #expect(position.line == 0)
        #expect(position.character == 0)
    }

    // MARK: - LSPRange

    @Test
    func lspRangeCoding() throws {
        let range = LSPRange(
            start: LSPPosition(line: 1, character: 5),
            end: LSPPosition(line: 1, character: 15)
        )
        let data = try LSPEncoder.encode(range)
        let decoded = try LSPEncoder.decode(LSPRange.self, from: data)
        #expect(decoded == range)
    }

    @Test
    func lspRangeEmptyRange() throws {
        let range = LSPRange(
            start: LSPPosition(line: 3, character: 7),
            end: LSPPosition(line: 3, character: 7)
        )
        let data = try LSPEncoder.encode(range)
        let decoded = try LSPEncoder.decode(LSPRange.self, from: data)
        #expect(decoded.start == decoded.end)
    }

    // MARK: - LSPLocation

    @Test
    func lspLocationCoding() throws {
        let location = LSPLocation(
            uri: "file:///Users/test/main.swift",
            range: LSPRange(
                start: LSPPosition(line: 10, character: 0),
                end: LSPPosition(line: 10, character: 20)
            )
        )
        let data = try LSPEncoder.encode(location)
        let decoded = try LSPEncoder.decode(LSPLocation.self, from: data)
        #expect(decoded == location)
    }

    @Test
    func lspLocationWithSpacesInPath() throws {
        let json = """
        {"uri":"file:///Users/test%20user/my%20project/main.swift","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}}}
        """.data(using: .utf8)!
        let location = try LSPEncoder.decode(LSPLocation.self, from: json)
        #expect(location.uri.contains("%20"))
    }

    // MARK: - TextDocumentItem

    @Test
    func textDocumentItemCoding() throws {
        let item = TextDocumentItem(
            uri: "file:///test.swift",
            languageId: "swift",
            version: 1,
            text: "import Foundation\n"
        )
        let data = try LSPEncoder.encode(item)
        let decoded = try LSPEncoder.decode(TextDocumentItem.self, from: data)
        #expect(decoded.uri == item.uri)
        #expect(decoded.languageId == item.languageId)
        #expect(decoded.version == item.version)
        #expect(decoded.text == item.text)
    }

    // MARK: - InitializeParams

    @Test
    func initializeParamsCoding() throws {
        let params = InitializeParams(
            processId: 12345,
            clientInfo: ClientInfo(name: "Rosewood", version: "0.1.0"),
            rootUri: "file:///Users/test/project",
            capabilities: ClientCapabilities(
                textDocument: TextDocumentClientCapabilities(
                    completion: CompletionClientCapabilities(
                        completionItem: CompletionItemClientCapabilities(snippetSupport: false)
                    ),
                    hover: HoverClientCapabilities(contentFormat: ["plaintext"]),
                    publishDiagnostics: PublishDiagnosticsClientCapabilities(relatedInformation: true)
                )
            )
        )
        let data = try LSPEncoder.encode(params)
        let decoded = try LSPEncoder.decode(InitializeParams.self, from: data)
        #expect(decoded.processId == 12345)
        #expect(decoded.clientInfo?.name == "Rosewood")
        #expect(decoded.rootUri == "file:///Users/test/project")
    }

    // MARK: - InitializeResult

    @Test
    func initializeResultDecoding() throws {
        let json = """
        {
            "capabilities": {
                "textDocumentSync": 1,
                "completionProvider": {
                    "triggerCharacters": ["."],
                    "resolveProvider": true
                },
                "hoverProvider": true,
                "definitionProvider": true
            }
        }
        """.data(using: .utf8)!
        let result = try LSPEncoder.decode(InitializeResult.self, from: json)
        #expect(result.capabilities.supportsCompletion)
        #expect(result.capabilities.supportsHover)
        #expect(result.capabilities.supportsDefinition)
        #expect(result.capabilities.completionProvider?.triggerCharacters == ["."])
    }

    // MARK: - ServerCapabilities

    @Test
    func serverCapabilitiesDecoding() throws {
        let json = """
        {
            "textDocumentSync": {"openClose": true, "change": 1},
            "completionProvider": {"triggerCharacters": [".", ":"], "resolveProvider": false},
            "hoverProvider": true,
            "definitionProvider": true
        }
        """.data(using: .utf8)!
        let caps = try LSPEncoder.decode(ServerCapabilities.self, from: json)
        #expect(caps.supportsCompletion)
        #expect(caps.supportsHover)
        #expect(caps.supportsDefinition)
        #expect(caps.completionProvider?.triggerCharacters?.count == 2)
    }

    @Test
    func serverCapabilitiesMissingOptionals() throws {
        let json = """
        {}
        """.data(using: .utf8)!
        let caps = try LSPEncoder.decode(ServerCapabilities.self, from: json)
        #expect(!caps.supportsCompletion)
        #expect(!caps.supportsHover)
        #expect(!caps.supportsDefinition)
        #expect(caps.completionProvider == nil)
    }

    @Test
    func serverCapabilitiesHoverAsBool() throws {
        let jsonTrue = #"{"hoverProvider":true}"#.data(using: .utf8)!
        let capsTrue = try LSPEncoder.decode(ServerCapabilities.self, from: jsonTrue)
        #expect(capsTrue.supportsHover)

        let jsonFalse = #"{"hoverProvider":false}"#.data(using: .utf8)!
        let capsFalse = try LSPEncoder.decode(ServerCapabilities.self, from: jsonFalse)
        #expect(!capsFalse.supportsHover)
    }

    @Test
    func serverCapabilitiesDefinitionAsBool() throws {
        let jsonTrue = #"{"definitionProvider":true}"#.data(using: .utf8)!
        let capsTrue = try LSPEncoder.decode(ServerCapabilities.self, from: jsonTrue)
        #expect(capsTrue.supportsDefinition)
    }

    // MARK: - Diagnostics

    @Test
    func publishDiagnosticsDecoding() throws {
        let json = """
        {
            "uri": "file:///test.swift",
            "diagnostics": [
                {
                    "range": {
                        "start": {"line": 5, "character": 0},
                        "end": {"line": 5, "character": 10}
                    },
                    "severity": 1,
                    "source": "sourcekit",
                    "message": "cannot find type 'Foo' in scope"
                }
            ]
        }
        """.data(using: .utf8)!
        let params = try LSPEncoder.decode(PublishDiagnosticsParams.self, from: json)
        #expect(params.uri == "file:///test.swift")
        #expect(params.diagnostics.count == 1)
        #expect(params.diagnostics[0].severity == .error)
        #expect(params.diagnostics[0].message == "cannot find type 'Foo' in scope")
        #expect(params.diagnostics[0].source == "sourcekit")
    }

    @Test
    func diagnosticSeverityRawValues() {
        #expect(DiagnosticSeverity.error.rawValue == 1)
        #expect(DiagnosticSeverity.warning.rawValue == 2)
        #expect(DiagnosticSeverity.information.rawValue == 3)
        #expect(DiagnosticSeverity.hint.rawValue == 4)
    }

    @Test
    func diagnosticWithRelatedInfo() throws {
        let json = """
        {
            "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 5}},
            "severity": 1,
            "message": "error here",
            "relatedInformation": [
                {
                    "location": {
                        "uri": "file:///other.swift",
                        "range": {"start": {"line": 10, "character": 0}, "end": {"line": 10, "character": 5}}
                    },
                    "message": "related to this"
                }
            ]
        }
        """.data(using: .utf8)!
        let diag = try LSPEncoder.decode(LSPDiagnostic.self, from: json)
        #expect(diag.relatedInformation?.count == 1)
        #expect(diag.relatedInformation?[0].message == "related to this")
        #expect(diag.relatedInformation?[0].location.uri == "file:///other.swift")
    }

    @Test
    func diagnosticMinimalFields() throws {
        let json = """
        {
            "range": {"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 3}},
            "message": "something wrong"
        }
        """.data(using: .utf8)!
        let diag = try LSPEncoder.decode(LSPDiagnostic.self, from: json)
        #expect(diag.severity == nil)
        #expect(diag.code == nil)
        #expect(diag.source == nil)
        #expect(diag.relatedInformation == nil)
        #expect(diag.message == "something wrong")
    }

    @Test
    func diagnosticWithCodeAsInt() throws {
        let json = """
        {
            "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}},
            "severity": 2,
            "code": 42,
            "message": "warning"
        }
        """.data(using: .utf8)!
        let diag = try LSPEncoder.decode(LSPDiagnostic.self, from: json)
        #expect(diag.code?.intValue == 42)
    }

    @Test
    func diagnosticWithCodeAsString() throws {
        let json = """
        {
            "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}},
            "severity": 2,
            "code": "E001",
            "message": "warning"
        }
        """.data(using: .utf8)!
        let diag = try LSPEncoder.decode(LSPDiagnostic.self, from: json)
        #expect(diag.code?.stringValue == "E001")
    }

    @Test
    func diagnosticId() {
        let diag = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 5, character: 3),
                end: LSPPosition(line: 5, character: 10)
            ),
            message: "test error"
        )
        #expect(diag.id == "5:3-5:10|test error")
    }

    // MARK: - Completion

    @Test
    func completionListDecoding() throws {
        let json = """
        {
            "isIncomplete": false,
            "items": [
                {"label": "append", "kind": 2, "detail": "func append(_ item: Element)"},
                {"label": "count", "kind": 10, "detail": "var count: Int"}
            ]
        }
        """.data(using: .utf8)!
        let list = try LSPEncoder.decode(CompletionList.self, from: json)
        #expect(!list.isIncomplete)
        #expect(list.items.count == 2)
        #expect(list.items[0].label == "append")
        #expect(list.items[1].label == "count")
    }

    @Test
    func completionItemDecoding() throws {
        let json = """
        {
            "label": "description",
            "kind": 10,
            "detail": "var description: String",
            "insertText": "description"
        }
        """.data(using: .utf8)!
        let item = try LSPEncoder.decode(CompletionItem.self, from: json)
        #expect(item.label == "description")
        #expect(item.kind == .property)
        #expect(item.detail == "var description: String")
        #expect(item.insertText == "description")
        #expect(item.insertionText == "description")
    }

    @Test
    func completionItemKindValues() {
        #expect(CompletionItemKind.text.rawValue == 1)
        #expect(CompletionItemKind.method.rawValue == 2)
        #expect(CompletionItemKind.function.rawValue == 3)
        #expect(CompletionItemKind.constructor.rawValue == 4)
        #expect(CompletionItemKind.field.rawValue == 5)
        #expect(CompletionItemKind.variable.rawValue == 6)
        #expect(CompletionItemKind.class.rawValue == 7)
        #expect(CompletionItemKind.interface.rawValue == 8)
        #expect(CompletionItemKind.module.rawValue == 9)
        #expect(CompletionItemKind.property.rawValue == 10)
        #expect(CompletionItemKind.unit.rawValue == 11)
        #expect(CompletionItemKind.value.rawValue == 12)
        #expect(CompletionItemKind.enum.rawValue == 13)
        #expect(CompletionItemKind.keyword.rawValue == 14)
        #expect(CompletionItemKind.snippet.rawValue == 15)
        #expect(CompletionItemKind.color.rawValue == 16)
        #expect(CompletionItemKind.file.rawValue == 17)
        #expect(CompletionItemKind.reference.rawValue == 18)
        #expect(CompletionItemKind.folder.rawValue == 19)
        #expect(CompletionItemKind.enumMember.rawValue == 20)
        #expect(CompletionItemKind.constant.rawValue == 21)
        #expect(CompletionItemKind.struct.rawValue == 22)
        #expect(CompletionItemKind.event.rawValue == 23)
        #expect(CompletionItemKind.operator.rawValue == 24)
        #expect(CompletionItemKind.typeParameter.rawValue == 25)
    }

    @Test
    func completionItemWithTextEdit() throws {
        let json = """
        {
            "label": "forEach",
            "kind": 2,
            "textEdit": {
                "range": {"start": {"line": 5, "character": 10}, "end": {"line": 5, "character": 13}},
                "newText": "forEach"
            }
        }
        """.data(using: .utf8)!
        let item = try LSPEncoder.decode(CompletionItem.self, from: json)
        #expect(item.textEdit != nil)
        #expect(item.insertionText == "forEach")
    }

    @Test
    func completionItemWithStringDocumentation() throws {
        let json = """
        {
            "label": "print",
            "kind": 3,
            "documentation": "Writes the textual representations to standard output."
        }
        """.data(using: .utf8)!
        let item = try LSPEncoder.decode(CompletionItem.self, from: json)
        #expect(item.documentationString == "Writes the textual representations to standard output.")
    }

    @Test
    func completionItemWithMarkupDocumentation() throws {
        let json = """
        {
            "label": "print",
            "kind": 3,
            "documentation": {"kind": "markdown", "value": "**Prints** to stdout."}
        }
        """.data(using: .utf8)!
        let item = try LSPEncoder.decode(CompletionItem.self, from: json)
        #expect(item.documentationString == "**Prints** to stdout.")
    }

    @Test
    func completionItemInsertionTextPrecedence() {
        // textEdit takes priority over insertText which takes priority over label
        let withTextEdit = CompletionItem(
            label: "label",
            kind: nil,
            detail: nil,
            documentation: nil,
            insertText: "insertText",
            textEdit: TextEdit(
                range: LSPRange(start: LSPPosition(line: 0, character: 0), end: LSPPosition(line: 0, character: 0)),
                newText: "textEditText"
            ),
            filterText: nil,
            sortText: nil
        )
        #expect(withTextEdit.insertionText == "textEditText")

        let withInsertText = CompletionItem(
            label: "label",
            kind: nil,
            detail: nil,
            documentation: nil,
            insertText: "insertText",
            textEdit: nil,
            filterText: nil,
            sortText: nil
        )
        #expect(withInsertText.insertionText == "insertText")

        let labelOnly = CompletionItem(
            label: "label",
            kind: nil,
            detail: nil,
            documentation: nil,
            insertText: nil,
            textEdit: nil,
            filterText: nil,
            sortText: nil
        )
        #expect(labelOnly.insertionText == "label")
    }

    @Test
    func completionTriggerKindValues() {
        #expect(CompletionTriggerKind.invoked.rawValue == 1)
        #expect(CompletionTriggerKind.triggerCharacter.rawValue == 2)
        #expect(CompletionTriggerKind.triggerForIncompleteCompletions.rawValue == 3)
    }

    // MARK: - Hover

    @Test
    func hoverResultWithStringContents() throws {
        let json = """
        {"contents": "func hello() -> String", "range": {"start": {"line": 1, "character": 5}, "end": {"line": 1, "character": 10}}}
        """.data(using: .utf8)!
        let result = try LSPEncoder.decode(HoverResult.self, from: json)
        #expect(result.contentsString == "func hello() -> String")
        #expect(result.range != nil)
    }

    @Test
    func hoverResultWithMarkupContent() throws {
        let json = """
        {"contents": {"kind": "markdown", "value": "```swift\\nfunc hello() -> String\\n```"}}
        """.data(using: .utf8)!
        let result = try LSPEncoder.decode(HoverResult.self, from: json)
        #expect(result.contentsString.contains("func hello()"))
    }

    @Test
    func hoverResultWithRange() throws {
        let json = """
        {"contents": "test", "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 4}}}
        """.data(using: .utf8)!
        let result = try LSPEncoder.decode(HoverResult.self, from: json)
        #expect(result.range != nil)
        #expect(result.range?.start.line == 0)
    }

    @Test
    func hoverResultWithoutRange() throws {
        let json = #"{"contents": "test"}"#.data(using: .utf8)!
        let result = try LSPEncoder.decode(HoverResult.self, from: json)
        #expect(result.range == nil)
        #expect(result.contentsString == "test")
    }

    @Test
    func hoverResultWithArrayContents() throws {
        let json = """
        {"contents": ["first line", {"kind": "markdown", "value": "second line"}]}
        """.data(using: .utf8)!
        let result = try LSPEncoder.decode(HoverResult.self, from: json)
        #expect(result.contentsString.contains("first line"))
        #expect(result.contentsString.contains("second line"))
    }

    // MARK: - Definition

    @Test
    func definitionResultSingleLocation() throws {
        let json = """
        {"uri": "file:///test.swift", "range": {"start": {"line": 10, "character": 4}, "end": {"line": 10, "character": 20}}}
        """.data(using: .utf8)!
        let location = try LSPEncoder.decode(LSPLocation.self, from: json)
        #expect(location.uri == "file:///test.swift")
        #expect(location.range.start.line == 10)
    }

    @Test
    func definitionResultMultipleLocations() throws {
        let json = """
        [
            {"uri": "file:///a.swift", "range": {"start": {"line": 1, "character": 0}, "end": {"line": 1, "character": 5}}},
            {"uri": "file:///b.swift", "range": {"start": {"line": 2, "character": 0}, "end": {"line": 2, "character": 5}}}
        ]
        """.data(using: .utf8)!
        let locations = try LSPEncoder.decode([LSPLocation].self, from: json)
        #expect(locations.count == 2)
        #expect(locations[0].uri == "file:///a.swift")
        #expect(locations[1].uri == "file:///b.swift")
    }

    @Test
    func definitionResultEmpty() throws {
        let json = "[]".data(using: .utf8)!
        let locations = try LSPEncoder.decode([LSPLocation].self, from: json)
        #expect(locations.isEmpty)
    }

    // MARK: - TextEdit

    @Test
    func textEditCoding() throws {
        let edit = TextEdit(
            range: LSPRange(
                start: LSPPosition(line: 5, character: 0),
                end: LSPPosition(line: 5, character: 10)
            ),
            newText: "replacement"
        )
        let data = try LSPEncoder.encode(edit)
        let decoded = try LSPEncoder.decode(TextEdit.self, from: data)
        #expect(decoded == edit)
    }

    // MARK: - Document Sync Params

    @Test
    func didOpenTextDocumentParamsCoding() throws {
        let params = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(
                uri: "file:///test.swift",
                languageId: "swift",
                version: 0,
                text: "import Foundation"
            )
        )
        let data = try LSPEncoder.encode(params)
        let decoded = try LSPEncoder.decode(DidOpenTextDocumentParams.self, from: data)
        #expect(decoded.textDocument.uri == "file:///test.swift")
        #expect(decoded.textDocument.languageId == "swift")
    }

    @Test
    func didChangeTextDocumentParamsCoding() throws {
        let params = DidChangeTextDocumentParams(
            textDocument: VersionedTextDocumentIdentifier(uri: "file:///test.swift", version: 3),
            contentChanges: [TextDocumentContentChangeEvent(text: "new content")]
        )
        let data = try LSPEncoder.encode(params)
        let decoded = try LSPEncoder.decode(DidChangeTextDocumentParams.self, from: data)
        #expect(decoded.textDocument.version == 3)
        #expect(decoded.contentChanges.count == 1)
    }

    @Test
    func didSaveTextDocumentParamsCoding() throws {
        let params = DidSaveTextDocumentParams(
            textDocument: TextDocumentIdentifier(uri: "file:///test.swift")
        )
        let data = try LSPEncoder.encode(params)
        let decoded = try LSPEncoder.decode(DidSaveTextDocumentParams.self, from: data)
        #expect(decoded.textDocument.uri == "file:///test.swift")
    }

    @Test
    func didCloseTextDocumentParamsCoding() throws {
        let params = DidCloseTextDocumentParams(
            textDocument: TextDocumentIdentifier(uri: "file:///test.swift")
        )
        let data = try LSPEncoder.encode(params)
        let decoded = try LSPEncoder.decode(DidCloseTextDocumentParams.self, from: data)
        #expect(decoded.textDocument.uri == "file:///test.swift")
    }

    // MARK: - JSON-RPC Envelope Types

    @Test
    func jsonRPCRequestCoding() throws {
        let request = JSONRPCRequest(id: 1, method: "initialize", params: AnyCodable(["processId": 123]))
        let data = try LSPEncoder.encode(request)
        let decoded = try LSPEncoder.decode(JSONRPCRequest.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == 1)
        #expect(decoded.method == "initialize")
    }

    @Test
    func jsonRPCNotificationCoding() throws {
        let notification = JSONRPCNotification(method: "initialized", params: nil)
        let data = try LSPEncoder.encode(notification)
        let decoded = try LSPEncoder.decode(JSONRPCNotification.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.method == "initialized")
        #expect(decoded.params == nil)
    }

    @Test
    func jsonRPCResponseCoding() throws {
        let json = """
        {"jsonrpc": "2.0", "id": 1, "result": {"capabilities": {}}}
        """.data(using: .utf8)!
        let response = try LSPEncoder.decode(JSONRPCResponse.self, from: json)
        #expect(response.jsonrpc == "2.0")
        #expect(response.id == 1)
        #expect(response.error == nil)
    }

    @Test
    func jsonRPCResponseWithError() throws {
        let json = """
        {"jsonrpc": "2.0", "id": 1, "error": {"code": -32600, "message": "Invalid Request"}}
        """.data(using: .utf8)!
        let response = try LSPEncoder.decode(JSONRPCResponse.self, from: json)
        #expect(response.error?.code == -32600)
        #expect(response.error?.message == "Invalid Request")
        #expect(response.result == nil)
    }

    @Test
    func jsonRPCVersionField() throws {
        let request = JSONRPCRequest(id: 42, method: "test")
        let data = try LSPEncoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["jsonrpc"] as? String == "2.0")

        let notification = JSONRPCNotification(method: "test")
        let notifData = try LSPEncoder.encode(notification)
        let notifJson = try JSONSerialization.jsonObject(with: notifData) as? [String: Any]
        #expect(notifJson?["jsonrpc"] as? String == "2.0")
    }

    // MARK: - AnyCodable

    @Test
    func anyCodableString() throws {
        let value = AnyCodable("hello")
        let data = try LSPEncoder.encode(value)
        let decoded = try LSPEncoder.decode(AnyCodable.self, from: data)
        #expect(decoded.stringValue == "hello")
    }

    @Test
    func anyCodableInt() throws {
        let value = AnyCodable(42)
        let data = try LSPEncoder.encode(value)
        let decoded = try LSPEncoder.decode(AnyCodable.self, from: data)
        #expect(decoded.intValue == 42)
    }

    @Test
    func anyCodableBool() throws {
        let value = AnyCodable(true)
        let data = try LSPEncoder.encode(value)
        let decoded = try LSPEncoder.decode(AnyCodable.self, from: data)
        #expect(decoded.boolValue == true)
    }

    @Test
    func anyCodableNull() throws {
        let value = AnyCodable(nil)
        let data = try LSPEncoder.encode(value)
        let decoded = try LSPEncoder.decode(AnyCodable.self, from: data)
        #expect(decoded.value == nil)
    }

    @Test
    func anyCodableNestedObject() throws {
        let dict: [String: Any] = ["key": "value", "number": 42]
        let value = AnyCodable(dict)
        let data = try LSPEncoder.encode(value)
        let decoded = try LSPEncoder.decode(AnyCodable.self, from: data)
        #expect(decoded.dictValue?["key"] as? String == "value")
    }

    @Test
    func anyCodableArray() throws {
        let array: [Any] = [1, "two", true]
        let value = AnyCodable(array)
        let data = try LSPEncoder.encode(value)
        let decoded = try LSPEncoder.decode(AnyCodable.self, from: data)
        #expect(decoded.arrayValue?.count == 3)
    }

    @Test
    func anyCodableRoundTrip() throws {
        let original = AnyCodable("round trip test")
        let data = try LSPEncoder.encode(original)
        let decoded = try LSPEncoder.decode(AnyCodable.self, from: data)
        #expect(original == decoded)
    }

    @Test
    func anyCodableEquality() {
        #expect(AnyCodable("a") == AnyCodable("a"))
        #expect(AnyCodable("a") != AnyCodable("b"))
        #expect(AnyCodable(42) == AnyCodable(42))
        #expect(AnyCodable(true) == AnyCodable(true))
        #expect(AnyCodable(nil) == AnyCodable(nil))
        #expect(AnyCodable("a") != AnyCodable(42))
    }

    // MARK: - LSPEncoder

    @Test
    func encodeToAnyCodable() {
        let position = LSPPosition(line: 1, character: 5)
        let encoded = LSPEncoder.encodeToAnyCodable(position)
        #expect(encoded != nil)
        #expect(encoded?.dictValue?["line"] as? Int == 1)
        #expect(encoded?.dictValue?["character"] as? Int == 5)
    }

    // MARK: - CompletionItemKind Symbol Names

    @Test
    func completionItemKindSymbolNames() {
        #expect(!CompletionItemKind.text.symbolName.isEmpty)
        #expect(!CompletionItemKind.method.symbolName.isEmpty)
        #expect(!CompletionItemKind.function.symbolName.isEmpty)
        #expect(!CompletionItemKind.constructor.symbolName.isEmpty)
        #expect(!CompletionItemKind.field.symbolName.isEmpty)
        #expect(!CompletionItemKind.variable.symbolName.isEmpty)
        #expect(!CompletionItemKind.class.symbolName.isEmpty)
        #expect(!CompletionItemKind.interface.symbolName.isEmpty)
        #expect(!CompletionItemKind.module.symbolName.isEmpty)
        #expect(!CompletionItemKind.property.symbolName.isEmpty)
        #expect(!CompletionItemKind.enum.symbolName.isEmpty)
        #expect(!CompletionItemKind.keyword.symbolName.isEmpty)
        #expect(!CompletionItemKind.snippet.symbolName.isEmpty)
        #expect(!CompletionItemKind.struct.symbolName.isEmpty)
        #expect(!CompletionItemKind.typeParameter.symbolName.isEmpty)
    }
}
