import AppKit
import Foundation
import Testing
@testable import Rosewood

struct EditorDocumentIndexTests {
    @Test
    func indexesEmptyLFCRLFAndTrailingLines() {
        let fixtures: [(text: String, lines: [OracleLine])] = [
            ("", [OracleLine(contentLength: 0, terminatorLength: 0)]),
            ("alpha", [OracleLine(contentLength: 5, terminatorLength: 0)]),
            ("alpha\nbeta", [
                OracleLine(contentLength: 5, terminatorLength: 1),
                OracleLine(contentLength: 4, terminatorLength: 0)
            ]),
            ("alpha\nbeta\n", [
                OracleLine(contentLength: 5, terminatorLength: 1),
                OracleLine(contentLength: 4, terminatorLength: 1),
                OracleLine(contentLength: 0, terminatorLength: 0)
            ]),
            ("alpha\r\nbeta\r\n", [
                OracleLine(contentLength: 5, terminatorLength: 2),
                OracleLine(contentLength: 4, terminatorLength: 2),
                OracleLine(contentLength: 0, terminatorLength: 0)
            ]),
            ("\r\n\n\r", [
                OracleLine(contentLength: 0, terminatorLength: 2),
                OracleLine(contentLength: 0, terminatorLength: 1),
                OracleLine(contentLength: 0, terminatorLength: 1),
                OracleLine(contentLength: 0, terminatorLength: 0)
            ])
        ]

        for fixture in fixtures {
            let index = EditorDocumentIndex(text: fixture.text)

            #expect(index.lines.map(OracleLine.init) == fixture.lines)
            expectMatchesOracle(index, text: fixture.text)
        }

        let trailing = EditorDocumentIndex(text: "alpha\n")
        #expect(trailing.lineAndColumn(atUTF16Offset: 6).line == 2)
        #expect(trailing.lineAndColumn(atUTF16Offset: 6).column == 1)
        #expect(trailing.fullLineRange(containingUTF16Offset: 6) == NSRange(location: 6, length: 0))
    }

    @Test
    func indexesAppKitUnicodeLineSeparators() {
        let separators = ["\u{0085}", "\u{2028}", "\u{2029}"]

        for separator in separators {
            var text = "left\(separator)right\(separator)"
            var index = EditorDocumentIndex(text: text)

            #expect(index.lines.map(OracleLine.init) == [
                OracleLine(contentLength: 4, terminatorLength: 1),
                OracleLine(contentLength: 5, terminatorLength: 1),
                OracleLine(contentLength: 0, terminatorLength: 0)
            ])
            expectMatchesOracle(index, text: text)

