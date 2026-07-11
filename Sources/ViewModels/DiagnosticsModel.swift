import Foundation

/// Owns diagnostics selection/scope state and the derived diagnostic views, extracted from
/// ProjectViewModel so an LSP diagnostics push (frequent while typing/compiling) re-renders only
/// the diagnostics consumers (editor gutter, status bar, problems panel) instead of every view
/// observing the app-wide view model.
///
/// The diagnostic DATA lives in LSPService. This model reads it via the injected `lspService`,
/// owns the LSP diagnostics-change handler, and learns the active document/cursor from context
/// the view model PUSHES in (it holds no back-reference to ProjectViewModel — avoiding a cycle).
/// File-system/path helpers are supplied as closures for the same reason.
@MainActor
final class DiagnosticsModel: ObservableObject {
    enum DiagnosticsPanelScope {
        case currentFile
        case workspace
    }

    // MARK: - Selection / scope state
    @Published var activeCurrentDiagnosticID: String?
    @Published var activeWorkspaceDiagnosticID: String?
    @Published var diagnosticsPanelScope: DiagnosticsPanelScope = .currentFile

    // MARK: - Pushed editor context
    // These are inputs the view model pushes in via `updateContext`; they are NOT @Published —
    // a cursor move that leaves the active diagnostic unchanged must not re-render diagnostics
    // consumers. `updateContext` fires `objectWillChange` itself only when the active document
    // changes (so the diagnostic LIST changes), and otherwise relies on the guarded @Published
    // writes in `synchronizeActiveDiagnosticSelection`.
    private(set) var currentDocumentURI: String?
    private(set) var currentNormalizedFilePath: String?
    private(set) var currentCursorLine: Int = 1
    private(set) var currentCursorColumn: Int = 1
    /// Advances for every language-server publish, even when the diagnostic values are identical.
    /// Consumers use this to distinguish a fresh confirmation from locally rebased stale ranges.
    private(set) var publicationGeneration: UInt64 = 0

    private let lspService: LSPServiceProtocol
    private let normalize: (URL) -> String
    private let displayPathProvider: (URL) -> String
    private let lineProvider: (URL, Int) -> String

    private var cachedWorkspaceDiagnostics: [WorkspaceDiagnosticItem]?

    init(
        lspService: LSPServiceProtocol,
        normalize: @escaping (URL) -> String,
        displayPathProvider: @escaping (URL) -> String,
        lineProvider: @escaping (URL, Int) -> String
    ) {
        self.lspService = lspService
        self.normalize = normalize
        self.displayPathProvider = displayPathProvider
        self.lineProvider = lineProvider

        // Own the LSP diagnostics-change handler so a push (frequent while typing/compiling)
        // re-renders ONLY this model's observers, not every view observing ProjectViewModel.
        lspService.setDiagnosticsChangeHandler { [weak self] in
            self?.handleDiagnosticsChanged()
        }
    }

    /// Invoked when LSPService reports new diagnostics. The active document/cursor context was
    /// already pushed by the view model on tab/caret changes, so we just refresh the cache and
    /// selection and republish. `objectWillChange.send()` is explicit because the diagnostic LIST
    /// can change (a new problem appears) without the active selection id changing.
    private func handleDiagnosticsChanged() {
        publicationGeneration &+= 1
        invalidateWorkspaceDiagnosticsCache()
        synchronizeActiveDiagnosticSelection()
        objectWillChange.send()
    }

    // MARK: - Current-file diagnostics

    var currentTabDiagnostics: [LSPDiagnostic] {
        guard let uri = currentDocumentURI else { return [] }
        return lspService.diagnostics(for: uri)
    }

    var currentTabDiagnosticCount: (errors: Int, warnings: Int) {
        guard let uri = currentDocumentURI else { return (0, 0) }
        return lspService.diagnosticCount(for: uri)
    }

    var orderedCurrentTabDiagnostics: [LSPDiagnostic] {
        sortedCurrentDiagnostics()
    }

    var activeCurrentDiagnostic: LSPDiagnostic? {
        let diagnostics = orderedCurrentTabDiagnostics
        guard !diagnostics.isEmpty else { return nil }

        if let activeCurrentDiagnosticID,
           let diagnostic = diagnostics.first(where: { $0.id == activeCurrentDiagnosticID }) {
            return diagnostic
        }

        return inferredCurrentDiagnostic(in: diagnostics)
    }

    var activeCurrentDiagnosticIndex: Int? {
        guard let activeCurrentDiagnostic else { return nil }
        return orderedCurrentTabDiagnostics.firstIndex(of: activeCurrentDiagnostic)
    }

    var currentProblemPositionText: String? {
        switch diagnosticsPanelScope {
        case .currentFile:
            guard let activeCurrentDiagnosticIndex else { return nil }
            let total = orderedCurrentTabDiagnostics.count
            return "Problem \(activeCurrentDiagnosticIndex + 1) of \(total)"
        case .workspace:
            guard let activeWorkspaceDiagnosticIndex else { return nil }
            let total = orderedWorkspaceDiagnostics.count
            return "Problem \(activeWorkspaceDiagnosticIndex + 1) of \(total)"
        }
    }

