import Foundation

enum GitChangeKind: String, CaseIterable, Equatable {
    case modified
    case added
    case deleted
    case renamed
    case copied
    case untracked
    case conflicted

    var shortLabel: String {
        switch self {
        case .modified:
            return "M"
        case .added:
            return "A"
        case .deleted:
            return "D"
        case .renamed:
            return "R"
        case .copied:
            return "C"
        case .untracked:
            return "?"
        case .conflicted:
            return "!"
        }
    }

    var explorerLabel: String {
        switch self {
        case .untracked:
            return "U"
        default:
            return shortLabel
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum GitChangeSection: String, CaseIterable, Equatable, Identifiable {
    case conflicted
    case staged
    case changes
    case untracked

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .conflicted:
            return "Conflicts"
        case .staged:
            return "Staged"
        case .changes:
            return "Changes"
        case .untracked:
            return "Untracked"
        }
    }
}

struct GitChangeSectionGroup: Equatable, Identifiable {
    let section: GitChangeSection
    let files: [GitChangedFile]

    var id: String {
        section.id
    }
}

struct GitChangedFile: Identifiable, Equatable {
    let path: String
    let previousPath: String?
    let kind: GitChangeKind
    let indexStatus: Character
    let workingTreeStatus: Character

    var id: String {
        [previousPath, path].compactMap { $0 }.joined(separator: "->")
    }

    var hasStagedChanges: Bool {
        indexStatus != " " && indexStatus != "?"
    }

    var hasUnstagedChanges: Bool {
        workingTreeStatus != " "
    }

    var canStage: Bool {
        kind == .untracked || hasUnstagedChanges
    }

    var canUnstage: Bool {
        hasStagedChanges
    }

    var canDiscard: Bool {
        kind == .untracked || hasUnstagedChanges
    }

    var section: GitChangeSection {
        if kind == .conflicted {
            return .conflicted
        }
        if kind == .untracked {
            return .untracked
        }
        if hasStagedChanges && !hasUnstagedChanges {
            return .staged
        }
        return .changes
    }

    var stateSummary: String {
        if kind == .conflicted {
            return "Conflict"
        }
        if kind == .untracked {
            return "New File"
        }

        switch (hasStagedChanges, hasUnstagedChanges) {
        case (true, true):
            return "Staged + Unstaged"
        case (true, false):
            return "Staged"
        case (false, true):
            return "Unstaged"
        case (false, false):
            return kind.displayName
        }
    }
}

struct GitRepositoryStatus: Equatable {
    let repositoryRoot: URL?
    let branchName: String?
    let changedFiles: [GitChangedFile]
    let ignoredPaths: Set<String>

    static let empty = GitRepositoryStatus(
        repositoryRoot: nil,
        branchName: nil,
        changedFiles: [],
        ignoredPaths: []
    )

    var isRepository: Bool {
        repositoryRoot != nil
    }

    var stagedCount: Int {
        changedFiles.filter {
            $0.section != .conflicted &&
                $0.section != .untracked &&
                $0.hasStagedChanges
        }.count
    }

    var unstagedCount: Int {
        changedFiles.filter {
            $0.section != .conflicted &&
                $0.section != .untracked &&
                $0.hasUnstagedChanges
        }.count
    }

    var untrackedCount: Int {
        changedFiles.filter { $0.kind == .untracked }.count
    }

    var conflictedCount: Int {
        changedFiles.filter { $0.kind == .conflicted }.count
    }

    var changeSections: [GitChangeSectionGroup] {
        GitChangeSection.allCases.compactMap { section in
            let files = changedFiles.filter { $0.section == section }
            guard !files.isEmpty else { return nil }
            return GitChangeSectionGroup(section: section, files: files)
        }
    }
}

struct GitDiffResult: Equatable {
    let path: String
    let text: String
    let hunks: [GitDiffHunk]

    init(path: String, text: String, hunks: [GitDiffHunk]? = nil) {
        self.path = path
        self.text = text
        self.hunks = hunks ?? GitDiffParser.parse(text)
    }

    var additionCount: Int {
        hunks
            .flatMap(\.rows)
            .reduce(into: 0) { count, row in
                if row.rightKind == .added {
                    count += 1
                }
            }
    }

    var deletionCount: Int {
        hunks
            .flatMap(\.rows)
            .reduce(into: 0) { count, row in
                if row.leftKind == .deleted {
                    count += 1
                }
            }
    }

    var hunkCount: Int {
        hunks.count
    }

    var hasStructuredChanges: Bool {
        !hunks.isEmpty
    }
}

struct GitDiffHunk: Equatable, Identifiable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let context: String?
    let rows: [GitDiffRow]

    var id: String {
        "\(oldStart):\(oldCount):\(newStart):\(newCount):\(context ?? "")"
    }

    var headerText: String {
        let oldRange = oldCount <= 1 ? "\(oldStart)" : "\(oldStart)-\(oldStart + oldCount - 1)"
        let newRange = newCount <= 1 ? "\(newStart)" : "\(newStart)-\(newStart + newCount - 1)"
        if let context, !context.isEmpty {
            return "Old \(oldRange) -> New \(newRange)  \(context)"
        }
        return "Old \(oldRange) -> New \(newRange)"
    }
}

