import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    let items: [FileItem]

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    FileTreeRow(item: item, depth: 0)
                }
            }
            .padding(.vertical, 6)
        }
        .background(themeColors.panelBackground)
    }
}

private struct FileTreeRow: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    let item: FileItem
    let depth: Int

    @State private var isHovering = false

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var isSelected: Bool {
        projectViewModel.selectedTab?.filePath?.standardizedFileURL.path == item.path.standardizedFileURL.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent

            if item.isDirectory && item.isExpanded {
                ForEach(item.children) { child in
                    FileTreeRow(item: child, depth: depth + 1)
                }
            }
        }
    }

    private var rowContent: some View {
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
                .foregroundColor(item.isDirectory ? themeColors.foreground : themeColors.subduedText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 14 + 10)
        .padding(.trailing, 10)
        .frame(height: 22)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDirectory {
                projectViewModel.toggleExpand(item)
            } else {
                projectViewModel.openFile(at: item.path)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
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

    private var rowBackground: Color {
        if isSelected {
            return themeColors.accentStrong
        }

        if isHovering {
            return themeColors.hoverBackground.opacity(0.3)
        }

        return .clear
    }
}
