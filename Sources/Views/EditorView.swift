import AppKit
import SwiftUI
import Combine

struct EditorView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    @EnvironmentObject private var commandDispatcher: AppCommandDispatcher
    @EnvironmentObject private var lspService: LSPService
    @EnvironmentObject private var diagnosticsModel: DiagnosticsModel
    let tab: EditorTab

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var configIdentity: some Hashable {
        ConfigIdentity(
            fontSize: configService.settings.editor.fontSize,
            fontFamily: configService.settings.editor.fontFamily,
            themeName: configService.currentThemeDefinition.id,
            tabSize: configService.settings.editor.tabSize,
            showLineNumbers: configService.settings.editor.showLineNumbers,
            showMinimap: effectiveShowMinimap,
            wordWrap: configService.settings.editor.wordWrap
        )
    }

    private var effectiveShowMinimap: Bool {
        switch tab.contentType {
        case .text(let isLarge):
            guard configService.settings.editor.showMinimap else { return false }
            if isLarge,
               let filePath = tab.filePath,
               let fileSize = try? filePath.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                return fileSize < configService.settings.fileHandling.largeFileThresholdKB * 1024
            }
            return true
        default:
            return false
        }
    }

    private var deferHighlightingDuringEditing: Bool {
        if case .text(let isLarge) = tab.contentType {
            if isLarge { return true }
            // Full-document re-highlight on every keystroke is the dominant
            // typing-latency cost above ~2KB; smaller files re-highlight fast
            // enough that instant re-color feels nicer than a 180ms gap.
            // Use the live buffer size so the heuristic tracks the document as it grows.
            return (projectViewModel.liveSelectedTabContent()?.utf8.count ?? tab.content.utf8.count) > 2048
        }
        return false
    }

    var body: some View {
        CodeEditorRepresentable(
            text: Binding(
                get: { projectViewModel.liveSelectedTabContent() ?? tab.content },
                set: { newValue in
                    // Update synchronously (already on the main thread). Deferring this to a
                    // later runloop turn lets a Save/autosave in the gap persist stale text.
                    projectViewModel.updateTabContent(newValue)
                }
            ),
            language: tab.language,
            editorFont: configService.font,
            commandDispatcher: commandDispatcher,
            deferHighlightingDuringEditing: deferHighlightingDuringEditing,
            pendingLineJump: Binding(
                get: { projectViewModel.selectedTab?.pendingLineJump },
                set: { newValue in
                    if newValue == nil {
                        DispatchQueue.main.async {
                            projectViewModel.clearPendingLineJump()
                        }
                    }
                }
            ),
            themeColors: themeColors,
            tabSize: configService.settings.editor.tabSize,
            showLineNumbers: configService.settings.editor.showLineNumbers,
            showMinimap: effectiveShowMinimap,
            wordWrap: configService.settings.editor.wordWrap,
            diagnostics: diagnosticsModel.currentTabDiagnostics,
            breakpointLines: projectViewModel.currentTabBreakpointLines,
            executionLine: projectViewModel.currentExecutionLine,
            fileURL: projectViewModel.selectedTab?.filePath ?? tab.filePath,
            documentIdentity: projectViewModel.selectedTab?.documentURI
                ?? tab.documentURI
                ?? (projectViewModel.selectedTab?.filePath ?? tab.filePath)?.path,
            projectRootDirectory: projectViewModel.rootDirectory,
            prefersProjectSearchNavigation: projectViewModel.canNavigateProjectSearchResults,
            isLanguageServerAvailable: lspService.serverAvailable(for: tab.language),
            documentURI: projectViewModel.selectedTab?.documentURI,
            lspService: lspService,
            onCursorChange: { line, column in
                DispatchQueue.main.async {
                    projectViewModel.updateCursorPosition(line: line, column: column)
                }
            },
            onViewportChange: { startLine, endLine in
                DispatchQueue.main.async {
                    projectViewModel.updateEditorVisibleLineRange(startLine: startLine, endLine: endLine)
                }
            },
            onToggleBreakpoint: { line in
                DispatchQueue.main.async {
                    projectViewModel.toggleBreakpoint(line: line)
                }
            },
            onNavigateToDefinition: { url, line in
                DispatchQueue.main.async {
                    projectViewModel.openFile(at: url)
                    if let idx = projectViewModel.selectedTabIndex {
                        projectViewModel.openTabs[idx].pendingLineJump = line
                    }
                }
            },
            onShowReferences: { locations in
                DispatchQueue.main.async {
                    projectViewModel.showReferences(locations)
                }
            },
            onBeginReferences: {
                DispatchQueue.main.async {
                    projectViewModel.beginFindReferences()
                }
            },
            onRevealInFinder: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        )
        .background(themeColors.background)
    }
}

private struct ConfigIdentity: Hashable {
    let fontSize: CGFloat
    let fontFamily: String
    let themeName: String
    let tabSize: Int
    let showLineNumbers: Bool
    let showMinimap: Bool
    let wordWrap: Bool
}

