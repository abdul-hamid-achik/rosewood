import Foundation

// MARK: - AnyCodable

/// A type-erased Codable wrapper for handling polymorphic JSON fields in the LSP protocol.
struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value == nil {
            try container.encodeNil()
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any?] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any?] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (nil, nil): return true
        case let (l as Bool, r as Bool): return l == r
        case let (l as Int, r as Int): return l == r
        case let (l as Double, r as Double): return l == r
        case let (l as String, r as String): return l == r
        default: return false
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
    var dictValue: [String: Any?]? { value as? [String: Any?] }
    var arrayValue: [Any?]? { value as? [Any?] }
}

// MARK: - Positions & Ranges

struct LSPPosition: Codable, Equatable, Sendable {
    let line: Int
    let character: Int
}

struct LSPRange: Codable, Equatable, Sendable {
    let start: LSPPosition
    let end: LSPPosition
}

struct LSPLocation: Codable, Equatable, Sendable {
    let uri: String
    let range: LSPRange
}

// MARK: - Text Document Identifiers

struct TextDocumentIdentifier: Codable, Sendable {
    let uri: String
}

struct VersionedTextDocumentIdentifier: Codable, Sendable {
    let uri: String
    let version: Int
}

struct TextDocumentItem: Codable, Sendable {
    let uri: String
    let languageId: String
    let version: Int
    let text: String
}

// MARK: - Text Edits

struct TextEdit: Codable, Equatable, Sendable {
    let range: LSPRange
    let newText: String
}

struct TextDocumentContentChangeEvent: Codable, Sendable {
    let text: String
}

// MARK: - Initialization

struct ClientInfo: Codable, Sendable {
    let name: String
    let version: String?
}

struct ClientCapabilities: Codable, Sendable {
    let textDocument: TextDocumentClientCapabilities?

    init(textDocument: TextDocumentClientCapabilities? = nil) {
        self.textDocument = textDocument
    }
}

struct TextDocumentClientCapabilities: Codable, Sendable {
    let completion: CompletionClientCapabilities?
    let hover: HoverClientCapabilities?
    let references: ReferencesClientCapabilities?
    let publishDiagnostics: PublishDiagnosticsClientCapabilities?

    init(
        completion: CompletionClientCapabilities? = nil,
        hover: HoverClientCapabilities? = nil,
        references: ReferencesClientCapabilities? = nil,
        publishDiagnostics: PublishDiagnosticsClientCapabilities? = nil
    ) {
        self.completion = completion
        self.hover = hover
        self.references = references
        self.publishDiagnostics = publishDiagnostics
    }
}

struct CompletionClientCapabilities: Codable, Sendable {
    let completionItem: CompletionItemClientCapabilities?

    init(completionItem: CompletionItemClientCapabilities? = nil) {
        self.completionItem = completionItem
    }
}

struct CompletionItemClientCapabilities: Codable, Sendable {
    let snippetSupport: Bool?
    let documentationFormat: [String]?

    init(snippetSupport: Bool? = nil, documentationFormat: [String]? = nil) {
        self.snippetSupport = snippetSupport
        self.documentationFormat = documentationFormat
    }
}

struct HoverClientCapabilities: Codable, Sendable {
    let contentFormat: [String]?

    init(contentFormat: [String]? = nil) {
        self.contentFormat = contentFormat
    }
}

struct ReferencesClientCapabilities: Codable, Sendable {
    let dynamicRegistration: Bool?

    init(dynamicRegistration: Bool? = nil) {
        self.dynamicRegistration = dynamicRegistration
    }
}

struct PublishDiagnosticsClientCapabilities: Codable, Sendable {
    let relatedInformation: Bool?

    init(relatedInformation: Bool? = nil) {
        self.relatedInformation = relatedInformation
    }
}

struct InitializeParams: Codable, Sendable {
    let processId: Int?
    let clientInfo: ClientInfo?
    let rootUri: String?
    let capabilities: ClientCapabilities

