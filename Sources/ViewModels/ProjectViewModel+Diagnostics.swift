import Foundation

extension ProjectViewModel {
    func toggleDiagnosticsPanel() {
        bottomPanel = isDiagnosticsPanelVisible ? nil : .diagnostics
        if bottomPanel == .diagnostics {
            if !canNavigateCurrentProblems && hasWorkspaceDiagnostics {
                diagnosticsPanelScope = .workspace
            }
            diagnosticsModel.synchronizeActiveDiagnosticSelection()
        }
        persistDebugPreferences()
    }

    func setDiagnosticsPanelScope(_ scope: DiagnosticsPanelScope) {
        diagnosticsPanelScope = scope
        diagnosticsModel.synchronizeActiveDiagnosticSelection()
    }

    func toggleReferencesPanel() {
        guard !referencesModel.referenceResults.isEmpty else { return }
        bottomPanel = isReferencesPanelVisible ? nil : .references
    }

    func openDiagnostic(_ diagnostic: LSPDiagnostic) {
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        diagnosticsPanelScope = .currentFile
        activeCurrentDiagnosticID = diagnostic.id
        openTabs[selectedTabIndex].pendingLineJump = diagnostic.range.start.line + 1
        persistDebugPreferences()
    }

    func openWorkspaceDiagnostic(_ diagnostic: WorkspaceDiagnosticItem) {
        diagnosticsPanelScope = .workspace
        activeWorkspaceDiagnosticID = diagnostic.id
        openFile(at: diagnostic.fileURL)
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        activeCurrentDiagnosticID = diagnostic.diagnostic.id
        openTabs[selectedTabIndex].pendingLineJump = diagnostic.lineNumber
        persistDebugPreferences()
    }

    func openNextProblem() {
        guard let diagnostic = diagnosticsModel.navigatedProblem(step: 1) else { return }
        switch diagnostic {
        case .current(let item):
            openDiagnostic(item)
        case .workspace(let item):
            openWorkspaceDiagnostic(item)
        }
    }

    func openPreviousProblem() {
        guard let diagnostic = diagnosticsModel.navigatedProblem(step: -1) else { return }
        switch diagnostic {
        case .current(let item):
            openDiagnostic(item)
        case .workspace(let item):
            openWorkspaceDiagnostic(item)
        }
    }

    /// Open the references panel in a loading state the instant the request starts, so the user
    /// gets immediate feedback rather than waiting on the language server with no indication.
    func beginFindReferences() {
        referencesModel.referenceResults = []
        referencesModel.isSearching = true
        bottomPanel = .references
    }

    func showReferences(_ locations: [LSPLocation]) {
        referencesModel.referenceResults = locations.compactMap(makeReferenceResult(for:)).sorted(by: compareReferenceResults)
        referencesModel.isSearching = false
        bottomPanel = .references
    }

    func closeReferencesPanel() {
        referencesModel.referenceResults = []
        referencesModel.isSearching = false
        if isReferencesPanelVisible {
            bottomPanel = nil
        }
    }

    func openReferenceResult(_ result: ReferenceResult) {
        openFile(at: result.fileURL)
        guard let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) else { return }
        guard let selectedFilePath = openTabs[selectedTabIndex].filePath,
              normalizedPath(for: selectedFilePath) == normalizedPath(for: result.fileURL) else {
            return
        }
        openTabs[selectedTabIndex].pendingLineJump = result.line
    }
}
