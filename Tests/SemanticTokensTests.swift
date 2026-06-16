import AppKit
import Testing
@testable import Rosewood

/// Tests the editor's semantic-token apply path: decoded LSP tokens are painted as temporary
/// foreground colors, layered after (and surviving) the Highlightr syntax pass, and dropped when
/// the request is superseded or the text has moved on. The wire-level decode is covered separately
/// by SemanticTokenDecoderTests; these focus on the EditorContainerView contract the Coordinator
/// drives.
@MainActor
struct SemanticTokensTests {
    private let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    // "let alpha = 1" — a single "keyword" token over "alpha" (chars [4, 9)). keyword → nsWarning,
    // which is distinct from the foreground color the identifier "alpha" gets from syntax.
    private let sampleText = "let alpha = 1"
    private let tokenLocation = 4
    private func sampleTokens() -> SemanticTokens { SemanticTokens(data: [0, 4, 5, 0, 0]) }
    private func sampleLegend() -> SemanticTokensLegend {
        SemanticTokensLegend(tokenTypes: ["keyword"], tokenModifiers: [])
    }

    private func makeContainer() -> EditorContainerView {
        EditorContainerView(
            themeColors: .nord,
            font: monoFont,
            showMinimap: true,
            showLineNumbers: true,
            wordWrap: false
        )
    }

    private func foregroundHex(at index: Int, in container: EditorContainerView) -> String? {
        guard let layoutManager = container.textView.layoutManager else { return nil }
        var effectiveRange = NSRange(location: 0, length: 0)
        let attributes = layoutManager.temporaryAttributes(atCharacterIndex: index, effectiveRange: &effectiveRange)
        return (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)?.hexString
    }

    /// Wait until the document has more than one temporary foreground color, i.e. the async
    /// Highlightr syntax pass has landed.
    private func waitForSyntaxHighlight(in container: EditorContainerView) async throws {
        try await waitForSemantic {
            guard let textStorage = container.textView.textStorage,
                  let layoutManager = container.textView.layoutManager else { return false }
            var colors = Set<String>()
            var index = 0
            while index < textStorage.length {
                var effectiveRange = NSRange(location: 0, length: 0)
                let attributes = layoutManager.temporaryAttributes(atCharacterIndex: index, effectiveRange: &effectiveRange)
                if let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB) {
                    colors.insert(color.hexString)
                }
                index = max(NSMaxRange(effectiveRange), index + 1)
            }
            return colors.count > 1
        }
    }

    @Test
    func appliesLegendColorAtTokenRange() async throws {
        let container = makeContainer()
        container.applyText(sampleText, language: "swift", themeColors: .nord, documentIdentity: "doc-a")
        try await waitForSyntaxHighlight(in: container)

        let version = container.beginSemanticTokensRequest()
        container.applySemanticTokens(
            sampleTokens(),
            legend: sampleLegend(),
            version: version,
            textForTokens: container.currentDisplayText
        )

        let expected = SemanticTokenDecoder.tokenTypeColor("keyword", themeColors: .nord).usingColorSpace(.sRGB)?.hexString
        #expect(foregroundHex(at: tokenLocation, in: container) == expected)
    }

    @Test
    func dropsResultFromSupersededVersion() async throws {
        let container = makeContainer()
        container.applyText(sampleText, language: "swift", themeColors: .nord, documentIdentity: "doc-a")
        try await waitForSyntaxHighlight(in: container)

        let stale = container.beginSemanticTokensRequest()
        _ = container.beginSemanticTokensRequest() // a newer request bumps the version past `stale`
        let before = foregroundHex(at: tokenLocation, in: container)

        container.applySemanticTokens(
            sampleTokens(),
            legend: sampleLegend(),
            version: stale,
            textForTokens: container.currentDisplayText
        )

        #expect(foregroundHex(at: tokenLocation, in: container) == before, "Stale-version tokens must not paint")
    }

    @Test
    func dropsResultWhenTextHasChanged() async throws {
        let container = makeContainer()
        container.applyText(sampleText, language: "swift", themeColors: .nord, documentIdentity: "doc-a")
        try await waitForSyntaxHighlight(in: container)

        let version = container.beginSemanticTokensRequest()
        let before = foregroundHex(at: tokenLocation, in: container)

        container.applySemanticTokens(
            sampleTokens(),
            legend: sampleLegend(),
            version: version,
            textForTokens: "something the user has since typed past"
        )

        #expect(foregroundHex(at: tokenLocation, in: container) == before, "Tokens for stale text must not paint")
    }

    @Test
    func semanticColorsSurviveRehighlightAndFollowTheme() async throws {
        let container = makeContainer()
        container.applyText(sampleText, language: "swift", themeColors: .nord, documentIdentity: "doc-a")
        try await waitForSyntaxHighlight(in: container)

        let version = container.beginSemanticTokensRequest()
        container.applySemanticTokens(
            sampleTokens(),
            legend: sampleLegend(),
            version: version,
            textForTokens: container.currentDisplayText
        )
        let nordWarning = SemanticTokenDecoder.tokenTypeColor("keyword", themeColors: .nord).usingColorSpace(.sRGB)?.hexString
        #expect(foregroundHex(at: tokenLocation, in: container) == nordWarning)

        // A theme change re-runs Highlightr (which clears + repaints the foreground temp layer).
        // The cached tokens must re-apply at the highlight tail, now resolved against the new theme.
        let draculaWarning = SemanticTokenDecoder.tokenTypeColor("keyword", themeColors: .dracula).usingColorSpace(.sRGB)?.hexString
        container.applyText(sampleText, language: "swift", themeColors: .dracula, documentIdentity: "doc-a")
        try await waitForSemantic {
            foregroundHex(at: tokenLocation, in: container) == draculaWarning
        }
        #expect(foregroundHex(at: tokenLocation, in: container) == draculaWarning)
    }

    @Test
    func documentSwitchInvalidatesCachedTokens() async throws {
        let container = makeContainer()
        container.applyText(sampleText, language: "swift", themeColors: .nord, documentIdentity: "doc-a")
        try await waitForSyntaxHighlight(in: container)

        let version = container.beginSemanticTokensRequest()
        container.applySemanticTokens(
            sampleTokens(),
            legend: sampleLegend(),
            version: version,
            textForTokens: container.currentDisplayText
        )
        let warning = SemanticTokenDecoder.tokenTypeColor("keyword", themeColors: .nord).usingColorSpace(.sRGB)?.hexString
        #expect(foregroundHex(at: tokenLocation, in: container) == warning)

        // Switching documents (new identity) must drop the cache so doc-a's tokens are never
        // repainted over doc-b. doc-b has no keyword at position 4, so the warning color must vanish.
        container.applyText("print(beta)", language: "swift", themeColors: .nord, documentIdentity: "doc-b")
        try await waitForSyntaxHighlight(in: container)
        container.applyDecodedSemanticTokens() // a highlight-tail re-apply would no-op on a cleared cache

        #expect(foregroundHex(at: tokenLocation, in: container) != warning, "Tokens must not survive a document switch")
    }
}

private func waitForSemantic(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    stepNanoseconds: UInt64 = 25_000_000,
    condition: @escaping () throws -> Bool
) async throws {
    let iterations = Int(timeoutNanoseconds / stepNanoseconds)
    for _ in 0..<iterations {
        if try condition() {
            return
        }
        try await Task.sleep(nanoseconds: stepNanoseconds)
    }
    Issue.record("Timed out waiting for semantic-token condition")
}