private struct CodeEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let language: String
    let editorFont: NSFont
    let commandDispatcher: AppCommandDispatcher
    let deferHighlightingDuringEditing: Bool
    @Binding var pendingLineJump: Int?
    let themeColors: ThemeColors
    let tabSize: Int
    let showLineNumbers: Bool
    let showMinimap: Bool
    let wordWrap: Bool
    let diagnostics: [LSPDiagnostic]
    let breakpointLines: Set<Int>
    let executionLine: Int?
    let fileURL: URL?
    let documentIdentity: String?
    let projectRootDirectory: URL?
    let prefersProjectSearchNavigation: Bool
    let isLanguageServerAvailable: Bool
    let documentURI: String?
    let lspService: LSPServiceProtocol?
    let onCursorChange: (Int, Int) -> Void
    let onViewportChange: (Int, Int) -> Void
    let onToggleBreakpoint: (Int) -> Void
    let onNavigateToDefinition: ((URL, Int) -> Void)?
    let onShowReferences: (([LSPLocation]) -> Void)?
    let onBeginReferences: (() -> Void)?
    let onRevealInFinder: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> EditorContainerView {
        let containerView = EditorContainerView(
            themeColors: themeColors,
            font: editorFont,
            showMinimap: showMinimap,
            showLineNumbers: showLineNumbers,
            wordWrap: wordWrap
        )
        containerView.onViewportChange = onViewportChange
        context.coordinator.attach(to: containerView)
        return containerView
    }

    func updateNSView(_ nsView: EditorContainerView, context: Context) {
        context.coordinator.parent = self

        // Track if we need to update anything
        let fontChanged = nsView.textView.font != editorFont
        let themeChanged = nsView.themeColors != themeColors
        let minimapChanged = nsView.minimapView.isHidden == showMinimap
        let wordWrapChanged = nsView.textView.isHorizontallyResizable == wordWrap
        let lineNumbersChanged = nsView.showLineNumbers != showLineNumbers
        let tabSizeChanged = nsView.tabSize != tabSize

        // Apply incremental changes
        if fontChanged {
            nsView.textView.font = editorFont
        }

        // Apply tab size before any theme pass so a re-render picks up the new tab width.
        if tabSizeChanged {
            nsView.setTabSize(tabSize)
        }

        if themeChanged {
            // applyTheme already re-applies line numbers / minimap / word wrap, so the
            // dedicated branches below are skipped when a full theme pass runs.
            nsView.applyTheme(
                themeColors,
                font: editorFont,
                showMinimap: showMinimap,
                showLineNumbers: showLineNumbers,
                wordWrap: wordWrap
            )
        } else {
            // Live-apply editor settings so Settings toggles take effect immediately on the open
            // editor instead of only after a theme change or tab reopen.
            if lineNumbersChanged {
                nsView.setLineNumbersVisible(showLineNumbers)
            }
            if minimapChanged {
                nsView.setMinimapVisible(showMinimap)
            }
            if wordWrapChanged {
                nsView.setWordWrap(wordWrap)
            }
        }

        // Always update these (cheap operations)
        nsView.onViewportChange = onViewportChange
        nsView.lineNumberView.breakpointLines = breakpointLines
        nsView.lineNumberView.currentExecutionLine = executionLine
        nsView.lineNumberView.onToggleBreakpoint = onToggleBreakpoint
        nsView.lineNumberView.needsDisplay = true
        context.coordinator.applyExternalState(text: text, language: language)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, EditorTextViewMenuDelegate, NSUserInterfaceValidations {
        var parent: CodeEditorRepresentable
        weak var containerView: EditorContainerView?

        private var renderState = EditorRenderState()
        private var isApplyingExternalUpdate = false
        private let completionPopup = CompletionPopupController()
        private let hoverPopup = HoverPopupController()
        private var completionTask: Task<Void, Never>?
        private var hoverTask: Task<Void, Never>?
        private var referencesTask: Task<Void, Never>?
        private var referenceRequestTracker = EditorLSPRequestTracker()
        private var foldedStartLines: Set<Int> = []
        private var currentFoldSnapshot = FoldedTextSnapshot.identity
        private var pendingSourceSelection: NSRange?
        private var mouseMonitor: Any?
        private var commandCancellables: Set<AnyCancellable> = []
        private var deferredHighlightTask: Task<Void, Never>?
        private let dwellDelayNanoseconds: UInt64 = 250_000_000
        private var dwellTimer: Task<Void, Never>?
        private var lastHoverPoint: NSPoint?
        private var isMouseOverText = false

        init(parent: CodeEditorRepresentable) {
            self.parent = parent
            super.init()
            completionPopup.onSelect = { [weak self] item in
                self?.insertCompletion(item)
            }
        }

        deinit {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
            }
            completionTask?.cancel()
            hoverTask?.cancel()
            referencesTask?.cancel()
            deferredHighlightTask?.cancel()
        }

        func attach(to containerView: EditorContainerView) {
            self.containerView = containerView
            containerView.configure(delegate: self)
            containerView.textView.menuDelegate = self
            applyPopupTheme()
            containerView.onLayout = { [weak self] in
                self?.containerViewDidLayout()
            }
            containerView.onScroll = { [weak self] in
                // Cancel in-flight async requests too, so a late response can't re-show a popup
                // anchored to a position that has since scrolled away.
                self?.completionTask?.cancel()
                self?.completionPopup.dismiss()
                self?.hoverTask?.cancel()
                self?.hoverPopup.dismiss()
            }
            setupMouseMonitor()
            setupCommandObservers()
        }

        func containerViewDidLayout() {
            guard !isApplyingExternalUpdate else { return }
            applyExternalState(text: parent.text, language: parent.language)
        }

        func applyExternalState(text: String, language: String) {
            guard let containerView else { return }
            applyPopupTheme()
            let textView = containerView.textView
            let requestedLineJump = parent.pendingLineJump

            if parent.deferHighlightingDuringEditing,
               requestedLineJump == nil,
               deferredHighlightTask != nil,
               textView.string == text {
                refreshEditorDecorations(in: textView)
                updateCursorPosition(in: textView)
                return
            }

            deferredHighlightTask?.cancel()
            if parent.pendingLineJump != nil {
                foldedStartLines.removeAll()
            }
            let shouldDeferInitialFolding = !containerView.isReadyForDisplay
                && foldedStartLines.isEmpty
                && requestedLineJump == nil
            let foldSnapshot = shouldDeferInitialFolding
                ? FoldedTextSnapshot.unfolded(text)
                : FoldedTextSnapshot.make(
                    from: text,
                    language: language,
                    foldedStartLines: foldedStartLines
                )
            foldedStartLines = foldSnapshot.foldedLines
            currentFoldSnapshot = foldSnapshot
            containerView.applyFolding(foldSnapshot) { [weak self] line in
                self?.toggleFold(atActualLine: line)
            }
            let shouldApplyText = renderState.needsTextApplication(
                for: foldSnapshot.displayText,
                language: language,
                renderedText: textView.string,
                isViewReadyForDisplay: containerView.isReadyForDisplay
            )
            guard shouldApplyText || requestedLineJump != nil else { return }

            let selectedRange = textView.selectedRange()
            isApplyingExternalUpdate = true
            if shouldApplyText {
                containerView.applyText(
                    foldSnapshot.displayText,
                    language: language,
                    themeColors: parent.themeColors,
                    documentIdentity: parent.documentIdentity
                )
                lineTableNeedsUpdate = true
                renderState.recordRender(
                    text: foldSnapshot.displayText,
                    language: language,
                    isViewReadyForDisplay: containerView.isReadyForDisplay
                )
            }

            if let requestedLineJump {
                jumpToLine(foldSnapshot.displayLine(forActualLine: requestedLineJump) ?? requestedLineJump, in: textView)
                DispatchQueue.main.async { [weak self] in
                    self?.parent.pendingLineJump = nil
                }
            } else if let pendingSourceSelection {
                textView.setSelectedRange(foldSnapshot.displayRange(forSourceRange: pendingSourceSelection))
                self.pendingSourceSelection = nil
            } else {
                let clampedLocation = min(selectedRange.location, (textView.string as NSString).length)
                textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            }
            isApplyingExternalUpdate = false

            refreshEditorDecorations(in: textView)
            updateCursorPosition(in: textView)
        }

        private func applyPopupTheme() {
            completionPopup.applyTheme(parent.themeColors, font: parent.editorFont)
            hoverPopup.applyTheme(parent.themeColors, font: parent.editorFont)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingExternalUpdate else { return }

            let updatedText = textView.string
            let selectedRange = textView.selectedRange()
            lineTableNeedsUpdate = true

            if parent.deferHighlightingDuringEditing {
                containerView?.refreshAfterEditing(text: updatedText, themeColors: parent.themeColors)
                scheduleDeferredHighlight(for: updatedText, language: parent.language)
            } else {
                isApplyingExternalUpdate = true
                containerView?.applyText(
                    updatedText,
                    language: parent.language,
                    themeColors: parent.themeColors,
                    documentIdentity: parent.documentIdentity
                )
                let clampedLocation = min(selectedRange.location, (textView.string as NSString).length)
                textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
                isApplyingExternalUpdate = false
            }

            renderState.recordRender(
                text: updatedText,
                language: parent.language,
                isViewReadyForDisplay: containerView?.isReadyForDisplay ?? false
            )

            // Push the new text to the model synchronously so a Save/autosave firing in the
            // same runloop turn never writes a stale buffer. Programmatic edits are guarded
            // by `isApplyingExternalUpdate` above, so this only runs for genuine user input.
            parent.text = updatedText
            refreshEditorDecorations(in: textView)
            updateCursorPosition(in: textView)

            // Completion: (re)trigger on . or :, narrow the list while typing identifier
            // characters, and dismiss on anything else.
            let nsText = updatedText as NSString
            let cursorLoc = textView.selectedRange().location
            if cursorLoc > 0 && cursorLoc <= nsText.length {
                let lastChar = nsText.substring(with: NSRange(location: cursorLoc - 1, length: 1))
                if lastChar == "." || lastChar == ":" {
                    triggerCompletionIfNeeded(in: textView, trigger: lastChar)
                } else if completionPopup.isVisible {
                    if Self.isCompletionIdentifierCharacter(lastChar) {
                        completionPopup.updateFilter(currentCompletionPrefix(in: textView))
                    } else {
                        completionPopup.dismiss()
                    }
                }
            } else if completionPopup.isVisible {
                completionPopup.dismiss()
            }
        }

        private func scheduleDeferredHighlight(for text: String, language: String) {
            deferredHighlightTask?.cancel()
            deferredHighlightTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }

                guard let self,
                      !Task.isCancelled,
                      let containerView,
                      containerView.textView.string == text else {
                    return
                }

                deferredHighlightTask = nil
                if parent.pendingLineJump != nil {
                    foldedStartLines.removeAll()
                }

                let foldSnapshot = FoldedTextSnapshot.make(
                    from: text,
                    language: language,
                    foldedStartLines: foldedStartLines
                )
                foldedStartLines = foldSnapshot.foldedLines
                currentFoldSnapshot = foldSnapshot
                containerView.applyFolding(foldSnapshot) { [weak self] line in
                    self?.toggleFold(atActualLine: line)
                }

                let selectedRange = containerView.textView.selectedRange()
                isApplyingExternalUpdate = true
                containerView.applyText(
                    foldSnapshot.displayText,
                    language: language,
                    themeColors: parent.themeColors,
                    documentIdentity: parent.documentIdentity
                )
                let clampedLocation = min(selectedRange.location, (containerView.textView.string as NSString).length)
                containerView.textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
                isApplyingExternalUpdate = false
                renderState.recordRender(
                    text: foldSnapshot.displayText,
                    language: language,
                    isViewReadyForDisplay: containerView.isReadyForDisplay
                )
                refreshEditorDecorations(in: containerView.textView)
                updateCursorPosition(in: containerView.textView)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingExternalUpdate else { return }
            // A mouse-driven hover popup shouldn't linger once the caret moves elsewhere. Cancel any
            // in-flight hover request too, so a late LSP response can't re-show the popup at a now
            // stale position (the document/caret has moved since the request was sent).
            hoverTask?.cancel()
            hoverPopup.dismiss()
            refreshEditorDecorations(in: textView)
            updateCursorPosition(in: textView)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if !isApplyingExternalUpdate, !foldedStartLines.isEmpty {
                let sourceAffectedRange = currentFoldSnapshot.sourceRange(forDisplayedRange: affectedCharRange)
                unfoldAllPreservingSelection(in: textView, selection: sourceAffectedRange)
                return applyManualTextChange(
                    in: textView,
                    affectedCharRange: sourceAffectedRange,
                    replacementString: replacementString ?? ""
                )
            }

            guard !isApplyingExternalUpdate,
                  let replacementString,
                  let outcome = EditorInputHandler.outcome(
                    for: replacementString,
                    selectedRange: textView.selectedRange(),
                    affectedRange: affectedCharRange,
                    tabSize: parent.tabSize,
                    in: textView.string as NSString
                  ) else {
                return true
            }

            isApplyingExternalUpdate = true
            textView.replaceCharacters(in: affectedCharRange, with: outcome.replacementText)
            textView.setSelectedRange(NSRange(location: outcome.selectedLocation, length: 0))
            isApplyingExternalUpdate = false
            // Let the normal textDidChange path re-highlight user edits.
            textView.didChangeText()
            return false
        }

        private func applyManualTextChange(
            in textView: NSTextView,
            affectedCharRange: NSRange,
            replacementString: String
        ) -> Bool {
            if let outcome = EditorInputHandler.outcome(
                for: replacementString,
                selectedRange: affectedCharRange,
                affectedRange: affectedCharRange,
                tabSize: parent.tabSize,
                in: textView.string as NSString
            ) {
                isApplyingExternalUpdate = true
                textView.replaceCharacters(in: affectedCharRange, with: outcome.replacementText)
                textView.setSelectedRange(NSRange(location: outcome.selectedLocation, length: 0))
                isApplyingExternalUpdate = false
                // Let the normal textDidChange path re-highlight user edits.
                textView.didChangeText()
                return false
            }

            isApplyingExternalUpdate = true
            textView.replaceCharacters(in: affectedCharRange, with: replacementString)
            let newLocation = affectedCharRange.location + (replacementString as NSString).length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
            isApplyingExternalUpdate = false
            // Let the normal textDidChange path re-highlight user edits.
            textView.didChangeText()
            return false
        }

        private var lineOffsetTable: [Int] = [0]
        private var lineTableNeedsUpdate = true

        private func updateLineOffsetTable(for text: String) {
            lineOffsetTable = [0]
            var offset = 0
            let nsText = text as NSString
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .byLines) { _, _, enclosingRange, _ in
                offset = enclosingRange.location + enclosingRange.length
                self.lineOffsetTable.append(offset)
            }
            lineTableNeedsUpdate = false
        }

        private func lineAndColumn(for offset: Int, in text: String) -> (line: Int, column: Int) {
            if lineTableNeedsUpdate {
                updateLineOffsetTable(for: text)
            }

            // Binary search
            var low = 0
            var high = lineOffsetTable.count - 1

            while low < high {
                let mid = (low + high) / 2
                if lineOffsetTable[mid] <= offset {
                    low = mid + 1
                } else {
                    high = mid
                }
            }

            let line = low
            let lineStart = line > 0 ? lineOffsetTable[line - 1] : 0
            let column = offset - lineStart + 1

            return (line, column)
        }

        private func updateCursorPosition(in textView: NSTextView) {
            let text = textView.string
            let location = min(textView.selectedRange().location, (text as NSString).length)

            let (line, column) = lineAndColumn(for: location, in: text)
            parent.onCursorChange(line, column)
        }

        private func jumpToLine(_ lineNumber: Int, in textView: NSTextView) {
            let clampedLine = max(lineNumber, 1)
            let nsText = textView.string as NSString
            var currentLine = 1
            var targetLocation = 0

            nsText.enumerateSubstrings(
                in: NSRange(location: 0, length: nsText.length),
                options: [.byLines, .substringNotRequired]
            ) { _, substringRange, _, stop in
                if currentLine == clampedLine {
                    targetLocation = substringRange.location
                    stop.pointee = true
                    return
                }
                currentLine += 1
            }

            if clampedLine > currentLine {
                targetLocation = nsText.length
            }

            let targetRange = NSRange(location: targetLocation, length: 0)
            textView.setSelectedRange(targetRange)
            textView.scrollRangeToVisible(targetRange)
        }

        private func toggleFold(atActualLine line: Int) {
            guard currentFoldSnapshot.foldableLines.contains(line) else { return }

            let sourceSelection = currentFoldSnapshot.sourceRange(forDisplayedRange: containerView?.textView.selectedRange() ?? NSRange(location: 0, length: 0))
            if let region = currentFoldSnapshot.region(startingAt: line),
               NSLocationInRange(sourceSelection.location, region.hiddenRange) {
                pendingSourceSelection = NSRange(location: region.hiddenRange.location, length: 0)
            } else {
                pendingSourceSelection = sourceSelection
            }

            if foldedStartLines.contains(line) {
                foldedStartLines.remove(line)
            } else {
                foldedStartLines.insert(line)
            }

            applyExternalState(text: parent.text, language: parent.language)
            if let textView = containerView?.textView {
                textView.window?.makeFirstResponder(textView)
            }
        }

        private func unfoldAllPreservingSelection(in textView: NSTextView, selection: NSRange? = nil) {
            guard !foldedStartLines.isEmpty else { return }
            pendingSourceSelection = selection ?? currentFoldSnapshot.sourceRange(forDisplayedRange: textView.selectedRange())
            foldedStartLines.removeAll()
            applyExternalState(text: parent.text, language: parent.language)
        }

        // MARK: - Context Menu

        func menu(for textView: EditorTextView, at point: NSPoint) -> NSMenu {
            let menu = NSMenu()

            for item in contextMenuState(for: textView).items {
                switch item {
                case .cut:
                    menu.addItem(makeTextActionItem(title: "Cut", action: #selector(NSText.cut(_:)), textView: textView))
                case .copy:
                    menu.addItem(makeTextActionItem(title: "Copy", action: #selector(NSText.copy(_:)), textView: textView))
                case .paste:
                    menu.addItem(makeTextActionItem(title: "Paste", action: #selector(NSText.paste(_:)), textView: textView))
                case .selectAll:
                    menu.addItem(makeTextActionItem(title: "Select All", action: #selector(NSText.selectAll(_:)), textView: textView))
                case .divider:
                    menu.addItem(.separator())
                case .goToDefinition:
                    menu.addItem(makeContextActionItem(title: "Go to Definition", action: #selector(handleContextGoToDefinition(_:))))
                case .findReferences:
                    menu.addItem(makeContextActionItem(title: "Find References", action: #selector(handleContextFindReferences(_:))))
                case .showHoverInfo:
                    menu.addItem(makeContextActionItem(title: "Show Hover Info", action: #selector(handleContextShowHover(_:))))
                case .revealInFinder:
                    menu.addItem(makeContextActionItem(title: "Reveal in Finder", action: #selector(handleContextRevealInFinder(_:))))
                case .copyFilePath:
                    menu.addItem(makeContextActionItem(title: "Copy File Path", action: #selector(handleContextCopyFilePath(_:))))
                case .copyRelativePath:
                    menu.addItem(makeContextActionItem(title: "Copy Relative Path", action: #selector(handleContextCopyRelativePath(_:))))
                }
            }

            return menu
        }

        func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            let state = contextMenuState(for: containerView?.textView)
            switch item.action {
            case #selector(handleContextGoToDefinition(_:)), #selector(handleContextFindReferences(_:)), #selector(handleContextShowHover(_:)):
                return state.isEnabled(.goToDefinition)
            case #selector(handleContextRevealInFinder(_:)), #selector(handleContextCopyFilePath(_:)):
                return state.isEnabled(.copyFilePath)
            case #selector(handleContextCopyRelativePath(_:)):
                return state.isEnabled(.copyRelativePath)
            default:
                return true
            }
        }

        @objc
        func handleContextGoToDefinition(_ sender: Any?) {
            guard let textView = containerView?.textView,
                  let point = textView.lastContextMenuPoint else { return }
            handleGoToDefinition(at: point, in: textView)
        }

        @objc
        func handleContextFindReferences(_ sender: Any?) {
            guard let textView = containerView?.textView,
                  let point = textView.lastContextMenuPoint else { return }
            handleFindReferences(at: point, in: textView)
        }

        @objc
        func handleContextShowHover(_ sender: Any?) {
            guard let textView = containerView?.textView,
                  let point = textView.lastContextMenuPoint else { return }
            handleHover(at: point, in: textView)
        }

        @objc
        func handleContextRevealInFinder(_ sender: Any?) {
            guard let fileURL = parent.fileURL else { return }
            parent.onRevealInFinder?(fileURL)
        }

        @objc
        func handleContextCopyFilePath(_ sender: Any?) {
            guard let fileURL = parent.fileURL else { return }
            copyToPasteboard(fileURL.path)
        }

        @objc
        func handleContextCopyRelativePath(_ sender: Any?) {
            guard let path = relativePathForCurrentFile() else { return }
            copyToPasteboard(path)
        }

        private func makeTextActionItem(title: String, action: Selector, textView: NSTextView) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = textView
            return item
        }

        private func makeContextActionItem(title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        private func contextMenuPosition(in textView: EditorTextView) -> LSPPosition? {
            guard let point = textView.lastContextMenuPoint else { return nil }
            return LSPPositionConverter.lspPosition(from: point, in: textView)
        }

        private func relativePathForCurrentFile() -> String? {
            guard let fileURL = parent.fileURL,
                  let projectRootDirectory = parent.projectRootDirectory else { return nil }
            let filePath = fileURL.path
            let rootPath = projectRootDirectory.path
            guard filePath.hasPrefix(rootPath + "/") else { return filePath }
            return String(filePath.dropFirst(rootPath.count + 1))
        }

        private func copyToPasteboard(_ value: String) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
        }

        private func contextMenuState(for textView: EditorTextView?) -> EditorContextMenuState {
            EditorContextMenuState(
                hasSavedFile: parent.fileURL != nil,
                hasLanguageServer: parent.documentURI != nil
                    && parent.language != "plaintext"
                    && parent.isLanguageServerAvailable,
                hasResolvableSymbol: textView.flatMap(contextMenuPosition(in:)) != nil,
                hasRelativePath: relativePathForCurrentFile() != nil
            )
        }

        // MARK: - Hover + Go-to-Definition

        private func setupMouseMonitor() {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
                self?.handleMouseEvent(event) ?? event
            }
        }

        private func setupCommandObservers() {
            parent.commandDispatcher.publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] command in
                    guard let self else { return }
                    switch command {
                    case .findInFile:
                        performTextFinderAction(.showFindInterface)
                    case .findNext:
                        guard parent.prefersProjectSearchNavigation != true else { return }
                        performTextFinderAction(.nextMatch)
                    case .findPrevious:
                        guard parent.prefersProjectSearchNavigation != true else { return }
                        performTextFinderAction(.previousMatch)
                    case .useSelectionForFind:
                        performTextFinderAction(.setSearchString)
                    case .showReplace:
                        performTextFinderAction(.showReplaceInterface)
                    case .goToDefinition:
                        handleGoToDefinitionFromCursor()
                    case .findReferences:
                        handleFindReferencesFromCursor()
                    case .toggleLineComment:
                        toggleLineComment()
                    case .moveLineUp:
                        moveSelectedLines(up: true)
                    case .moveLineDown:
                        moveSelectedLines(up: false)
                    case .duplicateLine:
                        applyLineEdit { LineEditing.duplicateLines(in: $0, selection: $1) }
                    case .deleteLine:
                        applyLineEdit { LineEditing.deleteLines(in: $0, selection: $1) }
                    case .joinLines:
                        applyLineEdit { LineEditing.joinLines(in: $0, selection: $1) }
                    default:
                        break
                    }
                }
                .store(in: &commandCancellables)
        }

        private func moveSelectedLines(up: Bool) {
            applyLineEdit { text, selection in
                up ? LineEditing.moveLinesUp(in: text, selection: selection)
                   : LineEditing.moveLinesDown(in: text, selection: selection)
            }
        }

        /// Apply a LineEditing operation through the NSTextView undo/binding path. `compute` returns
        /// the minimal edit (nil = no-op, e.g. moving the top line up).
        private func applyLineEdit(_ compute: (NSString, NSRange) -> LineEditing.Edit?) {
            guard let textView = containerView?.textView else { return }
            guard let edit = compute(textView.string as NSString, textView.selectedRange()) else { return }
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
            textView.setSelectedRange(edit.selection)
            textView.scrollRangeToVisible(edit.selection)
        }

        private func toggleLineComment() {
            guard let textView = containerView?.textView,
                  let token = LineCommentToggler.token(forLanguage: parent.language) else { return }
            let nsString = textView.string as NSString
            // Expand the selection to whole lines, toggle, and replace through the text-change path so
            // it participates in undo and notifies the binding (textDidChange -> updateTabContent).
            let lineRange = nsString.lineRange(for: textView.selectedRange())
            let selectedText = nsString.substring(with: lineRange)
            let toggled = LineCommentToggler
                .toggle(lines: selectedText.components(separatedBy: "\n"), token: token)
                .joined(separator: "\n")
            guard toggled != selectedText,
                  textView.shouldChangeText(in: lineRange, replacementString: toggled) else { return }
            textView.textStorage?.replaceCharacters(in: lineRange, with: toggled)
            textView.didChangeText()
            // Keep the affected lines selected so the user can re-toggle or keep editing the block.
            textView.setSelectedRange(NSRange(location: lineRange.location, length: (toggled as NSString).length))
        }

        private func handleMouseEvent(_ event: NSEvent) -> NSEvent? {
            guard let textView = containerView?.textView else { return event }

            let windowPoint = event.locationInWindow
            let textViewPoint = textView.convert(windowPoint, from: nil)
            let isOverText = textView.bounds.contains(textViewPoint)

            if isOverText != isMouseOverText {
                isMouseOverText = isOverText
                if !isOverText {
                    dwellTimer?.cancel()
                    dwellTimer = nil
                    hoverPopup.dismiss()
                }
            }

            guard isOverText else { return event }

            if event.modifierFlags.contains(.command) {
                if event.type == .leftMouseDown {
                    handleGoToDefinition(at: textViewPoint, in: textView)
                    return nil
                } else if event.type == .mouseMoved {
                    handleHover(at: textViewPoint, in: textView)
                }
                return event
            }

            if event.type == .mouseMoved {
                if textViewPoint != lastHoverPoint {
                    lastHoverPoint = textViewPoint
                    dwellTimer?.cancel()
                    dwellTimer = Task { @MainActor [weak self] in
                        guard let self else { return }
                        try? await Task.sleep(nanoseconds: self.dwellDelayNanoseconds)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            self.handleDwellHover(at: textViewPoint, in: textView)
                        }
                    }
                }
            }

            return event
        }

        private func handleDwellHover(at point: NSPoint, in textView: NSTextView) {
            guard !currentFoldSnapshot.hasActiveFolds else { return }
            guard let position = LSPPositionConverter.lspPosition(from: point, in: textView) else { return }
            performHover(at: position, in: textView)
        }

        private func handleGoToDefinitionFromCursor() {
            guard let textView = containerView?.textView else { return }
            if currentFoldSnapshot.hasActiveFolds {
                unfoldAllPreservingSelection(in: textView)
            }
            let position = LSPPositionConverter.lspPositionFromCursor(in: textView)
            performGoToDefinition(at: position)
        }

        private func handleFindReferencesFromCursor() {
            guard let textView = containerView?.textView else { return }
            if currentFoldSnapshot.hasActiveFolds {
                unfoldAllPreservingSelection(in: textView)
            }
            let position = LSPPositionConverter.lspPositionFromCursor(in: textView)
            performFindReferences(at: position)
        }

        private func handleHover(at point: NSPoint, in textView: NSTextView) {
            guard !currentFoldSnapshot.hasActiveFolds else {
                unfoldAllPreservingSelection(in: textView)
                return
            }
            guard let position = LSPPositionConverter.lspPosition(from: point, in: textView) else { return }
            performHover(at: position, in: textView)
        }

        private func handleGoToDefinition(at point: NSPoint, in textView: NSTextView) {
            guard !currentFoldSnapshot.hasActiveFolds else {
                unfoldAllPreservingSelection(in: textView)
                return
            }
            guard let position = LSPPositionConverter.lspPosition(from: point, in: textView) else { return }
            performGoToDefinition(at: position)
        }

        private func handleFindReferences(at point: NSPoint, in textView: NSTextView) {
            guard !currentFoldSnapshot.hasActiveFolds else {
                unfoldAllPreservingSelection(in: textView)
                return
            }
            guard let position = LSPPositionConverter.lspPosition(from: point, in: textView) else { return }
            performFindReferences(at: position)
        }

        private func performTextFinderAction(_ action: TextFinderAction) {
            guard let textView = containerView?.textView else { return }
            textView.window?.makeFirstResponder(textView)

            let sender = NSMenuItem()
            sender.tag = action.rawValue
            textView.performTextFinderAction(sender)
        }

        private func performHover(at position: LSPPosition, in textView: NSTextView) {
            guard let uri = parent.documentURI, let lspService = parent.lspService else { return }
            let language = parent.language

            hoverTask?.cancel()
            hoverTask = Task { @MainActor in
                guard let result = await lspService.hover(uri: uri, language: language, position: position) else { return }
                guard !Task.isCancelled else { return }

                if let offset = LSPPositionConverter.utf16Offset(for: position, in: textView.string),
                   let layoutManager = textView.layoutManager,
                   let textContainer = textView.textContainer {
                    let glyphRange = layoutManager.glyphRange(
                        forCharacterRange: NSRange(location: offset, length: 1),
                        actualCharacterRange: nil
                    )
                    var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    let origin = textView.textContainerOrigin
                    rect.origin.x += origin.x
                    rect.origin.y += origin.y

                    if let parsed = result.parsedContent {
                        hoverPopup.showEnhancedContent(parsed, at: rect, in: textView)
                    } else {
                        let content = result.contentsString
                        guard !content.isEmpty else { return }
                        hoverPopup.show(content: content, at: rect, in: textView)
                    }
                }
            }
        }

        private func performGoToDefinition(at position: LSPPosition) {
            guard let uri = parent.documentURI, let lspService = parent.lspService else { return }
            let language = parent.language

            Task { @MainActor in
                let locations = await lspService.definition(uri: uri, language: language, position: position)
                guard let location = locations.first else { return }

                guard let fileURL = URL(string: location.uri), fileURL.isFileURL else { return }
                let line = location.range.start.line + 1
                parent.onNavigateToDefinition?(fileURL, line)
            }
        }

        private func performFindReferences(at position: LSPPosition) {
            guard let uri = parent.documentURI, let lspService = parent.lspService else { return }
            let language = parent.language
            let requestID = referenceRequestTracker.nextRequestID()

            referencesTask?.cancel()

            // Open the panel in a loading state immediately — the request below can take seconds.
            parent.onBeginReferences?()

            referencesTask = Task { @MainActor in
                let locations = await lspService.references(uri: uri, language: language, position: position)
                guard !Task.isCancelled else { return }
                guard referenceRequestTracker.shouldDeliver(
                    requestID: requestID,
                    documentURI: uri,
                    currentDocumentURI: parent.documentURI
                ) else { return }

                parent.onShowReferences?(locations)
            }
        }

        // MARK: - Decorations

        private func refreshEditorDecorations(in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if fullRange.length > 0 {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
                layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
                layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
            }

            applyCurrentLineHighlight(in: textView)
            applyBracketHighlights(in: textView)
            applyDiagnosticUnderlines(in: textView)
        }

        private func applyCurrentLineHighlight(in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let nsText = textView.string as NSString
            let selection = textView.selectedRange()
            let lineRange = nsText.lineRange(for: NSRange(location: min(selection.location, nsText.length), length: 0))
            guard lineRange.length > 0 else { return }

            layoutManager.addTemporaryAttributes(
                [.backgroundColor: parent.themeColors.nsSelection.withAlphaComponent(0.12)],
                forCharacterRange: lineRange
            )
        }

        private func applyBracketHighlights(in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let nsText = textView.string as NSString
            let selectionLocation = min(textView.selectedRange().location, nsText.length)

            for range in BracketMatcher.matchingRanges(in: nsText, caretLocation: selectionLocation) {
                layoutManager.addTemporaryAttributes(
                    [
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: parent.themeColors.nsAccent
                    ],
                    forCharacterRange: range
                )
            }
        }

        // MARK: - Completion

        private func triggerCompletionIfNeeded(in textView: NSTextView, trigger: String?) {
            let triggerChars: Set<String> = [".", ":"]
            guard let trigger, triggerChars.contains(trigger) else { return }
            requestCompletion(in: textView)
        }

        func requestCompletion(in textView: NSTextView) {
            guard let uri = parent.documentURI, let lspService = parent.lspService else { return }
            let language = parent.language
            let position = LSPPositionConverter.lspPositionFromCursor(in: textView)

            completionTask?.cancel()
            completionTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 120_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let items = await lspService.completion(uri: uri, language: language, position: position)
                guard !Task.isCancelled, !items.isEmpty else { return }

                guard let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else { return }
                let cursorRange = textView.selectedRange()
                let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: cursorRange.location, length: 0), actualCharacterRange: nil)
                var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let origin = textView.textContainerOrigin
                rect.origin.x += origin.x
                rect.origin.y += origin.y + rect.height

                let windowRect = textView.convert(rect, to: nil)
                completionPopup.show(items: items, at: windowRect, in: textView.window)
                // Apply any characters typed between the trigger and this async response so
                // the list shows up already narrowed.
                let prefix = currentCompletionPrefix(in: textView)
                if !prefix.isEmpty {
                    completionPopup.updateFilter(prefix)
                }
            }
        }

        private func insertCompletion(_ item: CompletionItem) {
            guard let textView = containerView?.textView else { return }
            let insertText = item.insertionText
            // Replace the identifier prefix already typed before the caret (plus any forward
            // selection), so accepting "bar" after typing "foo.ba" yields "foo.bar", not
            // "foo.babar".
            let caret = textView.selectedRange()
            let prefixRange = completionPrefixRange(in: textView)
            let replaceRange = NSRange(
                location: prefixRange.location,
                length: max(0, caret.location + caret.length - prefixRange.location)
            )
            guard textView.shouldChangeText(in: replaceRange, replacementString: insertText) else { return }
            textView.replaceCharacters(in: replaceRange, with: insertText)
            textView.setSelectedRange(NSRange(location: prefixRange.location + (insertText as NSString).length, length: 0))
            textView.didChangeText()
        }

        /// The identifier run immediately before the caret (e.g. the `ba` in `foo.ba|`).
        private func completionPrefixRange(in textView: NSTextView) -> NSRange {
            let nsText = textView.string as NSString
            let caret = min(textView.selectedRange().location, nsText.length)
            var start = caret
            while start > 0 {
                let character = nsText.substring(with: NSRange(location: start - 1, length: 1))
                guard Self.isCompletionIdentifierCharacter(character) else { break }
                start -= 1
            }
            return NSRange(location: start, length: caret - start)
        }

        private func currentCompletionPrefix(in textView: NSTextView) -> String {
            let nsText = textView.string as NSString
            return nsText.substring(with: completionPrefixRange(in: textView))
        }

        static func isCompletionIdentifierCharacter(_ string: String) -> Bool {
            guard string.unicodeScalars.count == 1, let scalar = string.unicodeScalars.first else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if completionPopup.isVisible {
                switch commandSelector {
                case #selector(NSResponder.moveDown(_:)):
                    completionPopup.moveSelectionDown()
                    return true
                case #selector(NSResponder.moveUp(_:)):
                    completionPopup.moveSelectionUp()
                    return true
                case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertNewline(_:)):
                    completionPopup.confirmSelection()
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    completionPopup.dismiss()
                    return true
                default:
                    break
                }
            }
            // Native "Complete" action (Option+Escape / F5) manually triggers suggestions
            // regardless of trigger characters — avoids the Ctrl+Space input-source conflict.
            if commandSelector == #selector(NSResponder.complete(_:)) {
                requestCompletion(in: textView)
                return true
            }
            // Tab on a multi-line selection indents the block; Shift+Tab always outdents. A single
            // caret falls through to the default tab insertion.
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)) where hasMultilineSelection(in: textView):
                applyLineEdit { LineEditing.indentLines(in: $0, selection: $1, unit: "\t") }
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                applyLineEdit { LineEditing.outdentLines(in: $0, selection: $1, tabSize: parent.tabSize) }
                return true
            default:
                return false
            }
        }

        private func hasMultilineSelection(in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length > 0 else { return false }
            return (textView.string as NSString).substring(with: selection).contains("\n")
        }

        // MARK: - Diagnostics

        private func applyDiagnosticUnderlines(in textView: NSTextView) {
            guard !currentFoldSnapshot.hasActiveFolds else { return }
            guard let layoutManager = textView.layoutManager else { return }
            let text = textView.string

            for diagnostic in parent.diagnostics {
                guard let nsRange = LSPPositionConverter.nsRange(from: diagnostic.range, in: text) else { continue }
                let clampedRange = NSIntersectionRange(nsRange, NSRange(location: 0, length: (text as NSString).length))
                guard clampedRange.length > 0 else { continue }

                let color: NSColor
                switch diagnostic.severity {
                case .error:
                    color = parent.themeColors.nsDanger
                case .warning:
                    color = parent.themeColors.nsWarning
                case .information, .hint:
                    color = parent.themeColors.nsAccent
                case .none:
                    color = parent.themeColors.nsWarning
                }

                layoutManager.addTemporaryAttributes(
                    [
                        .underlineStyle: NSUnderlineStyle.thick.rawValue,
                        .underlineColor: color
                    ],
                    forCharacterRange: clampedRange
                )
            }
        }
    }
}

struct EditorRenderState {
    private var lastRenderedText: String = ""
    private var lastLanguage: String = ""
    private var requiresVisibleRefresh = true

    mutating func recordRender(text: String, language: String, isViewReadyForDisplay: Bool) {
        requiresVisibleRefresh = !isViewReadyForDisplay

        guard isViewReadyForDisplay else { return }
        lastRenderedText = text
        lastLanguage = language
    }

    func needsTextApplication(
        for text: String,
        language: String,
        renderedText: String,
        isViewReadyForDisplay: Bool
    ) -> Bool {
        if lastRenderedText != text || renderedText != text {
            return true
        }

        if lastLanguage != language {
            return true
        }

        return requiresVisibleRefresh && isViewReadyForDisplay
    }
}

struct EditorLSPRequestTracker {
    private(set) var currentRequestID: Int = 0

    mutating func nextRequestID() -> Int {
        currentRequestID += 1
        return currentRequestID
    }

    func shouldDeliver(requestID: Int, documentURI: String, currentDocumentURI: String?) -> Bool {
        currentRequestID == requestID && currentDocumentURI == documentURI
    }
}

private enum TextFinderAction: Int {
    case showFindInterface = 1
    case nextMatch = 2
    case previousMatch = 3
    case setSearchString = 7
    case showReplaceInterface = 12
}

struct MinimapSnapshot {
    static let empty = MinimapSnapshot(
        lineWidthFractions: [0.12],
        visibleStartLine: 1,
        visibleEndLine: 1
    )

    let lineWidthFractions: [CGFloat]
    let visibleStartLine: Int
    let visibleEndLine: Int

    static func make(text: String, visibleRect: NSRect, documentHeight: CGFloat) -> MinimapSnapshot {
        let lines = text.components(separatedBy: "\n")
        let measuredLengths = lines.map { min($0.trimmingCharacters(in: .whitespaces).count, 80) }
        let baseline = max(measuredLengths.max() ?? 1, 24)
        let lineWidthFractions = measuredLengths.map { length -> CGFloat in
            guard length > 0 else { return 0.12 }
            return max(CGFloat(length) / CGFloat(baseline), 0.18)
        }

        let totalLines = max(lineWidthFractions.count, 1)
        guard documentHeight > 0, visibleRect.height > 0 else {
            return MinimapSnapshot(
                lineWidthFractions: lineWidthFractions.isEmpty ? [0.12] : lineWidthFractions,
                visibleStartLine: 1,
                visibleEndLine: totalLines
            )
        }

        let visibleRatio = min(max(visibleRect.height / documentHeight, 0), 1)
        let visibleLineCount = max(Int(ceil(CGFloat(totalLines) * visibleRatio)), 1)
        let maxStartLine = max(totalLines - visibleLineCount + 1, 1)
        let maxOffset = max(documentHeight - visibleRect.height, 0)
        let scrollProgress = maxOffset > 0 ? min(max(visibleRect.minY / maxOffset, 0), 1) : 0
        let visibleStartLine = min(max(Int(round(CGFloat(maxStartLine - 1) * scrollProgress)) + 1, 1), maxStartLine)
        let visibleEndLine = min(totalLines, visibleStartLine + visibleLineCount - 1)

        return MinimapSnapshot(
            lineWidthFractions: lineWidthFractions.isEmpty ? [0.12] : lineWidthFractions,
            visibleStartLine: visibleStartLine,
            visibleEndLine: visibleEndLine
        )
    }

    var accessibilityValue: String {
        "\(visibleStartLine)-\(visibleEndLine)"
    }
}

private struct MinimapCacheKey: Equatable {
    let displayVersion: Int
    let visibleOriginY: CGFloat
    let visibleHeight: CGFloat
    let documentHeight: CGFloat
}

private enum HighlightRequestScope {
    case full
    case preview(NSRange)
}

final class EditorContainerView: NSView {
    let scrollView: NSScrollView
    let textView: EditorTextView
    fileprivate let lineNumberView: LineNumberRulerView
    fileprivate let minimapView: EditorMinimapView
    var onLayout: (() -> Void)?
    var onViewportChange: ((Int, Int) -> Void)?
    var onScroll: (() -> Void)?
    var editorFont: NSFont
    var themeColors: ThemeColors
    var showMinimap: Bool
    var showLineNumbers: Bool
    var wordWrap: Bool
    var tabSize: Int
    private var currentDisplayText = ""
    private var currentDisplayVersion = 0
    private let minimapWidthConstraint: NSLayoutConstraint
    private var lastMinimapCacheKey: MinimapCacheKey?
    private var lastMinimapSnapshot: MinimapSnapshot = .empty
    private let initialHighlightIdleDelayNanoseconds: UInt64 = 300_000_000
    private let fullHighlightIdleDelayNanoseconds: UInt64 = 800_000_000
    private let previewHighlightCharacterLimit = 12_000
    private let previewHighlightContextCharacters = 4_000
    private let highlightBufferCharacters = 2_000
    private var currentDocumentIdentity: String?
    private var currentSemanticTokensVersion: Int = 0
    private var semanticTokensRequestTask: Task<Void, Never>?
    private let semanticTokensDebounceNanoseconds: UInt64 = 150_000_000

    init(themeColors: ThemeColors, font: NSFont, showMinimap: Bool, showLineNumbers: Bool, wordWrap: Bool, tabSize: Int = 4) {
        self.editorFont = font
        self.themeColors = themeColors
        self.showMinimap = showMinimap
        self.showLineNumbers = showLineNumbers
        self.wordWrap = wordWrap
        self.tabSize = tabSize
        // Build an explicit TextKit 1 stack to avoid TextKit 2 rendering issues
        // on macOS 12+ where NSTextView defaults to TextKit 2 and the compatibility
        // shim for layoutManager doesn't reliably draw text.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        textView = EditorTextView(frame: .zero, textContainer: textContainer)

        scrollView = NSScrollView(frame: .zero)
        lineNumberView = LineNumberRulerView(textView: textView, themeColors: themeColors)
        minimapView = EditorMinimapView(scrollView: scrollView, themeColors: themeColors)
        minimapWidthConstraint = minimapView.widthAnchor.constraint(equalToConstant: 96)

        super.init(frame: .zero)

        textView.isRichText = true
        textView.usesFontPanel = false
        textView.importsGraphics = false
        textView.font = editorFont
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.drawsBackground = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesRuler = false
        textView.usesInspectorBar = false
        textView.acceptsGlyphInfo = false
        textView.setAccessibilityLabel("Editor text")
        textView.setAccessibilityIdentifier("editor-text-view")

        // No line wrap — enable horizontal scrolling
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.postsFrameChangedNotifications = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = lineNumberView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = textView

        addSubview(scrollView)
        addSubview(minimapView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        minimapView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: minimapView.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            minimapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            minimapView.topAnchor.constraint(equalTo: topAnchor),
            minimapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            minimapWidthConstraint
        ])

        applyTheme(
            themeColors,
            font: editorFont,
            showMinimap: showMinimap,
            showLineNumbers: showLineNumbers,
            wordWrap: wordWrap
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        highlightTask?.cancel()
        fullHighlightTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func configure(delegate: NSTextViewDelegate) {
        textView.delegate = delegate
    }

    /// Live-apply the "Show Line Numbers" setting without recreating the editor (mirrors the ruler
    /// handling in applyTheme). Previously the toggle only took effect after a theme change or tab reopen.
    func setLineNumbersVisible(_ visible: Bool) {
        showLineNumbers = visible
        scrollView.hasVerticalRuler = visible
        scrollView.rulersVisible = visible
        lineNumberView.needsDisplay = true
    }

    /// Live-apply the "Show Minimap" setting, updating BOTH visibility and the width constraint that
    /// reserves its horizontal space — updating only `isHidden` (as before) left a 96pt gap or overlap.
    func setMinimapVisible(_ visible: Bool) {
        showMinimap = visible
        minimapView.isHidden = !visible
        minimapWidthConstraint.constant = visible ? 96 : 0
        minimapView.needsDisplay = true
    }

    /// Live-apply the "Tab Size" setting: recompute the tab paragraph style and reapply it to the
    /// document, the typing attributes, and the text view default so tab-indented text re-renders.
    func setTabSize(_ size: Int) {
        tabSize = max(size, 1)
        let paragraphStyle = makeTabParagraphStyle()
        textView.defaultParagraphStyle = paragraphStyle
        var typing = textView.typingAttributes
        typing[.paragraphStyle] = paragraphStyle
        textView.typingAttributes = typing
        if let textStorage = textView.textStorage, textStorage.length > 0 {
            textStorage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: 0, length: textStorage.length)
            )
        }
    }

    /// Live-apply the "Word Wrap" setting, mirroring applyTheme's container/scroller setup so toggling
    /// at runtime matches a fresh load (the previous partial path left the horizontal scroller stale).
    func setWordWrap(_ wordWrap: Bool) {
        self.wordWrap = wordWrap
        if wordWrap {
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
        }
    }

    func applyTheme(_ themeColors: ThemeColors, font: NSFont, showMinimap: Bool, showLineNumbers: Bool, wordWrap: Bool) {
        self.editorFont = font
        self.showMinimap = showMinimap
        self.showLineNumbers = showLineNumbers
        self.wordWrap = wordWrap
        scrollView.backgroundColor = themeColors.nsBackground
        textView.backgroundColor = themeColors.nsBackground
        textView.insertionPointColor = themeColors.nsCursor
        textView.selectedTextAttributes = [
            .backgroundColor: themeColors.nsSelection.withAlphaComponent(0.45),
            .foregroundColor: themeColors.nsForeground
        ]
        textView.typingAttributes = [
            .font: editorFont,
            .foregroundColor: themeColors.nsForeground,
            .paragraphStyle: makeTabParagraphStyle()
        ]
        lineNumberView.themeColors = themeColors
        lineNumberView.editorFont = editorFont
        lineNumberView.needsDisplay = true
        minimapView.themeColors = themeColors
        minimapView.isHidden = !showMinimap
        minimapWidthConstraint.constant = showMinimap ? 96 : 0
        minimapView.needsDisplay = true
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers
        if wordWrap {
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
        }

        // Re-highlight with the new theme: the syntax token colors were computed with the previous
        // theme, and applyText (which re-highlights on a theme change) is skipped when the text and
        // language are unchanged — so a theme switch alone would leave stale token colors. Runs only
        // on a theme change; keep lastAppliedThemeColors in sync so applyText doesn't redundantly
        // re-highlight afterward.
        if !textView.string.isEmpty {
            lastAppliedThemeColors = themeColors
            applyBaseTextAttributes(themeColors: themeColors)
            requestHighlighting(
                text: textView.string,
                language: lastAppliedLanguage,
                themeColors: themeColors,
                debounceNanoseconds: 0,
                scope: highlightScope(for: textView.string)
            )
        }
    }

    var isReadyForDisplay: Bool {
        window != nil && !bounds.isEmpty && !scrollView.contentSize.equalTo(.zero)
    }

    private var highlightTask: Task<Void, Never>?
    private var fullHighlightTask: Task<Void, Never>?
    private var highlightRequestID = 0
    private var hasCompletedInitialHighlight = false
    private var hasCompletedFullDocumentHighlight = false
    private var lastAppliedText: String = ""
    private var lastAppliedLanguage: String = ""
    private var lastAppliedThemeColors: ThemeColors = .nord
    private var lastAppliedFontSignature: String = ""

    func applyText(_ text: String, language: String, themeColors: ThemeColors, documentIdentity: String?) {
        if currentDocumentIdentity != documentIdentity {
            currentDocumentIdentity = documentIdentity
            hasCompletedInitialHighlight = false
            hasCompletedFullDocumentHighlight = false
            highlightTask?.cancel()
            fullHighlightTask?.cancel()
            // A single NSTextView is reused across tabs. Clear the undo stack on document
            // switch so Cmd+Z can't replay the previous file's edits against this buffer
            // (content corruption / NSRangeException). Skip while the manager is mid-undo/redo —
            // removeAllActions() during a transaction can corrupt its internal state.
            if let undoManager = textView.undoManager, !undoManager.isUndoing, !undoManager.isRedoing {
                undoManager.removeAllActions()
            }
            textView.breakUndoCoalescing()
        }

        let fontSignature = "\(editorFont.fontName):\(editorFont.pointSize)"
        let shouldReplaceText = text != lastAppliedText
        let shouldRehighlight = shouldReplaceText
            || language != lastAppliedLanguage
            || themeColors != lastAppliedThemeColors
            || fontSignature != lastAppliedFontSignature

        guard shouldRehighlight else {
            return
        }

        lastAppliedText = text
        lastAppliedLanguage = language
        lastAppliedThemeColors = themeColors
        lastAppliedFontSignature = fontSignature
        currentDisplayText = text
        if shouldReplaceText {
            currentDisplayVersion += 1
        }

        guard let textStorage = textView.textStorage else { return }
        textStorage.beginEditing()

        if shouldReplaceText && textStorage.string != text {
            let replacementRange = NSRange(location: 0, length: textStorage.length)
            textStorage.replaceCharacters(in: replacementRange, with: text)
        }

        textStorage.endEditing()
        textView.setAccessibilityValue(text)
        applyBaseTextAttributes(themeColors: themeColors)

        if shouldReplaceText {
            updateTextViewFrame()
        }

        let highlightScope = highlightScope(for: text)

        let highlightDebounceNanoseconds = max(
            text.count > 10_000 ? 180_000_000 : 0,
            !hasCompletedInitialHighlight ? initialHighlightIdleDelayNanoseconds : 0
        )

        requestHighlighting(
            text: text,
            language: language,
            themeColors: themeColors,
            debounceNanoseconds: UInt64(highlightDebounceNanoseconds),
            scope: highlightScope
        )

        updateMinimap()
    }

    /// Paragraph style that makes a literal tab character render at the configured Tab Size
    /// (tabSize × the font's space width). Without it, AppKit renders tabs at its hardcoded
    /// default interval, so the "Tab Size" setting had no effect on tab-indented files.
    func makeTabParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: editorFont]).width
        style.tabStops = []
        style.defaultTabInterval = spaceWidth * CGFloat(max(tabSize, 1))
        return style
    }

    private func applyBaseTextAttributes(themeColors: ThemeColors) {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let paragraphStyle = makeTabParagraphStyle()
        textView.defaultParagraphStyle = paragraphStyle

        textStorage.beginEditing()
        if fullRange.length > 0 {
            textStorage.setAttributes([
                .font: editorFont,
                .foregroundColor: themeColors.nsForeground,
                .paragraphStyle: paragraphStyle
            ], range: fullRange)
        }
        textStorage.endEditing()

        guard let layoutManager = textView.layoutManager, fullRange.length > 0 else { return }
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.font, forCharacterRange: fullRange)
    }

    private func requestHighlighting(
        text: String,
        language: String,
        themeColors: ThemeColors,
        debounceNanoseconds: UInt64,
        scope: HighlightRequestScope
    ) {
        highlightTask?.cancel()
        fullHighlightTask?.cancel()
        highlightRequestID += 1
        let requestID = highlightRequestID
        let fontName = editorFont.fontName
        let fontSize = editorFont.pointSize

        highlightTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if debounceNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled,
                  requestID == self.highlightRequestID,
                  text == self.currentDisplayText else { return }

            let highlightedText: String
            let offset: Int
            let isFullDocumentHighlight: Bool
            switch scope {
            case .full:
                highlightedText = text
                offset = 0
                isFullDocumentHighlight = true
            case .preview(let range):
                let nsText = text as NSString
                let clampedLocation = min(max(range.location, 0), nsText.length)
                let clampedLength = min(max(range.length, 0), nsText.length - clampedLocation)
                highlightedText = nsText.substring(with: NSRange(location: clampedLocation, length: clampedLength))
                offset = clampedLocation
                isFullDocumentHighlight = false
            }

            let highlighted = await HighlightService.shared.highlightedAttributedStringAsync(
                highlightedText,
                language: language,
                themeColors: themeColors,
                fontName: fontName,
                fontSize: fontSize
            )

            guard !Task.isCancelled,
                  requestID == self.highlightRequestID else { return }
            self.applyHighlighting(
                highlighted,
                text: text,
                offset: offset,
                clearsExisting: isFullDocumentHighlight,
                isFullDocumentHighlight: isFullDocumentHighlight
            )

            if !isFullDocumentHighlight {
                self.scheduleFullDocumentHighlight(text: text, language: language, themeColors: themeColors)
            }
        }
    }

    private func applyHighlighting(
        _ highlighted: NSAttributedString,
        text: String,
        offset: Int,
        clearsExisting: Bool,
        isFullDocumentHighlight: Bool
    ) {
        guard text == currentDisplayText else {
            return
        }

        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        if let layoutManager = textView.layoutManager {
            if clearsExisting, fullRange.length > 0 {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
                layoutManager.removeTemporaryAttribute(.font, forCharacterRange: fullRange)
            }

            if fullRange.length > 0 {
                highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { attributes, range, _ in
                    var temporaryAttributes: [NSAttributedString.Key: Any] = [:]
                    if let foregroundColor = attributes[.foregroundColor] {
                        temporaryAttributes[.foregroundColor] = foregroundColor
                    }
                    if let font = attributes[.font] {
                        temporaryAttributes[.font] = font
                    }
                    guard !temporaryAttributes.isEmpty else { return }
                    let adjustedRange = NSRange(location: range.location + offset, length: range.length)
                    guard adjustedRange.location >= 0,
                          NSMaxRange(adjustedRange) <= fullRange.length else {
                        return
                    }
                    layoutManager.addTemporaryAttributes(temporaryAttributes, forCharacterRange: adjustedRange)
                }
            }
        }

        textView.needsDisplay = true
        lineNumberView.needsDisplay = true
        hasCompletedInitialHighlight = true
        if isFullDocumentHighlight {
            hasCompletedFullDocumentHighlight = true
        }
    }

    func applySemanticTokens(
        _ tokens: SemanticTokens,
        legend: SemanticTokensLegend,
        themeColors: ThemeColors,
        version: Int
    ) {
        guard version == currentSemanticTokensVersion else { return }
        guard !Task.isCancelled else { return }

        let decoder = SemanticTokenDecoder(legend: legend)
        let decodedTokens = decoder.decode(tokens.data, text: currentDisplayText)

        if let layoutManager = textView.layoutManager {
            for token in decodedTokens {
                let color = SemanticTokenDecoder.tokenTypeColor(token.tokenType, themeColors: themeColors)
                guard token.range.location >= 0,
                      NSMaxRange(token.range) <= (textView.string as NSString).length else { continue }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: token.range)
            }
        }

        textView.needsDisplay = true
    }

    private func highlightScope(for text: String) -> HighlightRequestScope {
        let nsText = text as NSString
        guard nsText.length > previewHighlightCharacterLimit,
              !hasCompletedFullDocumentHighlight else {
            return .full
        }

        return .preview(previewHighlightRange(for: nsText))
    }

    private func previewHighlightRange(for text: NSString) -> NSRange {
        guard isReadyForDisplay,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSRange(location: 0, length: min(text.length, previewHighlightCharacterLimit))
        }

        layoutManager.ensureLayout(for: textContainer)
        let expandedVisibleRect = scrollView.contentView.bounds.insetBy(dx: 0, dy: -160)
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: expandedVisibleRect, in: textContainer)
        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        guard visibleCharacterRange.length > 0 else {
            return NSRange(location: 0, length: min(text.length, previewHighlightCharacterLimit))
        }

        let location = max(0, visibleCharacterRange.location - previewHighlightContextCharacters)
        let end = min(text.length, NSMaxRange(visibleCharacterRange) + previewHighlightContextCharacters)
        return NSRange(location: location, length: max(end - location, 0))
    }

    private func scheduleFullDocumentHighlight(text: String, language: String, themeColors: ThemeColors) {
        guard !hasCompletedFullDocumentHighlight else { return }

        let expectedDocumentIdentity = currentDocumentIdentity
        let expectedDisplayVersion = currentDisplayVersion
        fullHighlightTask?.cancel()
        fullHighlightTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.fullHighlightIdleDelayNanoseconds ?? 0)
            } catch {
                return
            }

            guard let self,
                  !Task.isCancelled,
                  self.currentDocumentIdentity == expectedDocumentIdentity,
                  self.currentDisplayVersion == expectedDisplayVersion,
                  self.currentDisplayText == text,
                  !self.hasCompletedFullDocumentHighlight else {
                return
            }

            self.fullHighlightTask = nil
            self.requestHighlighting(
                text: text,
                language: language,
                themeColors: themeColors,
                debounceNanoseconds: 0,
                scope: .full
            )
        }
    }

    func refreshAfterEditing(text: String, themeColors: ThemeColors) {
        currentDisplayText = text
        currentDisplayVersion += 1
        // Only override the accessibility value while folds are active (then the displayed text
        // differs from the logical text). Otherwise NSTextView already reports its own string, so
        // skip this per-keystroke set — it was copying the whole document on every edit of any
        // file over 2KB (the deferred-highlight path).
        if !lineNumberView.foldedLines.isEmpty {
            textView.setAccessibilityValue(text)
        }
        textView.typingAttributes = [
            .font: editorFont,
            .foregroundColor: themeColors.nsForeground,
            .paragraphStyle: makeTabParagraphStyle()
        ]
        updateTextViewFrame()
        textView.needsDisplay = true
        lineNumberView.needsDisplay = true
        updateMinimap()
    }

    func applyFolding(_ snapshot: FoldedTextSnapshot, onToggleFold: @escaping (Int) -> Void) {
        lineNumberView.foldableLines = snapshot.foldableLines
        lineNumberView.foldedLines = snapshot.foldedLines
        lineNumberView.actualLineNumberForDisplayLine = { snapshot.actualLine(forDisplayLine: $0) }
        lineNumberView.onToggleFold = onToggleFold
        lineNumberView.setAccessibilityValue(
            snapshot.foldedLines
                .sorted()
                .map(String.init)
                .joined(separator: ",")
        )
        lineNumberView.needsDisplay = true
    }

    override func layout() {
        super.layout()
        updateTextViewFrame()
        updateMinimap()
        onLayout?()
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        updateTextViewFrame()
        lineNumberView.needsDisplay = true
        updateMinimap()
        // Anchored popups would otherwise float over unrelated text once the view scrolls.
        onScroll?()
    }

    private func updateTextViewFrame() {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let visibleSize = scrollView.contentSize
        let usedRect = layoutManager.usedRect(for: textContainer)
        let targetWidth = max(visibleSize.width, usedRect.width + textView.textContainerInset.width * 2)
        let targetHeight = max(visibleSize.height, usedRect.height + textView.textContainerInset.height * 2)
        textContainer.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(origin: .zero, size: NSSize(width: targetWidth, height: targetHeight))
    }

    private var minimapUpdateTask: Task<Void, Never>?

    private func updateMinimap() {
        minimapUpdateTask?.cancel()
        minimapUpdateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms debounce
            guard let self, !Task.isCancelled else { return }
            await self.calculateAndApplyMinimap()
        }
    }

    @MainActor
    private func calculateAndApplyMinimap() async {
        let visibleRect = scrollView.contentView.bounds
        let documentHeight = textView.bounds.height
        let cacheKey = MinimapCacheKey(
            displayVersion: currentDisplayVersion,
            visibleOriginY: visibleRect.minY.rounded(.towardZero),
            visibleHeight: visibleRect.height.rounded(.towardZero),
            documentHeight: documentHeight.rounded(.towardZero)
        )
        let snapshot: MinimapSnapshot
        if lastMinimapCacheKey == cacheKey {
            snapshot = lastMinimapSnapshot
        } else {
            // The whole-document line split + per-line measure is O(document); run it off the main
            // thread so a file with tens of thousands of lines doesn't hang the UI on rebuild.
            let text = currentDisplayText
            snapshot = await Task.detached(priority: .userInitiated) {
                MinimapSnapshot.make(text: text, visibleRect: visibleRect, documentHeight: documentHeight)
            }.value
            guard !Task.isCancelled else { return }
            lastMinimapCacheKey = cacheKey
            lastMinimapSnapshot = snapshot
        }

        guard showMinimap else {
            onViewportChange?(snapshot.visibleStartLine, snapshot.visibleEndLine)
            return
        }

        minimapView.apply(snapshot: snapshot)
        onViewportChange?(snapshot.visibleStartLine, snapshot.visibleEndLine)
    }
}

