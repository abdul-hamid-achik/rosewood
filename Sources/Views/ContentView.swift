import SwiftUI

struct ContentView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    @EnvironmentObject private var commandDispatcher: AppCommandDispatcher

    @State private var bottomPanelHeight: CGFloat = RosewoodUI.defaultBottomPanelHeight
    @State private var bottomPanelResizeBaseline: CGFloat?

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
            .onReceive(commandDispatcher.publisher) { command in
                handleAppCommand(command)
            }
    }

    private func handleAppCommand(_ command: AppCommand) {
        switch command {
        case .newFile:
            projectViewModel.createNewFile()
        case .openFolder:
            projectViewModel.openFolder()
        case .save:
            projectViewModel.saveCurrentFile()
        case .quickOpen:
            projectViewModel.toggleQuickOpen()
        case .commandPalette:
            projectViewModel.toggleCommandPalette()
        case .toggleProblems:
            guard projectViewModel.canShowProblemsPanel else { return }
            projectViewModel.toggleDiagnosticsPanel()
        case .closeTab:
            if let index = projectViewModel.selectedTabIndex {
                projectViewModel.closeTab(at: index)
            }
        case .projectSearch:
            projectViewModel.showSearchSidebar()
        case .goToLine:
            projectViewModel.beginGoToLine()
        case .findNext:
            guard projectViewModel.canNavigateProjectSearchResults else { return }
            projectViewModel.showNextProjectSearchResult()
        case .findPrevious:
            guard projectViewModel.canNavigateProjectSearchResults else { return }
            projectViewModel.showPreviousProjectSearchResult()
        case .nextProblem:
            projectViewModel.openNextProblem()
        case .previousProblem:
            projectViewModel.openPreviousProblem()
        case .settings, .findInFile, .useSelectionForFind, .showReplace, .goToDefinition, .findReferences:
            break
        }
    }

    private var shellView: some View {
        VStack(spacing: 0) {
            HSplitView {
                HStack(spacing: 0) {
                    ActivitySidebarView()
                        .frame(width: RosewoodUI.sidebarRailWidth)

                    ThemedDivider(Axis.vertical)

                    sidebarView
                }
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 420)

                VStack(spacing: 0) {
                    editorArea
                        .frame(minWidth: 400)

                    if let bottomPanel = projectViewModel.bottomPanel {
                        bottomPanelContainer(bottomPanel)
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

            ThemedDivider()

            if projectViewModel.sidebarMode == .search {
                SearchSidebarView()
            } else if projectViewModel.sidebarMode == .sourceControl {
                SourceControlSidebarView()
            } else if projectViewModel.sidebarMode == .debug {
                DebugSidebarView()
            } else if projectViewModel.fileTree.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    FileTreeView(items: projectViewModel.fileTree)

                    if projectViewModel.selectedTab?.filePath != nil {
                        ThemedDivider()

                        OutlineSidebarView()
                            .frame(minHeight: 120, idealHeight: 180, maxHeight: 220)
                    }
                }
            }
        }
        .background(themeColors.panelBackground)
    }

    private var sidebarHeaderView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sidebarTitle)
                    .font(RosewoodType.subheadlineStrong)
                    .foregroundColor(themeColors.foreground)

                Text(sidebarSubtitle)
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)
            }

            if projectViewModel.sidebarMode == .explorer {
                if projectViewModel.selectedTab?.filePath != nil {
                    Button {
                        projectViewModel.revealActiveFileInExplorer()
                    } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 12))
                            .foregroundColor(themeColors.mutedText)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal Active File")
                }

                Menu {
                    Button("New File") {
                        projectViewModel.showNewFileSheet = true
                    }
                    Button("New Folder") {
                        projectViewModel.showNewFolderSheet = true
                    }
                    Divider()
                    Button(projectViewModel.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                        projectViewModel.toggleShowHiddenFiles()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                        .foregroundColor(themeColors.mutedText)
                }
                .menuStyle(.borderlessButton)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(themeColors.panelBackground)
    }

    private var sidebarTitle: String {
        switch projectViewModel.sidebarMode {
        case .explorer:
            return "Explorer"
        case .search:
            return "Search"
        case .sourceControl:
            return "Source Control"
        case .debug:
            return "Run & Debug"
        }
    }

    private var sidebarSubtitle: String {
        switch projectViewModel.sidebarMode {
        case .explorer:
            if let rootDirectory = projectViewModel.rootDirectory {
                return projectViewModel.showHiddenFiles ? "\(rootDirectory.lastPathComponent) • hidden visible" : rootDirectory.lastPathComponent
            }
            return "Open a folder to browse files"
        case .search:
            let baseText = projectViewModel.projectSearchQuery.isEmpty ? "Find in the current workspace" : projectViewModel.projectSearchVisibilitySummary
            return projectViewModel.showHiddenFiles ? "\(baseText) • hidden on" : baseText
        case .sourceControl:
            return projectViewModel.gitRepositoryStatus.isRepository ? "Review local changes" : "Review changes and commits"
        case .debug:
            if projectViewModel.debugSessionState != .idle {
                return projectViewModel.debugSessionState.statusText
            }
            if let selectedDebugConfigurationName = projectViewModel.selectedDebugConfigurationName {
                return "Ready: \(selectedDebugConfigurationName)"
            }
            return "Set up launch configs and breakpoints"
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40, weight: .regular))
                .foregroundColor(themeColors.mutedText)
            Text("No Folder Open")
                .font(RosewoodType.bodyStrong)
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
                ThemedDivider()
            }

            if projectViewModel.isGitDiffWorkspaceVisible {
                GitDiffPanelView(layoutStyle: .workspace)
            } else if let tab = projectViewModel.selectedTab {
                tabContentView(for: tab)
            } else {
                emptyEditorView
            }
        }
        .background(themeColors.background)
    }

    @ViewBuilder
    private func tabContentView(for tab: EditorTab) -> some View {
        switch tab.contentType {
        case .text(let isLarge):
            if isLarge {
                LargeFileWarningView(tab: tab)
            } else {
                editorChromeView
                EditorView(tab: tab)
            }
        case .image:
            ImageViewerView(tab: tab)
        case .binary(.hex):
            HexViewerView(tab: tab)
        case .binary, .excluded:
            BinaryPlaceholderView(tab: tab)
        }
    }

    @ViewBuilder
    private var editorChromeView: some View {
        if !projectViewModel.editorBreadcrumbs.isEmpty {
            EditorBreadcrumbBar(segments: projectViewModel.editorBreadcrumbs) { line in
                if let line {
                    projectViewModel.jumpToLineInSelectedTab(line)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(themeColors.panelBackground)

            if !projectViewModel.editorStickyScopes.isEmpty {
                ThemedDivider()

                EditorStickyScopeBar(scopes: projectViewModel.editorStickyScopes) { line in
                    projectViewModel.jumpToLineInSelectedTab(line)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(themeColors.panelBackground)
            }

            ThemedDivider()
        }
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

    private func bottomPanelContainer(_ panel: ProjectViewModel.BottomPanelKind) -> some View {
        VStack(spacing: 0) {
            ThemedDivider()

            ZStack {
                Rectangle()
                    .fill(themeColors.panelBackground)
                    .frame(height: 8)

                Capsule()
                    .fill(themeColors.border.opacity(0.9))
                    .frame(width: 44, height: 4)
            }
            .contentShape(Rectangle())
            .gesture(bottomPanelResizeGesture)

            bottomPanelView(panel)
                .frame(height: bottomPanelHeight)
        }
        .background(themeColors.panelBackground)
    }

    private var bottomPanelResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let baseline = bottomPanelResizeBaseline ?? bottomPanelHeight
                if bottomPanelResizeBaseline == nil {
                    bottomPanelResizeBaseline = bottomPanelHeight
                }

                bottomPanelHeight = min(max(baseline - value.translation.height, 140), 460)
            }
            .onEnded { _ in
                bottomPanelResizeBaseline = nil
            }
    }
}

struct ActivitySidebarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: RosewoodUI.spacing2) {
            activityButton(
                mode: .explorer,
                systemImage: "doc.on.doc",
                label: "Explorer"
            )

