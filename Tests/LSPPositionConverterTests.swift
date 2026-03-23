import Foundation
import Testing
@testable import Rosewood

struct LSPPositionConverterTests {

    // MARK: - UTF-16 Offset to LSPPosition

    @Test
    func firstCharacter() {
        let pos = LSPPositionConverter.lspPosition(from: 0, in: "hello")
        #expect(pos.line == 0)
        #expect(pos.character == 0)
    }

    @Test
    func firstLineMiddle() {
        let pos = LSPPositionConverter.lspPosition(from: 5, in: "hello world")
        #expect(pos.line == 0)
        #expect(pos.character == 5)
    }

    @Test
    func secondLineStart() {
        let pos = LSPPositionConverter.lspPosition(from: 6, in: "hello\nworld")
        #expect(pos.line == 1)
        #expect(pos.character == 0)
    }

    @Test
    func secondLineMiddle() {
        let pos = LSPPositionConverter.lspPosition(from: 9, in: "hello\nworld")
        #expect(pos.line == 1)
        #expect(pos.character == 3)
    }

    @Test
    func lastCharacterNoTrailingNewline() {
        let text = "hello\nworld"
        let pos = LSPPositionConverter.lspPosition(from: (text as NSString).length, in: text)
        #expect(pos.line == 1)
        #expect(pos.character == 5)
    }

    @Test
    func lastCharacterWithTrailingNewline() {
        let text = "hello\nworld\n"
        let pos = LSPPositionConverter.lspPosition(from: (text as NSString).length, in: text)
        #expect(pos.line == 2)
        #expect(pos.character == 0)
    }

    @Test
    func emptyString() {
        let pos = LSPPositionConverter.lspPosition(from: 0, in: "")
        #expect(pos.line == 0)
        #expect(pos.character == 0)
    }

    @Test
    func emptyLines() {
        let text = "\n\n\n"
        let pos = LSPPositionConverter.lspPosition(from: 2, in: text)
        #expect(pos.line == 2)
        #expect(pos.character == 0)
    }

    @Test
    func windowsLineEndings() {
        let text = "line1\r\nline2\r\nline3"
        // After "line1\r\n" (7 utf-16 units), we should be at line 1
        let pos = LSPPositionConverter.lspPosition(from: 7, in: text)
        #expect(pos.line == 1)
        #expect(pos.character == 0)
    }

    @Test
    func emojiCharacter() {
        // 😀 is a single code point (U+1F600) which is 2 UTF-16 code units (surrogate pair)
        let text = "a😀b"
        let nsText = text as NSString
        // "a" = offset 0, "😀" = offset 1-2, "b" = offset 3
        let posB = LSPPositionConverter.lspPosition(from: 3, in: text)
        #expect(posB.line == 0)
        #expect(posB.character == 3) // UTF-16 offset
        #expect(nsText.length == 4) // a(1) + 😀(2) + b(1)
    }

    @Test
    func cjkCharacters() {
        // Chinese characters are 1 UTF-16 code unit each (BMP)
        let text = "你好世界"
        let pos = LSPPositionConverter.lspPosition(from: 2, in: text)
        #expect(pos.line == 0)
        #expect(pos.character == 2)
    }

    @Test
    func surrogatePair() {
        // 🎉 (U+1F389) = surrogate pair = 2 UTF-16 code units
        let text = "🎉x"
        let nsText = text as NSString
        #expect(nsText.length == 3) // 🎉(2) + x(1)
        let pos = LSPPositionConverter.lspPosition(from: 2, in: text)
        #expect(pos.line == 0)
        #expect(pos.character == 2)
    }

    @Test
    func combiningCharacters() {
        // e + combining acute accent = 2 UTF-16 code units, 1 grapheme cluster
        let text = "e\u{0301}x" // é + x
        let nsText = text as NSString
        #expect(nsText.length == 3)
        let pos = LSPPositionConverter.lspPosition(from: 2, in: text)
        #expect(pos.line == 0)
        #expect(pos.character == 2)
    }

    @Test
    func multipleLines() {
        let text = "func hello() {\n    print(\"hi\")\n}"
        let pos = LSPPositionConverter.lspPosition(from: 19, in: text)
        #expect(pos.line == 1)
        #expect(pos.character == 4) // "    " = 4 chars indent
    }

    // MARK: - NSRange from LSPRange

    @Test
    func nsRangeSimple() {
        let range = LSPRange(
            start: LSPPosition(line: 0, character: 5),
            end: LSPPosition(line: 0, character: 10)
        )
        let nsRange = LSPPositionConverter.nsRange(from: range, in: "hello world here")
        #expect(nsRange?.location == 5)
        #expect(nsRange?.length == 5)
    }

    @Test
    func nsRangeMultiLine() {
        let text = "line 1\nline 2\nline 3"
        let range = LSPRange(
            start: LSPPosition(line: 0, character: 5),
            end: LSPPosition(line: 1, character: 4)
        )
        let nsRange = LSPPositionConverter.nsRange(from: range, in: text)
        #expect(nsRange != nil)
        #expect(nsRange!.location == 5)
        #expect(nsRange!.length == 6) // "1\nline" = 6 chars (but actually "1\nline" without the " " before "2")
    }