            #expect(applyEdit(
                to: &index,
                text: &text,
                oldRange: NSRange(location: 5, length: 0),
                replacement: separator
            ))
            #expect(index.fullRebuildCount == 1)
            #expect(!index.lastEditUsedFullRebuild)
            expectMatchesOracle(index, text: text)
        }
    }

    @Test
    func lspModeUsesOnlyProtocolEndOfLineSequences() {
        for separator in ["\u{0085}", "\u{2028}", "\u{2029}"] {
            let text = "a\(separator)b"
            let visualIndex = EditorDocumentIndex(text: text, lineBreakMode: .visual)
            let lspIndex = EditorDocumentIndex(text: text, lineBreakMode: .lsp)

            #expect(visualIndex.lineAndColumn(atUTF16Offset: 2).line == 2)
            #expect(lspIndex.lineAndColumn(atUTF16Offset: 2) == (line: 1, column: 3))
            #expect(
                lspIndex.nsRange(for: LSPRange(
                    start: LSPPosition(line: 0, character: 2),
                    end: LSPPosition(line: 0, character: 3)
                )) == NSRange(location: 2, length: 1)
            )
        }
    }

    @Test
    func sameLineInsertAndDeleteUseBoundedIncrementalCounters() {
        let original = "alpha\nbeta\ngamma"
        var text = original
        var index = EditorDocumentIndex(text: text)

        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: 8, length: 0),
            replacement: "XYZ"
        ))
        #expect(text == "alpha\nbeXYZta\ngamma")
        #expect(index.fullRebuildCount == 1)
        #expect(index.incrementalEditCount == 1)
        #expect(index.structuralTreeRebuildCount == 0)
        #expect(index.lastScannedUTF16Length == 3)
        #expect(!index.lastEditUsedFullRebuild)
        expectMatchesOracle(index, text: text)

        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: 8, length: 3),
            replacement: ""
        ))
        #expect(text == original)
        #expect(index.fullRebuildCount == 1)
        #expect(index.incrementalEditCount == 2)
        #expect(index.structuralTreeRebuildCount == 0)
        #expect(index.lastScannedUTF16Length == 0)
        #expect(!index.lastEditUsedFullRebuild)
        expectMatchesOracle(index, text: text)
    }

    @Test
    func usesUTF16CoordinatesForEmojiAndCombiningScalars() {
        var text = "a😀e\u{0301}\nβ"
        var index = EditorDocumentIndex(text: text)

        #expect((text as NSString).length == 7)
        #expect(index.lineAndColumn(atUTF16Offset: 0).line == 1)
        #expect(index.lineAndColumn(atUTF16Offset: 0).column == 1)
        #expect(index.lineAndColumn(atUTF16Offset: 3).line == 1)
        #expect(index.lineAndColumn(atUTF16Offset: 3).column == 4)
        #expect(index.lineAndColumn(atUTF16Offset: 6).line == 2)
        #expect(index.lineAndColumn(atUTF16Offset: 6).column == 1)
        #expect(index.utf16Offset(for: LSPPosition(line: 0, character: 999)) == 5)
        #expect(index.nsRange(for: LSPRange(
            start: LSPPosition(line: 0, character: 1),
            end: LSPPosition(line: 0, character: 3)
        )) == NSRange(location: 1, length: 2))

        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: 7, length: 0),
            replacement: "🎉"
        ))
        #expect(index.lastScannedUTF16Length == 2)
        #expect(index.fullRebuildCount == 1)
        expectMatchesOracle(index, text: text)
    }

    @Test
    func multilineAndWholeDocumentEditsStayIncremental() {
        var text = "one\r\ntwo\nthree"
        var index = EditorDocumentIndex(text: text)

        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: 5, length: 4),
            replacement: "dos\r\nmiddle\n"
        ))
        expectMatchesOracle(index, text: text)

        let wholeLength = (text as NSString).length
        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: 0, length: wholeLength),
            replacement: "\n😀\r\n"
        ))
        #expect(index.lines.map(OracleLine.init) == [
            OracleLine(contentLength: 0, terminatorLength: 1),
            OracleLine(contentLength: 2, terminatorLength: 2),
            OracleLine(contentLength: 0, terminatorLength: 0)
        ])
        expectMatchesOracle(index, text: text)

        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: 0, length: (text as NSString).length),
            replacement: ""
        ))
        #expect(text.isEmpty)
        #expect(index.lineCount == 1)
        #expect(index.fullRebuildCount == 1)
        #expect(index.incrementalEditCount == 3)
        #expect(!index.lastEditUsedFullRebuild)
        expectMatchesOracle(index, text: text)
    }

    @Test
    func structuralEditAtDocumentEndDoesNotDuplicateTrailingEmptyLine() {
        var text = "a\nb\n"
        var index = EditorDocumentIndex(text: text)

        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: 1, length: 1),
            replacement: ""
        ))

        #expect(text == "ab\n")
        #expect(index.lines.map(OracleLine.init) == [
            OracleLine(contentLength: 2, terminatorLength: 1),
            OracleLine(contentLength: 0, terminatorLength: 0)
        ])
        #expect(index.utf16Offset(for: LSPPosition(line: 2, character: 0)) == nil)
    }

    @Test
    func deletingContentBetweenCRAndLFCoalescesTerminator() {
        var text = "\ra\n"
        var index = EditorDocumentIndex(text: text)

        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: 1, length: 1),
            replacement: ""
        ))

        #expect(text == "\r\n")
        #expect(index.lines.map(OracleLine.init) == [
            OracleLine(contentLength: 0, terminatorLength: 2),
            OracleLine(contentLength: 0, terminatorLength: 0)
        ])
        #expect(index.utf16Offset(for: LSPPosition(line: 1, character: 0)) == 2)
    }

    @Test
    func seededRandomEditsMatchIndependentFoundationOracle() {
        var random = DeterministicGenerator(seed: 0x524F_5345_574F_4F44)
        var text = "start\r\n😀e\u{0301}\nend"
        var index = EditorDocumentIndex(text: text)
        let replacements = [
            "", "x", "λ", "😀", "\n", "\r", "\r\n", "e\u{0301}", "left\nright", "[]"
        ]
        let editCount = 400

        for step in 0..<editCount {
            let boundaries = validUTF16Boundaries(in: text as NSString)
            let firstBoundary = random.nextInt(upperBound: boundaries.count)
            let secondBoundary = random.nextInt(upperBound: boundaries.count)
            let lowerBoundary = min(firstBoundary, secondBoundary)
            let upperBoundary = max(firstBoundary, secondBoundary)
            let oldRange = NSRange(
                location: boundaries[lowerBoundary],
                length: boundaries[upperBoundary] - boundaries[lowerBoundary]
            )
            let replacement = replacements[random.nextInt(upperBound: replacements.count)]
            let previousText = text

            let usedIncrementalPath = applyEdit(
                to: &index,
                text: &text,
                oldRange: oldRange,
                replacement: replacement
            )

            guard usedIncrementalPath else {
                Issue.record("Valid contiguous edit unexpectedly rebuilt at step \(step)")
                return
            }

            let expectedLines = foundationOracleLines(in: text as NSString)
            let actualLines = index.lines.map(OracleLine.init)
            guard actualLines == expectedLines else {
                Issue.record("""
                Differential mismatch at step \(step):
                before: \(previousText.debugDescription)
                old range: \(oldRange)
                replacement: \(replacement.debugDescription)
                after: \(text.debugDescription)
                expected lines: \(expectedLines)
                actual lines: \(actualLines)
                """)
                return
            }
            expectMatchesOracle(index, text: text)
        }

        #expect(index.fullRebuildCount == 1)
        #expect(index.incrementalEditCount == editCount)
        #expect(index.revision == UInt64(editCount + 1))
        #expect(!index.lastEditUsedFullRebuild)
    }

    @Test
    func largeSingleLineInsertDoesNotRebuildOrScanTheDocument() {
        let originalLength = 5_000_000
        var text = String(repeating: "x", count: originalLength)
        var index = EditorDocumentIndex(text: text)

        #expect(applyEdit(
            to: &index,
            text: &text,
            oldRange: NSRange(location: originalLength / 2, length: 0),
            replacement: "Z"
        ))

        #expect(index.utf16Length == originalLength + 1)
        #expect(index.lineCount == 1)
        #expect(index.lines[0].contentLength == originalLength + 1)
        #expect(index.fullRebuildCount == 1)
        #expect(index.incrementalEditCount == 1)
        #expect(index.structuralTreeRebuildCount == 0)
        #expect(index.lastScannedUTF16Length == 1)
        #expect(!index.lastEditUsedFullRebuild)
    }

    @Test
    func largeStructuralEditsStayTreeLocalAcrossRepeatedMiddleInsertAndDelete() {
        let physicalLineCount = 100_000
        let middleLine = physicalLineCount / 2
        let middleLineStart = middleLine * 2
        let editOffset = middleLineStart + 1
        let originalText = String(repeating: "x\n", count: physicalLineCount)
        var text = originalText
        var index = EditorDocumentIndex(text: text)
        var maximumEditTreeNodeVisitCount = 0

        #expect(index.lineCount == physicalLineCount + 1)
        #expect(index.treeDepth < 128)
        #expect(index.utf16Offset(
            for: LSPPosition(line: middleLine - 1, character: 0)
        ) == middleLineStart - 2)
        #expect(index.utf16Offset(
            for: LSPPosition(line: middleLine, character: 0)
        ) == middleLineStart)

        for _ in 0..<24 {
            #expect(applyEdit(
                to: &index,
                text: &text,
                oldRange: NSRange(location: editOffset, length: 0),
                replacement: "\n"
            ))
            maximumEditTreeNodeVisitCount = max(
                maximumEditTreeNodeVisitCount,
                index.lastEditTreeNodeVisitCount
            )

            #expect(index.lineCount == physicalLineCount + 2)
            #expect(index.fullRebuildCount == 1)
            #expect(index.structuralTreeRebuildCount == 0)
            #expect(index.lastScannedUTF16Length < 16)
            #expect(index.lastTreeMutationNodeVisitCount < 256)
            #expect(index.lastEditTreeNodeVisitCount < 512)
            #expect(index.lastEditTreeNodeVisitCount >= index.lastTreeMutationNodeVisitCount)
            #expect(index.treeDepth < 128)
            #expect(index.utf16Offset(
                for: LSPPosition(line: middleLine, character: 0)
            ) == middleLineStart)
            #expect(index.utf16Offset(
                for: LSPPosition(line: middleLine + 1, character: 0)
            ) == middleLineStart + 2)
            #expect(index.utf16Offset(
                for: LSPPosition(line: middleLine + 2, character: 0)
            ) == middleLineStart + 3)
            #expect(index.fullLineRange(
                containingUTF16Offset: middleLineStart + 2
            ) == NSRange(location: middleLineStart + 2, length: 1))
            #expect(index.lineAndColumn(
                atUTF16Offset: (text as NSString).length
            ) == (line: index.lineCount, column: 1))

            #expect(applyEdit(
                to: &index,
                text: &text,
                oldRange: NSRange(location: editOffset, length: 1),
                replacement: ""
            ))
            maximumEditTreeNodeVisitCount = max(
                maximumEditTreeNodeVisitCount,
                index.lastEditTreeNodeVisitCount
            )

            #expect(text == originalText)
            #expect(index.lineCount == physicalLineCount + 1)
            #expect(index.fullRebuildCount == 1)
            #expect(index.structuralTreeRebuildCount == 0)
            #expect(index.lastScannedUTF16Length < 16)
            #expect(index.lastTreeMutationNodeVisitCount < 256)
            #expect(index.lastEditTreeNodeVisitCount < 512)
            #expect(index.treeDepth < 128)
            #expect(index.utf16Offset(
                for: LSPPosition(line: middleLine + 1, character: 0)
            ) == middleLineStart + 2)
            #expect(index.fullLineRange(
                containingUTF16Offset: editOffset
            ) == NSRange(location: middleLineStart, length: 2))
            #expect(index.lineAndColumn(
                atUTF16Offset: (text as NSString).length
            ) == (line: index.lineCount, column: 1))
        }

        #expect(index.incrementalEditCount == 48)
        #expect(index.structuralLocalEditCount == 48)
        #expect(maximumEditTreeNodeVisitCount < 512)
    }

    @Test
    func unicodeSeparatorEditsAreStructuralOnlyInVisualMode() {
        for separator in ["\u{0085}", "\u{2028}", "\u{2029}"] {
            var visualText = "leftright"
            var visualIndex = EditorDocumentIndex(text: visualText, lineBreakMode: .visual)

            #expect(applyEdit(
                to: &visualIndex,
                text: &visualText,
                oldRange: NSRange(location: 4, length: 0),
                replacement: separator
            ))
            #expect(visualIndex.lineCount == 2)
            #expect(visualIndex.structuralLocalEditCount == 1)
            #expect(visualIndex.structuralTreeRebuildCount == 0)
            expectMatchesOracle(visualIndex, text: visualText)

            #expect(applyEdit(
                to: &visualIndex,
                text: &visualText,
                oldRange: NSRange(location: 4, length: 1),
                replacement: ""
            ))
            #expect(visualText == "leftright")
            #expect(visualIndex.lineCount == 1)
            #expect(visualIndex.structuralLocalEditCount == 2)

            var lspText = "leftright"
            var lspIndex = EditorDocumentIndex(text: lspText, lineBreakMode: .lsp)

            #expect(applyEdit(
                to: &lspIndex,
                text: &lspText,
                oldRange: NSRange(location: 4, length: 0),
                replacement: separator
            ))
            #expect(lspIndex.lineCount == 1)
            #expect(lspIndex.lines == [
                EditorDocumentIndex.Line(contentLength: 10, terminatorLength: 0)
            ])
            #expect(lspIndex.structuralLocalEditCount == 0)
            #expect(lspIndex.lastScannedUTF16Length == 1)
            #expect(lspIndex.lineAndColumn(atUTF16Offset: 5) == (line: 1, column: 6))

            #expect(applyEdit(
                to: &lspIndex,
                text: &lspText,
                oldRange: NSRange(location: 4, length: 1),
                replacement: ""
            ))
            #expect(lspText == "leftright")
            #expect(lspIndex.lineCount == 1)
            #expect(lspIndex.structuralLocalEditCount == 0)
        }
    }

    @Test
    func structuralEditsPreserveCRLFSeamsAndEOFSentinel() {
        let fixtures: [(
            text: String,
            oldRange: NSRange,
            replacement: String,
            expected: String
        )] = [
            ("a\rb", NSRange(location: 2, length: 0), "\n", "a\r\nb"),
            ("a\nb", NSRange(location: 1, length: 0), "\r", "a\r\nb"),
            ("a\r\nb", NSRange(location: 2, length: 1), "", "a\rb"),
            ("a\r\nb", NSRange(location: 1, length: 1), "", "a\nb"),
            ("\ra\n", NSRange(location: 1, length: 1), "", "\r\n"),
            ("", NSRange(location: 0, length: 0), "\n", "\n"),
            ("\n", NSRange(location: 0, length: 1), "", ""),
            ("a", NSRange(location: 1, length: 0), "\n", "a\n"),
            ("a\n", NSRange(location: 1, length: 1), "", "a")
        ]

        for fixture in fixtures {
            var text = fixture.text
            var index = EditorDocumentIndex(text: text)

            #expect(applyEdit(
                to: &index,
                text: &text,
                oldRange: fixture.oldRange,
                replacement: fixture.replacement
            ))
            #expect(text == fixture.expected)
            #expect(index.fullRebuildCount == 1)
            #expect(index.structuralTreeRebuildCount == 0)
            #expect(index.structuralLocalEditCount == 1)
            expectMatchesOracle(index, text: text)
        }
    }

    @Test
    func copiedIndexMutationsDoNotAliasPersistentTreeNodes() {
        var originalText = "alpha\nbeta\ngamma"
        var original = EditorDocumentIndex(text: originalText)
        var copied = original
        var copiedText = originalText

        #expect(applyEdit(
            to: &copied,
            text: &copiedText,
            oldRange: NSRange(location: 8, length: 0),
            replacement: "\ncopy"
        ))
        #expect(copiedText == "alpha\nbe\ncopyta\ngamma")
        #expect(copied.revision == 2)
        #expect(original.revision == 1)
        expectMatchesOracle(original, text: originalText)
        expectMatchesOracle(copied, text: copiedText)

        #expect(applyEdit(
            to: &original,
            text: &originalText,
            oldRange: NSRange(location: 0, length: 0),
            replacement: "Z"
        ))
        #expect(originalText == "Zalpha\nbeta\ngamma")
        #expect(original.revision == 2)
        #expect(copied.revision == 2)
        expectMatchesOracle(original, text: originalText)
        expectMatchesOracle(copied, text: copiedText)
    }

    @Test @MainActor
    func textStorageDelegateIndexesCharactersAndIgnoresAttributeEdits() {
        let storage = NSTextStorage(string: "alpha\nbeta")
        let observer = IndexingTextStorageDelegate(text: storage.string)
        storage.delegate = observer
        let initialRevision = observer.index.revision

        storage.addAttribute(
            NSAttributedString.Key("rosewood-test-attribute"),
            value: true,
            range: NSRange(location: 0, length: 1)
        )
        #expect(observer.characterEditCount == 0)
        #expect(observer.index.revision == initialRevision)

        storage.replaceCharacters(in: NSRange(location: 5, length: 1), with: "\r\n")
        #expect(observer.characterEditCount == 1)
        #expect(observer.index.revision == initialRevision + 1)
        expectMatchesOracle(observer.index, text: storage.string)
    }
}