private final class EditorMinimapView: NSView {
    weak var scrollView: NSScrollView?
    var themeColors: ThemeColors
    private var snapshot = MinimapSnapshot.empty

    override var isFlipped: Bool {
        true
    }

    init(scrollView: NSScrollView, themeColors: ThemeColors) {
        self.scrollView = scrollView
        self.themeColors = themeColors
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Editor minimap")
        setAccessibilityIdentifier("editor-minimap")
        setAccessibilityValue(snapshot.accessibilityValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: MinimapSnapshot) {
        self.snapshot = snapshot
        setAccessibilityValue(snapshot.accessibilityValue)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        themeColors.nsPanelBackground.setFill()
        bounds.fill()

        let drawableWidth = max(bounds.width - 14, 10)
        let totalLines = max(snapshot.lineWidthFractions.count, 1)
        let lineStride = bounds.height / CGFloat(totalLines)
        let lineHeight = max(lineStride - 0.35, 0.65)

        for (index, fraction) in snapshot.lineWidthFractions.enumerated() {
            let y = CGFloat(index) * lineStride
            let width = max(drawableWidth * fraction, 6)
            let rect = NSRect(
                x: bounds.maxX - width - 6,
                y: y,
                width: width,
                height: lineHeight
            )
            themeColors.nsMutedText.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2).fill()
        }

        let viewportStart = CGFloat(snapshot.visibleStartLine - 1) / CGFloat(totalLines) * bounds.height
        let viewportHeight = max(
            CGFloat(snapshot.visibleEndLine - snapshot.visibleStartLine + 1) / CGFloat(totalLines) * bounds.height,
            18
        )
        let viewportRect = NSRect(
            x: 3,
            y: min(viewportStart, max(bounds.height - viewportHeight - 3, 3)),
            width: bounds.width - 6,
            height: min(viewportHeight, bounds.height - 6)
        )
        themeColors.nsAccent.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: viewportRect, xRadius: 4, yRadius: 4).fill()
        themeColors.nsAccent.withAlphaComponent(0.55).setStroke()
        let borderPath = NSBezierPath(roundedRect: viewportRect, xRadius: 4, yRadius: 4)
        borderPath.lineWidth = 1
        borderPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        scrollTo(point: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        scrollTo(point: convert(event.locationInWindow, from: nil))
    }