    @Test
    func nsRangeZeroWidth() {
        let range = LSPRange(
            start: LSPPosition(line: 1, character: 3),
            end: LSPPosition(line: 1, character: 3)
        )
        let nsRange = LSPPositionConverter.nsRange(from: range, in: "hello\nworld")
        #expect(nsRange?.length == 0)
    }

    @Test
    func nsRangeEndOfFile() {
        let text = "hello\nworld"
        let range = LSPRange(
            start: LSPPosition(line: 1, character: 0),
            end: LSPPosition(line: 1, character: 5)
        )
        let nsRange = LSPPositionConverter.nsRange(from: range, in: text)
        #expect(nsRange?.location == 6)
        #expect(nsRange?.length == 5)
    }

    @Test
    func nsRangeWithEmoji() {
        let text = "😀hello"
        let range = LSPRange(
            start: LSPPosition(line: 0, character: 0),
            end: LSPPosition(line: 0, character: 2) // 😀 = 2 UTF-16 units
        )
        let nsRange = LSPPositionConverter.nsRange(from: range, in: text)
        #expect(nsRange?.location == 0)
        #expect(nsRange?.length == 2)
    }

    @Test
    func nsRangeInvalidLine() {
        let range = LSPRange(
            start: LSPPosition(line: 99, character: 0),
            end: LSPPosition(line: 99, character: 5)
        )
        let nsRange = LSPPositionConverter.nsRange(from: range, in: "hello\nworld")
        #expect(nsRange == nil)
    }

    @Test
    func nsRangeInvalidCharacterClamps() {
        let range = LSPRange(
            start: LSPPosition(line: 0, character: 0),
            end: LSPPosition(line: 0, character: 999)
        )
        let nsRange = LSPPositionConverter.nsRange(from: range, in: "hello")
        // Character should be clamped to line length
        #expect(nsRange?.location == 0)
        #expect(nsRange?.length == 5)
    }

    // MARK: - Round Trip

    @Test
    func roundTripConversion() {
        let text = "hello\nworld\nfoo"
        let originalOffset = 8 // "wo" on line 2
        let lspPos = LSPPositionConverter.lspPosition(from: originalOffset, in: text)
        let roundTripRange = LSPPositionConverter.nsRange(
            from: LSPRange(start: lspPos, end: lspPos),
            in: text
        )
        #expect(roundTripRange?.location == originalOffset)
    }

    @Test
    func roundTripFirstLine() {
        let text = "hello world"
        let offset = 5
        let pos = LSPPositionConverter.lspPosition(from: offset, in: text)
        let range = LSPPositionConverter.nsRange(
            from: LSPRange(start: pos, end: pos),
            in: text
        )
        #expect(range?.location == offset)
    }

    @Test
    func roundTripEmptyFile() {
        let text = ""
        let pos = LSPPositionConverter.lspPosition(from: 0, in: text)
        let range = LSPPositionConverter.nsRange(
            from: LSPRange(start: pos, end: pos),
            in: text
        )
        #expect(range?.location == 0)
    }

    // MARK: - utf16Offset

    @Test
    func utf16OffsetFirstLine() {
        let offset = LSPPositionConverter.utf16Offset(for: LSPPosition(line: 0, character: 3), in: "hello")
        #expect(offset == 3)
    }

    @Test
    func utf16OffsetSecondLine() {
        let offset = LSPPositionConverter.utf16Offset(for: LSPPosition(line: 1, character: 2), in: "hello\nworld")
        #expect(offset == 8) // 6 (hello\n) + 2
    }

    @Test
    func utf16OffsetBeyondEnd() {
        let offset = LSPPositionConverter.utf16Offset(for: LSPPosition(line: 99, character: 0), in: "hello")
        #expect(offset == nil)
    }

    @Test
    func utf16OffsetLineStart() {
        let offset = LSPPositionConverter.utf16Offset(for: LSPPosition(line: 1, character: 0), in: "hello\nworld")
        #expect(offset == 6)
    }

    // MARK: - Large File Performance

    @Test
    func largeFile() {
        // 10,000 lines
        let lines = (0..<10000).map { "line \($0)" }
        let text = lines.joined(separator: "\n")

        // Test position at line 5000
        let offset = LSPPositionConverter.utf16Offset(for: LSPPosition(line: 5000, character: 0), in: text)
        #expect(offset != nil)

        // Verify round trip
        let pos = LSPPositionConverter.lspPosition(from: offset!, in: text)
        #expect(pos.line == 5000)
        #expect(pos.character == 0)
    }

    @Test
    func largeFileEndOfLine() {
        let lines = (0..<1000).map { "line number \($0)" }
        let text = lines.joined(separator: "\n")

        let offset = LSPPositionConverter.utf16Offset(for: LSPPosition(line: 999, character: 0), in: text)
        #expect(offset != nil)

        let pos = LSPPositionConverter.lspPosition(from: offset!, in: text)
        #expect(pos.line == 999)
    }
}
