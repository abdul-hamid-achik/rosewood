import Foundation

extension ProjectViewModel {
    var currentProjectSearchOptions: ProjectSearchOptions {
        ProjectSearchOptions(
            isCaseSensitive: projectSearchCaseSensitive,
            isWholeWord: projectSearchWholeWord,
            isRegularExpression: projectSearchUseRegex,
            includeGlob: projectSearchIncludeGlob.trimmingCharacters(in: .whitespacesAndNewlines),
            excludeGlob: projectSearchExcludeGlob.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Returns a user-facing message if the query is an invalid regular expression under the
    /// given options, mirroring how `ProjectSearchMatcher` builds the effective pattern.
    func projectSearchRegexValidationError(for query: String, options: ProjectSearchOptions) -> String? {
        guard options.isRegularExpression else { return nil }

        var pattern = query
        if options.isWholeWord {
            pattern = "\\b(?:\(pattern))\\b"
        }
        let regexOptions: NSRegularExpression.Options = options.isCaseSensitive ? [] : [.caseInsensitive]
        do {
            _ = try NSRegularExpression(pattern: pattern, options: regexOptions)
            return nil
        } catch {
            return "Invalid regular expression"
        }
    }

    func performProjectSearch() {
        projectSearchDebounceTask?.cancel()
        projectSearchTask?.cancel()
        projectSearchToken = UUID()
        let token = projectSearchToken
        let searchOptions = currentProjectSearchOptions

        guard let rootDirectory else {
            updateRipgrepToolAvailability(true)
            isSearchingProject = false
            clearProjectSearchResults()
            return
        }

        let trimmedQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            updateRipgrepToolAvailability(true)
            isSearchingProject = false
            clearProjectSearchResults()
            return
        }

        // Surface an invalid regex instead of silently returning zero results (which is
        // indistinguishable from "no matches" with the Regex toggle on).
        if let regexError = projectSearchRegexValidationError(for: trimmedQuery, options: searchOptions) {
            isSearchingProject = false
            clearProjectSearchResults()
            projectSearchRegexError = regexError
            return
        }
        // Valid query — clear any stale regex error (the query change no longer wipes results).
        projectSearchRegexError = nil

        let normalizedRootPath = normalizedPath(for: rootDirectory)
        isSearchingProject = true

        projectSearchTask = Task { [weak self, fileService] in
            guard let self else { return }

            do {
                let ripgrepAvailable = fileService.preferRipgrepProjectSearch
                    ? await fileService.ripgrepAvailableAsync()
                    : true
                let results = try await fileService.searchProjectAsync(
                    at: rootDirectory,
                    query: trimmedQuery,
                    options: searchOptions,
                    includeHidden: self.showHiddenFiles
                )
                guard !Task.isCancelled,
                      self.projectSearchToken == token,
                      self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath,
                      self.projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery,
                      self.currentProjectSearchOptions == searchOptions else {
                    return
                }
                self.updateRipgrepToolAvailability(ripgrepAvailable)
                self.updateProjectSearchResults(results, query: trimmedQuery, options: searchOptions)
                self.isSearchingProject = false
            } catch is CancellationError {
                guard self.projectSearchToken == token else { return }
                self.clearProjectSearchResults()
                self.isSearchingProject = false
            } catch {
                guard self.projectSearchToken == token else { return }
                self.clearProjectSearchResults()
                self.isSearchingProject = false
            }
        }
    }

    func replaceAllProjectResults() {
        let trimmedQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, canReplaceSelectedProjectSearchResults else { return }
        let selectedResults = selectedProjectSearchResults
        guard !selectedResults.isEmpty else { return }
        projectReplacePreview = makeProjectReplacePreview(
            results: selectedResults,
            title: "Replace Preview",
            summary: "Replace \(selectedProjectSearchMatchCount) selected match\(selectedProjectSearchMatchCount == 1 ? "" : "es") across \(selectedProjectSearchFileCount) file\(selectedProjectSearchFileCount == 1 ? "" : "s").",
            searchQuery: trimmedQuery,
            searchOptions: currentProjectSearchOptions,
            replacement: projectReplaceQuery
        )
    }

    func replaceProjectSearchFileGroup(_ group: ProjectSearchFileGroup) {
        let trimmedQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              canReplaceProjectSearchResults,
              groupedProjectSearchResults.contains(group) else { return }
        projectReplacePreview = makeProjectReplacePreview(
            results: group.results,
            title: "Replace Preview",
            summary: "Replace \(group.matchCount) current match\(group.matchCount == 1 ? "" : "es") in \(group.fileName).",
            searchQuery: trimmedQuery,
            searchOptions: currentProjectSearchOptions,
            replacement: projectReplaceQuery
        )
    }

    func cancelProjectReplacePreview() {
        clearProjectReplacePreview()
    }

    func applyProjectReplacePreview() {
        guard let projectReplacePreview else { return }

        guard resolveUnsavedChangesForProjectReplace(
            affecting: projectReplacePreview.affectedFileURLs,
            title: "Replace in Project",
            message: "Do you want to save affected files before applying this replace preview?"
        ) else {
            return
        }

        let snapshots = snapshotFiles(at: projectReplacePreview.affectedFileURLs)
        clearProjectReplacePreview()

        performProjectReplace(
            preview: projectReplacePreview,
            snapshots: snapshots
        )
    }

    func undoLastProjectReplace() {
        guard let lastProjectReplaceTransaction else { return }

        guard resolveUnsavedChangesForProjectReplace(
            affecting: lastProjectReplaceTransaction.affectedFileURLs,
            title: "Undo Project Replace",
            message: "Do you want to save affected files before restoring the previous contents?"
        ) else {
            return
        }

        replaceInProjectTask?.cancel()
        replaceInProjectToken = UUID()
        let token = replaceInProjectToken
        let normalizedRootPath = rootDirectory.map(normalizedPath(for:))
        let fileSnapshots = lastProjectReplaceTransaction.fileSnapshots
        isReplacingInProject = true

        replaceInProjectTask = Task { [weak self, fileService] in
            guard let self else { return }

            // Restore each file with its original encoding/line endings. Isolate
            // per-file failures so one un-encodable file doesn't abort the whole undo.
            let failedURLs: [URL] = await Task.detached(priority: .utility) {
                var failures: [URL] = []
                for snapshot in fileSnapshots {
                    do {
                        try fileService.writeDocument(
                            content: snapshot.originalContent,
                            metadata: snapshot.metadata,
                            to: snapshot.fileURL
                        )
                    } catch {
                        failures.append(snapshot.fileURL)
                    }
                }
                return failures
            }.value
            guard self.replaceInProjectToken == token,
                  self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath else {
                return
            }

            self.syncOpenTabs(with: fileSnapshots.map(\.fileURL))
            self.isReplacingInProject = false
            self.lastProjectReplaceTransaction = nil
            self.performProjectSearch()
            self.refreshGitState()
            if failedURLs.isEmpty {
                self.ui.alert(
                    "Replace Undone",
                    "Restored \(lastProjectReplaceTransaction.replacementCount) match\(lastProjectReplaceTransaction.replacementCount == 1 ? "" : "es") across \(lastProjectReplaceTransaction.fileCount) file\(lastProjectReplaceTransaction.fileCount == 1 ? "" : "s").",
                    .informational
                )
            } else {
                self.ui.alert(
                    "Replace Partially Undone",
                    "Restored most files, but \(failedURLs.count) file\(failedURLs.count == 1 ? "" : "s") could not be written back.",
                    .warning
                )
            }
        }
    }

    func openSearchResult(_ result: ProjectSearchResult) {
        activeProjectSearchResultID = result.id
        openFile(at: result.filePath)
        if let selectedTabIndex, openTabs.indices.contains(selectedTabIndex) {
            openTabs[selectedTabIndex].cursorPosition = CursorPosition(line: result.lineNumber, column: result.columnNumber)
            openTabs[selectedTabIndex].pendingLineJump = result.lineNumber
        }
    }

    func clearProjectSearchResults() {
        projectSearchResults = []
        projectSearchRegexError = nil
        projectSearchResultsQuery = ""
        projectSearchResultsOptions = ProjectSearchOptions()
        activeProjectSearchResultID = nil
        collapsedProjectSearchGroupIDs = []
        selectedProjectSearchResultIDs = []
        clearProjectReplacePreview()
    }

    func updateProjectSearchResults(_ results: [ProjectSearchResult], query: String, options: ProjectSearchOptions) {
        projectSearchResults = results
        projectSearchResultsQuery = query
        projectSearchResultsOptions = options
        let validGroupIDs = Set(groupedProjectSearchResults.map(\.id))
        collapsedProjectSearchGroupIDs = collapsedProjectSearchGroupIDs.intersection(validGroupIDs)
        normalizeProjectSearchVisibilityState()
        selectedProjectSearchResultIDs = Set(results.map(\.id))
        clearProjectReplacePreview()
    }

    func normalizeProjectSearchVisibilityState() {
        let visibleResults = orderedProjectSearchResults
        if let activeProjectSearchResultID,
           visibleResults.contains(where: { $0.id == activeProjectSearchResultID }) {
            return
        }

        activeProjectSearchResultID = visibleResults.first?.id
    }

    func clearProjectReplacePreview() {
        projectReplacePreview = nil
    }

    func makeProjectReplacePreview(
        results: [ProjectSearchResult],
        title: String,
        summary: String,
        searchQuery: String,
        searchOptions: ProjectSearchOptions,
        replacement: String
    ) -> ProjectReplacePreview {
        let uniqueFileURLs = Array(Set(results.map(\.filePath))).sorted { lhs, rhs in
            normalizedPath(for: lhs).localizedStandardCompare(normalizedPath(for: rhs)) == .orderedAscending
        }
        let files = uniqueFileURLs.map { fileURL in
            let fileResults = results.filter { normalizedPath(for: $0.filePath) == normalizedPath(for: fileURL) }
            return ProjectReplacePreviewFile(
                fileURL: fileURL,
                fileName: fileURL.lastPathComponent,
                displayPath: relativeDisplayPath(for: fileURL),
                matchCount: fileResults.reduce(0) { $0 + $1.matchCount }
            )
        }

        return ProjectReplacePreview(
            title: title,
            summary: summary,
            searchQuery: searchQuery,
            searchOptions: searchOptions,
            replacement: replacement,
            results: results.sorted { lhs, rhs in
                if normalizedPath(for: lhs.filePath) == normalizedPath(for: rhs.filePath) {
                    if lhs.lineNumber == rhs.lineNumber {
                        return lhs.columnNumber < rhs.columnNumber
                    }
                    return lhs.lineNumber < rhs.lineNumber
                }
                return normalizedPath(for: lhs.filePath).localizedStandardCompare(normalizedPath(for: rhs.filePath)) == .orderedAscending
            },
            files: files
        )
    }

    func snapshotFiles(at fileURLs: [URL]) -> [ProjectReplaceFileSnapshot] {
        let uniqueFileURLs = Array(Set(fileURLs)).sorted { lhs, rhs in
            normalizedPath(for: lhs).localizedStandardCompare(normalizedPath(for: rhs)) == .orderedAscending
        }

        return uniqueFileURLs.compactMap { fileURL in
            guard let openTab = openTabs.first(where: {
                guard let path = $0.filePath else { return false }
                return normalizedPath(for: path) == normalizedPath(for: fileURL)
            }) else {
                return (try? fileService.readDocument(at: fileURL)).map { document in
                    ProjectReplaceFileSnapshot(
                        fileURL: fileURL,
                        originalContent: document.content,
                        metadata: document.metadata
                    )
                }
            }

            return ProjectReplaceFileSnapshot(
                fileURL: fileURL,
                originalContent: openTab.content,
                metadata: openTab.documentMetadata
            )
        }
    }

    func resolveUnsavedChangesForProjectReplace(
        affecting fileURLs: [URL],
        title: String,
        message: String
    ) -> Bool {
        let normalizedPaths = Set(fileURLs.map(normalizedPath(for:)))
        let affectedDirtyIndices = openTabs.indices.filter { index in
            guard openTabs[index].isDirty, let filePath = openTabs[index].filePath else {
                return false
            }
            return normalizedPaths.contains(normalizedPath(for: filePath))
        }

        return resolveUnsavedChanges(for: affectedDirtyIndices, title: title, message: message)
    }

    func performProjectReplace(
        preview: ProjectReplacePreview,
        snapshots: [ProjectReplaceFileSnapshot]
    ) {
        guard !preview.results.isEmpty else { return }

        replaceInProjectTask?.cancel()
        replaceInProjectToken = UUID()
        let token = replaceInProjectToken
        let normalizedRootPath = rootDirectory.map(normalizedPath(for:))
        isReplacingInProject = true

        replaceInProjectTask = Task { [weak self, fileService] in
            guard let self else { return }

            do {
                let summary = try await fileService.replaceSearchResultsAsync(
                    preview.results,
                    searchQuery: preview.searchQuery,
                    replacement: preview.replacement,
                    options: preview.searchOptions
                )
                guard self.replaceInProjectToken == token,
                      self.rootDirectory.map(self.normalizedPath(for:)) == normalizedRootPath else {
                    return
                }

                self.syncOpenTabs(with: summary.modifiedFiles)
                self.isReplacingInProject = false
                self.lastProjectReplaceTransaction = self.makeProjectReplaceTransaction(
                    preview: preview,
                    summary: summary,
                    snapshots: snapshots
                )
                self.performProjectSearch()
                self.refreshGitState()
                if summary.replacementCount > 0 {
                    self.ui.alert(
                        "Replace Complete",
                        "Replaced \(summary.replacementCount) match\(summary.replacementCount == 1 ? "" : "es") in \(summary.modifiedFiles.count) file\(summary.modifiedFiles.count == 1 ? "" : "s").",
                        .informational
                    )
                }
            } catch {
                guard self.replaceInProjectToken == token else { return }
                self.isReplacingInProject = false
                self.ui.alert("Error", "Could not replace matches: \(error.localizedDescription)", .warning)
            }
        }
    }

    func syncOpenTabs(with fileURLs: [URL]) {
        let normalizedPaths = Set(fileURLs.map(normalizedPath(for:)))
        guard !normalizedPaths.isEmpty else { return }

        for index in openTabs.indices {
            guard let filePath = openTabs[index].filePath,
                  normalizedPaths.contains(normalizedPath(for: filePath)),
                  let content = try? fileService.readFile(at: filePath) else {
                continue
            }

            openTabs[index].content = content
            openTabs[index].originalContent = content
            openTabs[index].isDirty = false
            updateWorkspaceSymbolCache(for: filePath, contents: content)
        }

        cachedWorkspaceSymbols = nil
    }

    func handleProjectSearchQueryChange(from oldValue: String) {
        let previousQuery = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previousQuery != currentQuery else { return }

        projectSearchDebounceTask?.cancel()
        projectSearchTask?.cancel()
        projectSearchToken = UUID()
        isSearchingProject = false

        guard sidebarMode == .search, rootDirectory != nil, !currentQuery.isEmpty else {
            clearProjectSearchResults()
            return
        }
        // Keep the previous results on screen while the new query's search runs, so the panel
        // doesn't flash a full "Searching…" splash on every keystroke. New results replace them
        // when the debounced search completes.
        scheduleProjectSearch()
    }

    func handleProjectReplaceQueryChange(from oldValue: String) {
        guard oldValue != projectReplaceQuery else { return }
        clearProjectReplacePreview()
    }

    func handleProjectSearchOptionsChange<T: Equatable>(from oldValue: T, to newValue: T) {
        guard oldValue != newValue else { return }
        invalidateProjectSearchState()
    }

    func handleProjectSearchFilterChange(from oldValue: String, to newValue: String) {
        guard oldValue.trimmingCharacters(in: .whitespacesAndNewlines) != newValue.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        invalidateProjectSearchState()
    }

    func invalidateProjectSearchState() {
        projectSearchDebounceTask?.cancel()
        projectSearchTask?.cancel()
        projectSearchToken = UUID()
        isSearchingProject = false

        let currentQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sidebarMode == .search, rootDirectory != nil, !currentQuery.isEmpty else {
            clearProjectSearchResults()
            return
        }
        // Keep prior results visible while re-searching after an option/filter change.
        scheduleProjectSearch()
    }

    func handleShowHiddenFilesChange(from oldValue: Bool) {
        guard oldValue != showHiddenFiles else { return }
        reloadFileTree()

        let currentQuery = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sidebarMode == .search, rootDirectory != nil, !currentQuery.isEmpty else { return }
        performProjectSearch()
    }

    func scheduleProjectSearch() {
        projectSearchDebounceTask?.cancel()
        let query = projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        projectSearchDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.projectSearchDebounceNanoseconds ?? 0)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  let self,
                  self.sidebarMode == .search,
                  self.rootDirectory != nil,
                  self.projectSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                return
            }

            self.performProjectSearch()
        }
    }
}
