import Foundation

struct ProjectSearchResult: Identifiable, Hashable {
    let filePath: URL
    let lineNumber: Int
    let lineText: String

    var id: String {
        "\(filePath.standardizedFileURL.path):\(lineNumber):\(lineText)"
    }

    var fileName: String {
        filePath.lastPathComponent
    }

    var parentDirectoryName: String {
        filePath.deletingLastPathComponent().lastPathComponent
    }
}

struct ProjectReplaceSummary: Equatable {
    let replacementCount: Int
    let modifiedFiles: [URL]
}

final class FileService {
    static let shared = FileService()

    var directoryLoadDelayPerItemNanoseconds: UInt64 = 0
    var projectSearchDelayPerFileNanoseconds: UInt64 = 0

    init() {}

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func projectFiles(at rootURL: URL, isCancelled: () -> Bool = { false }) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if isCancelled() {
                break
            }
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]),
                  resourceValues.isDirectory != true,
                  resourceValues.isRegularFile == true else {
                continue
            }
            files.append(fileURL)
        }
        return files
    }

    func loadDirectory(
        at url: URL,
        expandedPaths: Set<String> = [],
        isCancelled: () -> Bool = { false }
    ) -> [FileItem] {
        if isCancelled() {
            return []
        }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { itemURL -> FileItem? in
            if directoryLoadDelayPerItemNanoseconds > 0 {
                Thread.sleep(forTimeInterval: TimeInterval(directoryLoadDelayPerItemNanoseconds) / 1_000_000_000)
            }
            if isCancelled() {
                return nil
            }

            guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory else {
                return nil
            }

            let name = itemURL.lastPathComponent

            if isDirectory {
                let children = loadDirectory(
                    at: itemURL,
                    expandedPaths: expandedPaths,
                    isCancelled: isCancelled
                )
                return FileItem(
                    name: name,
                    path: itemURL,
                    isDirectory: true,
                    children: children,
                    isExpanded: expandedPaths.contains(normalizedPath(for: itemURL))
                )
            } else {
                return FileItem(
                    name: name,
                    path: itemURL,
                    isDirectory: false,
                    children: [],
                    isExpanded: false
                )
            }
        }.sorted { item1, item2 in
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
        }
    }

    func loadDirectoryAsync(at url: URL, expandedPaths: Set<String> = []) async throws -> [FileItem] {
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) { [self] in
            let tree = loadDirectory(at: url, expandedPaths: expandedPaths, isCancelled: { Task.isCancelled })
            try Task.checkCancellation()
            return tree
        }.value
    }

    func readFile(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            var detectedEncoding: String.Encoding = .utf8
            return try String(contentsOf: url, usedEncoding: &detectedEncoding)
        }
    }

    func writeFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func createFile(named name: String, in directory: URL) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        let didCreate = FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        guard didCreate else {
            throw CocoaError(.fileWriteUnknown)
        }
        return fileURL
    }

    func createDirectory(named name: String, in directory: URL) throws -> URL {
        let dirURL = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: false)
        return dirURL
    }

    func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func rename(from oldURL: URL, to newName: String) throws -> URL {
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        return newURL
    }

    func duplicate(at url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var copyName = "\(name) copy"
        if !ext.isEmpty {
            copyName += ".\(ext)"
        }
        let copyURL = directory.appendingPathComponent(copyName)
        try FileManager.default.copyItem(at: url, to: copyURL)
        return copyURL
    }

    func searchProject(
        at rootURL: URL,
        query: String,
        isCancelled: () -> Bool = { false }
    ) -> [ProjectSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        var results: [ProjectSearchResult] = []

        for fileURL in projectFiles(at: rootURL, isCancelled: isCancelled) {
            if isCancelled() {
                break
            }
            if projectSearchDelayPerFileNanoseconds > 0 {
                Thread.sleep(forTimeInterval: TimeInterval(projectSearchDelayPerFileNanoseconds) / 1_000_000_000)
            }
            if isCancelled() {
                break
            }
            guard let content = try? readFile(at: fileURL) else {
                continue
            }

            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.localizedCaseInsensitiveContains(normalizedQuery) {
                results.append(
                    ProjectSearchResult(
                        filePath: fileURL,
                        lineNumber: index + 1,
                        lineText: line.trimmingCharacters(in: .whitespaces)
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            let lhsPath = normalizedPath(for: lhs.filePath)
            let rhsPath = normalizedPath(for: rhs.filePath)
            if lhsPath == rhsPath {
                return lhs.lineNumber < rhs.lineNumber
            }
            return lhsPath.localizedStandardCompare(rhsPath) == .orderedAscending
        }
    }

    func searchProjectAsync(at rootURL: URL, query: String) async throws -> [ProjectSearchResult] {
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) { [self] in
            let results = searchProject(at: rootURL, query: query, isCancelled: { Task.isCancelled })
            try Task.checkCancellation()
            return results
        }.value
    }

    func replaceInProject(at rootURL: URL, searchQuery: String, replacement: String) throws -> ProjectReplaceSummary {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return ProjectReplaceSummary(replacementCount: 0, modifiedFiles: [])
        }

        var replacementCount = 0
        var modifiedFiles: [URL] = []

        for fileURL in projectFiles(at: rootURL) {
            guard let content = try? readFile(at: fileURL),
                  content.localizedCaseInsensitiveContains(normalizedQuery) else {
                continue
            }

            let matches = content.ranges(of: normalizedQuery, options: [.caseInsensitive])
            guard !matches.isEmpty else { continue }

            var updatedContent = content
            for range in matches.reversed() {
                updatedContent.replaceSubrange(range, with: replacement)
            }

            try writeFile(content: updatedContent, to: fileURL)
            replacementCount += matches.count
            modifiedFiles.append(fileURL)
        }

        return ProjectReplaceSummary(
            replacementCount: replacementCount,
            modifiedFiles: modifiedFiles.sorted {
                normalizedPath(for: $0).localizedStandardCompare(normalizedPath(for: $1)) == .orderedAscending
            }
        )
    }

    func replaceInProjectAsync(
        at rootURL: URL,
        searchQuery: String,
        replacement: String
    ) async throws -> ProjectReplaceSummary {
        try await Task.detached(priority: .utility) { [self] in
            try replaceInProject(at: rootURL, searchQuery: searchQuery, replacement: replacement)
        }.value
    }
}

private extension String {
    func ranges(of searchString: String, options: String.CompareOptions = []) -> [Range<String.Index>] {
        guard !searchString.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStartIndex = startIndex

        while searchStartIndex < endIndex,
              let range = self.range(of: searchString, options: options, range: searchStartIndex..<endIndex) {
            ranges.append(range)
            searchStartIndex = range.upperBound
        }

        return ranges
    }
}
