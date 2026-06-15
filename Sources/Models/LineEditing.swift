import Foundation

/// Pure, UTF-16-safe line operations for the editor (move line up/down, duplicate line). Each returns
/// the MINIMAL edit — the character range to replace, its replacement, and the resulting selection —
/// so the editor coordinator applies it through the NSTextView undo path without re-touching the whole
/// document. Foundation-only (NSString/NSRange) so it is fully unit-testable.
enum LineEditing {
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
        let selection: NSRange
    }

    /// Duplicate the full lines spanned by `selection`, inserting the copy directly below.
    static func duplicateLines(in text: NSString, selection: NSRange) -> Edit {
        let blockRange = text.lineRange(for: selection)
        let blockText = text.substring(with: blockRange)
        let insertLocation = blockRange.location + blockRange.length

        if blockText.hasSuffix("\n") {
            return Edit(
                range: NSRange(location: insertLocation, length: 0),
                replacement: blockText,
                selection: NSRange(location: insertLocation, length: (blockText as NSString).length)
            )
        }
        // Block is the last line with no trailing newline: add a separator before the copy.
        let replacement = "\n" + blockText
        return Edit(
            range: NSRange(location: insertLocation, length: 0),
            replacement: replacement,
            selection: NSRange(location: insertLocation + 1, length: (blockText as NSString).length)
        )
    }

    /// Move the full lines spanned by `selection` up by one line (swap with the line above).
    /// Returns nil if the block is already at the top.
    static func moveLinesUp(in text: NSString, selection: NSRange) -> Edit? {
        let blockRange = text.lineRange(for: selection)
        guard blockRange.location > 0 else { return nil }

        let previousRange = text.lineRange(for: NSRange(location: blockRange.location - 1, length: 0))
        let blockText = text.substring(with: blockRange)
        let previousText = text.substring(with: previousRange)
        let combined = NSRange(location: previousRange.location, length: previousRange.length + blockRange.length)

        let replacement: String
        if blockText.hasSuffix("\n") {
            replacement = blockText + previousText
        } else {
            // Block was the last line (no trailing newline); it gains one and the previous line loses its.
            replacement = blockText + "\n" + dropTrailingNewline(previousText)
        }
        return Edit(
            range: combined,
            replacement: replacement,
            selection: NSRange(location: previousRange.location, length: (blockText as NSString).length)
        )
    }

    /// Move the full lines spanned by `selection` down by one line (swap with the line below).
    /// Returns nil if the block is already the last content line.
    static func moveLinesDown(in text: NSString, selection: NSRange) -> Edit? {
        let blockRange = text.lineRange(for: selection)
        let blockEnd = blockRange.location + blockRange.length
        guard blockEnd < text.length else { return nil }

        let nextRange = text.lineRange(for: NSRange(location: blockEnd, length: 0))
        let blockText = text.substring(with: blockRange)
        let nextText = text.substring(with: nextRange)
        let combined = NSRange(location: blockRange.location, length: blockRange.length + nextRange.length)

        let replacement: String
        let newBlockLocation: Int
        let newBlockLength: Int
        if nextText.hasSuffix("\n") {
            replacement = nextText + blockText
            newBlockLocation = blockRange.location + (nextText as NSString).length
            newBlockLength = (blockText as NSString).length
        } else {
            // The line below was the last line (no trailing newline); after the swap the moved block
            // becomes the last line and loses its trailing newline, while the neighbor gains one.
            let trimmedBlock = dropTrailingNewline(blockText)
            replacement = nextText + "\n" + trimmedBlock
            newBlockLocation = blockRange.location + (nextText as NSString).length + 1
            newBlockLength = (trimmedBlock as NSString).length
        }
        return Edit(
            range: combined,
            replacement: replacement,
            selection: NSRange(location: newBlockLocation, length: newBlockLength)
        )
    }

    private static func dropTrailingNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }
}
