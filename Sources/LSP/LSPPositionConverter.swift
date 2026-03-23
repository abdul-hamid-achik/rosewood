import AppKit

/// Converts between LSP positions (0-indexed line/character in UTF-16) and NSTextView positions (UTF-16 offsets).
/// Both LSP and NSString use UTF-16, which simplifies the conversion.
enum LSPPositionConverter {

    /// Convert a UTF-16 offset to an LSP position (0-indexed line, 0-indexed character).
    static func lspPosition(from utf16Offset: Int, in text: String) -> LSPPosition {
        let nsText = text as NSString
        let clampedOffset = min(utf16Offset, nsText.length)

        var line = 0
        var lineStart = 0

        var i = 0
        while i < clampedOffset {
            let char = nsText.character(at: i)
            if char == 0x0D { // \r
                line += 1
                // Skip \n in \r\n pair
                if i + 1 < clampedOffset && nsText.character(at: i + 1) == 0x0A {
                    i += 2
                } else {
                    i += 1
                }
                lineStart = i
            } else if char == 0x0A { // \n
                line += 1
                i += 1
                lineStart = i
            } else {
                i += 1
            }
        }

        let character = clampedOffset - lineStart
        return LSPPosition(line: line, character: character)
    }

    /// Convert an LSP range to an NSRange.
    /// Returns nil if the line is beyond the end of the text.
    static func nsRange(from lspRange: LSPRange, in text: String) -> NSRange? {
        guard let startOffset = utf16Offset(for: lspRange.start, in: text),
              let endOffset = utf16Offset(for: lspRange.end, in: text) else {
            return nil
        }
        let location = startOffset
        let length = max(0, endOffset - startOffset)
        return NSRange(location: location, length: length)
    }

    /// Convert an LSP position to a UTF-16 offset.
    /// Returns nil if the line is beyond the end of the text.
    static func utf16Offset(for position: LSPPosition, in text: String) -> Int? {
        let nsText = text as NSString
        let targetLine = position.line
        let targetChar = position.character

        var currentLine = 0
        var i = 0

        // Walk to the start of the target line
        while currentLine < targetLine && i < nsText.length {
            let char = nsText.character(at: i)
            i += 1
            if char == 0x0A { // \n
                currentLine += 1
            } else if char == 0x0D { // \r
                currentLine += 1
                // Skip \n in \r\n pair
                if i < nsText.length && nsText.character(at: i) == 0x0A {
                    i += 1
                }
            }
        }

        if currentLine < targetLine {
            return nil // Line beyond end of text
        }

        // Calculate line length for clamping
        var lineEnd = i
        while lineEnd < nsText.length {
            let char = nsText.character(at: lineEnd)
            if char == 0x0A || char == 0x0D { break }
            lineEnd += 1
        }
        let lineLength = lineEnd - i
        let clampedChar = min(targetChar, lineLength)

        return i + clampedChar
    }

    /// Convert a point in an NSTextView to an LSP position.
    static func lspPosition(from point: NSPoint, in textView: NSTextView) -> LSPPosition? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }

        let textContainerOrigin = textView.textContainerOrigin
        let adjustedPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)

        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(for: adjustedPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)

        let nsText = textView.string as NSString
        let clampedIndex = min(index, nsText.length)

        return lspPosition(from: clampedIndex, in: textView.string)
    }

    /// Convert a cursor location (NSRange.location) in an NSTextView to an LSP position.
    static func lspPositionFromCursor(in textView: NSTextView) -> LSPPosition {
        let location = textView.selectedRange().location
        return lspPosition(from: location, in: textView.string)
    }

    /// Get the NSRect for a character range in an NSTextView (for positioning popups).
    static func screenRect(for lspRange: LSPRange, in textView: NSTextView) -> NSRect? {
        guard let nsRange = nsRange(from: lspRange, in: textView.string),
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let origin = textView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y

        return textView.window?.convertToScreen(textView.convert(rect, to: nil))
    }
}
