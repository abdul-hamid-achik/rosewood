import SwiftUI

struct GitDiffPanelView: View {
    let layoutStyle: GitDiffLayoutStyle

    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    @State private var presentationMode: GitDiffPresentationMode = .split
    @State private var selectedHunkIndex = 0
    @State private var scrollTargetHunkID: String?

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    init(layoutStyle: GitDiffLayoutStyle = .panel) {
        self.layoutStyle = layoutStyle
    }

    private var selectedChangedFile: GitChangedFile? {
        projectViewModel.selectedGitChangedFile
    }

    private var shouldShowFilePosition: Bool {
        projectViewModel.gitRepositoryStatus.changedFiles.count > 1
    }

    private var diffTitle: String {
        guard let path = projectViewModel.selectedGitDiffPath else { return "Diff" }
        return (path as NSString).lastPathComponent
    }

    private var diffDirectory: String {
        guard let path = projectViewModel.selectedGitDiffPath else {
            return "Review tracked changes side by side."
        }

        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "Project Root" : parent
    }

    private var diffIconName: String {
        guard let path = projectViewModel.selectedGitDiffPath else { return "doc.text" }
        return FileItem(name: (path as NSString).lastPathComponent, path: URL(fileURLWithPath: path), isDirectory: false).iconName
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .overlay(themeColors.border)

            bodyView
        }
        .frame(
            minHeight: layoutStyle == .workspace ? nil : 220,
            idealHeight: layoutStyle == .workspace ? nil : 300,
            maxHeight: layoutStyle == .workspace ? .infinity : 420
        )
        .frame(maxWidth: .infinity, maxHeight: layoutStyle == .workspace ? .infinity : nil)
        .background(layoutStyle == .workspace ? themeColors.background : themeColors.panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(layoutStyle == .workspace ? "git-diff-workspace" : "git-diff-panel")
        .onAppear {
            syncPresentationMode()
        }
        .onChange(of: projectViewModel.selectedGitDiffPath) { _, _ in
            selectedHunkIndex = 0
            syncPresentationMode()
        }
        .onChange(of: projectViewModel.selectedGitDiff) { _, _ in
            syncPresentationMode()
        }
    }