struct GitDiffRow: Equatable, Identifiable {
    let leftLineNumber: Int?
    let rightLineNumber: Int?
    let leftText: String?
    let rightText: String?
    let leftKind: GitDiffLineKind
    let rightKind: GitDiffLineKind

    var id: String {
        "\(leftLineNumber.map(String.init) ?? "_"):\(rightLineNumber.map(String.init) ?? "_"):\(leftText ?? ""):\(rightText ?? ""):\(leftKind.rawValue):\(rightKind.rawValue)"
    }
}

enum GitDiffLineKind: String, Equatable {
    case context
    case added
    case deleted
    case empty
}

enum GitDiffParser {
    private static let hunkPattern = try! NSRegularExpression(
        pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:\s?(.*))?$"#
    )

    static func parse(_ text: String) -> [GitDiffHunk] {
        let lines = text.components(separatedBy: .newlines)
        var hunks: [GitDiffHunk] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard let match = parseHunkHeader(line) else {
                index += 1
                continue
            }

            index += 1
            var oldLine = match.oldStart
            var newLine = match.newStart
            var removedBuffer: [(Int, String)] = []
            var addedBuffer: [(Int, String)] = []
            var rows: [GitDiffRow] = []

            func flushBuffers() {
                let pairedCount = max(removedBuffer.count, addedBuffer.count)
                guard pairedCount > 0 else { return }

                for offset in 0..<pairedCount {
                    let removed = offset < removedBuffer.count ? removedBuffer[offset] : nil
                    let added = offset < addedBuffer.count ? addedBuffer[offset] : nil
                    rows.append(
                        GitDiffRow(
                            leftLineNumber: removed?.0,
                            rightLineNumber: added?.0,
                            leftText: removed?.1,
                            rightText: added?.1,
                            leftKind: removed == nil ? .empty : .deleted,
                            rightKind: added == nil ? .empty : .added
                        )
                    )
                }

                removedBuffer.removeAll(keepingCapacity: true)
                addedBuffer.removeAll(keepingCapacity: true)
            }

            while index < lines.count {
                let currentLine = lines[index]
                if currentLine.hasPrefix("@@"), parseHunkHeader(currentLine) != nil {
                    break
                }
                if currentLine.hasPrefix("diff --git ") {
                    break
                }
                if currentLine.hasPrefix(#"\ No newline at end of file"#) {
                    index += 1
                    continue
                }

                guard let marker = currentLine.first else {
                    flushBuffers()
                    rows.append(
                        GitDiffRow(
                            leftLineNumber: oldLine,
                            rightLineNumber: newLine,
                            leftText: "",
                            rightText: "",
                            leftKind: .context,
                            rightKind: .context
                        )
                    )
                    oldLine += 1
                    newLine += 1
                    index += 1
                    continue
                }

                switch marker {
                case " ":
                    flushBuffers()
                    let content = String(currentLine.dropFirst())
                    rows.append(
                        GitDiffRow(
                            leftLineNumber: oldLine,
                            rightLineNumber: newLine,
                            leftText: content,
                            rightText: content,
                            leftKind: .context,
                            rightKind: .context
                        )
                    )
                    oldLine += 1
                    newLine += 1
                case "-":
                    removedBuffer.append((oldLine, String(currentLine.dropFirst())))
                    oldLine += 1
                case "+":
                    addedBuffer.append((newLine, String(currentLine.dropFirst())))
                    newLine += 1
                default:
                    break
                }

                index += 1
            }

            flushBuffers()
            hunks.append(
                GitDiffHunk(
                    oldStart: match.oldStart,
                    oldCount: match.oldCount,
                    newStart: match.newStart,
                    newCount: match.newCount,
                    context: match.context,
                    rows: rows
                )
            )
        }

        return hunks
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, context: String?)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = hunkPattern.firstMatch(in: line, options: [], range: range) else {
            return nil
        }

        func intValue(at index: Int, default fallback: Int) -> Int {
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: line),
                  let value = Int(line[swiftRange]) else {
                return fallback
            }
            return value
        }

        func stringValue(at index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: line) else {
                return nil
            }

            let value = String(line[swiftRange]).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }

        let oldStart = intValue(at: 1, default: 0)
        let oldCount = intValue(at: 2, default: 1)
        let newStart = intValue(at: 3, default: 0)
        let newCount = intValue(at: 4, default: 1)

        return (
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            context: stringValue(at: 5)
        )
    }
}

struct GitBlameInfo: Equatable {
    let commitHash: String
    let shortCommitHash: String
    let author: String
    let summary: String
    let authoredDate: Date?

    var isUncommitted: Bool {
        Set(commitHash) == ["0"]
    }
}

struct GitOperationResult: Equatable {
    let isSuccess: Bool
    let message: String?

    static let success = GitOperationResult(isSuccess: true, message: nil)

    static func failure(_ message: String) -> GitOperationResult {
        GitOperationResult(isSuccess: false, message: message)
    }
}
