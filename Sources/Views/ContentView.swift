import SwiftUI

struct ContentView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        configuredContent
    }

    private var configuredContent: some View {
        shellView
            .sheet(isPresented: $projectViewModel.showNewFileSheet) {
                NewItemSheet(title: "New File", placeholder: "filename.py") { name in
                    projectViewModel.createNewFile(named: name)
                }
            }
            .sheet(isPresented: $projectViewModel.showNewFolderSheet) {
                NewItemSheet(title: "New Folder", placeholder: "folder name") { name in
                    projectViewModel.createNewFolder(named: name)
                }
            }
            .sheet(isPresented: $projectViewModel.showSettings) {
                SettingsView()
            }
            .overlay {
                if let item = projectViewModel.renameItem {
                    RenameSheet(item: item) { newName in
                        projectViewModel.renameItem(item, to: newName)
                        projectViewModel.renameItem = nil
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleNewFile)) { _ in
                projectViewModel.createNewFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleOpenFolder)) { _ in
                projectViewModel.openFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleSave)) { _ in
                projectViewModel.saveCurrentFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleQuickOpen)) { _ in
                projectViewModel.toggleQuickOpen()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleCommandPalette)) { _ in
                projectViewModel.toggleCommandPalette()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleToggleProblems)) { _ in
                guard projectViewModel.canShowProblemsPanel else { return }
                projectViewModel.toggleDiagnosticsPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleCloseTab)) { _ in
                if let index = projectViewModel.selectedTabIndex {
                    projectViewModel.closeTab(at: index)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleProjectSearch)) { _ in
                projectViewModel.showSearchSidebar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleGoToLine)) { _ in
                projectViewModel.beginGoToLine()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleFindNext)) { _ in
                guard projectViewModel.canNavigateProjectSearchResults else { return }
                projectViewModel.showNextProjectSearchResult()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleFindPrevious)) { _ in
                guard projectViewModel.canNavigateProjectSearchResults else { return }
                projectViewModel.showPreviousProjectSearchResult()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handleNextProblem)) { _ in
                projectViewModel.openNextProblem()
            }
            .onReceive(NotificationCenter.default.publisher(for: .handlePreviousProblem)) { _ in
                projectViewModel.openPreviousProblem()
            }
    }

    private var shellView: some View {
        VStack(spacing: 0) {
            ToolbarView()

            HSplitView {
                sidebarView
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 400)

                VStack(spacing: 0) {
                    editorArea
                        .frame(minWidth: 400)

                    if let bottomPanel = projectViewModel.bottomPanel {
                        Divider()
                            .overlay(themeColors.border)
                        bottomPanelView(bottomPanel)
                    }
                }
            }

            StatusBarView()
        }
        .frame(minWidth: 800, minHeight: 600)
        .overlay {
            if let paletteMode = projectViewModel.activePalette {
                CommandPaletteView(mode: paletteMode)
            }
        }
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            sidebarHeaderView

            Divider()
                .overlay(themeColors.border)

            if projectViewModel.sidebarMode == .search {
                SearchSidebarView()
            } else if projectViewModel.sidebarMode == .sourceControl {
                SourceControlSidebarView()
            } else if projectViewModel.sidebarMode == .debug {
                DebugSidebarView()
            } else if projectViewModel.fileTree.isEmpty {
                emptyStateView
            } else {
                FileTreeView(items: projectViewModel.fileTree)
            }
        }
        .background(themeColors.panelBackground)
    }

    private var sidebarHeaderView: some View {
        HStack(spacing: 8) {
            Picker("Sidebar", selection: $projectViewModel.sidebarMode) {
                Text("Explorer").tag(ProjectViewModel.SidebarMode.explorer)
                Text("Search").tag(ProjectViewModel.SidebarMode.search)
                Text("Git").tag(ProjectViewModel.SidebarMode.sourceControl)
                Text("Debug").tag(ProjectViewModel.SidebarMode.debug)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("sidebar-mode-picker")

            if projectViewModel.sidebarMode == .explorer {
                Menu {
                    Button("New File") {
                        projectViewModel.showNewFileSheet = true
                    }
                    Button("New Folder") {
                        projectViewModel.showNewFolderSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                        .foregroundColor(themeColors.mutedText)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(themeColors.panelBackground)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(themeColors.mutedText)
            Text("No Folder Open")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeColors.subduedText)
            Button("Open Folder") {
                projectViewModel.openFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(themeColors.accentStrong)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            if !projectViewModel.openTabs.isEmpty {
                TabBarView()
                Divider()
                    .overlay(themeColors.border)
            }

            if projectViewModel.isGitDiffWorkspaceVisible {
                GitDiffPanelView(layoutStyle: .workspace)
            } else if let tab = projectViewModel.selectedTab {
                EditorView(tab: tab)
            } else {
                emptyEditorView
            }
        }
        .background(themeColors.background)
    }

    private var emptyEditorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(themeColors.mutedText.opacity(0.8))
            Text("Select a file to edit")
                .font(.system(size: 16))
                .foregroundColor(themeColors.subduedText)
            Text("or press ⌘O to open a folder")
                .font(.system(size: 13))
                .foregroundColor(themeColors.mutedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeColors.background)
    }

    @ViewBuilder
    private func bottomPanelView(_ panel: ProjectViewModel.BottomPanelKind) -> some View {
        switch panel {
        case .debugConsole:
            DebugPanelView()
        case .diagnostics:
            ProblemsPanelView()
        case .references:
            ReferencesPanelView()
        case .gitDiff:
            GitDiffPanelView()
        }
    }
}

struct SearchSidebarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(themeColors.mutedText)

                        TextField("Search in project", text: $projectViewModel.projectSearchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onSubmit {
                                projectViewModel.performProjectSearch()
                            }
                            .onKeyPress { event in
                                switch event.key {
                                case .upArrow:
                                    guard !projectViewModel.orderedProjectSearchResults.isEmpty else { return .ignored }
                                    projectViewModel.moveActiveProjectSearchResult(-1)
                                    return .handled
                                case .downArrow:
                                    guard !projectViewModel.orderedProjectSearchResults.isEmpty else { return .ignored }
                                    projectViewModel.moveActiveProjectSearchResult(1)
                                    return .handled
                                case .return:
                                    guard projectViewModel.projectReplacePreview == nil,
                                          projectViewModel.activeProjectSearchResult != nil else { return .ignored }
                                    projectViewModel.openActiveProjectSearchResult()
                                    return .handled
                                default:
                                    return .ignored
                                }
                            }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(themeColors.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button("Find") {
                        projectViewModel.performProjectSearch()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(themeColors.accent)
                }

                HStack(spacing: 8) {
                    Toggle("Case", isOn: $projectViewModel.projectSearchCaseSensitive)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .accessibilityIdentifier("project-search-case-sensitive")

                    Toggle("Word", isOn: $projectViewModel.projectSearchWholeWord)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .accessibilityIdentifier("project-search-whole-word")

                    Toggle("Regex", isOn: $projectViewModel.projectSearchUseRegex)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .accessibilityIdentifier("project-search-regex")

                    Spacer()
                }

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(themeColors.mutedText)

                        TextField("Include glob", text: $projectViewModel.projectSearchIncludeGlob)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .accessibilityIdentifier("project-search-include-glob")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(themeColors.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(themeColors.mutedText)

                        TextField("Exclude glob", text: $projectViewModel.projectSearchExcludeGlob)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .accessibilityIdentifier("project-search-exclude-glob")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(themeColors.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(themeColors.mutedText)

                        TextField("Replace with", text: $projectViewModel.projectReplaceQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(themeColors.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button(projectViewModel.replaceAllProjectResultsTitle) {
                        projectViewModel.replaceAllProjectResults()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(themeColors.warning)
                    .disabled(!projectViewModel.canReplaceSelectedProjectSearchResults)
                    .accessibilityIdentifier("project-search-replace-all")

                    if projectViewModel.canUndoLastProjectReplace {
                        Button(projectViewModel.undoLastProjectReplaceTitle) {
                            projectViewModel.undoLastProjectReplace()
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(themeColors.accent)
                        .disabled(!projectViewModel.canUndoLastProjectReplace)
                        .accessibilityIdentifier("project-replace-undo")
                    }
                }

                if projectViewModel.canReplaceProjectSearchResults {
                    Text("\(projectViewModel.selectedProjectSearchMatchCount) selected in \(projectViewModel.selectedProjectSearchFileCount) file\(projectViewModel.selectedProjectSearchFileCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !projectViewModel.projectSearchResults.isEmpty {
                    Text(projectViewModel.projectSearchVisibilitySummary)
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("project-search-visible-summary")

                    HStack(spacing: 8) {
                        if projectViewModel.canCollapseProjectSearchGroups {
                            Button("Collapse All") {
                                projectViewModel.collapseAllProjectSearchGroups()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(themeColors.accent)
                            .accessibilityIdentifier("project-search-collapse-all")
                        }

                        if projectViewModel.canExpandProjectSearchGroups {
                            Button("Expand All") {
                                projectViewModel.expandAllProjectSearchGroups()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(themeColors.accent)
                            .accessibilityIdentifier("project-search-expand-all")
                        }

                        Spacer()
                    }
                }

                if let projectReplacePreview = projectViewModel.projectReplacePreview {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(projectReplacePreview.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(themeColors.foreground)

                                Text(projectReplacePreview.summary)
                                    .font(.system(size: 11))
                                    .foregroundColor(themeColors.mutedText)
                            }
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Text("\"\(projectReplacePreview.searchQuery)\"")
                                .foregroundColor(themeColors.accent)
                            Image(systemName: "arrow.right")
                                .foregroundColor(themeColors.mutedText)
                            Text("\"\(projectReplacePreview.replacement)\"")
                                .foregroundColor(themeColors.success)
                        }
                        .font(.system(size: 11, design: .monospaced))

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(projectReplacePreview.files.prefix(5)) { file in
                                HStack(spacing: 6) {
                                    Text(file.fileName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(themeColors.foreground)
                                    Text(file.displayPath)
                                        .font(.system(size: 11))
                                        .foregroundColor(themeColors.mutedText)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(file.matchCount)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(themeColors.warning)
                                }
                            }

                            if projectReplacePreview.files.count > 5 {
                                Text("+\(projectReplacePreview.files.count - 5) more file\(projectReplacePreview.files.count - 5 == 1 ? "" : "s")")
                                    .font(.system(size: 11))
                                    .foregroundColor(themeColors.mutedText)
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Cancel") {
                                projectViewModel.cancelProjectReplacePreview()
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(themeColors.mutedText)
                            .accessibilityIdentifier("project-replace-cancel")

                            Button("Apply Replace") {
                                projectViewModel.applyProjectReplacePreview()
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(themeColors.warning)
                            .disabled(!projectViewModel.canApplyProjectReplacePreview)
                            .accessibilityIdentifier("project-replace-apply")
                        }
                    }
                    .padding(10)
                    .background(themeColors.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("project-replace-preview")
                }
            }
            .padding(12)

            Divider()
                .overlay(themeColors.border)

            if projectViewModel.isSearchingProject {
                searchEmptyPrompt(text: "Searching...")
            } else if projectViewModel.projectSearchQuery.isEmpty {
                searchEmptyPrompt(text: "Type a query to search across the current folder.")
            } else if projectViewModel.projectSearchResults.isEmpty {
                searchEmptyPrompt(text: "No results found.")
            } else {
                List {
                    ForEach(Array(projectViewModel.groupedProjectSearchResults.enumerated()), id: \.element.id) { sectionIndex, group in
                        Section {
                            if !projectViewModel.isProjectSearchGroupCollapsed(group) {
                                ForEach(Array(group.results.enumerated()), id: \.element.id) { resultIndex, result in
                                HStack(alignment: .top, spacing: 8) {
                                    Button {
                                        projectViewModel.toggleProjectSearchResultSelection(result)
                                    } label: {
                                        Image(systemName: projectViewModel.isProjectSearchResultSelected(result) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(projectViewModel.isProjectSearchResultSelected(result) ? themeColors.accent : themeColors.mutedText)
                                    .accessibilityIdentifier("project-search-select-row-\(sectionIndex)-\(resultIndex)")

                                    Button {
                                        projectViewModel.openSearchResult(result)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(alignment: .firstTextBaseline) {
                                                Text("Ln \(result.lineNumber):\(result.columnNumber)")
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(themeColors.mutedText)
                                                if projectViewModel.isActiveProjectSearchResult(result) {
                                                    Image(systemName: "arrowtriangle.right.fill")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(themeColors.accent)
                                                        .accessibilityIdentifier("project-search-active-row-\(sectionIndex)-\(resultIndex)")
                                                }
                                                Spacer()
                                                Text("\(result.matchCount) match\(result.matchCount == 1 ? "" : "es")")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(themeColors.mutedText)
                                            }

                                            highlightedLineText(for: result)
                                                .font(.system(size: 12, design: .monospaced))
                                                .lineLimit(2)

                                            if !projectViewModel.projectReplaceQuery.isEmpty {
                                                replacementPreviewText(for: result)
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .lineLimit(2)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("project-search-open-result")
                                    .onHover { hovering in
                                        if hovering {
                                            projectViewModel.setActiveProjectSearchResult(result)
                                        }
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .padding(.trailing, 4)
                                .accessibilityIdentifier("project-search-result-row-\(sectionIndex)-\(resultIndex)")
                                .listRowBackground(
                                    projectViewModel.isActiveProjectSearchResult(result)
                                    ? themeColors.selection.opacity(0.45)
                                    : themeColors.panelBackground
                                )
                                }
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Button {
                                        projectViewModel.toggleProjectSearchGroupCollapsed(group)
                                    } label: {
                                        Image(systemName: projectViewModel.isProjectSearchGroupCollapsed(group) ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(themeColors.mutedText)
                                            .frame(width: 12)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("project-search-toggle-file")
                                    .accessibilityLabel("Toggle \(group.fileName)")

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.fileName)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(themeColors.foreground)

                                        Text(group.displayPath)
                                            .font(.system(size: 11))
                                            .foregroundColor(themeColors.mutedText)
                                            .lineLimit(1)
                                    }

                                    Spacer()
                                    HStack(spacing: 8) {
                                        Text("\(group.matchCount) match\(group.matchCount == 1 ? "" : "es")")
                                            .font(.system(size: 11))
                                            .foregroundColor(themeColors.mutedText)

                                        Button(projectViewModel.isProjectSearchGroupFullySelected(group) ? "Clear File" : "Select File") {
                                            projectViewModel.toggleProjectSearchGroupSelection(group)
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(themeColors.accent)
                                        .accessibilityIdentifier("project-search-select-file-\(sectionIndex)")

                                        Button("Replace File") {
                                            projectViewModel.replaceProjectSearchFileGroup(group)
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(themeColors.warning)
                                        .disabled(!projectViewModel.canReplaceProjectSearchResults || projectViewModel.isProjectSearchGroupCollapsed(group))
                                        .accessibilityIdentifier("project-search-replace-file-\(sectionIndex)")
                                    }
                                }
                            }
                            .textCase(nil)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(themeColors.panelBackground)
            }
        }
        .background(themeColors.panelBackground)
        .onKeyPress { event in
            switch event.key {
            case .upArrow:
                guard !projectViewModel.orderedProjectSearchResults.isEmpty else { return .ignored }
                projectViewModel.moveActiveProjectSearchResult(-1)
                return .handled
            case .downArrow:
                guard !projectViewModel.orderedProjectSearchResults.isEmpty else { return .ignored }
                projectViewModel.moveActiveProjectSearchResult(1)
                return .handled
            case .return:
                guard projectViewModel.projectReplacePreview == nil,
                      projectViewModel.activeProjectSearchResult != nil else { return .ignored }
                projectViewModel.openActiveProjectSearchResult()
                return .handled
            default:
                return .ignored
            }
        }
    }

    private func searchEmptyPrompt(text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(themeColors.mutedText)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(themeColors.subduedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func replacementPreviewText(for result: ProjectSearchResult) -> Text {
        Text("→ ")
            .foregroundColor(themeColors.warning)
        + highlightedText(
            for: result,
            highlightedTextProvider: { _ in projectViewModel.projectReplaceQuery },
            baseColor: themeColors.subduedText,
            highlightColor: themeColors.success
        )
    }

    private func highlightedLineText(for result: ProjectSearchResult) -> Text {
        highlightedText(
            for: result,
            highlightedTextProvider: { substring(of: result.lineText.isEmpty ? " " : result.lineText, from: $0.start, to: $0.start + $0.length) },
            baseColor: themeColors.subduedText,
            highlightColor: themeColors.accent
        )
    }

    private func highlightedText(
        for result: ProjectSearchResult,
        highlightedTextProvider: (ProjectSearchMatchRange) -> String,
        baseColor: Color,
        highlightColor: Color
    ) -> Text {
        let content = result.lineText.isEmpty ? " " : result.lineText
        guard !result.matchRanges.isEmpty else {
            return Text(verbatim: content).foregroundColor(baseColor)
        }

        var renderedText = Text("")
        var currentOffset = 0

        for matchRange in result.matchRanges {
            let startOffset = min(matchRange.start, content.count)
            let endOffset = min(matchRange.start + matchRange.length, content.count)

            if currentOffset < startOffset {
                renderedText = renderedText + Text(verbatim: substring(of: content, from: currentOffset, to: startOffset))
                    .foregroundColor(baseColor)
            }

            renderedText = renderedText + Text(verbatim: highlightedTextProvider(matchRange))
                .foregroundColor(highlightColor)
                .fontWeight(.semibold)

            currentOffset = endOffset
        }

        if currentOffset < content.count {
            renderedText = renderedText + Text(verbatim: substring(of: content, from: currentOffset, to: content.count))
                .foregroundColor(baseColor)
        }

        return renderedText
    }

    private func substring(of text: String, from start: Int, to end: Int) -> String {
        guard start < end else { return "" }
        let lowerBound = text.index(text.startIndex, offsetBy: min(max(start, 0), text.count))
        let upperBound = text.index(text.startIndex, offsetBy: min(max(end, 0), text.count))
        guard lowerBound < upperBound else { return "" }
        return String(text[lowerBound..<upperBound])
    }
}

struct NewItemSheet: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let placeholder: String
    let onCreate: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)

            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    if !name.isEmpty {
                        onCreate(name)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320, height: 120)
    }
}

struct RenameSheet: View {
    @Environment(\.dismiss) var dismiss
    let item: FileItem
    let onRename: (String) -> Void

    @State private var newName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename")
                .font(.headline)

            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    if !newName.isEmpty {
                        onRename(newName)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320, height: 120)
        .onAppear {
            newName = item.name
        }
    }
}
