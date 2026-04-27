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
                            withAnimation(.rosewoodFast) {
                                projectViewModel.selectTab(at: index)
                            }
                        },
                        onClose: {
                            projectViewModel.closeTab(at: index)
                        }
                    )

                    Rectangle()
                        .fill(themeColors.border.opacity(RosewoodUI.borderOpacitySubtle))
                        .frame(width: 1, height: 18)
                }
            }
        }
        .frame(height: RosewoodUI.rowHeightRegular)
        .background(themeColors.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(themeColors.border.opacity(RosewoodUI.borderOpacitySubtle))
                .frame(height: 1)
        }
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
        Button {
            onSelect()
        } label: {
            HStack(spacing: RosewoodUI.spacing3) {
                Image(systemName: tabIconName)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? themeColors.accent : themeColors.mutedText)

                Text(tab.fileName)
                    .font(isSelected ? RosewoodType.bodyStrong : RosewoodType.body)
                    .foregroundColor(isSelected ? themeColors.foreground : themeColors.subduedText)

                if tab.isDirty {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(themeColors.warning)
                }

                ZStack {
                    if isHovering || isSelected {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(themeColors.mutedText)
                                .frame(width: 16, height: 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(themeColors.hoverBackground.opacity(isHovering ? 0.4 : 0))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .padding(.horizontal, RosewoodUI.spacing5)
            .frame(height: RosewoodUI.rowHeightRegular)
            .background(tabBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? themeColors.accent : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.rosewoodFast) {
                isHovering = hovering
            }
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
        .help(tab.fileName)
    }

    private var tabBackground: Color {
        if isSelected {
            return themeColors.background
        }
        if isHovering {
            return themeColors.hoverBackground.opacity(RosewoodUI.stateOpacityHover)
        }
        return themeColors.panelBackground
    }

    private var tabIconName: String {
        switch tab.contentType {
        case .text:
            return tab.filePath != nil ? iconForFile(tab.fileName) : "doc"
        default:
            return tab.contentType.tabIconName
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
