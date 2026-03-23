import AppKit
import Testing
@testable import Rosewood

struct EditorSupportTests {
    @Test
    func languageMappingCoversCommonExtensions() {
        #expect(EditorTab.languageFromExtension("swift") == "swift")
        #expect(EditorTab.languageFromExtension("yaml") == "yaml")
        #expect(EditorTab.languageFromExtension("tsx") == "typescript")
        #expect(EditorTab.languageFromExtension("unknown") == "plaintext")
    }

    @Test
    func editorContextMenuStateIncludesLSPAndFileItemsInExpectedOrder() {
        let state = EditorContextMenuState(
            hasSavedFile: true,
            hasLanguageServer: true,
            hasResolvableSymbol: true,
            hasRelativePath: true
        )

        #expect(
            state.items == [
                .cut,
                .copy,
                .paste,
                .selectAll,
                .divider,
                .goToDefinition,
                .findReferences,
                .showHoverInfo,
                .divider,
                .revealInFinder,
                .copyFilePath,
                .copyRelativePath
            ]
        )
        #expect(state.isEnabled(.goToDefinition))
        #expect(state.isEnabled(.findReferences))
        #expect(state.isEnabled(.showHoverInfo))
        #expect(state.isEnabled(.copyRelativePath))
    }

    @Test
    func editorContextMenuStateFallsBackToTextActionsForUntitledPlaintextEditor() {
        let state = EditorContextMenuState(
            hasSavedFile: false,
            hasLanguageServer: false,
            hasResolvableSymbol: false,
            hasRelativePath: false
        )

        #expect(state.items == [.cut, .copy, .paste, .selectAll])
    }

    @Test
    func editorContextMenuStateDisablesLSPAndRelativePathActionsWhenUnavailable() {
        let state = EditorContextMenuState(
            hasSavedFile: true,
            hasLanguageServer: true,
            hasResolvableSymbol: false,
            hasRelativePath: false
        )

        #expect(!state.isEnabled(.goToDefinition))
        #expect(!state.isEnabled(.findReferences))
        #expect(!state.isEnabled(.showHoverInfo))
        #expect(!state.isEnabled(.copyRelativePath))
        #expect(state.isEnabled(.copyFilePath))
    }

    @Test
    func editorContextMenuStateSupportsLSPActionsWithoutSavedFileActions() {
        let state = EditorContextMenuState(
            hasSavedFile: false,
            hasLanguageServer: true,
            hasResolvableSymbol: true,
            hasRelativePath: false
        )

        #expect(
            state.items == [
                .cut,
                .copy,
                .paste,
                .selectAll,
                .divider,
                .goToDefinition,
                .findReferences,
                .showHoverInfo
            ]
        )
        #expect(state.isEnabled(.goToDefinition))
        #expect(state.isEnabled(.findReferences))
        #expect(state.isEnabled(.showHoverInfo))
    }

    @Test
    func highlightServiceReturnsAttributedStringForUnknownLanguage() {
        let code = "plain text"
        let attributed = HighlightService.shared.highlightedAttributedString(
            code,
            language: "unknown-language",
            themeColors: HighlightService.shared.themeColors()
        )

        #expect(attributed.string == code)
        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        #expect(attributes[.font] is NSFont)
        #expect(attributes[.foregroundColor] is NSColor)
    }

    @Test
    func bracketMatcherFindsMatchingPairFromOpeningBracket() {
        let text = "func test() { print([1, 2, 3]) }" as NSString

        let ranges = BracketMatcher.matchingRanges(in: text, caretLocation: 12)

        #expect(ranges.count == 2)
        #expect(text.substring(with: ranges[0]) == "{")
        #expect(text.substring(with: ranges[1]) == "}")
    }

    @Test
    func bracketMatcherFindsMatchingPairFromClosingBracket() {
        let text = "items[index]" as NSString

        let ranges = BracketMatcher.matchingRanges(in: text, caretLocation: 12)

        #expect(ranges.count == 2)
        #expect(text.substring(with: ranges[0]) == "[")
        #expect(text.substring(with: ranges[1]) == "]")
    }

    @Test
    func editorInputHandlerInsertsMatchingDelimiterPair() {
        let outcome = EditorInputHandler.outcome(
            for: "(",
            selectedRange: NSRange(location: 4, length: 0),
            affectedRange: NSRange(location: 4, length: 0),
            in: "func" as NSString
        )

        #expect(outcome == EditorInputOutcome(replacementText: "()", selectedLocation: 5))
    }

    @Test
    func editorInputHandlerSkipsExistingClosingDelimiter() {
        let outcome = EditorInputHandler.outcome(
            for: ")",
            selectedRange: NSRange(location: 1, length: 0),
            affectedRange: NSRange(location: 1, length: 0),
            in: "()" as NSString
        )

        #expect(outcome == EditorInputOutcome(replacementText: "", selectedLocation: 2))
    }

    @Test
    func editorInputHandlerConvertsTabToSpaces() {
        let outcome = EditorInputHandler.outcome(
            for: "\t",
            selectedRange: NSRange(location: 0, length: 0),
            affectedRange: NSRange(location: 0, length: 0),
            in: "" as NSString
        )

        #expect(outcome == EditorInputOutcome(replacementText: "    ", selectedLocation: 4))
    }

    @Test
    func lineNumberLayoutPinsPartiallyVisibleWrappedLineToViewportTop() {
        let visibleRect = NSRect(x: 0, y: 100, width: 400, height: 300)
        let lineRect = NSRect(x: 0, y: 40, width: 400, height: 90)

        let yPosition = LineNumberLayout.labelYPosition(
            for: lineRect,
            visibleRect: visibleRect,
            textOriginY: 20
        )

        #expect(yPosition == 0)
    }

    @Test
    func lineNumberLayoutUsesActualLineStartWhenFullyVisible() {
        let visibleRect = NSRect(x: 0, y: 100, width: 400, height: 300)
        let lineRect = NSRect(x: 0, y: 120, width: 400, height: 18)

        let yPosition = LineNumberLayout.labelYPosition(
            for: lineRect,
            visibleRect: visibleRect,
            textOriginY: 10
        )

        #expect(yPosition == 30)
    }

    @Test
    func lineNumberLayoutSkipsLinesFullyAboveViewport() {
        let visibleRect = NSRect(x: 0, y: 100, width: 400, height: 300)
        let lineRect = NSRect(x: 0, y: 20, width: 400, height: 40)

        let yPosition = LineNumberLayout.labelYPosition(
            for: lineRect,
            visibleRect: visibleRect,
            textOriginY: 10
        )

        #expect(yPosition == nil)
    }

    @Test
    @MainActor
    func editorTextViewStoresContextMenuPointAndDelegatesMenuConstruction() throws {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 200, height: 200))
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), textContainer: textContainer)
        let delegate = TestEditorTextViewMenuDelegate()
        textView.menuDelegate = delegate

        let event = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: NSPoint(x: 24, y: 18),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        let expectedPoint = textView.convert(event.locationInWindow, from: nil)

        let menu = textView.menu(for: event)

        #expect(menu === delegate.menu)
        #expect(textView.lastContextMenuPoint == expectedPoint)
        #expect(delegate.receivedPoint == expectedPoint)
    }

    @Test
    func editorLSPRequestTrackerRejectsStaleRequests() {
        var tracker = EditorLSPRequestTracker()

        let firstRequestID = tracker.nextRequestID()
        let secondRequestID = tracker.nextRequestID()

        #expect(!tracker.shouldDeliver(
            requestID: firstRequestID,
            documentURI: "file:///one.swift",
            currentDocumentURI: "file:///one.swift"
        ))
        #expect(tracker.shouldDeliver(
            requestID: secondRequestID,
            documentURI: "file:///one.swift",
            currentDocumentURI: "file:///one.swift"
        ))
    }

    @Test
    func editorLSPRequestTrackerRejectsMismatchedDocumentURIs() {
        var tracker = EditorLSPRequestTracker()
        let requestID = tracker.nextRequestID()

        #expect(!tracker.shouldDeliver(
            requestID: requestID,
            documentURI: "file:///one.swift",
            currentDocumentURI: "file:///two.swift"
        ))
        #expect(!tracker.shouldDeliver(
            requestID: requestID,
            documentURI: "file:///one.swift",
            currentDocumentURI: nil
        ))
        #expect(tracker.shouldDeliver(
            requestID: requestID,
            documentURI: "file:///one.swift",
            currentDocumentURI: "file:///one.swift"
        ))
    }

    @Test
    @MainActor
    func editorContainerAppliesHighlightedTokenColorsToTextViewStorage() {
        let container = EditorContainerView(
            themeColors: .nord,
            font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            showLineNumbers: true,
            wordWrap: false
        )

        container.applyText("let alpha = 1", language: "swift", themeColors: .nord)

        let attributed = try! #require(container.textView.textStorage)
        let layoutManager = try! #require(container.textView.layoutManager)
        var distinctColors = Set<String>()
        var index = 0
        while index < attributed.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = layoutManager.temporaryAttributes(atCharacterIndex: index, effectiveRange: &effectiveRange)
            if let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB) {
                distinctColors.insert(color.hexString)
            }
            let nextIndex = NSMaxRange(effectiveRange)
            index = max(nextIndex, index + 1)
        }

        #expect(distinctColors.count > 1, "Editor layout should retain multiple syntax token colors after applyText")
    }
}

private final class TestEditorTextViewMenuDelegate: EditorTextViewMenuDelegate {
    let menu = NSMenu(title: "Test")
    var receivedPoint: NSPoint?

    func menu(for textView: EditorTextView, at point: NSPoint) -> NSMenu {
        receivedPoint = point
        return menu
    }
}
