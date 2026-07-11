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

    @Test
    func unfoldedSnapshotPreservesAllVisibleLinesWithoutParsingRegions() {
        let text = """
        struct Example {
            func greet() {
                print(\"hi\")
            }
        }
        let done = true
        """

        let snapshot = FoldedTextSnapshot.unfolded(text)

        #expect(snapshot.displayText == text)
        #expect(snapshot.foldableLines.isEmpty)
        #expect(snapshot.foldedLines.isEmpty)
        #expect(snapshot.visibleLineNumbers == [1, 2, 3, 4, 5, 6])
    }

    @Test
    func foldedSnapshotHandlesAppKitUnicodeLineSeparators() {
        for separator in ["\u{0085}", "\u{2028}", "\u{2029}"] {
            let text = "func f() {\(separator)  print(1)\(separator)}\(separator)let y = 2"
            let snapshot = FoldedTextSnapshot.make(
                from: text,
                language: "swift",
                foldedStartLines: [1]
            )
            let sourceLocation = (text as NSString).range(of: "let y").location
            let displayedLocation = snapshot.displayRange(
                forSourceRange: NSRange(location: sourceLocation, length: 0)
            )

            #expect(snapshot.displayText.contains("func f() { ...\nlet y = 2"))
            #expect(!snapshot.displayText.contains("print(1)"))
            #expect(
                snapshot.sourceRange(forDisplayedRange: displayedLocation).location
                    == sourceLocation
            )
        }
    }

    @Test
    func foldedSnapshotMapsAcrossMultipleDisjointRegions() {
        let text = "func a() {\n  print(1)\n}\nfunc b() {\n  print(2)\n}\nlet tail = true"
        let snapshot = FoldedTextSnapshot.make(
            from: text,
            language: "swift",
            foldedStartLines: [1, 4]
        )

        for visibleText in ["func a", "func b", "let tail"] {
            let sourceLocation = (text as NSString).range(of: visibleText).location
            let displayRange = snapshot.displayRange(
                forSourceRange: NSRange(location: sourceLocation, length: 0)
            )
            let roundTrip = snapshot.sourceRange(forDisplayedRange: displayRange)

            #expect(roundTrip.location == sourceLocation)
        }
        if let secondRegion = snapshot.region(startingAt: 4) {
            let sourceRange = NSRange(location: secondRegion.hiddenRange.location, length: 0)
            let displayRange = snapshot.displayRange(forSourceRange: sourceRange)
            #expect(snapshot.sourceRange(forDisplayedRange: displayRange) == sourceRange)
        } else {
            Issue.record("Expected a fold region starting on line 4")
        }
        #expect(snapshot.visibleLineNumbers == [1, 4, 7])
    }
}