    private func scrollTo(point: NSPoint) {
        guard let scrollView, let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let documentHeight = documentView.bounds.height
        let visibleHeight = clipView.bounds.height
        let maxOffset = max(documentHeight - visibleHeight, 0)
        guard maxOffset > 0 else { return }

        let clickRatio = min(max(point.y / max(bounds.height, 1), 0), 1)
        let viewportRatio = min(max(visibleHeight / max(documentHeight, 1), 0), 1)
        let targetRatio = min(max(clickRatio - (viewportRatio / 2), 0), max(1 - viewportRatio, 0))
        let targetY = maxOffset * targetRatio

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
    }
}

private final class LineNumberRulerView: NSRulerView {
    private struct VisibleLineFrame {
        let line: Int
        let frame: NSRect
        let foldIndicatorFrame: NSRect?
    }

    private weak var textView: NSTextView?
    private var visibleLineFrames: [VisibleLineFrame] = []

    var themeColors: ThemeColors
    var editorFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    var breakpointLines: Set<Int> = []
    var currentExecutionLine: Int?
    var onToggleBreakpoint: ((Int) -> Void)?
    var onToggleFold: ((Int) -> Void)?
    var foldableLines: Set<Int> = []
    var foldedLines: Set<Int> = []
    var actualLineNumberForDisplayLine: ((Int) -> Int)?

