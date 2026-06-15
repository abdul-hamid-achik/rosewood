import Foundation

extension ProjectViewModel {
    var currentFileSymbols: [WorkspaceSymbolMatch] {
        guard let selectedFileURL = selectedTab?.filePath else { return [] }
        return workspaceSymbols(for: selectedFileURL)
            .sorted { lhs, rhs in
                if lhs.line == rhs.line {
                    return lhs.column < rhs.column
                }
                return lhs.line < rhs.line
            }
    }

    var activeCurrentFileSymbolID: String? {
        guard let cursorLine = liveSelectedTabCursorPosition()?.line else { return nil }
        return currentFileSymbols.last(where: { $0.line <= cursorLine })?.id
    }

    func openWorkspaceSymbol(_ symbol: WorkspaceSymbolMatch) {
        if let selectedFilePath = selectedTab?.filePath,
           normalizedPath(for: selectedFilePath) == normalizedPath(for: symbol.fileURL) {
            jumpToLineInSelectedTab(symbol.line)
            return
        }

        openFile(at: symbol.fileURL)
        jumpToLineInSelectedTab(symbol.line)
    }

    func invalidateWorkspaceSymbolCache(for fileURL: URL? = nil) {
        cachedWorkspaceSymbols = nil

        guard let fileURL else {
            cachedWorkspaceSymbolRootPath = nil
            cachedWorkspaceSymbolsByPath = [:]
            workspaceSymbolIndexTask?.cancel()
            return
        }

        cachedWorkspaceSymbolsByPath.removeValue(forKey: normalizedPath(for: fileURL))
    }

    func workspaceSymbols() -> [WorkspaceSymbolMatch] {
        guard let rootDirectory else { return [] }
        let normalizedRootPath = normalizedPath(for: rootDirectory)

        if let cachedWorkspaceSymbols, cachedWorkspaceSymbolRootPath == normalizedRootPath {
            return cachedWorkspaceSymbols
        }

        cachedWorkspaceSymbolRootPath = normalizedRootPath
        let workspaceFiles = availableWorkspaceFileURLs
        var symbols: [WorkspaceSymbolMatch] = []
        symbols.reserveCapacity(workspaceFiles.count * 2)

        let workspacePaths = Set(workspaceFiles.map(normalizedPath(for:)))
        cachedWorkspaceSymbolsByPath = cachedWorkspaceSymbolsByPath.filter { workspacePaths.contains($0.key) }

        for (index, fileURL) in workspaceFiles.enumerated() {
            symbols.append(contentsOf: workspaceSymbols(for: fileURL, originalIndex: index))
        }

        cachedWorkspaceSymbols = symbols
        return symbols
    }

    func scheduleWorkspaceSymbolIndexRefresh() {
        workspaceSymbolIndexTask?.cancel()
        workspaceSymbolIndexToken = UUID()
        let token = workspaceSymbolIndexToken

        guard let rootDirectory else { return }
        let normalizedRootPath = normalizedPath(for: rootDirectory)
        let workspaceFiles = availableWorkspaceFileURLs.enumerated().map { index, fileURL in
            WorkspaceSymbolIndexEntry(
                fileURL: fileURL,
                normalizedPath: normalizedPath(for: fileURL),
                displayPath: relativeDisplayPath(for: fileURL),
                originalIndex: index
            )
        }
        let openTabContents = Dictionary(uniqueKeysWithValues: openTabs.compactMap { tab -> (String, String)? in
            guard let filePath = tab.filePath, tab.contentType.isText else { return nil }
            return (normalizedPath(for: filePath), liveContent(forTabID: tab.id) ?? tab.content)
        })

        workspaceSymbolIndexTask = Task { [weak self] in
            let indexedSymbols = await Task.detached(priority: .utility) {
                workspaceFiles.reduce(into: [String: [WorkspaceSymbolMatch]]()) { partialResult, entry in
                    guard WorkspaceSymbolIndexer.shouldIndex(fileURL: entry.fileURL) else { return }
                    let contents = openTabContents[entry.normalizedPath] ?? (try? String(contentsOf: entry.fileURL, encoding: .utf8))
                    guard let contents else { return }
                    partialResult[entry.normalizedPath] = WorkspaceSymbolIndexer.extractSymbols(
                        from: contents,
                        fileURL: entry.fileURL,
                        displayPath: entry.displayPath,
                        originalIndex: entry.originalIndex
                    )
                }
            }.value

            guard let self,
                  !Task.isCancelled,
                  self.workspaceSymbolIndexToken == token,
                  self.cachedWorkspaceSymbolRootPath == normalizedRootPath else {
                return
            }

            self.cachedWorkspaceSymbolsByPath.merge(indexedSymbols) { _, new in new }
            self.cachedWorkspaceSymbols = workspaceFiles.flatMap { entry in
                self.workspaceSymbols(for: entry.fileURL, originalIndex: entry.originalIndex)
            }
        }
    }

