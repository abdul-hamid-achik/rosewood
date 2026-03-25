import Foundation

struct EditorBreadcrumbSegment: Identifiable, Hashable {
    enum Kind: Hashable {
        case root
        case directory
        case file
        case scope
    }

    let id: String
    let title: String
    let kind: Kind
    let line: Int?
}

struct EditorStickyScopeItem: Identifiable, Hashable {
    let line: Int
    let title: String

    var id: String {
        "\(line):\(title)"
    }
}

enum EditorNavigationModel {
    static func breadcrumbs(
        fileURL: URL?,
        rootURL: URL?,
        text: String,
        language: String,
        visibleTopLine: Int,
        cursorLine: Int
    ) -> [EditorBreadcrumbSegment] {
        var segments: [EditorBreadcrumbSegment] = []

        if let fileURL {
            let pathComponents = pathComponents(for: fileURL, rootURL: rootURL)
            for (index, component) in pathComponents.enumerated() {
                let kind: EditorBreadcrumbSegment.Kind
                if index == 0, rootURL != nil {
                    kind = .root
                } else if index == pathComponents.count - 1 {
                    kind = .file
                } else {
                    kind = .directory
                }

                segments.append(
                    EditorBreadcrumbSegment(
                        id: "path-\(index)-\(component)",
                        title: component,
                        kind: kind,
                        line: nil
                    )
                )
            }
        }

        for scope in stickyScopes(text: text, language: language, focusLine: max(visibleTopLine, cursorLine)) {
            segments.append(
                EditorBreadcrumbSegment(
                    id: "scope-\(scope.id)",
                    title: scope.title,
                    kind: .scope,
                    line: scope.line
                )
            )
        }

        return segments
    }

    static func stickyScopes(text: String, language: String, focusLine: Int) -> [EditorStickyScopeItem] {
        guard focusLine > 0 else { return [] }

        let lineInfos = LineInfo.parse(text)
        let regions = FoldingParser.regions(for: text, language: language)
            .filter { $0.startLine <= focusLine && $0.endLine >= focusLine }
            .sorted { lhs, rhs in
                if lhs.startLine == rhs.startLine {
                    return lhs.endLine < rhs.endLine
                }
                return lhs.startLine < rhs.startLine
            }

        return regions.compactMap { region in
            guard lineInfos.indices.contains(region.startLine - 1) else { return nil }
            let title = scopeTitle(from: lineInfos[region.startLine - 1].trimmedText)
            guard !title.isEmpty else { return nil }
            return EditorStickyScopeItem(line: region.startLine, title: title)
        }
    }

    private static func pathComponents(for fileURL: URL, rootURL: URL?) -> [String] {
        if let rootURL {
            let rootPath = rootURL.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            if filePath.hasPrefix(rootPath + "/") {
                let relativePath = String(filePath.dropFirst(rootPath.count + 1))
                return [rootURL.lastPathComponent] + relativePath.split(separator: "/").map(String.init)
            }
        }

        return fileURL.pathComponents.filter { $0 != "/" }
    }

    private static func scopeTitle(from rawText: String) -> String {
        let stripped = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s*\{$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #":$"#, with: "", options: .regularExpression)

        if stripped.count > 80 {
            return String(stripped.prefix(77)) + "..."
        }

        return stripped
    }
}
