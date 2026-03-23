import Foundation
import Testing
@testable import Rosewood

struct LineInfoTests {

    @Test
    func parseSingleLineNoNewline() {
        let infos = LineInfo.parse("hello")

        #expect(infos.count == 1)
        #expect(infos[0].number == 1)
        #expect(infos[0].startUTF16 == 0)
        #expect(infos[0].trimmedText == "hello")
        #expect(!infos[0].hasTrailingNewline)
    }

    @Test
    func parseMultipleLines() {
        let infos = LineInfo.parse("line1\nline2\nline3")

        #expect(infos.count == 3)
        #expect(infos[0].number == 1)
        #expect(infos[0].trimmedText == "line1")
        #expect(infos[0].hasTrailingNewline)
        #expect(infos[1].number == 2)
        #expect(infos[1].trimmedText == "line2")
        #expect(infos[2].number == 3)
        #expect(infos[2].trimmedText == "line3")
        #expect(!infos[2].hasTrailingNewline)
    }

    @Test
    func parseTrailingNewlineAddsEmptyLine() {
        let infos = LineInfo.parse("hello\n")

        #expect(infos.count == 2)
        #expect(infos[0].trimmedText == "hello")
        #expect(infos[1].number == 2)
        #expect(infos[1].trimmedText == "")
    }

    @Test
    func parseEmptyString() {
        let infos = LineInfo.parse("")

        #expect(infos.count == 1)
        #expect(infos[0].number == 1)
        #expect(infos[0].trimmedText == "")
        #expect(infos[0].startUTF16 == 0)
        #expect(infos[0].lineEndUTF16 == 0)
    }

    @Test
    func parseIndentationWithSpaces() {
        let infos = LineInfo.parse("    indented")

        #expect(infos.count == 1)
        #expect(infos[0].indent == 4)
        #expect(infos[0].trimmedText == "indented")
    }

    @Test
    func parseIndentationWithTabs() {
        let infos = LineInfo.parse("\tindented")

        #expect(infos.count == 1)
        #expect(infos[0].indent == 4)
        #expect(infos[0].trimmedText == "indented")
    }

    @Test
    func parseMixedIndentation() {
        let infos = LineInfo.parse("\t  code")

        #expect(infos[0].indent == 6) // 1 tab (4) + 2 spaces
    }

    @Test
    func parseUTF16OffsetsAreCorrect() {
        let infos = LineInfo.parse("ab\ncd\nef")

        #expect(infos[0].startUTF16 == 0)
        #expect(infos[0].lineEndUTF16 == 2)  // "ab" without newline
        #expect(infos[0].fullEndUTF16 == 3)  // "ab\n"

        #expect(infos[1].startUTF16 == 3)
        #expect(infos[1].lineEndUTF16 == 5)  // "cd"
        #expect(infos[1].fullEndUTF16 == 6)  // "cd\n"

        #expect(infos[2].startUTF16 == 6)
        #expect(infos[2].lineEndUTF16 == 8)  // "ef"
    }

    @Test
    func parseBlankLinesPreserveLineNumbers() {
        let infos = LineInfo.parse("a\n\nb")

        #expect(infos.count == 3)
        #expect(infos[0].number == 1)
        #expect(infos[0].trimmedText == "a")
        #expect(infos[1].number == 2)
        #expect(infos[1].trimmedText == "")
        #expect(infos[2].number == 3)
        #expect(infos[2].trimmedText == "b")
    }

    @Test
    func parseUnicodeCharacters() {
        let text = "let emoji = \"🎉\"\nprint(emoji)"
        let infos = LineInfo.parse(text)

        #expect(infos.count == 2)
        #expect(infos[0].number == 1)
        #expect(infos[1].number == 2)
        // Verify UTF-16 offsets account for the emoji (2 UTF-16 code units)
        let nsText = text as NSString
        #expect(infos[0].fullEndUTF16 <= nsText.length)
        #expect(infos[1].fullEndUTF16 == nsText.length)
    }
}
