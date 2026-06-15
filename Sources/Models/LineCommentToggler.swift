import Foundation

/// Pure line-comment toggling for the editor's ⌘/ command. Deliberately free of AppKit so the logic
/// is unit-testable; the editor coordinator handles the NSTextView selection/undo plumbing.
enum LineCommentToggler {
    /// The line-comment token for a language, or nil for languages with no unambiguous line comment
    /// (JSON/HTML/CSS/Markdown/…), where toggling is a no-op.
    static func token(forLanguage language: String) -> String? {
        switch language {
        case "swift", "go", "javascript", "typescript", "kotlin", "rust",
             "c", "cpp", "php", "zig", "java", "dart", "scala":
            return "//"
        case "python", "ruby", "bash", "yaml", "toml", "dockerfile", "r", "elixir":
            return "#"
        case "haskell", "lua", "sql":
            return "--"
        default:
            return nil
        }
    }

    /// Toggle line comments across `lines`. If every non-blank line is already commented, all are
    /// uncommented; otherwise all non-blank lines are commented at their common minimum indentation.
    /// Blank lines are left untouched (matching common editor behavior).
    static func toggle(lines: [String], token: String) -> [String] {
        let nonBlankIndexes = lines.indices.filter { !isBlank(lines[$0]) }
        guard !nonBlankIndexes.isEmpty else { return lines }

        let allCommented = nonBlankIndexes.allSatisfy { isCommented(lines[$0], token: token) }
        if allCommented {
            return lines.map { isBlank($0) ? $0 : uncomment($0, token: token) }
        }

        let indentColumn = nonBlankIndexes.map { leadingWhitespaceCount(lines[$0]) }.min() ?? 0
        return lines.map { isBlank($0) ? $0 : comment($0, token: token, atColumn: indentColumn) }
    }

    // MARK: - Helpers

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func leadingWhitespaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func isCommented(_ line: String, token: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(token)
    }

    private static func comment(_ line: String, token: String, atColumn column: Int) -> String {
        let clamped = min(column, line.count)
        let index = line.index(line.startIndex, offsetBy: clamped)
        return String(line[..<index]) + token + " " + String(line[index...])
    }

    private static func uncomment(_ line: String, token: String) -> String {
        let whitespaceEnd = line.index(line.startIndex, offsetBy: leadingWhitespaceCount(line))
        let rest = line[whitespaceEnd...]
        guard rest.hasPrefix(token) else { return line }
        var afterToken = rest.dropFirst(token.count)
        if afterToken.first == " " { afterToken = afterToken.dropFirst() }
        return String(line[..<whitespaceEnd]) + String(afterToken)
    }
}
