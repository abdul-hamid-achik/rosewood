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
        decodeInternal(data, text: text, visibleRange: nil)
    }

    func decodeViewport(_ data: [Int], text: String, visibleRange: NSRange) -> [DecodedSemanticToken] {
        guard visibleRange.location >= 0 else {
            return decodeInternal(data, text: text, visibleRange: nil)
        }
        return decodeInternal(data, text: text, visibleRange: visibleRange)
    }

    private func decodeInternal(
        _ data: [Int],
        text: String,
        visibleRange: NSRange?
    ) -> [DecodedSemanticToken] {
        guard !data.isEmpty else { return [] }

        let nsText = text as NSString
        let textLength = nsText.length
        let lineOffsets = Self.computeLineOffsets(nsText)

        var tokens: [DecodedSemanticToken] = []
        var currentLine = 0
        var currentCharacter = 0

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

            // Deltas always advance forward; out-of-range lines are unrecoverable.
            guard currentLine >= 0 else { break }

            let lineStart: Int
            if currentLine < lineOffsets.count {
                lineStart = lineOffsets[currentLine]
            } else {
                lineStart = textLength
            }

            let startOffset = min(lineStart + currentCharacter, textLength)
            guard startOffset >= 0, startOffset < textLength else { continue }

            let endOffset = min(startOffset + length, textLength)
            guard endOffset > startOffset else { continue }

            if let visibleRange,
               startOffset >= NSMaxRange(visibleRange) || endOffset <= visibleRange.location {
                // Skip emitting; deltas are already accumulated above.
                continue
            }

            let tokenType = tokenTypeName(for: tokenTypeIndex)
            let modifiers = tokenModifiers(for: tokenModifiersBitset)
            let range = NSRange(location: startOffset, length: endOffset - startOffset)
            tokens.append(DecodedSemanticToken(range: range, tokenType: tokenType, modifiers: modifiers))
        }

        return tokens
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

    private static func computeLineOffsets(_ text: NSString) -> [Int] {
        var offsets: [Int] = [0]
        let length = text.length
        var location = 0
        while location < length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let next = lineRange.location + lineRange.length
            if next <= location { break }
            location = next
            offsets.append(location)
        }
        return offsets
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