    private var headerView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: diffIconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeColors.accent)
                        .frame(width: 18, height: 18)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(diffTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeColors.foreground)
                                .lineLimit(1)
                                .accessibilityIdentifier("git-diff-panel-title")

                            if let changedFile = selectedChangedFile {
                                changeBadge(changedFile.kind.displayName, tint: badgeColor(for: changedFile.kind))
                                changeBadge(changedFile.stateSummary, tint: stateBadgeColor(for: changedFile))
                            }
                        }

                        Text(diffDirectory)
                            .font(.system(size: 11))
                            .foregroundColor(themeColors.mutedText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 10)

                if projectViewModel.selectedGitDiff == nil {
                    headerControls
                }
            }

            if let diff = projectViewModel.selectedGitDiff {
                HStack(spacing: 8) {
                    summaryView(for: diff)
                    if shouldShowFilePosition,
                       let positionText = projectViewModel.selectedGitChangePositionText {
                        statChip(positionText, tint: themeColors.mutedText)
                            .accessibilityIdentifier("git-diff-file-position")
                    }
                    Spacer(minLength: 8)
                    workspaceViewActions
                    fileNavigationView
                    workspaceGitActions
                    hunkNavigationView(for: diff)
                    headerControls
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, layoutStyle == .workspace ? 6 : 8)
        .background(layoutStyle == .workspace ? themeColors.gutterBackground : themeColors.panelBackground)
    }

    @ViewBuilder
    private var bodyView: some View {
        if projectViewModel.isLoadingGitDiff {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Loading diff...")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.subduedText)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diff = projectViewModel.selectedGitDiff {
            switch presentationMode {
            case .split where diff.hasStructuredChanges:
                splitDiffView(diff)
            case .split:
                patchView(
                    text: diff.text,
                    message: "Split view is not available for this diff. Showing the raw patch instead."
                )
            case .patch:
                patchView(text: diff.text)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 22))
                    .foregroundColor(themeColors.mutedText)
                Text("No diff available for this change.")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.subduedText)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hunkNavigationView(for diff: GitDiffResult) -> some View {
        HStack(spacing: 6) {
            if diff.hunks.count > 1 {
                Button {
                    selectedHunkIndex = max(0, selectedHunkIndex - 1)
                    scrollTargetHunkID = diff.hunks[selectedHunkIndex].id
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(themeColors.mutedText)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(selectedHunkIndex == 0)
            }

            if diff.hunks.count > 1 {
                Menu {
                    ForEach(Array(diff.hunks.enumerated()), id: \.element.id) { index, hunk in
                        Button {
                            selectedHunkIndex = index
                            scrollTargetHunkID = hunk.id
                        } label: {
                            Text("Hunk \(index + 1)  \(hunk.headerText)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Hunk \(selectedHunkIndex + 1)/\(diff.hunks.count)")
                            .font(.system(size: 11, design: .monospaced))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(themeColors.mutedText)
                    .frame(minWidth: 88, alignment: .center)
                }
                .menuStyle(.borderlessButton)
            } else {
                Text(diff.hunks.isEmpty ? "No hunks" : "1 hunk")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeColors.mutedText)
                    .frame(minWidth: 64, alignment: .center)
            }

            if diff.hunks.count > 1 {
                Button {
                    selectedHunkIndex = min(diff.hunks.count - 1, selectedHunkIndex + 1)
                    scrollTargetHunkID = diff.hunks[selectedHunkIndex].id
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(themeColors.mutedText)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(selectedHunkIndex >= diff.hunks.count - 1)
            }
        }
        .accessibilityIdentifier("git-diff-hunk-label")
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(themeColors.elevatedBackground)
        )
    }

    private func splitDiffView(_ diff: GitDiffResult) -> some View {
        GeometryReader { geometry in
            let columnWidth = max((geometry.size.width - 25) / 2, 280)
            let columnHeaderHeight: CGFloat = layoutStyle == .workspace ? 20 : 18

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    columnHeader(title: "Before", subtitle: "Committed")
                        .frame(width: columnWidth)
                        .accessibilityIdentifier("git-diff-column-before")

                    Divider()
                        .overlay(themeColors.border)

                    columnHeader(title: "After", subtitle: "Working Tree")
                        .frame(width: columnWidth)
                        .accessibilityIdentifier("git-diff-column-after")
                }
                .frame(height: columnHeaderHeight)
                .background(layoutStyle == .workspace ? themeColors.panelBackground : themeColors.gutterBackground)

                Divider()
                    .overlay(themeColors.border)

                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: layoutStyle == .workspace ? 10 : 12) {
                            ForEach(Array(diff.hunks.enumerated()), id: \.element.id) { index, hunk in
                                VStack(alignment: .leading, spacing: 8) {
                                    hunkHeader(index: index, totalHunks: diff.hunks.count, hunk: hunk)
                                        .accessibilityIdentifier("git-diff-hunk-\(index)")

                                    VStack(spacing: 0) {
                                        ForEach(hunk.rows) { row in
                                            HStack(spacing: 0) {
                                                diffCell(
                                                    lineNumber: row.leftLineNumber,
                                                    text: row.leftText,
                                                    counterpart: row.rightText,
                                                    kind: row.leftKind,
                                                    width: columnWidth
                                                )

                                                Divider()
                                                    .overlay(themeColors.border)

                                                diffCell(
                                                    lineNumber: row.rightLineNumber,
                                                    text: row.rightText,
                                                    counterpart: row.leftText,
                                                    kind: row.rightKind,
                                                    width: columnWidth
                                                )
                                            }
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(themeColors.border, lineWidth: 1)
                                    )
                                }
                                .id(hunk.id)
                            }
                        }
                        .padding(.horizontal, layoutStyle == .workspace ? 14 : 12)
                        .padding(.top, layoutStyle == .workspace ? 10 : 12)
                        .padding(.bottom, layoutStyle == .workspace ? 14 : 12)
                        .frame(
                            minWidth: columnWidth * 2 + 1,
                            maxWidth: .infinity,
                            minHeight: max(geometry.size.height - columnHeaderHeight - 1, 0),
                            alignment: .topLeading
                        )
                        .textSelection(.enabled)
                    }
                    .accessibilityIdentifier("git-diff-split-view")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        guard let firstHunk = diff.hunks.first else { return }
                        scrollTargetHunkID = firstHunk.id
                    }
                    .onChange(of: scrollTargetHunkID) { _, target in
                        guard let target else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func patchView(text: String, message: String? = nil) -> some View {
        VStack(spacing: 0) {
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(themeColors.accent)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.subduedText)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(themeColors.gutterBackground)

                Divider()
                    .overlay(themeColors.border)
            }

            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(themeColors.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .accessibilityIdentifier("git-diff-patch-view")
        }
    }

    private var fileNavigationView: some View {
        HStack(spacing: 4) {
            Button {
                projectViewModel.showPreviousGitChange()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundColor(themeColors.mutedText)
            .disabled(!projectViewModel.canShowPreviousGitChange)
            .accessibilityIdentifier("git-diff-previous-file")

            Button {
                projectViewModel.showNextGitChange()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundColor(themeColors.mutedText)
            .disabled(!projectViewModel.canShowNextGitChange)
            .accessibilityIdentifier("git-diff-next-file")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(themeColors.elevatedBackground)
        )
    }

    private var workspaceGitActions: some View {
        HStack(spacing: 6) {
            if let changedFile = projectViewModel.selectedGitChangedFile, changedFile.canStage {
                diffActionButton(
                    title: "Stage",
                    systemImage: "square.and.arrow.down",
                    tint: themeColors.success,
                    accessibilityIdentifier: "git-diff-stage"
                ) {
                    projectViewModel.stageSelectedGitChange()
                }
            }

            if let changedFile = projectViewModel.selectedGitChangedFile, changedFile.canUnstage {
                diffActionButton(
                    title: "Unstage",
                    systemImage: "arrow.uturn.backward",
                    tint: themeColors.warning,
                    accessibilityIdentifier: "git-diff-unstage"
                ) {
                    projectViewModel.unstageSelectedGitChange()
                }
            }

            if let changedFile = projectViewModel.selectedGitChangedFile, changedFile.canDiscard {
                diffActionButton(
                    title: changedFile.kind == .untracked ? "Delete" : "Revert",
                    systemImage: changedFile.kind == .untracked ? "trash" : "arrow.counterclockwise",
                    tint: themeColors.danger,
                    accessibilityIdentifier: "git-diff-discard"
                ) {
                    projectViewModel.discardSelectedGitChange()
                }
            }
        }
    }

    private var workspaceViewActions: some View {
        HStack(spacing: 6) {
            compactIconActionButton(
                title: "Open In Editor",
                systemImage: "doc.text",
                tint: themeColors.accent,
                accessibilityIdentifier: "git-diff-open-editor"
            ) {
                projectViewModel.openSelectedGitChangeInEditor()
            }

            compactIconActionButton(
                title: "Reveal In Explorer",
                systemImage: "folder",
                tint: themeColors.mutedText,
                accessibilityIdentifier: "git-diff-reveal-explorer"
            ) {
                projectViewModel.revealSelectedGitChangeInExplorer()
            }
        }
    }

    private func columnHeader(title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 999)
                .fill(title == "Before" ? themeColors.danger.opacity(0.85) : themeColors.success.opacity(0.85))
                .frame(width: 2, height: 10)

            Text(subtitle)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(themeColors.mutedText)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    private func hunkHeader(index: Int, totalHunks: Int, hunk: GitDiffHunk) -> some View {
        HStack(spacing: 8) {
            if totalHunks > 1 {
                Text("Hunk \(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(themeColors.accentStrong.opacity(0.16))
                    )
            }

            Text(hunk.headerText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeColors.subduedText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private func diffCell(lineNumber: Int?, text: String?, counterpart: String?, kind: GitDiffLineKind, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(lineNumber.map(String.init) ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(lineNumberColor(for: kind))
                .frame(width: 42, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .background(gutterBackground(for: kind))

            Divider()
                .overlay(themeColors.border.opacity(0.75))

            diffLineText(text: text, counterpart: counterpart, kind: kind)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(cellBackground(for: kind))
        }
        .frame(width: width, alignment: .leading)
    }

    private func statChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            Picker("Diff Presentation", selection: $presentationMode) {
                ForEach(GitDiffPresentationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 98)
            .disabled(projectViewModel.selectedGitDiff == nil)
            .accessibilityIdentifier("git-diff-mode-picker")

            Button {
                projectViewModel.closeGitDiffPanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.mutedText)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(themeColors.elevatedBackground)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("git-diff-panel-close")
        }
    }

    private func compactIconActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func diffActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func diffLineText(text: String?, counterpart: String?, kind: GitDiffLineKind) -> some View {
        highlightedDiffText(text: text, counterpart: counterpart, kind: kind)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(textColor(for: kind))
            .lineLimit(1)
    }

    private func summaryView(for diff: GitDiffResult) -> some View {
        HStack(spacing: 8) {
            if diff.additionCount > 0 {
                statChip("+\(diff.additionCount)", tint: themeColors.success)
            }
            if diff.deletionCount > 0 {
                statChip("-\(diff.deletionCount)", tint: themeColors.danger)
            }
            if diff.hunkCount > 1 {
                statChip("\(diff.hunkCount) hunks", tint: themeColors.accent)
            } else if diff.additionCount == 0, diff.deletionCount == 0 {
                statChip("Patch", tint: themeColors.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diff summary")
        .accessibilityValue("+\(diff.additionCount), -\(diff.deletionCount), \(diff.hunkCount) hunks")
        .accessibilityIdentifier("git-diff-summary")
    }

    private func syncPresentationMode() {
        guard let diff = projectViewModel.selectedGitDiff else { return }
        presentationMode = diff.hasStructuredChanges ? .split : .patch
        selectedHunkIndex = 0
        scrollTargetHunkID = diff.hunks.first?.id
    }

    private func lineNumberColor(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .added:
            return themeColors.success
        case .deleted:
            return themeColors.danger
        case .context:
            return themeColors.lineNumbers
        case .empty:
            return themeColors.mutedText.opacity(0.35)
        }
    }

    private func textColor(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .empty:
            return themeColors.mutedText.opacity(0.35)
        default:
            return themeColors.foreground
        }
    }

    private func badgeColor(for kind: GitChangeKind) -> Color {
        switch kind {
        case .modified:
            return themeColors.warning
        case .added, .copied:
            return themeColors.success
        case .deleted, .conflicted:
            return themeColors.danger
        case .renamed, .untracked:
            return themeColors.accent
        }
    }

    private func stateBadgeColor(for changedFile: GitChangedFile) -> Color {
        switch changedFile.section {
        case .conflicted:
            return themeColors.danger
        case .staged:
            return themeColors.success
        case .changes:
            return themeColors.warning
        case .untracked:
            return themeColors.accent
        }
    }

    private func changeBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }

    private func highlightedDiffText(text: String?, counterpart: String?, kind: GitDiffLineKind) -> Text {
        guard let text else { return Text(" ") }
        let displayText = text.isEmpty ? " " : text
        guard kind == .added || kind == .deleted,
              let counterpart,
              text != counterpart,
              let ranges = changedTextRanges(text: text, counterpart: counterpart) else {
            return Text(verbatim: displayText)
        }

        let highlightRange = NSRange(ranges.start..<ranges.end, in: text)
        var attributed = AttributedString(displayText)
        if let attributedRange = Range(highlightRange, in: attributed) {
            attributed[attributedRange].backgroundColor = inlineHighlightBackground(for: kind)
        }
        return Text(attributed)
    }

    private func changedTextRanges(text: String, counterpart: String) -> (start: String.Index, end: String.Index)? {
        let leftCharacters = Array(text)
        let rightCharacters = Array(counterpart)
        let sharedPrefixCount = zip(leftCharacters, rightCharacters).prefix { $0 == $1 }.count

        let leftSuffixCharacters = leftCharacters.dropFirst(sharedPrefixCount)
        let rightSuffixCharacters = rightCharacters.dropFirst(sharedPrefixCount)
        let sharedSuffixCount = zip(leftSuffixCharacters.reversed(), rightSuffixCharacters.reversed())
            .prefix { $0 == $1 }
            .count

        let start = text.index(text.startIndex, offsetBy: sharedPrefixCount)
        let end = text.index(text.endIndex, offsetBy: -sharedSuffixCount)

        guard start < end else { return nil }
        return (start, end)
    }

    private func inlineHighlightBackground(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .added:
            return themeColors.success.opacity(0.26)
        case .deleted:
            return themeColors.danger.opacity(0.26)
        case .context, .empty:
            return .clear
        }
    }

    private func gutterBackground(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .added:
            return themeColors.success.opacity(0.14)
        case .deleted:
            return themeColors.danger.opacity(0.14)
        case .context:
            return themeColors.gutterBackground
        case .empty:
            return themeColors.gutterBackground.opacity(0.55)
        }
    }

    private func cellBackground(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .added:
            return themeColors.success.opacity(0.12)
        case .deleted:
            return themeColors.danger.opacity(0.12)
        case .context:
            return themeColors.elevatedBackground.opacity(0.45)
        case .empty:
            return themeColors.panelBackground.opacity(0.45)
        }
    }
}

private enum GitDiffPresentationMode: String, CaseIterable, Identifiable {
    case split
    case patch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .split:
            return "Split"
        case .patch:
            return "Patch"
        }
    }
}

enum GitDiffLayoutStyle {
    case panel
    case workspace
}
