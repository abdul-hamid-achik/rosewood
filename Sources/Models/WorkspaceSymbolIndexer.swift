import Foundation

enum WorkspaceSymbolIndexer {
    private static let indexedExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "hh", "c", "cc", "cpp", "cxx",
        "go", "rs", "py", "rb", "js", "jsx", "ts", "tsx",
        "java", "kt", "kts", "scala", "sc", "zig", "lua"
    ]
    private static let fileSizeLimit = 512_000

    private static let patterns: [Pattern] = [
        Pattern(
            pattern: #"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*(?::[^=]+)?=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)\s*=>"#,
            indexedExtensions: ["js", "jsx", "ts", "tsx"],
            kindGroup: nil,
            nameGroup: 1,
            fixedKind: "function"
        ),
        Pattern(
            pattern: #"^\s*func\s*\([^)]*\)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#,
            indexedExtensions: ["go"],
            kindGroup: nil,
            nameGroup: 1,
            fixedKind: "func"
        ),
        Pattern(
            pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|internal|fileprivate|open|final|indirect|async|static|class|override|mutating|nonmutating|required|convenience|prefix|postfix|infix)\s+)*(class|struct|enum|protocol|actor|extension|func|typealias|macro)\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)"#,
            indexedExtensions: ["swift"]
        ),
        Pattern(
            pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|internal|fileprivate|open|final|indirect|async|static|class|override|mutating|nonmutating|required|convenience)\s+)*(var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=]+)?=\s*(?:\{|\([^)]*\)\s*(?:async\s*)?(?:throws\s*)?->)"#,
            indexedExtensions: ["swift"]
        ),
        Pattern(
            pattern: #"^\s*(?:export\s+)?(?:default\s+)?(?:abstract\s+)?(class|interface|enum|type)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#,
            indexedExtensions: ["js", "jsx", "ts", "tsx"]
        ),
        Pattern(
            pattern: #"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?(function)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#,
            indexedExtensions: ["js", "jsx", "ts", "tsx"]
        ),
        Pattern(
            pattern: #"^\s*(?:async\s+)?(def|class)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            indexedExtensions: ["py"]
        ),
        Pattern(
            pattern: #"^\s*(type|const|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            indexedExtensions: ["go"]
        ),
        Pattern(
            pattern: #"^\s*(?:(?:pub|pub\(crate\)|crate|unsafe|async|const|default)\s+)*(struct|enum|trait|type|fn|const|static)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            indexedExtensions: ["rs"]
        ),
        Pattern(
            pattern: #"^\s*(?:(?:public|private|protected|internal|open|final|sealed|abstract|data|async|static|const)\s+)*(class|struct|enum|interface|trait|namespace|module|type|func|function|def|fn|let|var|const|object|fun)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            indexedExtensions: nil
        )
    ]

    static func shouldIndex(fileURL: URL) -> Bool {
        let pathExtension = fileURL.pathExtension.lowercased()
        guard indexedExtensions.contains(pathExtension) else { return false }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resourceValues?.isRegularFile != false else { return false }
        let fileSize = resourceValues?.fileSize ?? 0
        return fileSize <= fileSizeLimit
    }

    static func extractSymbols(
        from contents: String,
        fileURL: URL,
        displayPath: String,
        originalIndex: Int
    ) -> [WorkspaceSymbolMatch] {
        let lines = contents.components(separatedBy: .newlines)
        let fileExtension = fileURL.pathExtension.lowercased()

        return lines.enumerated().compactMap { offset, line in
            guard let match = firstMatch(in: line, fileExtension: fileExtension) else { return nil }

            return WorkspaceSymbolMatch(
                name: match.name,
                kind: match.kind,
                fileURL: fileURL,
                displayPath: displayPath,
                line: offset + 1,
                column: match.column,
                lineText: line.trimmingCharacters(in: .whitespaces),
                originalIndex: originalIndex
            )
        }
    }

    private static func firstMatch(in line: String, fileExtension: String) -> (kind: String, name: String, column: Int)? {
        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)

        for pattern in patterns where pattern.matches(fileExtension: fileExtension) {
            guard let match = pattern.regularExpression.firstMatch(in: line, options: [], range: fullRange) else {
                continue
            }

            guard let nameRange = Range(match.range(at: pattern.nameGroup), in: line) else {
                continue
            }

            let kind: String
            if let fixedKind = pattern.fixedKind {
                kind = fixedKind
            } else if let kindGroup = pattern.kindGroup,
                      let kindRange = Range(match.range(at: kindGroup), in: line) {
                kind = String(line[kindRange])
            } else {
                continue
            }

            let name = String(line[nameRange])
            let column = line.distance(from: line.startIndex, to: nameRange.lowerBound) + 1
            return (kind, name, column)
        }

        return nil
    }
}

private struct Pattern {
    let regularExpression: NSRegularExpression
    let indexedExtensions: Set<String>?
    let kindGroup: Int?
    let nameGroup: Int
    let fixedKind: String?

    init(
        pattern: String,
        indexedExtensions: Set<String>? = nil,
        kindGroup: Int? = 1,
        nameGroup: Int = 2,
        fixedKind: String? = nil
    ) {
        self.regularExpression = try! NSRegularExpression(pattern: pattern, options: [])
        self.indexedExtensions = indexedExtensions
        self.kindGroup = kindGroup
        self.nameGroup = nameGroup
        self.fixedKind = fixedKind
    }

    func matches(fileExtension: String) -> Bool {
        indexedExtensions?.contains(fileExtension) ?? true
    }
}
