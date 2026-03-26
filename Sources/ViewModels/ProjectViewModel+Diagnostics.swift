import Foundation

extension ProjectViewModel {
    func toggleDiagnosticsPanel() {
        bottomPanel = isDiagnosticsPanelVisible ? nil : .diagnostics
        if bottomPanel == .diagnostics {
            if !canNavigateCurrentProblems && hasWorkspaceDiagnostics {
                diagnosticsPanelScope = .workspace
            }
            synchronizeActiveDiagnosticSelection()
        }
        persistDebugPreferences()
    }

    func setDiagnosticsPanelScope(_ scope: DiagnosticsPanelScope) {
        diagnosticsPanelScope = scope
        synchronizeActiveDiagnosticSelection()
    }

    func toggleReferencesPanel() {
        guard !referenceResults.isEmpty else { return }
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
        guard let diagnostic = navigatedProblem(step: 1) else { return }
        switch diagnostic {
        case .current(let item):
            openDiagnostic(item)
        case .workspace(let item):
            openWorkspaceDiagnostic(item)
        }
    }

    func openPreviousProblem() {
        guard let diagnostic = navigatedProblem(step: -1) else { return }
        switch diagnostic {
        case .current(let item):
            openDiagnostic(item)
        case .workspace(let item):
            openWorkspaceDiagnostic(item)
        }
    }

    func showReferences(_ locations: [LSPLocation]) {
        referenceResults = locations.compactMap(makeReferenceResult(for:)).sorted(by: compareReferenceResults)
        bottomPanel = .references
    }

    func closeReferencesPanel() {
        referenceResults = []
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

    private func navigatedProblem(step: Int) -> NavigableProblem? {
        switch diagnosticsPanelScope {
        case .currentFile:
            let diagnostics = orderedCurrentTabDiagnostics
            guard !diagnostics.isEmpty else { return nil }

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
                    }) ?? diagnostics.first!
                )
            }

            return .current(
                diagnostics.last(where: { diagnostic in
                    let position = diagnosticSortPosition(for: diagnostic)
                    return position.line < currentPosition.line
                        || (position.line == currentPosition.line && position.column < currentPosition.column)
                }) ?? diagnostics.last!
            )
        case .workspace:
            let diagnostics = orderedWorkspaceDiagnostics
            guard !diagnostics.isEmpty else { return nil }

            if let activeWorkspaceDiagnostic,
               let currentIndex = diagnostics.firstIndex(of: activeWorkspaceDiagnostic) {
                let nextIndex = (currentIndex + step + diagnostics.count) % diagnostics.count
                return .workspace(diagnostics[nextIndex])
            }

            return .workspace(inferredWorkspaceDiagnostic(in: diagnostics) ?? diagnostics.first!)
        }
    }
}
