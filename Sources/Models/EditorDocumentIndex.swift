import Foundation

/// Incremental UTF-16 line index for the text currently displayed by the AppKit editor.
///
/// NSTextView, NSRange, and the LSP protocol all address text in UTF-16 code units. Storing each
/// logical line's content and terminator lengths keeps those coordinate systems aligned. An
/// implicit prefix-sum treap makes offset/line queries logarithmic and lets both ordinary typing
/// and newline-count-changing edits update a local tree path instead of shifting every later line
/// or rebuilding a document-wide prefix tree.
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

    /// Compatibility snapshot for whole-document consumers and tests. Incremental edits operate
    /// directly on `lineTree` and never materialize this array.
    var lines: [Line] {
        lineTree.lines
    }

    private(set) var utf16Length: Int
    private(set) var revision: UInt64

    // Deterministic performance counters used by tests. These describe index work rather than
    // wall-clock timing, keeping CI assertions stable across different Macs.
    private(set) var fullRebuildCount: Int
    private(set) var incrementalEditCount: Int
    /// Retained as an explicit regression counter: structural edits must not rebuild the tree.
    private(set) var structuralTreeRebuildCount: Int
    private(set) var structuralLocalEditCount: Int
    private(set) var lastScannedUTF16Length: Int
    /// Deterministic amount of tree mutation work in the latest incremental edit.
    private(set) var lastTreeMutationNodeVisitCount: Int
    /// Deterministic total tree work in the latest edit, including lookup and mutation paths.
    private(set) var lastEditTreeNodeVisitCount: Int
    private(set) var lastEditUsedFullRebuild: Bool

    private let lineBreakMode: LineBreakMode
    private var lineTree: LineIndexTree

    init(text: String = "", lineBreakMode: LineBreakMode = .visual) {
        let nsText = text as NSString
        let parsedLines = Self.parseLines(
            nsText,
            includesDocumentEnd: true,
            lineBreakMode: lineBreakMode
        )
        self.utf16Length = nsText.length
        self.revision = 1
        self.fullRebuildCount = 1
        self.incrementalEditCount = 0
        self.structuralTreeRebuildCount = 0
        self.structuralLocalEditCount = 0
        self.lastScannedUTF16Length = nsText.length
        self.lastTreeMutationNodeVisitCount = 0
        self.lastEditTreeNodeVisitCount = 0
        self.lastEditUsedFullRebuild = true
        self.lineBreakMode = lineBreakMode
        self.lineTree = LineIndexTree(lines: parsedLines)
    }

    var lineCount: Int {
        lineTree.count
    }

    /// Deterministic structural diagnostic used by large-document performance tests.
    var treeDepth: Int {
        lineTree.depth
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
        utf16Length = text.length
        lineTree = LineIndexTree(lines: parsedLines)
        revision &+= 1
        fullRebuildCount += 1
        lastScannedUTF16Length = text.length
        lastTreeMutationNodeVisitCount = 0
        lastEditTreeNodeVisitCount = 0
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
        var editTreeNodeVisitCount = 0
        let startLineIndex = lineIndex(
            containingUTF16Offset: oldRange.location,
            nodeVisitCount: &editTreeNodeVisitCount
        )
        guard let startLine = lineTree.line(
            at: startLineIndex,
            nodeVisitCount: &editTreeNodeVisitCount
        ) else {
            reset(text: updatedNSString)
            return false
        }
        let lineStart = lineTree.prefixUTF16Length(
            beforeLine: startLineIndex,
            nodeVisitCount: &editTreeNodeVisitCount
        )
        let contentEnd = lineStart + startLine.contentLength
        let resultingContentLength = startLine.contentLength
            + replacementLength
            - oldRange.length
        let wouldJoinCRLFBoundary = resultingContentLength == 0
            && lineStart > 0
            && lineStart < updatedNSString.length
            && updatedNSString.character(at: lineStart - 1) == 13
            && updatedNSString.character(at: lineStart) == 10

        // Common typing/deletion path: no line separator is touched or introduced. Updating one
        // line length along one treap path is O(log lineCount), even for a multi-megabyte line.
        if oldRange.location <= contentEnd,
           NSMaxRange(oldRange) <= contentEnd,
           !Self.containsLineBreak(replacementText, lineBreakMode: lineBreakMode),
           !wouldJoinCRLFBoundary {
            let contentDelta = replacementLength - oldRange.length
            var updatedLine = startLine
            updatedLine.contentLength += contentDelta
            lastTreeMutationNodeVisitCount = lineTree.replaceLine(
                at: startLineIndex,
                with: updatedLine
            )
            lastEditTreeNodeVisitCount = editTreeNodeVisitCount
                + lastTreeMutationNodeVisitCount
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
        let endLineIndex = lineIndex(
            containingUTF16Offset: endProbe,
            nodeVisitCount: &editTreeNodeVisitCount
        )

        // Include one complete neighboring line on each side. This makes edits that create or
        // destroy a CRLF pair at a line boundary local and deterministic.
        let affectedStartLine = max(startLineIndex - 1, 0)
        let affectedEndLine = min(endLineIndex + 1, lineTree.count - 1)
        let oldSegmentStart = lineTree.prefixUTF16Length(
            beforeLine: affectedStartLine,
            nodeVisitCount: &editTreeNodeVisitCount
        )
        let oldSegmentEnd = lineTree.prefixUTF16Length(
            beforeLine: affectedEndLine + 1,
            nodeVisitCount: &editTreeNodeVisitCount
        )
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
            includesDocumentEnd: affectedEndLine == lineTree.count - 1,
            lineBreakMode: lineBreakMode
        )
        let replacedLineRange = affectedStartLine..<(affectedEndLine + 1)
        let replacementUTF16Length = replacementLines.reduce(0) { partialResult, line in
            partialResult + line.totalLength
        }
        let candidateLineCount = lineTree.count - replacedLineRange.count + replacementLines.count
        let candidateUTF16Length = lineTree.totalUTF16Length
            - (oldSegmentEnd - oldSegmentStart)
            + replacementUTF16Length
        let replacementTerminatorsAreValid = replacementLines.enumerated().allSatisfy { localIndex, line in
            let candidateIndex = affectedStartLine + localIndex
            if candidateIndex == candidateLineCount - 1 {
                return line.terminatorLength == 0
            }
            return line.terminatorLength > 0
        }

        // The retained prefix/suffix were already validated. Tree aggregates and the local seams
        // are therefore sufficient; a document-wide copy/reduce/allSatisfy would put O(lineCount)
        // work back on the newline editing path.
        guard candidateLineCount > 0,
              candidateUTF16Length == updatedNSString.length,
              replacementTerminatorsAreValid else {
            reset(text: updatedNSString)
            return false
        }

        lastTreeMutationNodeVisitCount = lineTree.replaceSubrange(
            replacedLineRange,
            with: replacementLines
        )
        lastEditTreeNodeVisitCount = editTreeNodeVisitCount
            + lastTreeMutationNodeVisitCount
        utf16Length = updatedNSString.length
        revision &+= 1
        incrementalEditCount += 1
        structuralLocalEditCount += 1
        lastScannedUTF16Length = updatedSegment.length
        lastEditUsedFullRebuild = false
        return true
    }

    func lineAndColumn(atUTF16Offset offset: Int) -> (line: Int, column: Int) {
        let clampedOffset = min(max(offset, 0), utf16Length)
        let index = lineIndex(containingUTF16Offset: clampedOffset)
        let lineStart = lineTree.prefixUTF16Length(beforeLine: index)
        return (line: index + 1, column: clampedOffset - lineStart + 1)
    }

    func utf16Offset(for position: LSPPosition) -> Int? {
        guard position.line >= 0,
              position.character >= 0,
              let line = lineTree.line(at: position.line) else {
            return nil
        }
        let lineStart = lineTree.prefixUTF16Length(beforeLine: position.line)
        let character = min(position.character, line.contentLength)
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
        guard let line = lineTree.line(at: index) else {
            return NSRange(location: 0, length: 0)
        }
        return NSRange(
            location: lineTree.prefixUTF16Length(beforeLine: index),
            length: line.totalLength
        )
    }

    private func lineIndex(containingUTF16Offset offset: Int) -> Int {
        var ignoredNodeVisitCount = 0
        return lineIndex(
            containingUTF16Offset: offset,
            nodeVisitCount: &ignoredNodeVisitCount
        )
    }

    private func lineIndex(
        containingUTF16Offset offset: Int,
        nodeVisitCount: inout Int
    ) -> Int {
        guard lineTree.count > 1 else { return 0 }
        let clampedOffset = min(max(offset, 0), utf16Length)
        if clampedOffset == utf16Length {
            return lineTree.count - 1
        }
        return lineTree.index(
            containingUTF16Offset: clampedOffset,
            nodeVisitCount: &nodeVisitCount
        )
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

/// Persistent implicit treap keyed by logical line rank and augmented with subtree UTF-16 sums.
///
/// Nodes are immutable, so copying `EditorDocumentIndex` preserves value semantics while sharing
/// unchanged subtrees. Mutations rebuild only the searched/split/merged paths. Randomized priorities
/// are deterministic to keep performance assertions stable, and initial/replacement trees use an
/// O(lineCount) Cartesian-tree build rather than repeated O(log lineCount) insertion.
private struct LineIndexTree {
    typealias Line = EditorDocumentIndex.Line

    private final class Node {
        let line: Line
        let priority: UInt64
        let left: Node?
        let right: Node?
        let lineCount: Int
        let totalUTF16Length: Int
        let maxDepth: Int

        init(line: Line, priority: UInt64, left: Node?, right: Node?) {
            self.line = line
            self.priority = priority
            self.left = left
            self.right = right
            self.lineCount = 1 + (left?.lineCount ?? 0) + (right?.lineCount ?? 0)
            self.totalUTF16Length = line.totalLength
                + (left?.totalUTF16Length ?? 0)
                + (right?.totalUTF16Length ?? 0)
            self.maxDepth = 1 + max(left?.maxDepth ?? 0, right?.maxDepth ?? 0)
        }
    }

    /// Temporary mutable node used only while constructing a Cartesian tree. It never escapes the
    /// builder, so the live index remains fully persistent and immutable below the root reference.
    private final class BuilderNode {
        let line: Line
        let priority: UInt64
        var left: BuilderNode?
        var right: BuilderNode?
        var frozen: Node?

        init(line: Line, priority: UInt64) {
            self.line = line
            self.priority = priority
        }
    }

    private static let initialPriorityState: UInt64 = 0x524F_5345_574F_4F44

    private var root: Node?
    private var priorityState: UInt64

    init(lines: [Line]) {
        var priorityState = Self.initialPriorityState
        self.root = Self.buildTree(lines: lines, priorityState: &priorityState)
        self.priorityState = priorityState
    }

    var count: Int {
        root?.lineCount ?? 0
    }

    var totalUTF16Length: Int {
        root?.totalUTF16Length ?? 0
    }

    var depth: Int {
        root?.maxDepth ?? 0
    }

    var lines: [Line] {
        var result: [Line] = []
        result.reserveCapacity(count)
        var stack: [Node] = []
        var current = root

        while current != nil || !stack.isEmpty {
            while let node = current {
                stack.append(node)
                current = node.left
            }
            let node = stack.removeLast()
            result.append(node.line)
            current = node.right
        }
        return result
    }

    func line(at index: Int) -> Line? {
        var ignoredNodeVisitCount = 0
        return line(at: index, nodeVisitCount: &ignoredNodeVisitCount)
    }

    func line(at index: Int, nodeVisitCount: inout Int) -> Line? {
        guard index >= 0, index < count else { return nil }
        var remainingIndex = index
        var current = root

        while let node = current {
            nodeVisitCount += 1
            let leftCount = node.left?.lineCount ?? 0
            if remainingIndex < leftCount {
                current = node.left
            } else if remainingIndex == leftCount {
                return node.line
            } else {
                remainingIndex -= leftCount + 1
                current = node.right
            }
        }
        return nil
    }

    /// UTF-16 length of the first `lineCount` lines.
    func prefixUTF16Length(beforeLine lineCount: Int) -> Int {
        var ignoredNodeVisitCount = 0
        return prefixUTF16Length(
            beforeLine: lineCount,
            nodeVisitCount: &ignoredNodeVisitCount
        )
    }

    func prefixUTF16Length(
        beforeLine lineCount: Int,
        nodeVisitCount: inout Int
    ) -> Int {
        var remainingCount = min(max(lineCount, 0), count)
        var result = 0
        var current = root

        while remainingCount > 0, let node = current {
            nodeVisitCount += 1
            let leftCount = node.left?.lineCount ?? 0
            if remainingCount <= leftCount {
                current = node.left
            } else {
                result += (node.left?.totalUTF16Length ?? 0) + node.line.totalLength
                remainingCount -= leftCount + 1
                current = node.right
            }
        }
        return result
    }

    /// Zero-based line rank whose cumulative UTF-16 range contains `offset`.
    func index(containingUTF16Offset offset: Int) -> Int {
        var ignoredNodeVisitCount = 0
        return index(
            containingUTF16Offset: offset,
            nodeVisitCount: &ignoredNodeVisitCount
        )
    }

    func index(
        containingUTF16Offset offset: Int,
        nodeVisitCount: inout Int
    ) -> Int {
        precondition(offset >= 0 && offset < totalUTF16Length)
        var remainingOffset = offset
        var precedingLineCount = 0
        var current = root

        while let node = current {
            nodeVisitCount += 1
            let leftLength = node.left?.totalUTF16Length ?? 0
            let leftCount = node.left?.lineCount ?? 0
            if remainingOffset < leftLength {
                current = node.left
            } else if remainingOffset < leftLength + node.line.totalLength {
                return precedingLineCount + leftCount
            } else {
                remainingOffset -= leftLength + node.line.totalLength
                precedingLineCount += leftCount + 1
                current = node.right
            }
        }

        preconditionFailure("Line tree aggregates did not contain UTF-16 offset")
    }

    /// Replace one line while retaining its treap priority. Returns deterministic path work.
    @discardableResult
    mutating func replaceLine(at index: Int, with line: Line) -> Int {
        precondition(index >= 0 && index < count)
        var nodeVisitCount = 0
        root = Self.replacingLine(
            in: root,
            at: index,
            with: line,
            nodeVisitCount: &nodeVisitCount
        )
        return nodeVisitCount
    }

    /// Replace a contiguous rank range. The work is O(log lineCount + replacement.count).
    @discardableResult
    mutating func replaceSubrange(_ range: Range<Int>, with replacement: [Line]) -> Int {
        precondition(range.lowerBound >= 0 && range.upperBound <= count)
        // Count both the Cartesian builder pass and the iterative freeze pass. Split/merge path
        // visits are accumulated below, so this remains a deterministic bound on all tree work.
        var nodeVisitCount = replacement.count * 2
        let replacementRoot = Self.buildTree(
            lines: replacement,
            priorityState: &priorityState
        )
        let (prefix, remainder) = Self.split(
            root,
            keepingFirst: range.lowerBound,
            nodeVisitCount: &nodeVisitCount
        )
        let (_, suffix) = Self.split(
            remainder,
            keepingFirst: range.count,
            nodeVisitCount: &nodeVisitCount
        )
        let prefixAndReplacement = Self.merge(
            prefix,
            replacementRoot,
            nodeVisitCount: &nodeVisitCount
        )
        root = Self.merge(
            prefixAndReplacement,
            suffix,
            nodeVisitCount: &nodeVisitCount
        )
        return nodeVisitCount
    }

    private static func replacingLine(
        in root: Node?,
        at index: Int,
        with line: Line,
        nodeVisitCount: inout Int
    ) -> Node? {
        guard let root else { return nil }
        nodeVisitCount += 1
        let leftCount = root.left?.lineCount ?? 0
        if index < leftCount {
            return Node(
                line: root.line,
                priority: root.priority,
                left: replacingLine(
                    in: root.left,
                    at: index,
                    with: line,
                    nodeVisitCount: &nodeVisitCount
                ),
                right: root.right
            )
        }
        if index == leftCount {
            return Node(
                line: line,
                priority: root.priority,
                left: root.left,
                right: root.right
            )
        }
        return Node(
            line: root.line,
            priority: root.priority,
            left: root.left,
            right: replacingLine(
                in: root.right,
                at: index - leftCount - 1,
                with: line,
                nodeVisitCount: &nodeVisitCount
            )
        )
    }

    /// Split by rank, returning the first `count` lines and the remainder.
    private static func split(
        _ root: Node?,
        keepingFirst count: Int,
        nodeVisitCount: inout Int
    ) -> (Node?, Node?) {
        guard let root else { return (nil, nil) }
        guard count > 0 else { return (nil, root) }
        guard count < root.lineCount else { return (root, nil) }

        nodeVisitCount += 1
        let leftCount = root.left?.lineCount ?? 0
        if count <= leftCount {
            let (prefix, leftRemainder) = split(
                root.left,
                keepingFirst: count,
                nodeVisitCount: &nodeVisitCount
            )
            return (
                prefix,
                Node(
                    line: root.line,
                    priority: root.priority,
                    left: leftRemainder,
                    right: root.right
                )
            )
        }

        let (rightPrefix, suffix) = split(
            root.right,
            keepingFirst: count - leftCount - 1,
            nodeVisitCount: &nodeVisitCount
        )
        return (
            Node(
                line: root.line,
                priority: root.priority,
                left: root.left,
                right: rightPrefix
            ),
            suffix
        )
    }

    private static func merge(
        _ left: Node?,
        _ right: Node?,
        nodeVisitCount: inout Int
    ) -> Node? {
        guard let left else { return right }
        guard let right else { return left }

        nodeVisitCount += 1
        if left.priority >= right.priority {
            return Node(
                line: left.line,
                priority: left.priority,
                left: left.left,
                right: merge(left.right, right, nodeVisitCount: &nodeVisitCount)
            )
        }
        return Node(
            line: right.line,
            priority: right.priority,
            left: merge(left, right.left, nodeVisitCount: &nodeVisitCount),
            right: right.right
        )
    }

    private static func buildTree(
        lines: [Line],
        priorityState: inout UInt64
    ) -> Node? {
        guard !lines.isEmpty else { return nil }
        var stack: [BuilderNode] = []
        stack.reserveCapacity(lines.count)
        var treeRoot: BuilderNode?

        for line in lines {
            let node = BuilderNode(
                line: line,
                priority: nextPriority(state: &priorityState)
            )
            var lastPopped: BuilderNode?
            while let last = stack.last, last.priority < node.priority {
                lastPopped = stack.removeLast()
            }
            node.left = lastPopped
            if let parent = stack.last {
                parent.right = node
            } else {
                treeRoot = node
            }
            stack.append(node)
        }

        return freeze(treeRoot)
    }

    private static func freeze(_ builder: BuilderNode?) -> Node? {
        guard let builder else { return nil }
        var stack: [(node: BuilderNode, childrenAreFrozen: Bool)] = [(builder, false)]

        while let entry = stack.popLast() {
            if entry.childrenAreFrozen {
                entry.node.frozen = Node(
                    line: entry.node.line,
                    priority: entry.node.priority,
                    left: entry.node.left?.frozen,
                    right: entry.node.right?.frozen
                )
                continue
            }

            stack.append((entry.node, true))
            if let right = entry.node.right {
                stack.append((right, false))
            }
            if let left = entry.node.left {
                stack.append((left, false))
            }
        }

        return builder.frozen
    }

    private static func nextPriority(state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