            activityButton(
                mode: .search,
                systemImage: "magnifyingglass",
                label: "Search"
            )

            activityButton(
                mode: .sourceControl,
                systemImage: "arrow.triangle.branch",
                label: "Source Control",
                badge: projectViewModel.gitRepositoryStatus.changedFiles.isEmpty ? nil : "\(projectViewModel.gitRepositoryStatus.changedFiles.count)"
            )

            activityButton(
                mode: .debug,
                systemImage: "ladybug",
                label: "Run & Debug",
                badge: projectViewModel.workspaceDiagnosticCount.errors > 0 ? "!" : nil
            )

            Spacer()
        }
        .padding(.vertical, RosewoodUI.spacing4)
        .background(themeColors.gutterBackground)
    }

    private func activityButton(
        mode: ProjectViewModel.SidebarMode,
        systemImage: String,
        label: String,
        badge: String? = nil
    ) -> some View {
        let isActive = projectViewModel.sidebarMode == mode

        return Button {
            projectViewModel.sidebarMode = mode
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isActive ? themeColors.accent : themeColors.mutedText)
                    .frame(width: 34, height: 34)
                    .background(isActive ? themeColors.selection : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall))

                if let badge {
                    Text(badge)
                        .font(RosewoodType.micro)
                        .foregroundColor(themeColors.background)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(themeColors.accentStrong)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -6)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityIdentifier("activity-sidebar-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

struct SearchSidebarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    @State private var showsFilterControls = true
    @State private var showsReplaceControls = true
    @FocusState private var isSearchFieldFocused: Bool

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            RosewoodSidebarCard(spacing: RosewoodUI.spacing3) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(themeColors.mutedText)

                        TextField("Search in project", text: $projectViewModel.projectSearchQuery)
                            .focused($isSearchFieldFocused)
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

                        Spacer(minLength: 0)

                        searchModeToggle(
                            systemImage: "textformat.abc",
                            helpText: "Match Case",
                            isOn: projectViewModel.projectSearchCaseSensitive,
                            accessibilityIdentifier: "project-search-case-sensitive"
                        ) {
                            projectViewModel.projectSearchCaseSensitive.toggle()
                        }

                        searchModeToggle(
                            systemImage: "text.word.spacing",
                            helpText: "Match Whole Word",
                            isOn: projectViewModel.projectSearchWholeWord,
                            accessibilityIdentifier: "project-search-whole-word"
                        ) {
                            projectViewModel.projectSearchWholeWord.toggle()
                        }

                        searchModeToggle(
                            systemImage: "curlybraces.square",
                            helpText: "Use Regular Expression",
                            isOn: projectViewModel.projectSearchUseRegex,
                            accessibilityIdentifier: "project-search-regex"
                        ) {
                            projectViewModel.projectSearchUseRegex.toggle()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(themeColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                DisclosureGroup(isExpanded: $showsFilterControls) {
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
                        .background(themeColors.background)
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
                        .background(themeColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: 8) {
                        Button {
                            projectViewModel.toggleShowHiddenFiles()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: projectViewModel.showHiddenFiles ? "eye" : "eye.slash")
                                Text(projectViewModel.showHiddenFiles ? "Hidden On" : "Hidden Off")
                            }
                            .font(RosewoodType.captionStrong)
                            .foregroundColor(projectViewModel.showHiddenFiles ? themeColors.accentStrong : themeColors.subduedText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(projectViewModel.showHiddenFiles ? themeColors.selection : themeColors.hoverBackground.opacity(0.4))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(projectViewModel.showHiddenFiles ? themeColors.accent.opacity(0.45) : themeColors.border.opacity(0.35), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("project-search-hidden-files")

                        Spacer()
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                        .font(RosewoodType.captionStrong)
                        .foregroundColor(themeColors.subduedText)
                }

                DisclosureGroup(isExpanded: $showsReplaceControls) {
                    VStack(alignment: .leading, spacing: 8) {
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
                            .background(themeColors.background)
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
                            .background(themeColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("project-replace-preview")
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                        .font(RosewoodType.captionStrong)
                        .foregroundColor(themeColors.subduedText)
                }

                if !projectViewModel.projectSearchResults.isEmpty {
                    Text(projectViewModel.projectSearchVisibilitySummary)
                        .font(.system(size: 1))
                        .foregroundColor(.clear)
                        .opacity(0.01)
                        .frame(height: 1)
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
                searchResultsSurface
            }
        }
        .background(themeColors.panelBackground)
        .onAppear {
            if !projectViewModel.projectReplaceQuery.isEmpty || projectViewModel.projectReplacePreview != nil {
                showsReplaceControls = true
            }
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
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

    private var searchResultsSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(projectViewModel.groupedProjectSearchResults.enumerated()), id: \.element.id) { sectionIndex, group in
                        VStack(alignment: .leading, spacing: 0) {
                            searchGroupHeader(group, sectionIndex: sectionIndex)

                            if !projectViewModel.isProjectSearchGroupCollapsed(group) {
                                ThemedDivider()

                                VStack(spacing: 0) {
                                    ForEach(Array(group.results.enumerated()), id: \.element.id) { resultIndex, result in
                                        if resultIndex > 0 {
                                            ThemedDivider()
                                                .padding(.leading, 34)
                                        }

                                        searchResultRow(result, sectionIndex: sectionIndex, resultIndex: resultIndex)
                                            .id(result.id)
                                    }
                                }
                            }
                        }
                        .rosewoodCard(themeColors, radius: RosewoodUI.radiusSmall)
                    }
                }
                .padding(12)
            }
            .background(themeColors.panelBackground)
            .onAppear {
                scrollToActiveResult(with: proxy)
            }
            .onChange(of: projectViewModel.activeProjectSearchResultID) { _, _ in
                scrollToActiveResult(with: proxy)
            }
        }
    }

    private func searchGroupHeader(_ group: ProjectSearchFileGroup, sectionIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
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

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    RosewoodHeaderChip(text: "\(group.matchCount)x", tint: themeColors.mutedText)

                    Button(projectViewModel.isProjectSearchGroupFullySelected(group) ? "Clear File" : "Select File") {
                        projectViewModel.toggleProjectSearchGroupSelection(group)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.accent)
                    .accessibilityIdentifier("project-search-select-file-\(sectionIndex)")

                    Button("Replace File") {
                        projectViewModel.replaceProjectSearchFileGroup(group)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.warning)
                    .disabled(!projectViewModel.canReplaceProjectSearchResults || projectViewModel.isProjectSearchGroupCollapsed(group))
                    .accessibilityIdentifier("project-search-replace-file-\(sectionIndex)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func searchResultRow(_ result: ProjectSearchResult, sectionIndex: Int, resultIndex: Int) -> some View {
        let isActiveResult = projectViewModel.isActiveProjectSearchResult(result)

        return HStack(alignment: .top, spacing: 8) {
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        RosewoodHeaderChip(
                            text: "Ln \(result.lineNumber):\(result.columnNumber)",
                            tint: isActiveResult ? themeColors.accent : themeColors.mutedText
                        )
                        if isActiveResult {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.system(size: 9))
                                .foregroundColor(themeColors.accent)
                                .accessibilityIdentifier("project-search-active-row-\(sectionIndex)-\(resultIndex)")
                        }
                        Spacer()
                        RosewoodHeaderChip(
                            text: "\(result.matchCount)x",
                            tint: isActiveResult ? themeColors.accent : themeColors.mutedText
                        )
                    }

                    highlightedLineText(for: result)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(projectViewModel.projectReplaceQuery.isEmpty ? 1 : 2)

                    if !projectViewModel.projectReplaceQuery.isEmpty {
                        replacementPreviewText(for: result)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActiveResult ? themeColors.selection.opacity(0.4) : Color.clear)
        .accessibilityIdentifier("project-search-result-row-\(sectionIndex)-\(resultIndex)")
    }

    private func scrollToActiveResult(with proxy: ScrollViewProxy) {
        guard let activeID = projectViewModel.activeProjectSearchResultID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(activeID, anchor: .center)
            }
        }
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

    private func searchModeToggle(
        systemImage: String,
        helpText: String,
        isOn: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isOn ? themeColors.accentStrong : themeColors.subduedText)
                .frame(width: 20, height: 18)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isOn ? themeColors.selection : themeColors.hoverBackground.opacity(0.45))
                )
                .overlay(
                    Capsule()
                        .stroke(isOn ? themeColors.accent.opacity(0.45) : themeColors.border.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityIdentifier(accessibilityIdentifier)
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
    @EnvironmentObject private var configService: ConfigurationService
    @Environment(\.dismiss) var dismiss
    let title: String
    let placeholder: String
    let onCreate: (String) -> Void

    @State private var name: String = ""
    @FocusState private var isNameFieldFocused: Bool

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: RosewoodUI.spacing6) {
            HStack {
                Text(title)
                    .font(RosewoodType.title)
                    .foregroundColor(themeColors.foreground)
                Spacer()
            }

            HStack(spacing: RosewoodUI.spacing3) {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(themeColors.accent)

                TextField(placeholder, text: $name)
                    .focused($isNameFieldFocused)
                    .textFieldStyle(.plain)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
            }
            .padding(.horizontal, RosewoodUI.spacing5)
            .padding(.vertical, RosewoodUI.spacing4)
            .background(themeColors.background)
            .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium)
                    .stroke(themeColors.border.opacity(0.8), lineWidth: 1)
            )

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    if !name.isEmpty {
                        onCreate(name)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(themeColors.accent)
            }
        }
        .padding(RosewoodUI.spacing8)
        .frame(width: 360)
        .background(themeColors.panelBackground)
        .onAppear {
            DispatchQueue.main.async {
                isNameFieldFocused = true
            }
        }
    }
}

