import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    let items: [FileItem]

    @FocusState private var isExplorerFocused: Bool
    @State private var selectedPath: String?

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var activeFilePath: String? {
        projectViewModel.selectedTab?.filePath?.standardizedFileURL.path
    }

    private var visibleItems: [ExplorerVisibleItem] {
        flatten(items: items, depth: 0, parentPath: nil)
    }

    private var visibleItemIDs: [String] {
        visibleItems.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleItems) { entry in
                        FileTreeRow(
                            entry: entry,
                            isSelected: selectedPath == entry.id,
                            isActiveFile: activeFilePath == entry.id,
                            onSelect: {
                                selectedPath = entry.id
                                isExplorerFocused = true
                            },
                            onActivate: {
                                selectedPath = entry.id
                                isExplorerFocused = true
                                activate(entry)
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
            .background(themeColors.panelBackground)
            .accessibilityIdentifier("explorer-file-tree")
            .focusable()
            .focused($isExplorerFocused)
            .overlay {
                RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall)
                    .stroke(isExplorerFocused ? themeColors.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                    .padding(4)
            }
            .onAppear {
                syncSelectionWithExplorerState()
            }
            .onChange(of: activeFilePath) { _, newValue in
                if let newValue {
                    selectedPath = newValue
                } else if visibleItems.isEmpty {
                    selectedPath = nil
                }
            }
            .onChange(of: visibleItemIDs) { _, _ in
                syncSelectionWithExplorerState()
            }
            .onChange(of: selectedPath) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onKeyPress { event in
                switch event.key {
                case .upArrow:
                    moveSelection(delta: -1)
                    return .handled
                case .downArrow:
                    moveSelection(delta: 1)
                    return .handled
                case .leftArrow:
                    collapseOrSelectParent()
                    return .handled
                case .rightArrow:
                    expandOrSelectChild()
                    return .handled
                case .return:
                    activateSelectedItem()
                    return .handled
                default:
                    return .ignored
                }
            }
        }
    }

    private func activateSelectedItem() {
        guard let entry = selectedEntry else { return }
        activate(entry)
    }

    private func activate(_ entry: ExplorerVisibleItem) {
        if entry.item.isDirectory {
            projectViewModel.toggleExpand(entry.item)
        } else {
            projectViewModel.openFile(at: entry.item.path)
        }
    }

    private func moveSelection(delta: Int) {
        guard !visibleItems.isEmpty else { return }

        if let currentIndex = selectedIndex {
            let newIndex = min(max(currentIndex + delta, 0), visibleItems.count - 1)
            selectedPath = visibleItems[newIndex].id
        } else if let activeFilePath,
                  let activeIndex = visibleItems.firstIndex(where: { $0.id == activeFilePath }) {
            selectedPath = visibleItems[activeIndex].id
        } else {
            selectedPath = visibleItems[delta < 0 ? visibleItems.count - 1 : 0].id
        }

        isExplorerFocused = true
    }

    private func collapseOrSelectParent() {
        guard let entry = selectedEntry else {
            syncSelectionWithExplorerState()
            return
        }

        if entry.item.isDirectory, entry.item.isExpanded {
            projectViewModel.toggleExpand(entry.item)
            return
        }

        if let parentPath = entry.parentPath {
            selectedPath = parentPath
        }
    }

    private func expandOrSelectChild() {
        guard let entry = selectedEntry else {
            syncSelectionWithExplorerState()
            return
        }

        guard entry.item.isDirectory else { return }

        if !entry.item.isExpanded {
            projectViewModel.toggleExpand(entry.item)
            return
        }

        if let firstChildPath = entry.firstChildPath {
            selectedPath = firstChildPath
        }
    }

    private func syncSelectionWithExplorerState() {
        guard !visibleItems.isEmpty else {
            selectedPath = nil
            return
        }

        if let selectedPath,
           visibleItems.contains(where: { $0.id == selectedPath }) {
            return
        }

        if let activeFilePath,
           visibleItems.contains(where: { $0.id == activeFilePath }) {
            selectedPath = activeFilePath
            return
        }

        selectedPath = visibleItems.first?.id
    }

    private var selectedIndex: Int? {
        guard let selectedPath else { return nil }
        return visibleItems.firstIndex(where: { $0.id == selectedPath })
    }

    private var selectedEntry: ExplorerVisibleItem? {
        guard let selectedIndex else { return nil }
        return visibleItems[selectedIndex]
    }

    private func flatten(items: [FileItem], depth: Int, parentPath: String?) -> [ExplorerVisibleItem] {
        var flattened: [ExplorerVisibleItem] = []

        for item in items {
            let itemPath = item.path.standardizedFileURL.path
            let firstChildPath = item.children.first?.path.standardizedFileURL.path
            flattened.append(
                ExplorerVisibleItem(
                    item: item,
                    depth: depth,
                    parentPath: parentPath,
                    firstChildPath: firstChildPath
                )
            )

            if item.isDirectory, item.isExpanded {
                flattened.append(contentsOf: flatten(items: item.children, depth: depth + 1, parentPath: itemPath))
            }
        }

        return flattened
    }
}

