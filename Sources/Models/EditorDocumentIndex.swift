import Foundation

/// Incremental UTF-16 line index for the text currently displayed by the AppKit editor.
///
/// NSTextView, NSRange, and the LSP protocol all address text in UTF-16 code units. Storing each
/// logical line's content and terminator lengths keeps those coordinate systems aligned. A Fenwick
/// prefix-sum tree makes offset/line queries logarithmic and lets ordinary same-line typing update
/// one line without shifting every later line start.
struct EditorDocumentIndex {
    enum LineBreakMode: Equatable {
        /// Matches NSString/TextKit visual lines, including Unicode NEL/LS/PS separators.
        case visual
        /// Matches the LSP specification: LF, CRLF, and CR only.
        case lsp
    }

    struct Line: Equatable {
        var contentLength: Int
        var terminatorLength: Int

        var totalLength: Int {
            contentLength + terminatorLength
        }
    }

    private(set) var lines: [Line]
    private(set) var utf16Length: Int
    private(set) var revision: UInt64

    // Deterministic performance counters used by tests. These describe index work rather than
    // wall-clock timing, keeping CI assertions stable across different Macs.
    private(set) var fullRebuildCount: Int
    private(set) var incrementalEditCount: Int
    private(set) var structuralTreeRebuildCount: Int
    private(set) var lastScannedUTF16Length: Int
    private(set) var lastEditUsedFullRebuild: Bool

    private let lineBreakMode: LineBreakMode
    private var prefixTree: FenwickTree

    init(text: String = "", lineBreakMode: LineBreakMode = .visual) {
        let nsText = text as NSString
        let parsedLines = Self.parseLines(
            nsText,
            includesDocumentEnd: true,
            lineBreakMode: lineBreakMode
        )
        self.lines = parsedLines
        self.utf16Length = nsText.length
        self.revision = 1
        self.fullRebuildCount = 1
        self.incrementalEditCount = 0
        self.structuralTreeRebuildCount = 0
        self.lastScannedUTF16Length = nsText.length
        self.lastEditUsedFullRebuild = true
        self.lineBreakMode = lineBreakMode
        self.prefixTree = FenwickTree(values: parsedLines.map(\.totalLength))
    }

    var lineCount: Int {
        lines.count
    }

    mutating func reset(text: String) {
        reset(text: text as NSString)
    }

    mutating func reset(text: NSString) {
        let parsedLines = Self.parseLines(
            text,
            includesDocumentEnd: true,
            lineBreakMode: lineBreakMode
        )
        lines = parsedLines
        utf16Length = text.length
        prefixTree = FenwickTree(values: parsedLines.map(\.totalLength))
        revision &+= 1
        fullRebuildCount += 1
        lastScannedUTF16Length = text.length
        lastEditUsedFullRebuild = true
    }

    /// Apply the character edit reported by NSTextStorageDelegate.
    ///
    /// `editedRange` is the post-edit UTF-16 range and `changeInLength` is the new-minus-old UTF-16
    /// length. Returns true when the incremental path was used. Any ambiguous or inconsistent edit
    /// safely falls back to a complete rebuild and returns false.
    @discardableResult
    mutating func applyEdit(
        editedRange: NSRange,
        changeInLength: Int,
        updatedText: String
    ) -> Bool {
        applyEdit(
            editedRange: editedRange,
            changeInLength: changeInLength,
            updatedText: updatedText as NSString
        )
    }

