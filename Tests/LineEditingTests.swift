import Foundation
import Testing
@testable import Rosewood

struct LineEditingTests {
    private func apply(_ edit: LineEditing.Edit, to text: String) -> String {
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: edit.range, with: edit.replacement)
        return mutable as String
    }

    // MARK: - Duplicate

    @Test
    func duplicatesCurrentLine() {
        let edit = LineEditing.duplicateLines(in: "a\nb\nc\n", selection: NSRange(location: 2, length: 0))
        #expect(apply(edit, to: "a\nb\nc\n") == "a\nb\nb\nc\n")
        #expect(edit.selection == NSRange(location: 4, length: 2))
    }

    @Test
    func duplicatesLastLineWithoutTrailingNewline() {
        let edit = LineEditing.duplicateLines(in: "a\nb", selection: NSRange(location: 2, length: 0))
        #expect(apply(edit, to: "a\nb") == "a\nb\nb")
        #expect(edit.selection == NSRange(location: 4, length: 1))
    }

    @Test
    func duplicatesMultiLineSelection() {
        let edit = LineEditing.duplicateLines(in: "a\nb\nc\n", selection: NSRange(location: 0, length: 4))
        #expect(apply(edit, to: "a\nb\nc\n") == "a\nb\na\nb\nc\n")
    }

    // MARK: - Move up

    @Test
    func movesLineUp() {
        let edit = LineEditing.moveLinesUp(in: "a\nb\nc\n", selection: NSRange(location: 2, length: 0))
        let unwrapped = try! #require(edit)
        #expect(apply(unwrapped, to: "a\nb\nc\n") == "b\na\nc\n")
        #expect(unwrapped.selection == NSRange(location: 0, length: 2))
    }

    @Test
    func moveUpAtTopIsNil() {
        #expect(LineEditing.moveLinesUp(in: "a\nb\n", selection: NSRange(location: 0, length: 0)) == nil)
    }

    @Test
    func movesLastLineUpWithoutTrailingNewline() {
        let edit = LineEditing.moveLinesUp(in: "a\nb", selection: NSRange(location: 2, length: 0))
        let unwrapped = try! #require(edit)
        #expect(apply(unwrapped, to: "a\nb") == "b\na")
    }

    // MARK: - Move down

    @Test
    func movesLineDown() {
        let edit = LineEditing.moveLinesDown(in: "a\nb\nc\n", selection: NSRange(location: 2, length: 0))
        let unwrapped = try! #require(edit)
        #expect(apply(unwrapped, to: "a\nb\nc\n") == "a\nc\nb\n")
        #expect(unwrapped.selection == NSRange(location: 4, length: 2))
    }

    @Test
    func moveDownOnLastContentLineIsNil() {
        #expect(LineEditing.moveLinesDown(in: "a\nb\nc\n", selection: NSRange(location: 4, length: 0)) == nil)
    }

    @Test
    func movesLineDownWhenNeighborIsLastLineWithoutNewline() {
        let edit = LineEditing.moveLinesDown(in: "a\nb", selection: NSRange(location: 0, length: 0))
        let unwrapped = try! #require(edit)
        #expect(apply(unwrapped, to: "a\nb") == "b\na")
        #expect(unwrapped.selection == NSRange(location: 2, length: 1))
    }
}
