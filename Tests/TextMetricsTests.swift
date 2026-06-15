import Foundation
import Testing
@testable import Rosewood

struct TextMetricsTests {
    @Test
    func lineNumberAtOffset() {
        let text = "a\nbb\nccc" as NSString
        #expect(TextMetrics.lineNumber(atUTF16Offset: 0, in: text) == 1)
        #expect(TextMetrics.lineNumber(atUTF16Offset: 2, in: text) == 2)
        #expect(TextMetrics.lineNumber(atUTF16Offset: 5, in: text) == 3)
        #expect(TextMetrics.lineNumber(atUTF16Offset: text.length, in: text) == 3)
        #expect(TextMetrics.lineNumber(atUTF16Offset: 0, in: "" as NSString) == 1)
    }

    @Test
    func matchesNaiveCountAcrossChunkBoundary() {
        // Longer than the 4096 chunk, to exercise chunked scanning.
        let big = String(repeating: String(repeating: "x", count: 100) + "\n", count: 100) as NSString
        #expect(TextMetrics.lineNumber(atUTF16Offset: big.length, in: big) == 101)
        for offset in [0, 101, 202, 5000, big.length] {
            let naive = (big.substring(to: min(offset, big.length)) as String)
                .reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
            #expect(TextMetrics.lineNumber(atUTF16Offset: offset, in: big) == naive)
        }
    }
}