    @discardableResult
    mutating func applyEdit(
        editedRange: NSRange,
        changeInLength: Int,
        updatedText updatedNSString: NSString
    ) -> Bool {
        let oldRangeLength = editedRange.length - changeInLength
        guard editedRange.location >= 0,
              editedRange.length >= 0,
              oldRangeLength >= 0,
              editedRange.location <= utf16Length,
              editedRange.location + oldRangeLength <= utf16Length,
              NSMaxRange(editedRange) <= updatedNSString.length,
              utf16Length + changeInLength == updatedNSString.length else {
            reset(text: updatedNSString)
            return false
        }

        let oldRange = NSRange(location: editedRange.location, length: oldRangeLength)
        let replacementText = updatedNSString.substring(with: editedRange)
        let replacementLength = editedRange.length
        let startLineIndex = lineIndex(containingUTF16Offset: oldRange.location)
        let lineStart = prefixTree.prefixSum(startLineIndex)
        let contentEnd = lineStart + lines[startLineIndex].contentLength
        let resultingContentLength = lines[startLineIndex].contentLength
            + replacementLength
            - oldRange.length
        let wouldJoinCRLFBoundary = resultingContentLength == 0
            && lineStart > 0
            && lineStart < updatedNSString.length
            && updatedNSString.character(at: lineStart - 1) == 13
            && updatedNSString.character(at: lineStart) == 10

        // Common typing/deletion path: no line separator is touched or introduced. Updating one
        // line length and one Fenwick node is O(log lineCount), even for a multi-megabyte line.
        if oldRange.location <= contentEnd,
           NSMaxRange(oldRange) <= contentEnd,
           !Self.containsLineBreak(replacementText, lineBreakMode: lineBreakMode),
           !wouldJoinCRLFBoundary {
            let contentDelta = replacementLength - oldRange.length
            lines[startLineIndex].contentLength += contentDelta
            prefixTree.add(contentDelta, at: startLineIndex)
            utf16Length = updatedNSString.length
            revision &+= 1
            incrementalEditCount += 1
            lastScannedUTF16Length = replacementLength
            lastEditUsedFullRebuild = false
            return true
        }

        let endProbe: Int
        if oldRange.length == 0 {
            endProbe = oldRange.location
        } else {
            endProbe = max(oldRange.location, NSMaxRange(oldRange) - 1)
        }
        let endLineIndex = lineIndex(containingUTF16Offset: endProbe)

        // Include one complete neighboring line on each side. This makes edits that create or
        // destroy a CRLF pair at a line boundary local and deterministic.
        let affectedStartLine = max(startLineIndex - 1, 0)
        let affectedEndLine = min(endLineIndex + 1, lines.count - 1)
        let oldSegmentStart = prefixTree.prefixSum(affectedStartLine)
        let oldSegmentEnd = prefixTree.prefixSum(affectedEndLine + 1)
        let newSegmentEnd = oldSegmentEnd + changeInLength

        guard oldSegmentStart >= 0,
              newSegmentEnd >= oldSegmentStart,
              newSegmentEnd <= updatedNSString.length else {
            reset(text: updatedNSString)
            return false
        }

        let updatedSegmentRange = NSRange(
            location: oldSegmentStart,
            length: newSegmentEnd - oldSegmentStart
        )
        let updatedSegment = updatedNSString.substring(with: updatedSegmentRange) as NSString
        let replacementLines = Self.parseLines(
            updatedSegment,
            // A zero-width final line has the same prefix offset as EOF. Test whether the replaced
            // model range owns that sentinel rather than inferring ownership from the byte offset,
            // otherwise a reparsed sentinel can be inserted beside the retained old one.
            includesDocumentEnd: affectedEndLine == lines.count - 1,
            lineBreakMode: lineBreakMode
        )
        let replacedLineRange = affectedStartLine..<(affectedEndLine + 1)
        var candidateLines = lines
        candidateLines.replaceSubrange(replacedLineRange, with: replacementLines)

        guard !candidateLines.isEmpty,
              candidateLines.dropLast().allSatisfy({ $0.terminatorLength > 0 }),
              candidateLines.reduce(0, { $0 + $1.totalLength }) == updatedNSString.length else {
            reset(text: updatedNSString)
            return false
        }

        if replacementLines.count == replacedLineRange.count {
            for localIndex in replacementLines.indices {
                let lineIndex = affectedStartLine + localIndex
                let delta = replacementLines[localIndex].totalLength - lines[lineIndex].totalLength
                prefixTree.add(delta, at: lineIndex)
            }
        } else {
            prefixTree = FenwickTree(values: candidateLines.map(\.totalLength))
            structuralTreeRebuildCount += 1
        }

        lines = candidateLines
        utf16Length = updatedNSString.length
        revision &+= 1
        incrementalEditCount += 1
        lastScannedUTF16Length = updatedSegment.length
        lastEditUsedFullRebuild = false
        return true
    }

    func lineAndColumn(atUTF16Offset offset: Int) -> (line: Int, column: Int) {
        let clampedOffset = min(max(offset, 0), utf16Length)
        let index = lineIndex(containingUTF16Offset: clampedOffset)
        let lineStart = prefixTree.prefixSum(index)
        return (line: index + 1, column: clampedOffset - lineStart + 1)
    }

    func utf16Offset(for position: LSPPosition) -> Int? {
        guard position.line >= 0,
              position.character >= 0,
              lines.indices.contains(position.line) else {
            return nil
        }
        let lineStart = prefixTree.prefixSum(position.line)
        let character = min(position.character, lines[position.line].contentLength)
        return lineStart + character
    }