@MainActor
private final class IndexingTextStorageDelegate: NSObject, @preconcurrency NSTextStorageDelegate {
    var index: EditorDocumentIndex
    var characterEditCount = 0

    init(text: String) {
        index = EditorDocumentIndex(text: text)
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        characterEditCount += 1
        index.applyEdit(
            editedRange: editedRange,
            changeInLength: delta,
            updatedText: textStorage.mutableString
        )
    }
}

private struct OracleLine: Equatable {
    let contentLength: Int
    let terminatorLength: Int

    var totalLength: Int {
        contentLength + terminatorLength
    }

    init(contentLength: Int, terminatorLength: Int) {
        self.contentLength = contentLength
        self.terminatorLength = terminatorLength
    }

    init(_ line: EditorDocumentIndex.Line) {
        self.init(
            contentLength: line.contentLength,
            terminatorLength: line.terminatorLength
        )
    }
}

private func applyEdit(
    to index: inout EditorDocumentIndex,
    text: inout String,
    oldRange: NSRange,
    replacement: String
) -> Bool {
    let replacementLength = (replacement as NSString).length
    let mutableText = NSMutableString(string: text)
    mutableText.replaceCharacters(in: oldRange, with: replacement)
    text = mutableText as String

    return index.applyEdit(
        editedRange: NSRange(location: oldRange.location, length: replacementLength),
        changeInLength: replacementLength - oldRange.length,
        updatedText: text
    )
}

