import Testing
@testable import Rosewood

struct EditorRenderStateTests {
    @Test
    func offscreenRenderStillRequiresVisibleRefresh() {
        var state = EditorRenderState()

        state.recordRender(text: "let value = 1", language: "swift", isViewReadyForDisplay: false)

        #expect(
            state.needsTextApplication(
                for: "let value = 1",
                language: "swift",
                renderedText: "let value = 1",
                isViewReadyForDisplay: true
            )
        )
    }

    @Test
    func visibleRenderClearsForcedRefreshFlag() {
        var state = EditorRenderState()

        state.recordRender(text: "let value = 1", language: "swift", isViewReadyForDisplay: false)
        state.recordRender(text: "let value = 1", language: "swift", isViewReadyForDisplay: true)

        #expect(
            !state.needsTextApplication(
                for: "let value = 1",
                language: "swift",
                renderedText: "let value = 1",
                isViewReadyForDisplay: true
            )
        )
    }

    @Test
    func languageChangeForcesHighlightRefresh() {
        var state = EditorRenderState()

        state.recordRender(text: "const value = 1", language: "javascript", isViewReadyForDisplay: true)

        #expect(
            state.needsTextApplication(
                for: "const value = 1",
                language: "typescript",
                renderedText: "const value = 1",
                isViewReadyForDisplay: true
            )
        )
    }
}