    var canNavigateCurrentProblems: Bool {
        !currentTabDiagnostics.isEmpty
    }

    func isActiveDiagnostic(_ diagnostic: LSPDiagnostic) -> Bool {
        activeCurrentDiagnostic?.id == diagnostic.id
    }

    // MARK: - Workspace diagnostics

    var workspaceDiagnosticCount: (errors: Int, warnings: Int) {
        orderedWorkspaceDiagnostics.reduce(into: (errors: 0, warnings: 0)) { partialResult, item in
            switch item.diagnostic.severity {
            case .error:
                partialResult.errors += 1
            case .warning:
                partialResult.warnings += 1
            default:
                break
            }
        }
    }

    var workspaceDiagnosticFileCount: Int {
        Set(orderedWorkspaceDiagnostics.map { normalize($0.fileURL) }).count
    }

    var hasWorkspaceDiagnostics: Bool {
        !orderedWorkspaceDiagnostics.isEmpty
    }

    var canNavigateProblems: Bool {
        switch diagnosticsPanelScope {
        case .currentFile:
            return canNavigateCurrentProblems
        case .workspace:
            return hasWorkspaceDiagnostics
        }
    }

    var orderedWorkspaceDiagnostics: [WorkspaceDiagnosticItem] {
        if let cachedWorkspaceDiagnostics {
            return cachedWorkspaceDiagnostics
        }

        let diagnostics = lspService.diagnosticsByURI
            .compactMap { uri, diagnostics -> [WorkspaceDiagnosticItem]? in
                guard let fileURL = URL(string: uri), fileURL.isFileURL else { return nil }
                return diagnostics.map { diagnostic in
                    WorkspaceDiagnosticItem(
                        fileURL: fileURL,
                        displayPath: displayPathProvider(fileURL),
                        lineText: lineProvider(fileURL, diagnostic.range.start.line + 1),
                        diagnostic: diagnostic
                    )
                }
            }
            .flatMap { $0 }
            .sorted(by: compareWorkspaceDiagnostics)

        cachedWorkspaceDiagnostics = diagnostics
        return diagnostics
    }

    var activeWorkspaceDiagnostic: WorkspaceDiagnosticItem? {
        let diagnostics = orderedWorkspaceDiagnostics
        guard !diagnostics.isEmpty else { return nil }

        if let activeWorkspaceDiagnosticID,
           let diagnostic = diagnostics.first(where: { $0.id == activeWorkspaceDiagnosticID }) {
            return diagnostic
        }

        return inferredWorkspaceDiagnostic(in: diagnostics)
    }

    var activeWorkspaceDiagnosticIndex: Int? {
        guard let activeWorkspaceDiagnostic else { return nil }
        return orderedWorkspaceDiagnostics.firstIndex(of: activeWorkspaceDiagnostic)
    }

    var activeProblemScrollID: String? {
        switch diagnosticsPanelScope {
        case .currentFile:
            return activeCurrentDiagnostic?.id
        case .workspace:
            return activeWorkspaceDiagnostic?.id
        }
    }

    // MARK: - Context updates / cache

    /// Pushed by the view model whenever the active tab or cursor moves. Fires `objectWillChange`
    /// only when the active document changes (the diagnostic list view depends on it); cursor-only
    /// moves are absorbed by the guarded writes in `synchronizeActiveDiagnosticSelection`.
    func updateContext(documentURI: String?, normalizedFilePath: String?, cursorLine: Int, cursorColumn: Int) {
        let documentChanged = documentURI != currentDocumentURI || normalizedFilePath != currentNormalizedFilePath
        currentDocumentURI = documentURI
        currentNormalizedFilePath = normalizedFilePath
        currentCursorLine = cursorLine
        currentCursorColumn = cursorColumn
        if documentChanged {
            objectWillChange.send()
        }
        synchronizeActiveDiagnosticSelection()
    }

    func invalidateWorkspaceDiagnosticsCache() {
        cachedWorkspaceDiagnostics = nil
    }

    func synchronizeActiveDiagnosticSelection() {
        // Guard the @Published writes: this runs on every caret move, and a no-op assignment
        // still fires objectWillChange and re-renders every view observing this model.
        let current = inferredCurrentDiagnostic(in: orderedCurrentTabDiagnostics)?.id
        if activeCurrentDiagnosticID != current {
            activeCurrentDiagnosticID = current
        }
        let workspace = inferredWorkspaceDiagnostic(in: orderedWorkspaceDiagnostics)?.id
        if activeWorkspaceDiagnosticID != workspace {
            activeWorkspaceDiagnosticID = workspace
        }
    }

    // MARK: - Navigation