    init(textView: NSTextView, themeColors: ThemeColors) {
        self.textView = textView
        self.themeColors = themeColors
        super.init(scrollView: nil, orientation: .verticalRuler)
        self.clipsToBounds = true
        self.clientView = textView
        self.ruleThickness = 56
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.group)
        self.setAccessibilityLabel("Editor gutter")
        self.setAccessibilityIdentifier("editor-gutter")
        self.setAccessibilityValue("")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }

        visibleLineFrames = []
        themeColors.nsGutterBackground.setFill()
        bounds.fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        let attributes: [NSAttributedString.Key: Any] = [
            .font: editorFont,
            .foregroundColor: themeColors.nsLineNumbers,
            .paragraphStyle: paragraphStyle
        ]

        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let textOriginY = textView.textContainerOrigin.y
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let textNSString = textView.string as NSString

        if textNSString.length == 0 {
            let labelRect = NSRect(x: 20, y: 10, width: ruleThickness - 24, height: 16)
            visibleLineFrames = [VisibleLineFrame(line: 1, frame: NSRect(x: 0, y: 8, width: ruleThickness, height: 18), foldIndicatorFrame: nil)]
            drawLineMarker(
                for: 1,
                in: NSRect(x: 0, y: 8, width: ruleThickness, height: 18)
            )
            "1".draw(in: labelRect, withAttributes: attributes)
            drawDivider()
            return
        }

        var lineNumber = TextMetrics.lineNumber(atUTF16Offset: characterRange.location, in: textNSString)

        textNSString.enumerateSubstrings(
            in: NSRange(location: characterRange.location, length: textNSString.length - characterRange.location),
            options: [.byLines, .substringNotRequired]
        ) { _, substringRange, _, stop in
            let glyphRangeForLine = layoutManager.glyphRange(forCharacterRange: substringRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRangeForLine, in: textContainer)
            let lineMinY = lineRect.minY + textOriginY

            if lineMinY > visibleRect.maxY {
                stop.pointee = true
                return
            }

            guard let yPosition = LineNumberLayout.labelYPosition(
                for: lineRect,
                visibleRect: visibleRect,
                textOriginY: textOriginY
            ) else {
                return
            }

            let markerRect = NSRect(
                x: 0,
                y: yPosition,
                width: self.ruleThickness,
                height: max(lineRect.height, 14)
            )
            let actualLineNumber = self.actualLineNumberForDisplayLine?(lineNumber) ?? lineNumber
            let foldIndicatorFrame = self.foldableLines.contains(actualLineNumber)
                ? NSRect(x: 18, y: yPosition + max((markerRect.height - 10) / 2, 0), width: 10, height: 10)
                : nil
            self.visibleLineFrames.append(
                VisibleLineFrame(
                    line: actualLineNumber,
                    frame: markerRect,
                    foldIndicatorFrame: foldIndicatorFrame
                )
            )
            self.drawLineMarker(for: actualLineNumber, in: markerRect)

            let labelRect = NSRect(x: 28, y: yPosition, width: self.ruleThickness - 32, height: max(lineRect.height, 14))
            "\(actualLineNumber)".draw(in: labelRect, withAttributes: attributes)
            lineNumber += 1
        }

        drawDivider()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let visibleLine = visibleLineFrames.first(where: { $0.frame.contains(point) }) else {
            super.mouseDown(with: event)
            return
        }

        if let foldIndicatorFrame = visibleLine.foldIndicatorFrame,
           foldIndicatorFrame.contains(point) {
            onToggleFold?(visibleLine.line)
            return
        }

        onToggleBreakpoint?(visibleLine.line)
    }

    private func drawLineMarker(for lineNumber: Int, in rect: NSRect) {
        if foldableLines.contains(lineNumber) {
            drawFoldIndicator(for: lineNumber, in: rect)
        }

        if currentExecutionLine == lineNumber {
            let highlightRect = NSRect(x: 0, y: rect.minY, width: ruleThickness - 1, height: rect.height)
            themeColors.nsAccent.withAlphaComponent(0.14).setFill()
            highlightRect.fill()

            let indicatorRect = NSRect(x: 0, y: rect.minY, width: 3, height: rect.height)
            themeColors.nsAccent.setFill()
            indicatorRect.fill()
        }

        guard breakpointLines.contains(lineNumber) else { return }

        let markerSize: CGFloat = 8
        let markerRect = NSRect(
            x: 6,
            y: rect.midY - (markerSize / 2),
            width: markerSize,
            height: markerSize
        )
        let markerPath = NSBezierPath(ovalIn: markerRect)
        themeColors.nsDanger.setFill()
        markerPath.fill()
    }

    private func drawFoldIndicator(for lineNumber: Int, in rect: NSRect) {
        let indicatorRect = NSRect(
            x: 18,
            y: rect.minY + max((rect.height - 10) / 2, 0),
            width: 10,
            height: 10
        )
        let path = NSBezierPath()
        if foldedLines.contains(lineNumber) {
            path.move(to: NSPoint(x: indicatorRect.minX + 3, y: indicatorRect.minY + 2))
            path.line(to: NSPoint(x: indicatorRect.minX + 3, y: indicatorRect.maxY - 2))
            path.line(to: NSPoint(x: indicatorRect.maxX - 2, y: indicatorRect.midY))
        } else {
            path.move(to: NSPoint(x: indicatorRect.minX + 2, y: indicatorRect.minY + 3))
            path.line(to: NSPoint(x: indicatorRect.maxX - 2, y: indicatorRect.minY + 3))
            path.line(to: NSPoint(x: indicatorRect.midX, y: indicatorRect.maxY - 2))
        }
        path.close()
        themeColors.nsMutedText.setFill()
        path.fill()
    }

    private func drawDivider() {
        let dividerPath = NSBezierPath()
        dividerPath.move(to: NSPoint(x: ruleThickness - 1, y: bounds.minY))
        dividerPath.line(to: NSPoint(x: ruleThickness - 1, y: bounds.maxY))
        dividerPath.lineWidth = 1
        themeColors.nsGutterDivider.setStroke()
        dividerPath.stroke()
    }
}