    init(
        processId: Int? = nil,
        clientInfo: ClientInfo? = nil,
        rootUri: String? = nil,
        capabilities: ClientCapabilities = ClientCapabilities()
    ) {
        self.processId = processId
        self.clientInfo = clientInfo
        self.rootUri = rootUri
        self.capabilities = capabilities
    }
}

struct InitializeResult: Codable, Sendable {
    let capabilities: ServerCapabilities
}

struct ServerCapabilities: Codable, Sendable {
    let textDocumentSync: AnyCodable?
    let completionProvider: CompletionOptions?
    let hoverProvider: AnyCodable?
    let definitionProvider: AnyCodable?
    let referencesProvider: AnyCodable?

    init(
        textDocumentSync: AnyCodable? = nil,
        completionProvider: CompletionOptions? = nil,
        hoverProvider: AnyCodable? = nil,
        definitionProvider: AnyCodable? = nil,
        referencesProvider: AnyCodable? = nil
    ) {
        self.textDocumentSync = textDocumentSync
        self.completionProvider = completionProvider
        self.hoverProvider = hoverProvider
        self.definitionProvider = definitionProvider
        self.referencesProvider = referencesProvider
    }

    var supportsCompletion: Bool {
        completionProvider != nil
    }

    var supportsHover: Bool {
        guard let provider = hoverProvider else { return false }
        if let boolVal = provider.boolValue { return boolVal }
        return provider.value != nil
    }

    var supportsDefinition: Bool {
        guard let provider = definitionProvider else { return false }
        if let boolVal = provider.boolValue { return boolVal }
        return provider.value != nil
    }

    var supportsReferences: Bool {
        guard let provider = referencesProvider else { return false }
        if let boolVal = provider.boolValue { return boolVal }
        return provider.value != nil
    }
}

struct CompletionOptions: Codable, Sendable {
    let triggerCharacters: [String]?
    let resolveProvider: Bool?
}

// MARK: - Diagnostics

struct PublishDiagnosticsParams: Codable, Sendable {
    let uri: String
    let diagnostics: [LSPDiagnostic]
}

struct LSPDiagnostic: Codable, Equatable, Sendable, Identifiable {
    let range: LSPRange
    let severity: DiagnosticSeverity?
    let code: AnyCodable?
    let source: String?
    let message: String
    let relatedInformation: [DiagnosticRelatedInformation]?

    var id: String {
        "\(range.start.line):\(range.start.character)-\(range.end.line):\(range.end.character)|\(message)"
    }

    init(
        range: LSPRange,
        severity: DiagnosticSeverity? = nil,
        code: AnyCodable? = nil,
        source: String? = nil,
        message: String,
        relatedInformation: [DiagnosticRelatedInformation]? = nil
    ) {
        self.range = range
        self.severity = severity
        self.code = code
        self.source = source
        self.message = message
        self.relatedInformation = relatedInformation
    }

    static func == (lhs: LSPDiagnostic, rhs: LSPDiagnostic) -> Bool {
        lhs.range == rhs.range
            && lhs.severity == rhs.severity
            && lhs.message == rhs.message
            && lhs.source == rhs.source
    }
}

enum DiagnosticSeverity: Int, Codable, Sendable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

struct DiagnosticRelatedInformation: Codable, Equatable, Sendable {
    let location: LSPLocation
    let message: String
}

// MARK: - Completion

struct CompletionParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
    let context: CompletionContext?
}

struct CompletionContext: Codable, Sendable {
    let triggerKind: CompletionTriggerKind
    let triggerCharacter: String?
}

enum CompletionTriggerKind: Int, Codable, Sendable {
    case invoked = 1
    case triggerCharacter = 2
    case triggerForIncompleteCompletions = 3
}

struct CompletionList: Codable, Sendable {
    let isIncomplete: Bool
    let items: [CompletionItem]
}

