import Foundation

extension ProjectViewModel {
    var currentFileSymbols: [WorkspaceSymbolMatch] {
        guard let selectedFileURL = selectedTab?.filePath else { return [] }
        let selectedPath = normalizedPath(for: selectedFileURL)
        return workspaceSymbols()
            .filter { normalizedPath(for: $0.fileURL) == selectedPath }
            .sorted { lhs, rhs in
                if lhs.line == rhs.line {
                    return lhs.column < rhs.column
                }
                return lhs.line < rhs.line
            }
    }

    var activeCurrentFileSymbolID: String? {
        guard let cursorLine = selectedTab?.cursorPosition.line else { return nil }
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

    func invalidateWorkspaceSymbolCache() {
        cachedWorkspaceSymbols = nil
        cachedWorkspaceSymbolRootPath = nil
    }

    func workspaceSymbols() -> [WorkspaceSymbolMatch] {
        guard let rootDirectory else { return [] }
        let normalizedRootPath = normalizedPath(for: rootDirectory)

        if let cachedWorkspaceSymbols, cachedWorkspaceSymbolRootPath == normalizedRootPath {
            return cachedWorkspaceSymbols
        }

        var symbols: [WorkspaceSymbolMatch] = []
        symbols.reserveCapacity(flatFileList.count * 2)

        for (index, item) in flatFileList.enumerated() where !item.isDirectory {
            let fileURL = item.path
            guard WorkspaceSymbolIndexer.shouldIndex(fileURL: fileURL),
                  let contents = workspaceSymbolContents(for: fileURL) else {
                continue
            }

            symbols.append(
                contentsOf: WorkspaceSymbolIndexer.extractSymbols(
                    from: contents,
                    fileURL: fileURL,
                    displayPath: relativeDisplayPath(for: fileURL),
                    originalIndex: index
                )
            )
        }

        cachedWorkspaceSymbols = symbols
        cachedWorkspaceSymbolRootPath = normalizedRootPath
        return symbols
    }

    private func workspaceSymbolContents(for fileURL: URL) -> String? {
        if let openTab = openTabs.first(where: {
            guard let path = $0.filePath else { return false }
            return normalizedPath(for: path) == normalizedPath(for: fileURL)
        }) {
            return openTab.content
        }

        return try? fileService.readFile(at: fileURL)
    }
}
