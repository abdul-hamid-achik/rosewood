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
    func unicodeVisualSeparatorsRemainCharactersForLSPPositions() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)

        for separator in ["\u{0085}", "\u{2028}", "\u{2029}"] {
            let text = "a\(separator)b"
            let token = decoder.decode([0, 2, 1, 2, 0], text: text)

            #expect(token.first?.range == NSRange(location: 2, length: 1))
            #expect(decoder.decode([1, 0, 1, 2, 0], text: text).isEmpty)
        }
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

    // MARK: - Malformed / adversarial server data (must not trap on integer overflow)

    @Test
    func decodeDoesNotTrapOnOverflowingDeltaStart() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        // Two huge deltaStart values: the column accumulation would overflow Int and trap.
        let data = [0, Int.max, 1, 0, 0, 0, Int.max, 1, 0, 0]
        let tokens = decoder.decode(data, text: "let value = 1")
        #expect(tokens.isEmpty)
    }

    @Test
    func decodeDoesNotTrapOnOverflowingDeltaLine() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        // Two huge deltaLine values: the line accumulation would overflow Int and trap.
        let data = [Int.max, 0, 1, 0, 0, Int.max, 0, 1, 0, 0]
        let tokens = decoder.decode(data, text: "abc")
        #expect(tokens.isEmpty)
    }

    @Test
    func decodeClampsOverflowingTokenLength() {
        let decoder = SemanticTokenDecoder(legend: Self.legend)
        let text = "abcdef"
        // Second token starts at offset 4 with length Int.max → 4 + Int.max overflows Int.
        let data = [
            0, 0, 3, 0, 0,        // valid token at 0..3
            0, 4, Int.max, 0, 0   // overflowing length
        ]
        let tokens = decoder.decode(data, text: text)
        #expect(tokens.count == 2)
        #expect(tokens[0].range == NSRange(location: 0, length: 3))
        // Overflowing length clamps to end of text rather than trapping.
        #expect(tokens[1].range == NSRange(location: 4, length: 2))
    }
}
