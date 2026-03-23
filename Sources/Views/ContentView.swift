import SwiftUI

struct ContentView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
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
            if projectViewModel.showCommandPalette {
                CommandPaletteView()
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .handleCommandPalette)) { _ in
            projectViewModel.toggleCommandPalette()
        }
        .onReceive(NotificationCenter.default.publisher(for: .handleCloseTab)) { _ in
            if let index = projectViewModel.selectedTabIndex {
                projectViewModel.closeTab(at: index)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .handleProjectSearch)) { _ in
            projectViewModel.showSearchSidebar()
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

                    Button("Replace All") {
                        projectViewModel.replaceAllProjectResults()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(themeColors.warning)
                    .disabled(projectViewModel.projectSearchResults.isEmpty || projectViewModel.projectSearchQuery.isEmpty)
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
                List(projectViewModel.projectSearchResults) { result in
                    Button {
                        projectViewModel.openSearchResult(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(result.fileName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(themeColors.foreground)
                                Spacer()
                                Text("Ln \(result.lineNumber)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(themeColors.mutedText)
                            }

                            Text(result.lineText.isEmpty ? " " : result.lineText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(themeColors.subduedText)
                                .lineLimit(2)

                            Text(result.filePath.deletingLastPathComponent().path)
                                .font(.system(size: 11))
                                .foregroundColor(themeColors.mutedText)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(themeColors.panelBackground)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(themeColors.panelBackground)
            }
        }
        .background(themeColors.panelBackground)
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
