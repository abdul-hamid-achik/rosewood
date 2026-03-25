import Foundation

struct ProjectSearchOptions: Hashable {
    var isCaseSensitive: Bool = false
    var isWholeWord: Bool = false
    var isRegularExpression: Bool = false
    var includeGlob: String = ""
    var excludeGlob: String = ""
}

struct ProjectSearchMatchRange: Hashable {
    let start: Int
    let length: Int
}

struct ProjectSearchResult: Identifiable, Hashable {
    let filePath: URL
    let lineNumber: Int
    let columnNumber: Int
    let lineText: String
    let matchRanges: [ProjectSearchMatchRange]

    var id: String {
        "\(filePath.standardizedFileURL.path):\(lineNumber):\(columnNumber):\(lineText)"
    }

    var fileName: String {
        filePath.lastPathComponent
    }

    var parentDirectoryName: String {
        filePath.deletingLastPathComponent().lastPathComponent
    }

    var matchCount: Int {
        matchRanges.count
    }
}

struct ProjectReplaceSummary: Equatable {
    let replacementCount: Int
    let modifiedFiles: [URL]
}

private struct ProjectSearchMatcher {
    let query: String
    let options: ProjectSearchOptions
    let regularExpression: NSRegularExpression?

    init?(query: String, options: ProjectSearchOptions) {
        self.query = query
        self.options = options

        guard options.isRegularExpression else {
            regularExpression = nil
            return
        }

        var pattern = query
        if options.isWholeWord {
            pattern = "\\b(?:\(pattern))\\b"
        }

        let regexOptions: NSRegularExpression.Options = options.isCaseSensitive ? [] : [.caseInsensitive]
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            return nil
        }
        regularExpression = compiled
    }

    func ranges(in text: String) -> [Range<String.Index>] {
        if let regularExpression {
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            return regularExpression.matches(in: text, options: [], range: fullRange).compactMap {
                Range($0.range, in: text)
            }
        }

        let compareOptions: String.CompareOptions = options.isCaseSensitive ? [] : [.caseInsensitive]
        let ranges = text.ranges(of: query, options: compareOptions)
        guard options.isWholeWord else { return ranges }
        return ranges.filter { isWholeWordMatch(in: text, range: $0) }
    }

    func replacingMatches(in text: String, replacement: String) -> (content: String, replacementCount: Int) {
        if let regularExpression {
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regularExpression.matches(in: text, options: [], range: fullRange)
            guard !matches.isEmpty else { return (text, 0) }
            return (
                regularExpression.stringByReplacingMatches(in: text, options: [], range: fullRange, withTemplate: replacement),
                matches.count
            )
        }

        let ranges = ranges(in: text)
        guard !ranges.isEmpty else { return (text, 0) }

        var updatedText = text
        for range in ranges.reversed() {
            updatedText.replaceSubrange(range, with: replacement)
        }
        return (updatedText, ranges.count)
    }

    private func isWholeWordMatch(in text: String, range: Range<String.Index>) -> Bool {
        let previousCharacter = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let nextCharacter = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        return !isWordCharacter(previousCharacter) && !isWordCharacter(nextCharacter)
    }

    private func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }
}

final class FileService {
    static let shared = FileService()

    var directoryLoadDelayPerItemNanoseconds: UInt64 = 0
    var projectSearchDelayPerFileNanoseconds: UInt64 = 0

