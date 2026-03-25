import Foundation

struct EditorTab: Identifiable {
    let id: UUID
    var filePath: URL?
    var fileName: String
    var content: String
    var originalContent: String
    var isDirty: Bool
    var cursorPosition: CursorPosition
    var pendingLineJump: Int?
    var documentVersion: Int
    var documentMetadata: FileDocumentMetadata

    init(
        id: UUID = UUID(),
        filePath: URL? = nil,
        fileName: String = "Untitled",
        content: String = "",
        originalContent: String = "",
        isDirty: Bool = false,
        cursorPosition: CursorPosition = CursorPosition(),
        pendingLineJump: Int? = nil,
        documentVersion: Int = 0,
        documentMetadata: FileDocumentMetadata = .utf8LF
    ) {
        self.id = id
        self.filePath = filePath
        self.fileName = fileName
        self.content = content
        self.originalContent = originalContent
        self.isDirty = isDirty
        self.cursorPosition = cursorPosition
        self.pendingLineJump = pendingLineJump
        self.documentVersion = documentVersion
        self.documentMetadata = documentMetadata
    }

    var documentURI: String? {
        filePath?.absoluteString
    }

    var language: String {
        guard let path = filePath else { return "plaintext" }
        let ext = (path.pathExtension as NSString).lowercased
        return Self.languageFromExtension(ext)
    }

    static func languageFromExtension(_ ext: String) -> String {
        switch ext {
        case "swift": return "swift"
        case "py": return "python"
        case "go": return "go"
        case "rb": return "ruby"
        case "js", "mjs", "cjs": return "javascript"
        case "ts", "mts", "cts": return "typescript"
        case "jsx": return "javascript"
        case "tsx": return "typescript"
        case "vue": return "vue"
        case "kt", "kts": return "kotlin"
        case "ex", "exs": return "elixir"
        case "sh", "bash", "zsh": return "bash"
        case "md", "markdown": return "markdown"
        case "dockerfile": return "dockerfile"
        case "yml", "yaml": return "yaml"
        case "json": return "json"
        case "toml": return "toml"
        case "rs": return "rust"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "hh": return "cpp"
        case "php": return "php"
        case "zig": return "zig"
        case "java": return "java"
        case "lua": return "lua"
        case "dart": return "dart"
        case "hs", "lhs": return "haskell"
        case "ml", "mli": return "ocaml"
        case "css": return "css"
        case "html", "htm": return "html"
        case "xml", "xsl": return "xml"
        case "sql": return "sql"
        case "r": return "r"
        case "scala", "sc": return "scala"
        default: return "plaintext"
        }
    }
}

struct CursorPosition {
    var line: Int = 1
    var column: Int = 1

    var description: String {
        "Line \(line), Col \(column)"
    }
}