    func navigatedProblem(step: Int) -> NavigableProblem? {
        switch diagnosticsPanelScope {
        case .currentFile:
            let diagnostics = orderedCurrentTabDiagnostics
            guard !diagnostics.isEmpty else { return nil }
            let firstDiagnostic = diagnostics[0]
            let lastDiagnostic = diagnostics[diagnostics.count - 1]

            if let activeCurrentDiagnostic,
               let currentIndex = diagnostics.firstIndex(of: activeCurrentDiagnostic) {
                let nextIndex = (currentIndex + step + diagnostics.count) % diagnostics.count
                return .current(diagnostics[nextIndex])
            }

            let currentPosition = currentProblemReferencePosition()

            if step >= 0 {
                return .current(
                    diagnostics.first(where: { diagnostic in
                        let position = diagnosticSortPosition(for: diagnostic)
                        return position.line > currentPosition.line
                            || (position.line == currentPosition.line && position.column > currentPosition.column)
                    }) ?? firstDiagnostic
                )
            }

            return .current(
                diagnostics.last(where: { diagnostic in
                    let position = diagnosticSortPosition(for: diagnostic)
                    return position.line < currentPosition.line
                        || (position.line == currentPosition.line && position.column < currentPosition.column)
                }) ?? lastDiagnostic
            )
        case .workspace:
            let diagnostics = orderedWorkspaceDiagnostics
            guard !diagnostics.isEmpty else { return nil }

            if let activeWorkspaceDiagnostic,
               let currentIndex = diagnostics.firstIndex(of: activeWorkspaceDiagnostic) {
                let nextIndex = (currentIndex + step + diagnostics.count) % diagnostics.count
                return .workspace(diagnostics[nextIndex])
            }

            return .workspace(inferredWorkspaceDiagnostic(in: diagnostics) ?? diagnostics[0])
        }
    }

    // MARK: - Sorting / inference helpers

    private func sortedCurrentDiagnostics() -> [LSPDiagnostic] {
        currentTabDiagnostics.sorted { lhs, rhs in
            let lhsPosition = diagnosticSortPosition(for: lhs)
            let rhsPosition = diagnosticSortPosition(for: rhs)
            if lhsPosition.line != rhsPosition.line {
                return lhsPosition.line < rhsPosition.line
            }
            if lhsPosition.column != rhsPosition.column {
                return lhsPosition.column < rhsPosition.column
            }
            let lhsSeverity = lhs.severity?.rawValue ?? Int.max
            let rhsSeverity = rhs.severity?.rawValue ?? Int.max
            if lhsSeverity != rhsSeverity {
                return lhsSeverity < rhsSeverity
            }
            return lhs.message.localizedCaseInsensitiveCompare(rhs.message) == .orderedAscending
        }
    }

    private func diagnosticSortPosition(for diagnostic: LSPDiagnostic) -> (line: Int, column: Int) {
        (diagnostic.range.start.line, diagnostic.range.start.character)
    }

    private func compareWorkspaceDiagnostics(_ lhs: WorkspaceDiagnosticItem, _ rhs: WorkspaceDiagnosticItem) -> Bool {
        if lhs.displayPath != rhs.displayPath {
            return lhs.displayPath.localizedStandardCompare(rhs.displayPath) == .orderedAscending
        }

        if lhs.lineNumber != rhs.lineNumber {
            return lhs.lineNumber < rhs.lineNumber
        }

        if lhs.columnNumber != rhs.columnNumber {
            return lhs.columnNumber < rhs.columnNumber
        }

        let lhsSeverity = lhs.diagnostic.severity?.rawValue ?? Int.max
        let rhsSeverity = rhs.diagnostic.severity?.rawValue ?? Int.max
        if lhsSeverity != rhsSeverity {
            return lhsSeverity < rhsSeverity
        }

        return lhs.diagnostic.message.localizedCaseInsensitiveCompare(rhs.diagnostic.message) == .orderedAscending
    }

    private func currentProblemReferencePosition() -> (line: Int, column: Int) {
        let currentLine = max(currentCursorLine - 1, 0)
        let currentColumn = max(currentCursorColumn - 1, 0)
        return (line: currentLine, column: currentColumn)
    }

    private func inferredCurrentDiagnostic(in diagnostics: [LSPDiagnostic]) -> LSPDiagnostic? {
        guard !diagnostics.isEmpty else { return nil }
        let currentPosition = currentProblemReferencePosition()
        return diagnostics.last(where: { diagnostic in
            let position = diagnosticSortPosition(for: diagnostic)
            return position.line < currentPosition.line
                || (position.line == currentPosition.line && position.column <= currentPosition.column)
        }) ?? diagnostics.first
    }

    private func inferredWorkspaceDiagnostic(in diagnostics: [WorkspaceDiagnosticItem]) -> WorkspaceDiagnosticItem? {
        guard !diagnostics.isEmpty else { return nil }

        if let selectedFilePath = currentNormalizedFilePath {
            let sameFileDiagnostics = diagnostics.filter { normalize($0.fileURL) == selectedFilePath }
            if !sameFileDiagnostics.isEmpty {
                let currentPosition = currentProblemReferencePosition()
                return sameFileDiagnostics.last(where: { diagnostic in
                    let position = (line: diagnostic.lineNumber - 1, column: diagnostic.columnNumber - 1)
                    return position.line < currentPosition.line
                        || (position.line == currentPosition.line && position.column <= currentPosition.column)
                }) ?? sameFileDiagnostics.first
            }
        }

        return diagnostics.first
    }
}
