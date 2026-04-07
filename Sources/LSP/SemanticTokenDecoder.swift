import Foundation
import AppKit

struct DecodedSemanticToken {
    let range: NSRange
    let tokenType: String
    let modifiers: [String]

    var isReadonly: Bool { modifiers.contains("readonly") }
    var isStatic: Bool { modifiers.contains("static") }
    var isAsync: Bool { modifiers.contains("async") }
    var isDeprecated: Bool { modifiers.contains("deprecated") }
    var isDeclaration: Bool { modifiers.contains("definition") || modifiers.contains("declaration") }
}

struct SemanticTokenDecoder {
    let legend: SemanticTokensLegend

    func decode(_ data: [Int], text: String) -> [DecodedSemanticToken] {
        guard !data.isEmpty else { return [] }

        var tokens: [DecodedSemanticToken] = []
        var currentLine = 0
        var currentCharacter = 0

        let nsText = text as NSString
        let textLength = nsText.length

        var index = 0
        while index + 4 < data.count {
            let deltaLine = data[index]
            let deltaStart = data[index + 1]
            let length = data[index + 2]
            let tokenTypeIndex = data[index + 3]
            let tokenModifiersBitset = data[index + 4]

            index += 5

            currentLine += deltaLine
            if deltaLine == 0 {
                currentCharacter += deltaStart
            } else {
                currentCharacter = deltaStart
            }

            let tokenType = tokenTypeName(for: tokenTypeIndex)
            let modifiers = tokenModifiers(for: tokenModifiersBitset)

            let startOffset = lineCharacterToOffset(line: currentLine, char: currentCharacter, text: nsText)
            guard startOffset >= 0 && startOffset < textLength else { continue }

            let endOffset = min(startOffset + length, textLength)
            let range = NSRange(location: startOffset, length: endOffset - startOffset)

            guard range.length > 0 else { continue }

            tokens.append(DecodedSemanticToken(range: range, tokenType: tokenType, modifiers: modifiers))
        }

        return tokens
    }

    func decodeViewport(_ data: [Int], text: String, visibleRange: NSRange) -> [DecodedSemanticToken] {
        let allTokens = decode(data, text: text)
        guard visibleRange.location >= 0 else { return allTokens }

        return allTokens.filter { token in
            NSIntersectionRange(token.range, visibleRange).length > 0
        }
    }

    private func tokenTypeName(for index: Int) -> String {
        guard index >= 0 && index < legend.tokenTypes.count else {
            return "unknown"
        }
        return legend.tokenTypes[index]
    }

    private func tokenModifiers(for bitset: Int) -> [String] {
        guard bitset > 0 else { return [] }

        var modifiers: [String] = []
        for (index, modifier) in legend.tokenModifiers.enumerated() {
            if (bitset & (1 << index)) != 0 {
                modifiers.append(modifier)
            }
        }
        return modifiers
    }

    private func lineCharacterToOffset(line: Int, char: Int, text: NSString) -> Int {
        guard line >= 0 && char >= 0 else { return 0 }

        var currentLine = 0
        var offset = 0

        while currentLine < line && offset < text.length {
            let lineEnd = text.lineRange(for: NSRange(location: offset, length: 0)).location + text.lineRange(for: NSRange(location: offset, length: 0)).length
            offset = lineEnd
            currentLine += 1
        }

        offset += char
        return min(offset, text.length)
    }
}

extension SemanticTokenDecoder {
    static func tokenTypeColor(_ tokenType: String, themeColors: ThemeColors) -> NSColor {
        switch tokenType.lowercased() {
        case "namespace", "module", "package":
            return themeColors.nsSuccess
        case "type", "class", "interface", "enum", "struct", "delegate":
            return themeColors.nsAccentStrong
        case "function", "method", "constructor", "destructor":
            return themeColors.nsAccent
        case "variable", "local variable":
            return themeColors.nsForeground
        case "property", "field":
            return themeColors.nsSubduedText
        case "parameter", "argument", "local":
            return themeColors.nsForeground
        case "constant", "readonly", "immutable":
            return themeColors.nsSuccess
        case "keyword", "modifier":
            return themeColors.nsWarning
        case "operator", "punctuation":
            return themeColors.nsMutedText
        case "string", "number", "boolean", "regexp", "escape":
            return themeColors.nsAccent
        case "comment", "documentation":
            return themeColors.nsMutedText
        case "typeParameter", "generic":
            return themeColors.nsAccentStrong
        case "macro":
            return themeColors.nsWarning
        case "label":
            return themeColors.nsMutedText
        default:
            return themeColors.nsForeground
        }
    }
}