    func nsRange(for range: LSPRange) -> NSRange? {
        guard let start = utf16Offset(for: range.start),
              let end = utf16Offset(for: range.end),
              end >= start else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    func fullLineRange(containingUTF16Offset offset: Int) -> NSRange {
        let index = lineIndex(containingUTF16Offset: min(max(offset, 0), utf16Length))
        return NSRange(
            location: prefixTree.prefixSum(index),
            length: lines[index].totalLength
        )
    }

    private func lineIndex(containingUTF16Offset offset: Int) -> Int {
        guard lines.count > 1 else { return 0 }
        let clampedOffset = min(max(offset, 0), utf16Length)
        if clampedOffset == utf16Length {
            return lines.count - 1
        }
        return prefixTree.index(containing: clampedOffset)
    }

    private static func containsLineBreak(
        _ text: String,
        lineBreakMode: LineBreakMode
    ) -> Bool {
        text.unicodeScalars.contains {
            $0.value == 10
                || $0.value == 13
                || (lineBreakMode == .visual && (
                    $0.value == 0x85
                        || $0.value == 0x2028
                        || $0.value == 0x2029
                ))
        }
    }

    private static func parseLines(
        _ text: NSString,
        includesDocumentEnd: Bool,
        lineBreakMode: LineBreakMode
    ) -> [Line] {
        var result: [Line] = []
        var lineStart = 0
        var index = 0

        while index < text.length {
            let character = text.character(at: index)
            let terminatorLength: Int
            if character == 13 {
                terminatorLength = index + 1 < text.length && text.character(at: index + 1) == 10
                    ? 2
                    : 1
            } else if character == 10 || (lineBreakMode == .visual && (
                character == 0x85
                    || character == 0x2028
                    || character == 0x2029
            )) {
                terminatorLength = 1
            } else {
                index += 1
                continue
            }

            result.append(Line(
                contentLength: index - lineStart,
                terminatorLength: terminatorLength
            ))
            index += terminatorLength
            lineStart = index
        }

        if lineStart < text.length {
            result.append(Line(
                contentLength: text.length - lineStart,
                terminatorLength: 0
            ))
        } else if includesDocumentEnd {
            // Empty documents and documents ending in any newline sequence have a final empty line.
            result.append(Line(contentLength: 0, terminatorLength: 0))
        }

        return result
    }
}

/// Maps ranges recorded before an NSTextStorage character edit into the storage's post-edit
/// coordinate space. Keeping this logic beside the document index makes the UTF-16 assumptions
/// explicit and gives editor decorations and semantic tokens one shared definition of an edit.
enum EditorTextEditRangeTransformer {
    /// Rebase a range that remains meaningful after an edit. Ranges intersecting replaced text are
    /// discarded because their contents no longer describe the same source.
    static func rebasedRange(
        _ range: NSRange,
        editedRange: NSRange,
        changeInLength: Int
    ) -> NSRange? {
        let oldLength = editedRange.length - changeInLength
        guard range.location >= 0,
              range.length >= 0,
              oldLength >= 0 else {
            return nil
        }

        let oldEditEnd = editedRange.location + oldLength
        if NSMaxRange(range) <= editedRange.location {
            return range
        }
        if range.location >= oldEditEnd {
            return NSRange(
                location: max(0, range.location + changeInLength),
                length: range.length
            )
        }
        return nil
    }

    /// Return the conservative post-edit span where a temporary attribute from `range` may remain.
    /// Intersecting ranges include both surviving old content and newly inserted content so cleanup
    /// cannot leave a stale decoration behind.
    static func cleanupRange(
        _ range: NSRange,
        editedRange: NSRange,
        changeInLength: Int,
        updatedLength: Int
    ) -> NSRange? {
        guard updatedLength >= 0,
              range.location >= 0,
              range.length >= 0 else {
            return nil
        }

        if let rebased = rebasedRange(
            range,
            editedRange: editedRange,
            changeInLength: changeInLength
        ) {
            return clamped(rebased, to: updatedLength)
        }

        let start = min(range.location, editedRange.location)
        let survivingOldEnd = NSMaxRange(range) + changeInLength
        let end = max(editedRange.location + editedRange.length, survivingOldEnd, start)
        return clamped(
            NSRange(location: start, length: max(0, end - start)),
            to: updatedLength
        )
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange? {
        let location = min(max(range.location, 0), length)
        let end = min(max(NSMaxRange(range), location), length)
        let result = NSRange(location: location, length: end - location)
        return result.length > 0 ? result : nil
    }
}

private struct FenwickTree {
    private var tree: [Int]

    init(values: [Int]) {
        tree = Array(repeating: 0, count: values.count + 1)
        for (index, value) in values.enumerated() {
            let treeIndex = index + 1
            tree[treeIndex] += value
            let parent = treeIndex + (treeIndex & -treeIndex)
            if parent < tree.count {
                tree[parent] += tree[treeIndex]
            }
        }
    }

    mutating func add(_ delta: Int, at index: Int) {
        guard delta != 0, index >= 0, index + 1 < tree.count else { return }
        var treeIndex = index + 1
        while treeIndex < tree.count {
            tree[treeIndex] += delta
            treeIndex += treeIndex & -treeIndex
        }
    }

    /// Sum of the first `count` values.
    func prefixSum(_ count: Int) -> Int {
        var treeIndex = min(max(count, 0), tree.count - 1)
        var result = 0
        while treeIndex > 0 {
            result += tree[treeIndex]
            treeIndex -= treeIndex & -treeIndex
        }
        return result
    }

    /// Zero-based value index whose cumulative range contains the UTF-16 offset.
    func index(containing offset: Int) -> Int {
        let target = offset + 1
        var index = 0
        var accumulated = 0
        var bit = 1
        while bit << 1 < tree.count {
            bit <<= 1
        }

        while bit > 0 {
            let next = index + bit
            if next < tree.count, accumulated + tree[next] < target {
                index = next
                accumulated += tree[next]
            }
            bit >>= 1
        }
        return min(index, tree.count - 2)
    }
}