    /// Debounced, off-main variant of `updateWorkspaceSymbolCache` for the typing hot path.
    /// `WorkspaceSymbolIndexer.extractSymbols` re-parses the whole document, so running it
    /// synchronously on every keystroke adds latency; instead we coalesce edits and extract
    /// on a background priority, then publish the result.
    func scheduleWorkspaceSymbolCacheUpdate(for fileURL: URL, contents: String) {
        workspaceSymbolUpdateTask?.cancel()

        let normalizedFilePath = normalizedPath(for: fileURL)
        guard let originalIndex = availableWorkspaceFileURLs.firstIndex(where: {
            normalizedPath(for: $0) == normalizedFilePath
        }) else {
            invalidateWorkspaceSymbolCache(for: fileURL)
            return
        }

        guard WorkspaceSymbolIndexer.shouldIndex(fileURL: fileURL) else {
            cachedWorkspaceSymbolsByPath.removeValue(forKey: normalizedFilePath)
            cachedWorkspaceSymbols = nil
            return
        }

        let displayPath = relativeDisplayPath(for: fileURL)

        workspaceSymbolUpdateTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.workspaceSymbolUpdateDebounceNanoseconds ?? 0)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let symbols = await Task.detached(priority: .utility) {
                WorkspaceSymbolIndexer.extractSymbols(
                    from: contents,
                    fileURL: fileURL,
                    displayPath: displayPath,
                    originalIndex: originalIndex
                )
            }.value

            guard let self, !Task.isCancelled else { return }
            self.cachedWorkspaceSymbolsByPath[normalizedFilePath] = symbols
            self.cachedWorkspaceSymbols = nil
            // The symbols feed the outline sidebar (its only consumer). Bump the outline child rather
            // than the view model, so this ~250ms-debounced refresh re-renders ONLY the outline, not
            // every view observing ProjectViewModel while the user types.
            self.outlineModel.revision &+= 1
        }
    }

    func updateWorkspaceSymbolCache(for fileURL: URL, contents: String) {
        let normalizedFilePath = normalizedPath(for: fileURL)
        guard availableWorkspaceFileURLs.contains(where: { normalizedPath(for: $0) == normalizedFilePath }) else {
            invalidateWorkspaceSymbolCache(for: fileURL)
            return
        }

        guard let originalIndex = availableWorkspaceFileURLs.firstIndex(where: { normalizedPath(for: $0) == normalizedFilePath }) else {
            invalidateWorkspaceSymbolCache(for: fileURL)
            return
        }

        guard WorkspaceSymbolIndexer.shouldIndex(fileURL: fileURL) else {
            cachedWorkspaceSymbolsByPath.removeValue(forKey: normalizedFilePath)
            cachedWorkspaceSymbols = nil
            return
        }

        cachedWorkspaceSymbolsByPath[normalizedFilePath] = WorkspaceSymbolIndexer.extractSymbols(
            from: contents,
            fileURL: fileURL,
            displayPath: relativeDisplayPath(for: fileURL),
            originalIndex: originalIndex
        )
        cachedWorkspaceSymbols = nil
    }

    private func workspaceSymbols(for fileURL: URL, originalIndex: Int? = nil) -> [WorkspaceSymbolMatch] {
        let normalizedFilePath = normalizedPath(for: fileURL)
        let resolvedOriginalIndex = originalIndex
            ?? availableWorkspaceFileURLs.firstIndex(where: { normalizedPath(for: $0) == normalizedFilePath })
            ?? 0

        if let cached = cachedWorkspaceSymbolsByPath[normalizedFilePath] {
            return cached.map {
                WorkspaceSymbolMatch(
                    name: $0.name,
                    kind: $0.kind,
                    fileURL: $0.fileURL,
                    displayPath: $0.displayPath,
                    line: $0.line,
                    column: $0.column,
                    lineText: $0.lineText,
                    originalIndex: resolvedOriginalIndex
                )
            }
        }

        guard WorkspaceSymbolIndexer.shouldIndex(fileURL: fileURL),
              let contents = workspaceSymbolContents(for: fileURL) else {
            return []
        }

        let symbols = WorkspaceSymbolIndexer.extractSymbols(
            from: contents,
            fileURL: fileURL,
            displayPath: relativeDisplayPath(for: fileURL),
            originalIndex: resolvedOriginalIndex
        )
        cachedWorkspaceSymbolsByPath[normalizedFilePath] = symbols
        return symbols
    }

    private func workspaceSymbolContents(for fileURL: URL) -> String? {
        if let openTab = openTabs.first(where: {
            guard let path = $0.filePath else { return false }
            return normalizedPath(for: path) == normalizedPath(for: fileURL)
        }) {
            return liveContent(forTabID: openTab.id) ?? openTab.content
        }

        return try? fileService.readFile(at: fileURL)
    }
}

private struct WorkspaceSymbolIndexEntry: Sendable {
    let fileURL: URL
    let normalizedPath: String
    let displayPath: String
    let originalIndex: Int
}