private func expectMatchesOracle(_ index: EditorDocumentIndex, text: String) {
    let nsText = text as NSString
    let expectedLines = foundationOracleLines(in: nsText)

    #expect(index.utf16Length == nsText.length)
    #expect(index.lines.map(OracleLine.init) == expectedLines)

    var lineStart = 0
    for (lineIndex, line) in expectedLines.enumerated() {
        #expect(index.utf16Offset(for: LSPPosition(line: lineIndex, character: 0)) == lineStart)
        #expect(
            index.utf16Offset(for: LSPPosition(line: lineIndex, character: line.contentLength + 100))
                == lineStart + line.contentLength
        )
        lineStart += line.totalLength
    }
    #expect(index.utf16Offset(for: LSPPosition(line: expectedLines.count, character: 0)) == nil)

    for offset in validUTF16Boundaries(in: nsText) {
        let expectedPosition = oracleLineAndColumn(
            atUTF16Offset: offset,
            lines: expectedLines,
            utf16Length: nsText.length
        )
        let actualPosition = index.lineAndColumn(atUTF16Offset: offset)
        #expect(actualPosition.line == expectedPosition.line)
        #expect(actualPosition.column == expectedPosition.column)

        let expectedLine = expectedLines[expectedPosition.line - 1]
        let expectedLineStart = offset - (expectedPosition.column - 1)
        #expect(index.fullLineRange(containingUTF16Offset: offset) == NSRange(
            location: expectedLineStart,
            length: expectedLine.totalLength
        ))
    }
}