private struct ExplorerVisibleItem: Identifiable {
    let item: FileItem
    let depth: Int
    let parentPath: String?
    let firstChildPath: String?

    var id: String {
        item.path.standardizedFileURL.path
    }
}

private struct FileTreeRow: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    let entry: ExplorerVisibleItem
    let isSelected: Bool
    let isActiveFile: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void

    @State private var isHovering = false

    private var item: FileItem {
        entry.item
    }

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var gitChange: GitChangedFile? {
        projectViewModel.gitChange(for: item)
    }

    private var changedDescendantCount: Int {
        projectViewModel.gitChangedDescendantCount(for: item)
    }

    private var isIgnored: Bool {
        projectViewModel.isGitIgnored(item)
    }

    var body: some View {
        HStack(spacing: 6) {
            if item.isDirectory {
                Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.mutedText)
                    .frame(width: 12, height: 12)
            } else {
                Color.clear
                    .frame(width: 12, height: 12)
            }

            Image(systemName: item.iconName)
                .font(.system(size: 13))
                .foregroundColor(item.isDirectory ? themeColors.accent : themeColors.mutedText)
                .frame(width: 14)

            Text(item.name)
                .font(.system(size: 13))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let gitChange {
                Text(gitChange.kind.explorerLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(gitBadgeColor(for: gitChange.kind))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(gitBadgeColor(for: gitChange.kind).opacity(isSelected ? 0.28 : 0.16))
                    )
            } else if item.isDirectory && changedDescendantCount > 0 {
                Text("\(changedDescendantCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeColors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(themeColors.accent.opacity(isSelected ? 0.24 : 0.14))
                    )
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 14 + 10)
        .padding(.trailing, 10)
        .frame(height: 24)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill((isSelected || isActiveFile) ? themeColors.accent : Color.clear)
                .frame(width: 3)
        }
        .opacity(isIgnored && !isSelected ? 0.58 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            onActivate()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("file-tree-row-\(item.name)")
        .accessibilityValue(accessibilityValue)
        .contextMenu {
            if item.isDirectory {
                Button("New File") {
                    projectViewModel.pendingNewItemDirectory = item.path
                    projectViewModel.showNewFileSheet = true
                }

                Button("New Folder") {
                    projectViewModel.pendingNewItemDirectory = item.path
                    projectViewModel.showNewFolderSheet = true
                }

                Divider()
            }

            Button("Rename") {
                projectViewModel.renameItem = item
            }

            Button("Duplicate") {
                projectViewModel.duplicateItem(item)
            }

            Divider()

            Button("Delete") {
                projectViewModel.deleteItem(item)
            }
        }
    }

    private var primaryTextColor: Color {
        if isIgnored {
            return themeColors.mutedText
        }
        return item.isDirectory ? themeColors.foreground : themeColors.subduedText
    }

    private var accessibilityValue: String {
        if isIgnored {
            return "Ignored"
        }
        if let gitChange {
            return gitChange.kind.displayName
        }
        if item.isDirectory && changedDescendantCount > 0 {
            return "\(changedDescendantCount) changed descendants"
        }
        return "Clean"
    }

    private func gitBadgeColor(for kind: GitChangeKind) -> Color {
        switch kind {
        case .modified:
            return themeColors.warning
        case .added, .copied, .untracked:
            return themeColors.success
        case .deleted, .conflicted:
            return themeColors.danger
        case .renamed:
            return themeColors.accent
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return themeColors.rowSelection
        }

        if isActiveFile {
            return themeColors.selection.opacity(themeColors.isLightAppearance ? 0.35 : 0.22)
        }

        if isHovering {
            return themeColors.hoverBackground.opacity(0.3)
        }

        return .clear
    }
}