enum LineNumberLayout {
    static func labelYPosition(for lineRect: NSRect, visibleRect: NSRect, textOriginY: CGFloat) -> CGFloat? {
        let minY = lineRect.minY + textOriginY
        let maxY = lineRect.maxY + textOriginY

        guard maxY >= visibleRect.minY else { return nil }
        guard minY <= visibleRect.maxY else { return nil }

        return max(minY, visibleRect.minY) - visibleRect.minY
    }
}

struct FoldRegion: Hashable {
    let startLine: Int
    let endLine: Int
    let hiddenRange: NSRange
    let placeholder: String
}

private enum FoldingOffsetAffinity {
    case leading
    case trailing
}

struct FoldedTextSnapshot {
    private struct CollapsedSection: Hashable {
        let region: FoldRegion
        let displayRange: NSRange

        var hiddenRange: NSRange { region.hiddenRange }
        var placeholderLength: Int { displayRange.length }
    }

    static let identity = FoldedTextSnapshot(
        displayText: "",
        visibleLineNumbers: [1],
        foldableLines: [],
        foldedLines: [],
        regionsByStartLine: [:],
        sections: [],
        sourceLength: 0
    )

    let displayText: String
    let visibleLineNumbers: [Int]
    let foldableLines: Set<Int>
    let foldedLines: Set<Int>
    let regionsByStartLine: [Int: FoldRegion]

