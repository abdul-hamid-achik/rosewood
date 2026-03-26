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

    private func projectFiles(
        at rootURL: URL,
        includeHidden: Bool = false,
        isCancelled: () -> Bool = { false }
    ) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .nameKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
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
        includeHidden: Bool = false,
        isCancelled: () -> Bool = { false }
    ) -> [FileItem] {
        if isCancelled() {
            return []
        }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
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
                    includeHidden: includeHidden,
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

    func loadDirectoryAsync(
        at url: URL,
        expandedPaths: Set<String> = [],
        includeHidden: Bool = false
    ) async throws -> [FileItem] {
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) { [self] in
            let tree = loadDirectory(
                at: url,
                expandedPaths: expandedPaths,
                includeHidden: includeHidden,
                isCancelled: { Task.isCancelled }
            )
            try Task.checkCancellation()
            return tree
        }.value
    }

    func readFile(at url: URL) throws -> String {
        try readDocument(at: url).content
    }

    func readDocument(at url: URL) throws -> (content: String, metadata: FileDocumentMetadata) {
        let data = try Data(contentsOf: url)

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return (
                content,
                FileDocumentMetadata(
                    encoding: .utf8,
                    lineEnding: LineEndingStyle.detect(in: content)
                )
            )
        } catch {
            var detectedEncoding: String.Encoding = .utf8
            let content = try String(contentsOf: url, usedEncoding: &detectedEncoding)
            return (
                content,
                FileDocumentMetadata(
                    encoding: detectedEncoding,
                    lineEnding: detectLineEnding(in: content, data: data, encoding: detectedEncoding)
                )
            )
        }
    }

    func writeFile(content: String, to url: URL) throws {
        try writeDocument(content: content, metadata: .utf8LF, to: url)
    }

    func writeDocument(content: String, metadata: FileDocumentMetadata, to url: URL) throws {
        let normalizedContent = normalized(content: content, lineEnding: metadata.lineEnding)
        guard let data = normalizedContent.data(using: metadata.encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        try data.write(to: url, options: .atomic)
    }

    func detectContentType(at url: URL, settings: AppSettings.FileHandling) -> ContentType {
        let fileExtension = url.pathExtension.lowercased()
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let prefixData = readPrefixData(at: url)
        let imageFormat = detectedImageFormat(for: url, fileExtension: fileExtension, prefixData: prefixData)

        if let imageFormat {
            let imageSizeLimit = settings.imageSizeLimitMB * 1_048_576
            return fileSize > imageSizeLimit ? .excluded(reason: .tooLarge) : .image(format: imageFormat)
        }

        let binaryDetection = isBinary(prefixData: prefixData, fileExtension: fileExtension)
        if binaryDetection {
            if settings.excludedBinaryExtensions.contains(fileExtension) {
                return .excluded(reason: .excludedExtension)
            }

            if fileSize <= settings.binarySizeHexKB * 1024 {
                return .binary(viewer: .hex)
            }

            if fileSize > settings.binarySizeWarningKB * 1024 {
                return .binary(viewer: .external)
            }

            return .binary(viewer: .placeholder)
        }

        if fileSize > settings.textSizeLimitKB * 1024 {
            return .excluded(reason: .tooLarge)
        }

        return .text(isLarge: fileSize >= settings.textSizeWarningKB * 1024)
    }

    func readFileAsData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func readFileAsText(at url: URL, maxSize: Int) throws -> String? {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize <= maxSize else { return nil }
        return try readDocument(at: url).content
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
        includeHidden: Bool = false,
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

        for fileURL in projectFiles(at: rootURL, includeHidden: includeHidden, isCancelled: isCancelled) {
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
        options: ProjectSearchOptions = ProjectSearchOptions(),
        includeHidden: Bool = false
    ) async throws -> [ProjectSearchResult] {
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) { [self] in
            let results = searchProject(
                at: rootURL,
                query: query,
                options: options,
                includeHidden: includeHidden,
                isCancelled: { Task.isCancelled }
            )
            try Task.checkCancellation()
            return results
        }.value
    }

    func replaceInProject(
        at rootURL: URL,
        searchQuery: String,
        replacement: String,
        options: ProjectSearchOptions = ProjectSearchOptions(),
        includeHidden: Bool = false
    ) throws -> ProjectReplaceSummary {
        try replaceMatches(
            in: projectFiles(at: rootURL, includeHidden: includeHidden).filter { shouldSearchFile($0, rootURL: rootURL, options: options) },
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
                  let document = try? readDocument(at: fileURL) else {
                continue
            }

            var updatedContent = document.content
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

            try writeDocument(content: updatedContent, metadata: document.metadata, to: fileURL)
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
            guard let document = try? readDocument(at: fileURL) else {
                continue
            }

            let replacementResult = matcher.replacingMatches(in: document.content, replacement: replacement)
            guard replacementResult.replacementCount > 0 else { continue }

            try writeDocument(content: replacementResult.content, metadata: document.metadata, to: fileURL)
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

private extension FileService {
    private static let imageSignatures: [ImageFormat: [UInt8]] = [
        .png: [0x89, 0x50, 0x4E, 0x47],
        .jpg: [0xFF, 0xD8, 0xFF],
        .gif: [0x47, 0x49, 0x46, 0x38],
        .bmp: [0x42, 0x4D],
        .pdf: [0x25, 0x50, 0x44, 0x46],
        .tiff: [0x49, 0x49, 0x2A, 0x00],
        .heic: [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]
    ]

    private static let imageExtensionMap: [String: ImageFormat] = [
        "png": .png,
        "jpg": .jpg,
        "jpeg": .jpg,
        "gif": .gif,
        "svg": .svg,
        "webp": .webp,
        "bmp": .bmp,
        "ico": .ico,
        "icns": .ico,
        "tif": .tiff,
        "tiff": .tiff,
        "heic": .heic,
        "heif": .heic,
        "raw": .raw,
        "pdf": .pdf,
        "eps": .eps
    ]

    private static let likelyTextExtensions: Set<String> = [
        "txt", "md", "markdown", "swift", "py", "rb", "js", "jsx", "ts", "tsx",
        "go", "rs", "json", "yaml", "yml", "toml", "xml", "html", "css", "scss",
        "sql", "sh", "bash", "zsh", "fish", "c", "h", "m", "mm", "cpp", "cc",
        "cxx", "hpp", "hh", "java", "kt", "kts", "dart", "lua", "r", "scala",
        "zig", "php", "pl", "ini", "cfg", "conf", "log", "env", "gitignore"
    ]

    func detectedImageFormat(for url: URL, fileExtension: String, prefixData: Data?) -> ImageFormat? {
        if fileExtension == "webp",
           let prefixData,
           prefixData.starts(with: [0x52, 0x49, 0x46, 0x46]),
           prefixData.dropFirst(8).starts(with: [0x57, 0x45, 0x42, 0x50]) {
            return .webp
        }

        if let prefixData {
            let prefixBytes = Array(prefixData)
            for (format, signature) in Self.imageSignatures where prefixBytes.starts(with: signature) {
                return format
            }
        }

        return Self.imageExtensionMap[fileExtension]
    }

    func readPrefixData(at url: URL, count: Int = 512) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }

    func isBinary(prefixData: Data?, fileExtension: String) -> Bool {
        if Self.likelyTextExtensions.contains(fileExtension) {
            return false
        }

        guard let prefixData, !prefixData.isEmpty else {
            return false
        }

        if prefixData.contains(0) {
            return true
        }

        let prefixBytes = Array(prefixData.prefix(256))
        let nonTextCount = prefixBytes.filter { byte in
            switch byte {
            case 0x09, 0x0A, 0x0D, 0x20...0x7E:
                return false
            default:
                return true
            }
        }.count

        let binaryRatio = Double(nonTextCount) / Double(max(prefixBytes.count, 1))
        return binaryRatio > 0.18
    }

    func detectLineEnding(in content: String, data: Data, encoding: String.Encoding) -> LineEndingStyle {
        let textBasedLineEnding = LineEndingStyle.detect(in: content)
        if textBasedLineEnding != .lf || !content.contains("\n") {
            return textBasedLineEnding
        }

        let byteOrderMarkAwareData: Data
        switch encoding {
        case .utf16LittleEndian, .utf16:
            byteOrderMarkAwareData = data
        default:
            byteOrderMarkAwareData = data
        }

        if byteOrderMarkAwareData.windows(ofCount: 2).contains(where: { $0.elementsEqual([0x0D, 0x0A]) }) {
            return .crlf
        }

        if byteOrderMarkAwareData.contains(0x0D) && !byteOrderMarkAwareData.contains(0x0A) {
            return .cr
        }

        return textBasedLineEnding
    }

    func normalized(content: String, lineEnding: LineEndingStyle) -> String {
        let unixNormalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard lineEnding != .lf else {
            return unixNormalized
        }

        return unixNormalized.replacingOccurrences(of: "\n", with: lineEnding.sequence)
    }
}

private extension Data {
    func windows(ofCount count: Int) -> [ArraySlice<UInt8>] {
        let bytes = Array(self)
        guard bytes.count >= count else { return [] }
        return (0...(bytes.count - count)).map { index in
            bytes[index..<(index + count)]
        }
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
