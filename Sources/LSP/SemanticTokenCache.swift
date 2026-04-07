import Foundation

struct CachedTokenRange: Sendable {
    let lineStart: Int
    let lineEnd: Int
    let tokens: [DecodedSemanticToken]
    let documentVersion: Int
}

actor SemanticTokenCache {
    private var lineRanges: [Int: CachedTokenRange] = [:]
    private var currentDocumentVersion: Int = 0
    private let linesPerEntry: Int = 50

    func tokens(for line: Int) -> CachedTokenRange? {
        let bucket = line / linesPerEntry
        return lineRanges[bucket]
    }

    func allTokens() -> [DecodedSemanticToken] {
        return lineRanges.values.flatMap { $0.tokens }
    }

    func setTokens(_ tokens: [DecodedSemanticToken], for range: NSRange, documentVersion: Int) {
        guard !tokens.isEmpty else { return }

        let nsText = "" as NSString
        let lineStart = nsText.lineRange(for: NSRange(location: range.location, length: 0)).location
        let lineEnd = nsText.lineRange(for: NSRange(location: NSMaxRange(range), length: 0)).location

        let bucket = lineStart / linesPerEntry
        lineRanges[bucket] = CachedTokenRange(
            lineStart: lineStart,
            lineEnd: lineEnd,
            tokens: tokens,
            documentVersion: documentVersion
        )
    }

    func setTokensForBucket(_ tokens: [DecodedSemanticToken], bucket: Int, documentVersion: Int) {
        guard !tokens.isEmpty else { return }

        if let bucketRange = lineRanges[bucket] {
            lineRanges[bucket] = CachedTokenRange(
                lineStart: bucketRange.lineStart,
                lineEnd: bucketRange.lineEnd,
                tokens: tokens,
                documentVersion: documentVersion
            )
        } else {
            lineRanges[bucket] = CachedTokenRange(
                lineStart: bucket * linesPerEntry,
                lineEnd: (bucket + 1) * linesPerEntry - 1,
                tokens: tokens,
                documentVersion: documentVersion
            )
        }
    }

    func invalidate(lineStart: Int, lineEnd: Int) {
        let startBucket = lineStart / linesPerEntry
        let endBucket = lineEnd / linesPerEntry

        for bucket in startBucket...endBucket {
            lineRanges[bucket] = nil
        }
    }

    func invalidateForOffset(_ offset: Int, length: Int, text: NSString) {
        guard length > 0 else { return }

        let editLineStart = text.lineRange(for: NSRange(location: offset, length: 0)).location
        let editLineEnd = text.lineRange(for: NSRange(location: offset + length, length: 0)).location

        invalidate(lineStart: editLineStart, lineEnd: editLineEnd)
    }

    func updateDocumentVersion(_ version: Int) {
        currentDocumentVersion = version
    }

    func currentVersion() -> Int {
        return currentDocumentVersion
    }

    func clear() {
        lineRanges.removeAll()
        currentDocumentVersion = 0
    }

    func cachedLineCount() -> Int {
        return lineRanges.count
    }

    func hasFullCoverage(upToLine line: Int) -> Bool {
        guard line > 0 else { return true }

        let requiredBuckets = (line / linesPerEntry) + 1
        return lineRanges.count >= requiredBuckets
    }
}