    private let sections: [CollapsedSection]
    private let sourceLength: Int

    var hasActiveFolds: Bool {
        !sections.isEmpty
    }

    static func make(from text: String, language: String, foldedStartLines: Set<Int>) -> FoldedTextSnapshot {
        let sourceLength = (text as NSString).length
        let allRegions = FoldingParser.regions(for: text, language: language)
        let regionsByStartLine = Dictionary(uniqueKeysWithValues: allRegions.map { ($0.startLine, $0) })
        let requestedRegions = foldedStartLines
            .sorted()
            .compactMap { regionsByStartLine[$0] }
            .sorted { lhs, rhs in
                if lhs.hiddenRange.location == rhs.hiddenRange.location {
                    return lhs.hiddenRange.length > rhs.hiddenRange.length
                }
                return lhs.hiddenRange.location < rhs.hiddenRange.location
            }

        var acceptedRegions: [FoldRegion] = []
        var lastCoveredUpperBound = -1
        for region in requestedRegions {
            if region.hiddenRange.location < lastCoveredUpperBound {
                continue
            }
            acceptedRegions.append(region)
            lastCoveredUpperBound = region.hiddenRange.upperBound
        }

        let foldedLines = Set(acceptedRegions.map(\.startLine))
        let visibleLineNumbers = makeVisibleLineNumbers(from: allRegions, foldedLines: foldedLines, text: text)

        let sections = makeCollapsedSections(from: acceptedRegions)
        let displayText = makeDisplayText(from: text, using: acceptedRegions)

        return FoldedTextSnapshot(
            displayText: displayText,
            visibleLineNumbers: visibleLineNumbers,
            foldableLines: Set(allRegions.map(\.startLine)),
            foldedLines: foldedLines,
            regionsByStartLine: regionsByStartLine,
            sections: sections,
            sourceLength: sourceLength
        )
    }

    static func unfolded(_ text: String) -> FoldedTextSnapshot {
        let sourceLength = (text as NSString).length
        return FoldedTextSnapshot(
            displayText: text,
            visibleLineNumbers: makeVisibleLineNumbers(from: [], foldedLines: [], text: text),
            foldableLines: [],
            foldedLines: [],
            regionsByStartLine: [:],
            sections: [],
            sourceLength: sourceLength
        )
    }

    func actualLine(forDisplayLine displayLine: Int) -> Int {
        guard displayLine > 0 else { return 1 }
        guard visibleLineNumbers.indices.contains(displayLine - 1) else {
            return visibleLineNumbers.last ?? displayLine
        }
        return visibleLineNumbers[displayLine - 1]
    }

    func displayLine(forActualLine actualLine: Int) -> Int? {
        visibleLineNumbers.firstIndex(of: actualLine).map { $0 + 1 }
    }

    func region(startingAt line: Int) -> FoldRegion? {
        regionsByStartLine[line]
    }

    func sourceRange(forDisplayedRange range: NSRange) -> NSRange {
        if range.length == 0 {
            let offset = sourceOffset(forDisplayedOffset: range.location, affinity: .leading)
            return NSRange(location: offset, length: 0)
        }
        let start = sourceOffset(forDisplayedOffset: range.location, affinity: .leading)
        let end = sourceOffset(forDisplayedOffset: range.upperBound, affinity: .trailing)
        return NSRange(location: start, length: max(end - start, 0))
    }

    func displayRange(forSourceRange range: NSRange) -> NSRange {
        if range.length == 0 {
            let offset = displayOffset(forSourceOffset: range.location, affinity: .leading)
            return NSRange(location: offset, length: 0)
        }
        let start = displayOffset(forSourceOffset: range.location, affinity: .leading)
        let end = displayOffset(forSourceOffset: range.upperBound, affinity: .trailing)
        return NSRange(location: start, length: max(end - start, 0))
    }

    private func sourceOffset(forDisplayedOffset offset: Int, affinity: FoldingOffsetAffinity) -> Int {
        var sourceOffset = max(0, min(offset, (displayText as NSString).length))

        for section in sections {
            let hiddenLength = section.hiddenRange.length - section.placeholderLength
            if sourceOffset < section.displayRange.location {
                break
            }
            if sourceOffset < section.displayRange.upperBound {
                return affinity == .leading ? section.hiddenRange.location : section.hiddenRange.upperBound
            }
            sourceOffset += hiddenLength
        }

        return min(sourceOffset, sourceLength)
    }

    private func displayOffset(forSourceOffset offset: Int, affinity: FoldingOffsetAffinity) -> Int {
        var displayOffset = max(0, min(offset, sourceLength))

        for section in sections {
            let hiddenLength = section.hiddenRange.length - section.placeholderLength
            if displayOffset < section.hiddenRange.location {
                break
            }
            if displayOffset < section.hiddenRange.upperBound {
                return affinity == .leading ? section.displayRange.location : section.displayRange.upperBound
            }
            displayOffset -= hiddenLength
        }

        return min(displayOffset, (displayText as NSString).length)
    }

    private static func makeCollapsedSections(from acceptedRegions: [FoldRegion]) -> [CollapsedSection] {
        var delta = 0
        return acceptedRegions.map { region in
            let placeholderLength = (region.placeholder as NSString).length
            let displayRange = NSRange(
                location: region.hiddenRange.location - delta,
                length: placeholderLength
            )
            delta += region.hiddenRange.length - placeholderLength
            return CollapsedSection(region: region, displayRange: displayRange)
        }
    }

    private static func makeDisplayText(from text: String, using acceptedRegions: [FoldRegion]) -> String {
        guard !acceptedRegions.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for region in acceptedRegions.reversed() {
            mutable.replaceCharacters(in: region.hiddenRange, with: region.placeholder)
        }
        return mutable as String
    }

    private static func makeVisibleLineNumbers(from regions: [FoldRegion], foldedLines: Set<Int>, text: String) -> [Int] {
        let regionByStartLine = Dictionary(uniqueKeysWithValues: regions.map { ($0.startLine, $0) })
        let sourceLines = LineInfo.parse(text)
        let maxLineNumber = max(
            1,
            sourceLines.last.map { $0.trimmedText.isEmpty ? max($0.number - 1, 1) : $0.number } ?? 1
        )

        var visibleLineNumbers: [Int] = []
        var lineNumber = 1
        while lineNumber <= maxLineNumber {
            visibleLineNumbers.append(lineNumber)
            if foldedLines.contains(lineNumber), let region = regionByStartLine[lineNumber] {
                lineNumber = region.endLine + 1
            } else {
                lineNumber += 1
            }
        }

        return visibleLineNumbers.isEmpty ? [1] : visibleLineNumbers
    }
}