    init() {}

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let filePath = normalizedPath(for: fileURL)
        let rootPath = normalizedPath(for: rootURL)
        guard filePath.hasPrefix(rootPath + "/") else { return fileURL.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func globPatterns(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func globMatches(_ pattern: String, text: String) -> Bool {
        var regexPattern = "^"
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "*" {
                let nextIndex = pattern.index(after: index)
                if nextIndex < pattern.endIndex, pattern[nextIndex] == "*" {
                    let afterWildcardIndex = pattern.index(after: nextIndex)
                    if afterWildcardIndex < pattern.endIndex, pattern[afterWildcardIndex] == "/" {
                        regexPattern += "(?:.*/)?"
                        index = pattern.index(after: afterWildcardIndex)
                    } else {
                        regexPattern += ".*"
                        index = afterWildcardIndex
                    }
                } else {
                    regexPattern += "[^/]*"
                    index = nextIndex
                }
                continue
            }

            if character == "?" {
                regexPattern += "."
                index = pattern.index(after: index)
                continue
            }

            if "\\.^$+{}[]|()".contains(character) {
                regexPattern += "\\"
            }
            regexPattern.append(character)
            index = pattern.index(after: index)
        }

        regexPattern += "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: fullRange) != nil
    }

    private func shouldSearchFile(_ fileURL: URL, rootURL: URL, options: ProjectSearchOptions) -> Bool {
        let relativePath = relativePath(for: fileURL, rootURL: rootURL)
        let includePatterns = globPatterns(from: options.includeGlob)
        let excludePatterns = globPatterns(from: options.excludeGlob)

        if !includePatterns.isEmpty, !includePatterns.contains(where: { globMatches($0, text: relativePath) }) {
            return false
        }

        if excludePatterns.contains(where: { globMatches($0, text: relativePath) }) {
            return false
        }

        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize else {
            return true
        }

        if fileSize > 1_000_000 {
            return false
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return true
        }
        defer { try? handle.close() }

        let prefix = (try? handle.read(upToCount: 1024)) ?? Data()
        return !prefix.contains(0)
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
        options: ProjectSearchOptions = ProjectSearchOptions(),
        isCancelled: () -> Bool = { false }
    ) -> [ProjectSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }
        guard let matcher = ProjectSearchMatcher(query: normalizedQuery, options: options) else {
            return []
        }

        var results: [ProjectSearchResult] = []

        for fileURL in projectFiles(at: rootURL, isCancelled: isCancelled) {
            if isCancelled() {
                break
            }
            guard shouldSearchFile(fileURL, rootURL: rootURL, options: options) else {
                continue
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
            for (index, line) in lines.enumerated() {
                let lineMatches = matcher.ranges(in: line)
                guard !lineMatches.isEmpty else { continue }

                let previewText = line.trimmingCharacters(in: .whitespaces)
                let leadingWhitespaceCount = line.distance(
                    from: line.startIndex,
                    to: line.firstIndex(where: { !$0.isWhitespace }) ?? line.endIndex
                )
                let matchRanges = lineMatches.map { matchRange in
                    let start = line.distance(from: line.startIndex, to: matchRange.lowerBound)
                    let length = line.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
                    return ProjectSearchMatchRange(
                        start: max(start - leadingWhitespaceCount, 0),
                        length: length
                    )
                }
                let firstMatchColumn = line.distance(from: line.startIndex, to: lineMatches[0].lowerBound) + 1

                results.append(
                    ProjectSearchResult(
                        filePath: fileURL,
                        lineNumber: index + 1,
                        columnNumber: firstMatchColumn,
                        lineText: previewText,
                        matchRanges: matchRanges
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            let lhsPath = normalizedPath(for: lhs.filePath)
            let rhsPath = normalizedPath(for: rhs.filePath)
            if lhsPath == rhsPath {
                if lhs.lineNumber == rhs.lineNumber {
                    return lhs.columnNumber < rhs.columnNumber
                }
                return lhs.lineNumber < rhs.lineNumber
            }
            return lhsPath.localizedStandardCompare(rhsPath) == .orderedAscending
        }
    }

    func searchProjectAsync(
        at rootURL: URL,
        query: String,
        options: ProjectSearchOptions = ProjectSearchOptions()
    ) async throws -> [ProjectSearchResult] {
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) { [self] in
            let results = searchProject(at: rootURL, query: query, options: options, isCancelled: { Task.isCancelled })
            try Task.checkCancellation()
            return results
        }.value
    }

    func replaceInProject(
        at rootURL: URL,
        searchQuery: String,
        replacement: String,
        options: ProjectSearchOptions = ProjectSearchOptions()
    ) throws -> ProjectReplaceSummary {
        try replaceMatches(
            in: projectFiles(at: rootURL).filter { shouldSearchFile($0, rootURL: rootURL, options: options) },
            searchQuery: searchQuery,
            replacement: replacement,
            options: options
        )
    }

    func replaceInFiles(
        at fileURLs: [URL],
        searchQuery: String,
        replacement: String,
        options: ProjectSearchOptions = ProjectSearchOptions()
    ) throws -> ProjectReplaceSummary {
        try replaceMatches(
            in: fileURLs,
            searchQuery: searchQuery,
            replacement: replacement,
            options: options
        )
    }

    func replaceInProjectAsync(
        at rootURL: URL,
        searchQuery: String,
        replacement: String,
        options: ProjectSearchOptions = ProjectSearchOptions()
    ) async throws -> ProjectReplaceSummary {
        try await Task.detached(priority: .utility) { [self] in
            try replaceInProject(at: rootURL, searchQuery: searchQuery, replacement: replacement, options: options)
        }.value
    }

    func replaceInFilesAsync(
        at fileURLs: [URL],
        searchQuery: String,
        replacement: String,
        options: ProjectSearchOptions = ProjectSearchOptions()
    ) async throws -> ProjectReplaceSummary {
        try await Task.detached(priority: .utility) { [self] in
            try replaceInFiles(at: fileURLs, searchQuery: searchQuery, replacement: replacement, options: options)
        }.value
    }

    func replaceSearchResults(
        _ results: [ProjectSearchResult],
        searchQuery: String,
        replacement: String,
        options: ProjectSearchOptions = ProjectSearchOptions()
    ) throws -> ProjectReplaceSummary {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty, !results.isEmpty else {
            return ProjectReplaceSummary(replacementCount: 0, modifiedFiles: [])
        }
        guard let matcher = ProjectSearchMatcher(query: normalizedQuery, options: options) else {
            return ProjectReplaceSummary(replacementCount: 0, modifiedFiles: [])
        }

        let groupedResults = Dictionary(grouping: results) { normalizedPath(for: $0.filePath) }
        var replacementCount = 0
        var modifiedFiles: [URL] = []

        for groupedResult in groupedResults.values {
            guard let fileURL = groupedResult.first?.filePath.standardizedFileURL,
                  let originalContent = try? readFile(at: fileURL) else {
                continue
            }

            var updatedContent = originalContent
            var fileReplacementCount = 0
            let targetLineNumbers = Set(groupedResult.map(\.lineNumber)).sorted(by: >)

            for lineNumber in targetLineNumbers {
                guard let lineRange = rangeForLineNumber(lineNumber, in: updatedContent) else { continue }
                let line = String(updatedContent[lineRange])
                let replacementResult = matcher.replacingMatches(in: line, replacement: replacement)
                guard replacementResult.replacementCount > 0 else { continue }

                updatedContent.replaceSubrange(lineRange, with: replacementResult.content)
                fileReplacementCount += replacementResult.replacementCount
            }

            guard fileReplacementCount > 0 else { continue }

            try writeFile(content: updatedContent, to: fileURL)
            replacementCount += fileReplacementCount
            modifiedFiles.append(fileURL)
        }

        return ProjectReplaceSummary(
            replacementCount: replacementCount,
            modifiedFiles: modifiedFiles.sorted {
                normalizedPath(for: $0).localizedStandardCompare(normalizedPath(for: $1)) == .orderedAscending
            }
        )
    }

    func replaceSearchResultsAsync(
        _ results: [ProjectSearchResult],
        searchQuery: String,
        replacement: String,
        options: ProjectSearchOptions = ProjectSearchOptions()
    ) async throws -> ProjectReplaceSummary {
        try await Task.detached(priority: .utility) { [self] in
            try replaceSearchResults(results, searchQuery: searchQuery, replacement: replacement, options: options)
        }.value
    }

    private func replaceMatches(
        in fileURLs: [URL],
        searchQuery: String,
        replacement: String,
        options: ProjectSearchOptions = ProjectSearchOptions()
    ) throws -> ProjectReplaceSummary {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return ProjectReplaceSummary(replacementCount: 0, modifiedFiles: [])
        }
        guard let matcher = ProjectSearchMatcher(query: normalizedQuery, options: options) else {
            return ProjectReplaceSummary(replacementCount: 0, modifiedFiles: [])
        }

        let uniqueFileURLs = Array(
            Dictionary(
                fileURLs.map { (normalizedPath(for: $0), $0.standardizedFileURL) },
                uniquingKeysWith: { current, _ in current }
            ).values
        )

        var replacementCount = 0
        var modifiedFiles: [URL] = []

        for fileURL in uniqueFileURLs {
            guard let content = try? readFile(at: fileURL) else {
                continue
            }

            let replacementResult = matcher.replacingMatches(in: content, replacement: replacement)
            guard replacementResult.replacementCount > 0 else { continue }

            try writeFile(content: replacementResult.content, to: fileURL)
            replacementCount += replacementResult.replacementCount
            modifiedFiles.append(fileURL)
        }

        return ProjectReplaceSummary(
            replacementCount: replacementCount,
            modifiedFiles: modifiedFiles.sorted {
                normalizedPath(for: $0).localizedStandardCompare(normalizedPath(for: $1)) == .orderedAscending
            }
        )
    }

    private func rangeForLineNumber(_ lineNumber: Int, in content: String) -> Range<String.Index>? {
        guard lineNumber > 0 else { return nil }

        var currentLineNumber = 1
        var lineStart = content.startIndex
        var index = content.startIndex

        while index < content.endIndex, currentLineNumber < lineNumber {
            if content[index].isNewline {
                currentLineNumber += 1
                lineStart = content.index(after: index)
            }
            index = content.index(after: index)
        }

        guard currentLineNumber == lineNumber else { return nil }

        var lineEnd = lineStart
        while lineEnd < content.endIndex, !content[lineEnd].isNewline {
            lineEnd = content.index(after: lineEnd)
        }

        return lineStart..<lineEnd
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
