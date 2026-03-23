import Foundation
import Testing
@testable import Rosewood

struct FoldingParserTests {
    @Test
    func swiftBraceFoldingFindsTypeBlock() {
        let text = """
        struct Example {
            func greet() {
                print("hi")
            }
        }
        """

        let regions = FoldingParser.regions(for: text, language: "swift")

        #expect(regions.contains { $0.startLine == 1 && $0.endLine == 5 })
        #expect(regions.contains { $0.startLine == 2 && $0.endLine == 4 })
    }

    @Test
    func yamlIndentationFoldingFindsNestedBlock() {
        let text = """
        root:
          nested:
            value: 1
          sibling: 2
        """

        let regions = FoldingParser.regions(for: text, language: "yaml")

        #expect(regions.contains { $0.startLine == 1 && $0.endLine == 4 })
        #expect(regions.contains { $0.startLine == 2 && $0.endLine >= 3 })
    }

    @Test
    func foldedSnapshotCollapsesNestedFoldIntoSingleVisiblePlaceholder() {
        let text = """
        struct Example {
            func greet() {
                print("hi")
            }
        }
        let done = true
        """

        let snapshot = FoldedTextSnapshot.make(
            from: text,
            language: "swift",
            foldedStartLines: [1, 2]
        )

        #expect(snapshot.displayText.contains("struct Example { ...\n"))
        #expect(!snapshot.displayText.contains("print(\"hi\")"))
        #expect(snapshot.visibleLineNumbers == [1, 6])
    }

    @Test
    func foldedSnapshotMapsDisplayAndSourceRangesAcrossCollapsedRegion() {
        let text = """
        struct Example {
            func greet() {
                print("hi")
            }
        }
        let done = true
        """

        let snapshot = FoldedTextSnapshot.make(
            from: text,
            language: "swift",
            foldedStartLines: [1]
        )

        let doneLocation = (text as NSString).range(of: "let done").location
        let displayRange = snapshot.displayRange(forSourceRange: NSRange(location: doneLocation, length: 0))
        let roundTripped = snapshot.sourceRange(forDisplayedRange: displayRange)

        #expect(roundTripped.location == doneLocation)
        #expect(snapshot.actualLine(forDisplayLine: 2) == 6)
        #expect(snapshot.displayLine(forActualLine: 6) == 2)
    }
}
