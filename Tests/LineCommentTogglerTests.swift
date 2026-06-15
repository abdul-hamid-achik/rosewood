import Testing
@testable import Rosewood

struct LineCommentTogglerTests {
    @Test
    func tokenMapsKnownLanguagesAndSkipsAmbiguousOnes() {
        #expect(LineCommentToggler.token(forLanguage: "swift") == "//")
        #expect(LineCommentToggler.token(forLanguage: "typescript") == "//")
        #expect(LineCommentToggler.token(forLanguage: "python") == "#")
        #expect(LineCommentToggler.token(forLanguage: "yaml") == "#")
        #expect(LineCommentToggler.token(forLanguage: "sql") == "--")
        #expect(LineCommentToggler.token(forLanguage: "haskell") == "--")
        // No unambiguous line comment -> no-op languages.
        #expect(LineCommentToggler.token(forLanguage: "json") == nil)
        #expect(LineCommentToggler.token(forLanguage: "html") == nil)
        #expect(LineCommentToggler.token(forLanguage: "plaintext") == nil)
    }

    @Test
    func commentsAllLinesAtCommonIndentWhenNoneCommented() {
        let result = LineCommentToggler.toggle(lines: ["let a = 1", "let b = 2"], token: "//")
        #expect(result == ["// let a = 1", "// let b = 2"])
    }

    @Test
    func uncommentsWhenEveryNonBlankLineIsCommented() {
        let result = LineCommentToggler.toggle(lines: ["// let a = 1", "//   let b = 2"], token: "//")
        #expect(result == ["let a = 1", "  let b = 2"])
    }

    @Test
    func commentsWhenMixedSoUncommentedLinesGetCommentedToo() {
        // Not all commented -> comment everything (double-commenting the already-commented line).
        let result = LineCommentToggler.toggle(lines: ["// done", "todo"], token: "//")
        #expect(result == ["// // done", "// todo"])
    }

    @Test
    func leavesBlankLinesUntouched() {
        let result = LineCommentToggler.toggle(lines: ["foo", "", "bar"], token: "#")
        #expect(result == ["# foo", "", "# bar"])
    }

    @Test
    func commentsAtCommonMinimumIndentation() {
        let result = LineCommentToggler.toggle(lines: ["    a", "        b"], token: "//")
        #expect(result == ["    // a", "    //     b"])
    }

    @Test
    func roundTripsCommentThenUncomment() {
        let original = ["    func f() {", "        return 1", "    }"]
        let commented = LineCommentToggler.toggle(lines: original, token: "//")
        let restored = LineCommentToggler.toggle(lines: commented, token: "//")
        #expect(restored == original)
    }

    @Test
    func allBlankSelectionIsNoOp() {
        #expect(LineCommentToggler.toggle(lines: ["", "   "], token: "//") == ["", "   "])
    }
}
