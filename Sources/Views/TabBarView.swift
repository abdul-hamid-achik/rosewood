import AppKit
import SwiftUI

struct TabBarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(projectViewModel.openTabs.enumerated()), id: \.element.id) { index, tab in
                    TabItemView(
                        index: index,
                        tab: tab,
                        isSelected: index == projectViewModel.selectedTabIndex,
                        onSelect: {
                            projectViewModel.selectTab(at: index)
                        },
                        onClose: {
                            projectViewModel.closeTab(at: index)
                        }
                    )
                }
            }
        }
        .frame(height: 36)
        .background(themeColors.panelBackground)
    }
}

struct TabItemView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    let index: Int
    let tab: EditorTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.filePath != nil ? iconForFile(tab.fileName) : "doc")
                .font(.system(size: 12))
                .foregroundColor(isSelected ? themeColors.accent : themeColors.mutedText)

            Text(tab.fileName)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? themeColors.foreground : themeColors.subduedText)

            if tab.isDirty {
                Circle()
                    .fill(themeColors.warning)
                    .frame(width: 6, height: 6)
            }

            if isHovering || isSelected {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(themeColors.mutedText)
                }
                .buttonStyle(.plain)
                .padding(2)
            } else {
                Spacer()
                    .frame(width: 18)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 36)
        .background(
            isSelected ? themeColors.background : (isHovering ? themeColors.hoverBackground.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tab-item-\(index)")
        .contextMenu {
            Button("Close") {
                onClose()
            }

            Button("Close Others") {
                projectViewModel.closeOtherTabs(except: index)
            }
            .disabled(projectViewModel.openTabs.count <= 1)

            Button("Close All") {
                projectViewModel.closeAllTabs()
            }
            .disabled(projectViewModel.openTabs.isEmpty)

            Button("Close to the Right") {
                projectViewModel.closeTabsToTheRight(of: index)
            }
            .disabled(index >= projectViewModel.openTabs.count - 1)

            if tab.filePath != nil {
                Divider()

                Button("Copy Path") {
                    copyToPasteboard(projectViewModel.copyFilePath(tab: tab))
                }

                Button("Copy Relative Path") {
                    copyToPasteboard(projectViewModel.relativeFilePath(tab: tab))
                }
                .disabled(projectViewModel.relativeFilePath(tab: tab) == nil)

                Divider()

                Button("Reveal in Finder") {
                    projectViewModel.revealInFinder(tab: tab)
                }
            }
        }
    }

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "text.badge.star"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "rb": return "diamond"
        case "js", "ts", "jsx", "tsx": return "square.fill"
        case "vue": return "v.square.fill"
        case "kt": return "k.square.fill"
        case "ex", "exs": return "e.square.fill"
        case "sh", "bash": return "terminal"
        case "md": return "doc.richtext"
        case "json": return "curlybraces"
        default: return "doc.text"
        }
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