/// Single-entry, equality-checked memo for pure whole-document parses. The same document is
/// parsed by the folding system and the breadcrumb/sticky-scope navigation model; this collapses
/// those redundant parses (the result is only recomputed when the text or language actually changes).
final class SingleEntryParseCache<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedText: String?
    private var cachedLanguage: String?
    private var cachedValue: Value?

    func value(forText text: String, language: String) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard cachedText == text, cachedLanguage == language else { return nil }
        return cachedValue
    }

    func store(_ value: Value, forText text: String, language: String) {
        lock.lock()
        defer { lock.unlock() }
        cachedText = text
        cachedLanguage = language
        cachedValue = value
    }
}

enum FoldingParser {
    private static let regionsCache = SingleEntryParseCache<[FoldRegion]>()

    static func regions(for text: String, language: String) -> [FoldRegion] {
        if let cached = regionsCache.value(forText: text, language: language) {
            return cached
        }
        let result = computeRegions(for: text, language: language)
        regionsCache.store(result, forText: text, language: language)
        return result
    }

    private static func computeRegions(for text: String, language: String) -> [FoldRegion] {
        let lineInfos = LineInfo.parse(text)
        guard !lineInfos.isEmpty else { return [] }

        let braceRegions = braceRegions(for: text, lineInfos: lineInfos)
        let indentRegions = indentRegions(for: text, lineInfos: lineInfos, language: language)

        var byStartLine: [Int: FoldRegion] = [:]
        for region in braceRegions + indentRegions {
            if let existing = byStartLine[region.startLine] {
                if region.endLine > existing.endLine {
                    byStartLine[region.startLine] = region
                }
            } else {
                byStartLine[region.startLine] = region
            }
        }

        return byStartLine.values.sorted { lhs, rhs in
            if lhs.startLine == rhs.startLine {
                return lhs.endLine < rhs.endLine
            }
            return lhs.startLine < rhs.startLine
        }
    }

    private static func braceRegions(for text: String, lineInfos: [LineInfo]) -> [FoldRegion] {
        let nsText = text as NSString
        var stack: [(line: Int, char: Character)] = []
        var regions: [FoldRegion] = []

        for lineInfo in lineInfos {
            let lineText = nsText.substring(with: NSRange(location: lineInfo.startUTF16, length: lineInfo.lineEndUTF16 - lineInfo.startUTF16))
            for character in lineText {
                if "{[(".contains(character) {
                    stack.append((lineInfo.number, character))
                } else if "}])".contains(character), let last = stack.popLast() {
                    if lineInfo.number > last.line,
                       let region = makeRegion(startLine: last.line, endLine: lineInfo.number, lineInfos: lineInfos) {
                        regions.append(region)
                    }
                }
            }
        }

        return regions
    }

    private static func indentRegions(for text: String, lineInfos: [LineInfo], language: String) -> [FoldRegion] {
        let indentationLanguages: Set<String> = ["python", "yaml"]
        guard indentationLanguages.contains(language) else { return [] }

        var regions: [FoldRegion] = []
        var index = 0

        while index < lineInfos.count - 1 {
            let current = lineInfos[index]
            if current.trimmedText.isEmpty {
                index += 1
                continue
            }

            guard let nextIndex = nextNonEmptyLine(after: index, lineInfos: lineInfos) else {
                break
            }

            let next = lineInfos[nextIndex]
            guard next.indent > current.indent else {
                index += 1
                continue
            }

            var endIndex = nextIndex
            var scanIndex = nextIndex + 1
            while scanIndex < lineInfos.count {
                let candidate = lineInfos[scanIndex]
                if !candidate.trimmedText.isEmpty && candidate.indent <= current.indent {
                    break
                }
                if !candidate.trimmedText.isEmpty {
                    endIndex = scanIndex
                }
                scanIndex += 1
            }

            if lineInfos[endIndex].number > current.number,
               let region = makeRegion(startLine: current.number, endLine: lineInfos[endIndex].number, lineInfos: lineInfos) {
                regions.append(region)
            }
            index += 1
        }

        return regions
    }

    private static func nextNonEmptyLine(after index: Int, lineInfos: [LineInfo]) -> Int? {
        var candidateIndex = index + 1
        while candidateIndex < lineInfos.count {
            if !lineInfos[candidateIndex].trimmedText.isEmpty {
                return candidateIndex
            }
            candidateIndex += 1
        }
        return nil
    }

    private static func makeRegion(startLine: Int, endLine: Int, lineInfos: [LineInfo]) -> FoldRegion? {
        guard startLine >= 1, endLine <= lineInfos.count, endLine > startLine else { return nil }
        let startInfo = lineInfos[startLine - 1]
        let endInfo = lineInfos[endLine - 1]
        let hiddenStart = startInfo.lineEndUTF16
        let hiddenEnd = endInfo.fullEndUTF16
        guard hiddenEnd > hiddenStart else { return nil }
        let placeholder = endInfo.hasTrailingNewline ? " ...\n" : " ..."
        return FoldRegion(
            startLine: startLine,
            endLine: endLine,
            hiddenRange: NSRange(location: hiddenStart, length: hiddenEnd - hiddenStart),
            placeholder: placeholder
        )
    }
}

struct LineInfo {
    let number: Int
    let startUTF16: Int
    let lineEndUTF16: Int
    let fullEndUTF16: Int
    let indent: Int
    let trimmedText: String
    let hasTrailingNewline: Bool

    private static let parseCache = SingleEntryParseCache<[LineInfo]>()

    static func parse(_ text: String) -> [LineInfo] {
        if let cached = parseCache.value(forText: text, language: "") {
            return cached
        }
        let result = computeParse(text)
        parseCache.store(result, forText: text, language: "")
        return result
    }

    private static func computeParse(_ text: String) -> [LineInfo] {
        let nsText = text as NSString
        let length = nsText.length

        if length == 0 {
            return [
                LineInfo(
                    number: 1,
                    startUTF16: 0,
                    lineEndUTF16: 0,
                    fullEndUTF16: 0,
                    indent: 0,
                    trimmedText: "",
                    hasTrailingNewline: false
                )
            ]
        }

        var infos: [LineInfo] = []
        var location = 0
        var lineNumber = 1

        while location < length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            var lineEnd = lineRange.upperBound
            var hasTrailingNewline = false

            while lineEnd > lineRange.location {
                let char = nsText.character(at: lineEnd - 1)
                if char == 10 || char == 13 {
                    hasTrailingNewline = true
                    lineEnd -= 1
                } else {
                    break
                }
            }

            let lineString = nsText.substring(with: NSRange(location: lineRange.location, length: lineEnd - lineRange.location))
            let indent = lineString.reduce(into: 0) { count, character in
                if character == " " {
                    count += 1
                } else if character == "\t" {
                    count += 4
                } else {
                    return
                }
            }

            infos.append(
                LineInfo(
                    number: lineNumber,
                    startUTF16: lineRange.location,
                    lineEndUTF16: lineEnd,
                    fullEndUTF16: lineRange.upperBound,
                    indent: indent,
                    trimmedText: lineString.trimmingCharacters(in: .whitespaces),
                    hasTrailingNewline: hasTrailingNewline
                )
            )

            lineNumber += 1
            location = lineRange.upperBound
        }

        if text.hasSuffix("\n") {
            infos.append(
                LineInfo(
                    number: lineNumber,
                    startUTF16: length,
                    lineEndUTF16: length,
                    fullEndUTF16: length,
                    indent: 0,
                    trimmedText: "",
                    hasTrailingNewline: false
                )
            )
        }

        return infos
    }
}

private extension NSRange {
    var upperBound: Int {
        location + length
    }
}

enum BracketMatcher {
    static func matchingRanges(in text: NSString, caretLocation: Int) -> [NSRange] {
        guard text.length > 0 else { return [] }

        if let openingIndex = bracketIndex(in: text, preferredLocation: caretLocation),
           let matchIndex = matchingIndex(in: text, from: openingIndex) {
            return [
                NSRange(location: openingIndex, length: 1),
                NSRange(location: matchIndex, length: 1)
            ]
            .sorted { $0.location < $1.location }
        }

        return []
    }

    private static func bracketIndex(in text: NSString, preferredLocation: Int) -> Int? {
        let candidates = [preferredLocation, preferredLocation - 1]
        for index in candidates where index >= 0 && index < text.length {
            let scalar = text.character(at: index)
            if bracketPairs.keys.contains(scalar) || bracketPairs.values.contains(scalar) {
                return index
            }
        }
        return nil
    }

    private static func matchingIndex(in text: NSString, from index: Int) -> Int? {
        let character = text.character(at: index)

        if let closing = bracketPairs[character] {
            var depth = 0
            for scanIndex in index..<text.length {
                let scanCharacter = text.character(at: scanIndex)
                if scanCharacter == character {
                    depth += 1
                } else if scanCharacter == closing {
                    depth -= 1
                    if depth == 0 {
                        return scanIndex
                    }
                }
            }
            return nil
        }

        if let opening = reverseBracketPairs[character] {
            var depth = 0
            for scanIndex in stride(from: index, through: 0, by: -1) {
                let scanCharacter = text.character(at: scanIndex)
                if scanCharacter == character {
                    depth += 1
                } else if scanCharacter == opening {
                    depth -= 1
                    if depth == 0 {
                        return scanIndex
                    }
                }
            }
        }

        return nil
    }

    private static let bracketPairs: [unichar: unichar] = [
        40: 41,
        91: 93,
        123: 125
    ]

    private static let reverseBracketPairs: [unichar: unichar] = [
        41: 40,
        93: 91,
        125: 123
    ]
}

struct EditorInputOutcome: Equatable {
    let replacementText: String
    let selectedLocation: Int
}

enum EditorInputHandler {
    static func outcome(
        for replacementString: String,
        selectedRange: NSRange,
        affectedRange: NSRange,
        tabSize: Int,
        in text: NSString
    ) -> EditorInputOutcome? {
        if replacementString == "\t" {
            let normalizedTabSize = max(tabSize, 1)
            let spaces = String(repeating: " ", count: normalizedTabSize)
            return EditorInputOutcome(
                replacementText: spaces,
                selectedLocation: affectedRange.location + normalizedTabSize
            )
        }

        guard selectedRange.length == 0, affectedRange.length == 0, replacementString.count == 1 else {
            return nil
        }

        let character = replacementString[replacementString.startIndex]
        if let closingCharacter = pairCharacter(for: character) {
            return EditorInputOutcome(
                replacementText: "\(character)\(closingCharacter)",
                selectedLocation: affectedRange.location + 1
            )
        }

        if let previousCharacter = previousCharacter(at: affectedRange.location, in: text),
           isClosingCharacter(character),
           pairCharacter(for: previousCharacter) == character,
           nextCharacter(at: affectedRange.location, in: text) == character {
            return EditorInputOutcome(
                replacementText: "",
                selectedLocation: affectedRange.location + 1
            )
        }

        return nil
    }

    private static func pairCharacter(for character: Character) -> Character? {
        switch character {
        case "(": return ")"
        case "[": return "]"
        case "{": return "}"
        case "\"": return "\""
        case "'": return "'"
        default: return nil
        }
    }

    private static func isClosingCharacter(_ character: Character) -> Bool {
        [")", "]", "}", "\"", "'"].contains(character)
    }

    private static func previousCharacter(at location: Int, in text: NSString) -> Character? {
        guard location > 0 else { return nil }
        let string = text as String
        let cursorIndex = String.Index(utf16Offset: location, in: string)
        guard cursorIndex > string.startIndex else { return nil }
        let previousIndex = string.index(before: cursorIndex)
        return string[previousIndex]
    }

    private static func nextCharacter(at location: Int, in text: NSString) -> Character? {
        guard location < text.length else { return nil }
        let string = text as String
        let cursorIndex = String.Index(utf16Offset: location, in: string)
        guard cursorIndex < string.endIndex else { return nil }
        return string[cursorIndex]
    }
}