/// Uses NSString's line-boundary implementation as an oracle, independently of the index parser.
private func foundationOracleLines(in text: NSString) -> [OracleLine] {
    guard text.length > 0 else {
        return [OracleLine(contentLength: 0, terminatorLength: 0)]
    }

    var lines: [OracleLine] = []
    var location = 0
    while location < text.length {
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        text.getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: location, length: 0)
        )
        lines.append(OracleLine(
            contentLength: contentsEnd - lineStart,
            terminatorLength: lineEnd - contentsEnd
        ))
        guard lineEnd > location else { break }
        location = lineEnd
    }

    if location == text.length, lines.last?.terminatorLength ?? 0 > 0 {
        lines.append(OracleLine(contentLength: 0, terminatorLength: 0))
    }
    return lines
}

private func oracleLineAndColumn(
    atUTF16Offset offset: Int,
    lines: [OracleLine],
    utf16Length: Int
) -> (line: Int, column: Int) {
    let clampedOffset = min(max(offset, 0), utf16Length)
    var lineIndex = 0
    var lineStart = 0
    var nextLineStart = 0

    for candidate in 1..<lines.count {
        nextLineStart += lines[candidate - 1].totalLength
        guard nextLineStart <= clampedOffset else { break }
        lineIndex = candidate
        lineStart = nextLineStart
    }

    return (line: lineIndex + 1, column: clampedOffset - lineStart + 1)
}

private func validUTF16Boundaries(in text: NSString) -> [Int] {
    var boundaries = [0]
    var offset = 0
    while offset < text.length {
        let first = text.character(at: offset)
        if (0xD800...0xDBFF).contains(first),
           offset + 1 < text.length,
           (0xDC00...0xDFFF).contains(text.character(at: offset + 1)) {
            offset += 2
        } else {
            offset += 1
        }
        boundaries.append(offset)
    }
    return boundaries
}

private struct DeterministicGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 32) % UInt64(upperBound))
    }
}