struct CompletionItem: Codable, Sendable, Identifiable {
    let label: String
    let kind: CompletionItemKind?
    let detail: String?
    let documentation: AnyCodable?
    let insertText: String?
    let textEdit: TextEdit?
    let filterText: String?
    let sortText: String?

    var id: String { label }

    var insertionText: String {
        if let textEdit { return textEdit.newText }
        return insertText ?? label
    }

    var documentationString: String? {
        if let str = documentation?.stringValue { return str }
        if let dict = documentation?.dictValue, let value = dict["value"] as? String {
            return value
        }
        return nil
    }
}

enum CompletionItemKind: Int, Codable, Sendable {
    case text = 1
    case method = 2
    case function = 3
    case constructor = 4
    case field = 5
    case variable = 6
    case `class` = 7
    case interface = 8
    case module = 9
    case property = 10
    case unit = 11
    case value = 12
    case `enum` = 13
    case keyword = 14
    case snippet = 15
    case color = 16
    case file = 17
    case reference = 18
    case folder = 19
    case enumMember = 20
    case constant = 21
    case `struct` = 22
    case event = 23
    case `operator` = 24
    case typeParameter = 25

    var symbolName: String {
        switch self {
        case .text: return "doc.text"
        case .method, .function: return "function"
        case .constructor: return "hammer"
        case .field, .property: return "rectangle.and.pencil.and.ellipsis"
        case .variable: return "x.squareroot"
        case .class: return "c.square"
        case .interface: return "i.square"
        case .module: return "shippingbox"
        case .unit, .value: return "number"
        case .enum, .enumMember: return "e.square"
        case .keyword: return "k.square"
        case .snippet: return "text.insert"
        case .color: return "paintpalette"
        case .file: return "doc"
        case .reference: return "link"
        case .folder: return "folder"
        case .constant: return "c.circle"
        case .struct: return "s.square"
        case .event: return "bolt"
        case .operator: return "plus.forwardslash.minus"
        case .typeParameter: return "t.square"
        }
    }
}

// MARK: - Hover

struct HoverParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
}

struct ReferenceParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
    let context: ReferenceContext
}

struct ReferenceContext: Codable, Sendable {
    let includeDeclaration: Bool
}

struct HoverResult: Codable, Sendable {
    let contents: AnyCodable
    let range: LSPRange?

    var contentsString: String {
        if let str = contents.stringValue { return str }
        if let dict = contents.dictValue, let value = dict["value"] as? String {
            return value
        }
        if let array = contents.arrayValue {
            return array.compactMap { item -> String? in
                if let str = item as? String { return str }
                if let dict = item as? [String: Any?], let value = dict["value"] as? String {
                    return value
                }
                return nil
            }.joined(separator: "\n")
        }
        return ""
    }
}

// MARK: - Definition

struct DefinitionParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
}

// MARK: - Document Sync Notifications

struct DidOpenTextDocumentParams: Codable, Sendable {
    let textDocument: TextDocumentItem
}

struct DidChangeTextDocumentParams: Codable, Sendable {
    let textDocument: VersionedTextDocumentIdentifier
    let contentChanges: [TextDocumentContentChangeEvent]
}

struct DidSaveTextDocumentParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
}

struct DidCloseTextDocumentParams: Codable, Sendable {
    let textDocument: TextDocumentIdentifier
}

// MARK: - JSON-RPC Envelope Types

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: AnyCodable?

    init(id: Int, method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCNotification: Codable, Sendable {
    let jsonrpc: String
    let method: String
    let params: AnyCodable?

    init(method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: JSONRPCError?
}

struct JSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

// MARK: - Encoding Helpers

enum LSPEncoder {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    static func encodeToAnyCodable<T: Encodable>(_ value: T) -> AnyCodable? {
        guard let data = try? encode(value),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return AnyCodable(json)
    }
}
