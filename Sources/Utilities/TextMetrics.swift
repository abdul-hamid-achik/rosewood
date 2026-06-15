import Foundation

enum TextMetrics {
    /// The 1-based logical line number at a UTF-16 offset (newlines before it, plus one). Scans in
    /// fixed-size chunks rather than allocating a prefix substring and iterating it as Swift
    /// `Character`s — the gutter recomputes this on every redraw/scroll, so on a large file the old
    /// `substring(to:).reduce` was an O(n) allocation + grapheme-cluster pass each time.
    static func lineNumber(atUTF16Offset offset: Int, in text: NSString) -> Int {
        let prefixLength = min(max(offset, 0), text.length)
        guard prefixLength > 0 else { return 1 }

        var lineNumber = 1
        let chunkSize = 4096
        var buffer = [unichar](repeating: 0, count: chunkSize)
        var index = 0
        while index < prefixLength {
            let length = min(chunkSize, prefixLength - index)
            text.getCharacters(&buffer, range: NSRange(location: index, length: length))
            for position in 0..<length where buffer[position] == 0x0A {
                lineNumber += 1
            }
            index += length
        }
        return lineNumber
    }
}
