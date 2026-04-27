import AppKit

enum HoverMarkdownRenderer {
    private static let codeFenceRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(?:```|~~~)([^\n]*)\n?([\s\S]*?)(?:```|~~~)"#,
            options: []
        )
    }()

    static func render(
        _ markdown: String,
        themeColors: ThemeColors,
        proseFontSize: CGFloat = 12,
        codeFontSize: CGFloat = 12
    ) -> NSAttributedString {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NSAttributedString() }

        let nsString = trimmed as NSString
        let result = NSMutableAttributedString()
        var cursor = 0

        let matches = codeFenceRegex?.matches(
            in: trimmed,
            range: NSRange(location: 0, length: nsString.length)
        ) ?? []

        for match in matches {
            if match.range.location > cursor {
                let prose = nsString.substring(
                    with: NSRange(location: cursor, length: match.range.location - cursor)
                )
                appendProse(
                    prose,
                    into: result,
                    themeColors: themeColors,
                    fontSize: proseFontSize
                )
            }

            let code = nsString.substring(with: match.range(at: 2))
            appendCode(
                code,
                into: result,
                themeColors: themeColors,
                fontSize: codeFontSize
            )

            cursor = match.range.location + match.range.length
        }

        if cursor < nsString.length {
            let prose = nsString.substring(from: cursor)
            appendProse(
                prose,
                into: result,
                themeColors: themeColors,
                fontSize: proseFontSize
            )
        }

        trimTrailingNewlines(of: result)
        return result
    }

    static func detectSymbolKind(in markdown: String) -> String? {
        guard let firstFence = firstCodeFenceContent(in: markdown) else { return nil }
        let signature = firstFence
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let lowered = signature.lowercased()
        let prefixes: [(String, String)] = [
            ("func ", "function"),
            ("fn ", "function"),
            ("def ", "function"),
            ("class ", "class"),
            ("struct ", "struct"),
            ("enum ", "enum"),
            ("protocol ", "protocol"),
            ("interface ", "interface"),
            ("typealias ", "typealias"),
            ("type ", "type"),
            ("trait ", "protocol"),
            ("module ", "module"),
            ("namespace ", "namespace"),
            ("var ", "variable"),
            ("let ", "constant"),
            ("const ", "constant")
        ]

        for (prefix, kind) in prefixes where lowered.contains(prefix) {
            return kind
        }

        if signature.contains("(") && signature.contains(")") {
            return "function"
        }

        return nil
    }

    private static func appendProse(
        _ prose: String,
        into target: NSMutableAttributedString,
        themeColors: ThemeColors,
        fontSize: CGFloat
    ) {
        let trimmed = prose.trimmingCharacters(in: CharacterSet.newlines)
        guard !trimmed.isEmpty else { return }

        let proseFont = NSFont.systemFont(ofSize: fontSize)
        let attributed = parsedAttributedString(from: trimmed)
        let working = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: working.length)

        working.addAttributes([
            .font: proseFont,
            .foregroundColor: themeColors.nsForeground
        ], range: fullRange)

        styleInlineCode(in: working, themeColors: themeColors, fontSize: fontSize)

        if target.length > 0 {
            target.append(NSAttributedString(string: "\n", attributes: [.font: proseFont]))
        }
        target.append(working)
    }

    private static func appendCode(
        _ code: String,
        into target: NSMutableAttributedString,
        themeColors: ThemeColors,
        fontSize: CGFloat
    ) {
        let trimmed = code.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }

        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.18
        paragraph.paragraphSpacingBefore = 4
        paragraph.paragraphSpacing = 4

        let attrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: themeColors.nsAccentStrong,
            .backgroundColor: themeColors.nsElevatedBackground.withAlphaComponent(0.65),
            .paragraphStyle: paragraph
        ]

        if target.length > 0 {
            target.append(NSAttributedString(string: "\n", attributes: [.font: monoFont]))
        }
        target.append(NSAttributedString(string: trimmed, attributes: attrs))
        target.append(NSAttributedString(string: "\n", attributes: [.font: monoFont]))
    }

    private static func parsedAttributedString(from text: String) -> NSAttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible

        if let parsed = try? AttributedString(markdown: text, options: options) {
            return NSAttributedString(parsed)
        }
        return NSAttributedString(string: text)
    }

    private static func styleInlineCode(
        in attributed: NSMutableAttributedString,
        themeColors: ThemeColors,
        fontSize: CGFloat
    ) {
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let fullRange = NSRange(location: 0, length: attributed.length)

        attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let font = value as? NSFont else { return }
            if font.fontDescriptor.symbolicTraits.contains(.monoSpace) || font.familyName == "Menlo" {
                attributed.addAttributes([
                    .font: mono,
                    .foregroundColor: themeColors.nsAccent,
                    .backgroundColor: themeColors.nsElevatedBackground.withAlphaComponent(0.5)
                ], range: range)
            }
        }
    }

    private static func trimTrailingNewlines(of attributed: NSMutableAttributedString) {
        let raw = attributed.string
        var trailing = 0
        for character in raw.reversed() {
            if character.isNewline {
                trailing += 1
            } else {
                break
            }
        }
        if trailing > 0 {
            attributed.deleteCharacters(in: NSRange(location: attributed.length - trailing, length: trailing))
        }
    }

    private static func firstCodeFenceContent(in markdown: String) -> String? {
        guard let regex = codeFenceRegex else { return nil }
        let ns = markdown as NSString
        guard let match = regex.firstMatch(in: markdown, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: match.range(at: 2))
    }
}
