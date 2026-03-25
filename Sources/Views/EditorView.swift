import AppKit
import SwiftUI
import Combine

struct EditorView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    @EnvironmentObject private var commandDispatcher: AppCommandDispatcher
    @ObservedObject private var lspService = LSPService.shared
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
            showMinimap: configService.settings.editor.showMinimap,
            wordWrap: configService.settings.editor.wordWrap
        )
    }

    var body: some View {
        CodeEditorRepresentable(
            text: Binding(
                get: { projectViewModel.selectedTab?.content ?? tab.content },
                set: { newValue in
                    DispatchQueue.main.async {
                        projectViewModel.updateTabContent(newValue)
                    }
                }
            ),
            language: tab.language,
            editorFont: configService.font,
            commandDispatcher: commandDispatcher,
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
            showMinimap: configService.settings.editor.showMinimap,
            wordWrap: configService.settings.editor.wordWrap,
            diagnostics: projectViewModel.currentTabDiagnostics,
            breakpointLines: projectViewModel.currentTabBreakpointLines,
            executionLine: projectViewModel.currentExecutionLine,
            fileURL: projectViewModel.selectedTab?.filePath ?? tab.filePath,
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
            onRevealInFinder: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        )
        .id(configIdentity)
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
        nsView.applyTheme(
            themeColors,
            font: editorFont,
            showMinimap: showMinimap,
            showLineNumbers: showLineNumbers,
            wordWrap: wordWrap
        )
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
        }

        func attach(to containerView: EditorContainerView) {
            self.containerView = containerView
            containerView.configure(delegate: self)
            containerView.textView.menuDelegate = self
            applyPopupTheme()
            containerView.onLayout = { [weak self] in
                self?.containerViewDidLayout()
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
            let shouldApplyText = renderState.needsTextApplication(
                for: foldSnapshot.displayText,
                language: language,
                renderedText: textView.string,
                isViewReadyForDisplay: containerView.isReadyForDisplay
            )
            let requestedLineJump = parent.pendingLineJump

            guard shouldApplyText || requestedLineJump != nil else { return }

            let selectedRange = textView.selectedRange()
            isApplyingExternalUpdate = true
            if shouldApplyText {
                containerView.applyText(foldSnapshot.displayText, language: language, themeColors: parent.themeColors)
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

            isApplyingExternalUpdate = true
            containerView?.applyText(updatedText, language: parent.language, themeColors: parent.themeColors)
            let clampedLocation = min(selectedRange.location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            isApplyingExternalUpdate = false

            renderState.recordRender(
                text: updatedText,
                language: parent.language,
                isViewReadyForDisplay: containerView?.isReadyForDisplay ?? false
            )

            DispatchQueue.main.async { [weak self] in
                self?.parent.text = updatedText
            }
            refreshEditorDecorations(in: textView)
            updateCursorPosition(in: textView)

            // Trigger completion on . or : characters
            let nsText = updatedText as NSString
            let cursorLoc = textView.selectedRange().location
            if cursorLoc > 0 && cursorLoc <= nsText.length {
                let lastChar = nsText.substring(with: NSRange(location: cursorLoc - 1, length: 1))
                triggerCompletionIfNeeded(in: textView, trigger: lastChar)
            } else if completionPopup.isVisible {
                completionPopup.dismiss()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isApplyingExternalUpdate else { return }
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

        private func updateCursorPosition(in textView: NSTextView) {
            let text = textView.string
            let location = min(textView.selectedRange().location, (text as NSString).length)
            let utf16View = text.utf16
            let utf16Index = utf16View.index(utf16View.startIndex, offsetBy: location)
            let stringIndex = String.Index(utf16Index, within: text) ?? text.endIndex
            let prefix = text[..<stringIndex]
            let line = prefix.reduce(into: 1) { result, character in
                if character == "\n" {
                    result += 1
                }
            }
            let column = (prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0) + 1
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
                    default:
                        break
                    }
                }
                .store(in: &commandCancellables)
        }

        private func handleMouseEvent(_ event: NSEvent) -> NSEvent? {
            guard let textView = containerView?.textView else { return event }

            // Only handle events when Cmd is held
            guard event.modifierFlags.contains(.command) else {
                if hoverPopup.isVisible {
                    hoverPopup.dismiss()
                }
                return event
            }

            let windowPoint = event.locationInWindow
            let textViewPoint = textView.convert(windowPoint, from: nil)

            // Ensure point is within the text view
            guard textView.bounds.contains(textViewPoint) else { return event }

            if event.type == .leftMouseDown {
                // Cmd+Click = go-to-definition
                handleGoToDefinition(at: textViewPoint, in: textView)
                return nil // Consume the event
            } else if event.type == .mouseMoved {
                // Cmd+hover = show hover info
                handleHover(at: textViewPoint, in: textView)
            }

            return event
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

                let content = result.contentsString
                guard !content.isEmpty else { return }

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
                    hoverPopup.show(content: content, at: rect, in: textView)
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
            }
        }

        private func insertCompletion(_ item: CompletionItem) {
            guard let textView = containerView?.textView else { return }
            let insertText = item.insertText ?? item.label
            let range = textView.selectedRange()
            textView.replaceCharacters(in: range, with: insertText)
            textView.setSelectedRange(NSRange(location: range.location + (insertText as NSString).length, length: 0))
            textView.didChangeText()
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
            return false
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

final class EditorContainerView: NSView {
    let scrollView: NSScrollView
    let textView: EditorTextView
    fileprivate let lineNumberView: LineNumberRulerView
    fileprivate let minimapView: EditorMinimapView
    var onLayout: (() -> Void)?
    var onViewportChange: ((Int, Int) -> Void)?
    var editorFont: NSFont
    var showMinimap: Bool
    var showLineNumbers: Bool
    var wordWrap: Bool
    private var currentDisplayText = ""
    private let minimapWidthConstraint: NSLayoutConstraint

    init(themeColors: ThemeColors, font: NSFont, showMinimap: Bool, showLineNumbers: Bool, wordWrap: Bool) {
        self.editorFont = font
        self.showMinimap = showMinimap
        self.showLineNumbers = showLineNumbers
        self.wordWrap = wordWrap
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
        scrollView.drawsBackground = true
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
        NotificationCenter.default.removeObserver(self)
    }

    func configure(delegate: NSTextViewDelegate) {
        textView.delegate = delegate
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
            .foregroundColor: themeColors.nsForeground
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
    }

    var isReadyForDisplay: Bool {
        window != nil && !bounds.isEmpty && !scrollView.contentSize.equalTo(.zero)
    }

    func applyText(_ text: String, language: String, themeColors: ThemeColors) {
        currentDisplayText = text
        let highlighted = HighlightService.shared.highlightedAttributedString(
            text,
            language: language,
            themeColors: themeColors,
            font: editorFont
        )

        guard let textStorage = textView.textStorage else { return }
        let replacementRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: replacementRange, with: highlighted.string)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.setAttributes([
            .font: editorFont,
            .foregroundColor: themeColors.nsForeground
        ], range: fullRange)
        textStorage.endEditing()
        textView.setAccessibilityValue(text)

        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            if fullRange.length > 0 {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
                layoutManager.removeTemporaryAttribute(.font, forCharacterRange: fullRange)
                highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { attributes, range, _ in
                    var temporaryAttributes: [NSAttributedString.Key: Any] = [:]
                    if let foregroundColor = attributes[.foregroundColor] {
                        temporaryAttributes[.foregroundColor] = foregroundColor
                    }
                    if let font = attributes[.font] {
                        temporaryAttributes[.font] = font
                    }
                    guard !temporaryAttributes.isEmpty else { return }
                    layoutManager.addTemporaryAttributes(temporaryAttributes, forCharacterRange: range)
                }
            }
            layoutManager.ensureLayout(for: textContainer)
        }
        updateTextViewFrame()
        textView.needsDisplay = true
        lineNumberView.needsDisplay = true
        lineNumberView.themeColors = themeColors
        lineNumberView.editorFont = editorFont
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
        textView.needsDisplay = true
        lineNumberView.needsDisplay = true
        updateMinimap()
        onLayout?()
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        updateTextViewFrame()
        lineNumberView.needsDisplay = true
        updateMinimap()
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

    private func updateMinimap() {
        let snapshot = MinimapSnapshot.make(
            text: currentDisplayText,
            visibleRect: scrollView.contentView.bounds,
            documentHeight: textView.bounds.height
        )
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

        var lineNumber = textNSString.substring(to: min(characterRange.location, textNSString.length)).reduce(1) { partial, character in
            character == "\n" ? partial + 1 : partial
        }

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

enum FoldingParser {
    static func regions(for text: String, language: String) -> [FoldRegion] {
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

    static func parse(_ text: String) -> [LineInfo] {
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
        return Character(UnicodeScalar(text.character(at: location - 1))!)
    }

    private static func nextCharacter(at location: Int, in text: NSString) -> Character? {
        guard location < text.length else { return nil }
        return Character(UnicodeScalar(text.character(at: location))!)
    }
}