struct RenameSheet: View {
    @EnvironmentObject private var configService: ConfigurationService
    @Environment(\.dismiss) var dismiss
    let item: FileItem
    let onRename: (String) -> Void

    @State private var newName: String = ""
    @FocusState private var isRenameFieldFocused: Bool

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: RosewoodUI.spacing6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rename")
                        .font(RosewoodType.title)
                        .foregroundColor(themeColors.foreground)
                    Text(item.name)
                        .font(RosewoodType.caption)
                        .foregroundColor(themeColors.mutedText)
                }
                Spacer()
            }

            HStack(spacing: RosewoodUI.spacing3) {
                Image(systemName: "pencil")
                    .foregroundColor(themeColors.accent)

                TextField("New name", text: $newName)
                    .focused($isRenameFieldFocused)
                    .textFieldStyle(.plain)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
            }
            .padding(.horizontal, RosewoodUI.spacing5)
            .padding(.vertical, RosewoodUI.spacing4)
            .background(themeColors.background)
            .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium)
                    .stroke(themeColors.border.opacity(0.8), lineWidth: 1)
            )

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Rename") {
                    if !newName.isEmpty {
                        onRename(newName)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(themeColors.accent)
            }
        }
        .padding(RosewoodUI.spacing8)
        .frame(width: 360)
        .background(themeColors.panelBackground)
        .onAppear {
            newName = item.name
            DispatchQueue.main.async {
                isRenameFieldFocused = true
            }
        }
    }
}
