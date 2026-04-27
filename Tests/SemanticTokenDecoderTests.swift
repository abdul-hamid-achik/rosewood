import Foundation
import Testing
@testable import Rosewood

struct SemanticTokenDecoderTests {

    private static let legend = SemanticTokensLegend(
        tokenTypes: ["keyword", "function", "variable"],
        tokenModifiers: ["readonly", "static"]
    )

    @Test
    func decodeSingleTokenOnFirstLine() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        // (deltaLine=0, deltaStart=0, length=3, type=0 keyword, modifiers=0)
        let tokens = decoder.decode([0, 0, 3, 0, 0], text: "let value = 1")

        #expect(tokens.count == 1)
        #expect(tokens.first?.range == NSRange(location: 0, length: 3))
        #expect(tokens.first?.tokenType == "keyword")
    }

    @Test
    func decodeMultipleTokensAcrossLines() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        let text = "let foo = 1\nfunc bar() {}"
        // First token: line 0, char 0, length 3 (keyword "let")
        // Second token: line 0, char 4, length 3 (variable "foo") — delta from prev
        // Third token: line 1, char 0, length 4 (keyword "func")
        let data = [
            0, 0, 3, 0, 0,   // "let" at (0,0)
            0, 4, 3, 2, 0,   // "foo" at (0,4)
            1, 0, 4, 0, 0    // "func" at (1,0)
        ]
        let tokens = decoder.decode(data, text: text)

        #expect(tokens.count == 3)
        #expect(tokens[0].range == NSRange(location: 0, length: 3))
        #expect(tokens[1].range == NSRange(location: 4, length: 3))
        #expect(tokens[2].range == NSRange(location: 12, length: 4))
        #expect(tokens[2].tokenType == "keyword")
    }

    @Test
    func decodeIgnoresTokensPastEndOfText() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        let text = "abc"
        // Token at line 5 (past end): should be skipped, not crash
        let data = [5, 0, 3, 0, 0]
        let tokens = decoder.decode(data, text: text)

        #expect(tokens.isEmpty)
    }

    @Test
    func decodeViewportFiltersTokensOutsideRange() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        let text = "line0\nline1\nline2\nline3\nline4"
        // Tokens on lines 0, 2, 4
        let data = [
            0, 0, 5, 0, 0,   // "line0" at (0,0) → offset 0..5
            2, 0, 5, 1, 0,   // "line2" at (2,0) → offset 12..17
            2, 0, 5, 2, 0    // "line4" at (4,0) → offset 24..29
        ]

        let allTokens = decoder.decode(data, text: text)
        #expect(allTokens.count == 3)

        // Visible range covers only line2 (offset ~12..17)
        let visible = NSRange(location: 12, length: 5)
        let viewportTokens = decoder.decodeViewport(data, text: text, visibleRange: visible)

        #expect(viewportTokens.count == 1)
        #expect(viewportTokens.first?.range == NSRange(location: 12, length: 5))
    }

    @Test
    func decodeViewportFallsBackToFullDecodeForNegativeRange() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        let text = "abc"
        let data = [0, 0, 3, 0, 0]
        let tokens = decoder.decodeViewport(
            data,
            text: text,
            visibleRange: NSRange(location: -1, length: 0)
        )

        #expect(tokens.count == 1)
    }

    @Test
    func decodeRespectsLineDeltasWhenSkippingForViewport() {
        // Regression: viewport filter must not break delta accumulation —
        // tokens after a skipped one still need correct line/char positions.
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        let text = "line0\nline1\nline2"
        let data = [
            0, 0, 5, 0, 0,   // line0 — outside viewport
            2, 0, 5, 1, 0    // line2 — inside viewport (depends on line 0 having been counted)
        ]

        let viewportTokens = decoder.decodeViewport(
            data,
            text: text,
            visibleRange: NSRange(location: 12, length: 5)
        )

        #expect(viewportTokens.count == 1)
        #expect(viewportTokens.first?.range == NSRange(location: 12, length: 5))
    }

    @Test
    func decodesModifiersFromBitset() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        // bitset 0b11 → both "readonly" and "static"
        let tokens = decoder.decode([0, 0, 3, 0, 3], text: "let")

        #expect(tokens.first?.modifiers.contains("readonly") == true)
        #expect(tokens.first?.modifiers.contains("static") == true)
        #expect(tokens.first?.isReadonly == true)
        #expect(tokens.first?.isStatic == true)
    }
}
