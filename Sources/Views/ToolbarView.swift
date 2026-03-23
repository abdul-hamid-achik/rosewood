import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var disabledIconColor: Color {
        themeColors.mutedText.opacity(0.55)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                projectViewModel.openFolder()
            } label: {
                toolbarIcon(
                    systemName: "folder",
                    size: 14,
                    color: themeColors.accent,
                    isEnabled: true
                )
            }
            .buttonStyle(.borderless)
            .help("Open Folder (⌘O)")

            let canCreateFile = projectViewModel.rootDirectory != nil
            Button {
                projectViewModel.createNewFile()
            } label: {
                toolbarIcon(
                    systemName: "doc.badge.plus",
                    size: 14,
                    color: themeColors.accent,
                    isEnabled: canCreateFile
                )
            }
            .buttonStyle(.borderless)
            .help("New File (⌘N)")
            .disabled(!canCreateFile)

            Divider()
                .frame(height: 20)

            let canSearchProject = projectViewModel.rootDirectory != nil
            Button {
                projectViewModel.showSearchSidebar()
            } label: {
                toolbarIcon(
                    systemName: "magnifyingglass",
                    size: 14,
                    color: themeColors.accent,
                    isEnabled: canSearchProject
                )
            }
            .buttonStyle(.borderless)
            .help("Search in Project")
            .disabled(!canSearchProject)

            let canShowDebugSidebar = projectViewModel.canAccessDebugControls
            Button {
                projectViewModel.showDebugSidebar()
            } label: {
                toolbarIcon(
                    systemName: "ladybug",
                    size: 14,
                    color: themeColors.warning,
                    isEnabled: canShowDebugSidebar
                )
            }
            .buttonStyle(.borderless)
            .help("Debug Sidebar")
            .disabled(!canShowDebugSidebar)
            .accessibilityIdentifier("toolbar-debug-sidebar")

            if projectViewModel.selectedTab != nil {
                Button {
                    projectViewModel.saveCurrentFile()
                } label: {
                    toolbarIcon(
                        systemName: "square.and.arrow.down",
                        size: 14,
                        color: themeColors.success,
                        isEnabled: true
                    )
                }
                .buttonStyle(.borderless)
                .help("Save (⌘S)")
            }

            Divider()
                .frame(height: 20)

            let canStartDebugging = projectViewModel.canStartDebugging
            Button {
                projectViewModel.startDebugging()
            } label: {
                toolbarIcon(
                    systemName: "play.fill",
                    size: 13,
                    color: themeColors.success,
                    isEnabled: canStartDebugging
                )
            }
            .buttonStyle(.borderless)
            .help(projectViewModel.debugPrimaryActionTitle)
            .disabled(!canStartDebugging)
            .accessibilityIdentifier("toolbar-debug-start")

            let canStopDebugging = projectViewModel.canStopDebugging
            Button {
                projectViewModel.stopDebugging()
            } label: {
                toolbarIcon(
                    systemName: "stop.fill",
                    size: 12,
                    color: themeColors.danger,
                    isEnabled: canStopDebugging
                )
            }
            .buttonStyle(.borderless)
            .help("Reset Debugger")
            .disabled(!canStopDebugging)
            .accessibilityIdentifier("toolbar-debug-stop")

            Spacer()

            Button {
                projectViewModel.toggleCommandPalette()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "command")
                        .font(.system(size: 11))
                    Text("⌘P")
                        .font(.system(size: 11))
                }
                .foregroundColor(themeColors.subduedText)
            }
            .buttonStyle(.borderless)
            .help("Command Palette (⌘⇧P)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 44)
        .background(themeColors.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(themeColors.border)
                .frame(height: 1)
        }
    }

    private func toolbarIcon(systemName: String, size: CGFloat, color: Color, isEnabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundColor(isEnabled ? color : disabledIconColor)
            .opacity(isEnabled ? 1 : 0.65)
    }
}
