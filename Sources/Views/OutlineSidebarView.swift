import SwiftUI

struct OutlineSidebarView: View {
    @EnvironmentObject private var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    // Observed so the outline re-renders when the (debounced, off-main) symbol index updates,
    // without ProjectViewModel having to re-render every view to deliver that refresh.
    @EnvironmentObject private var outlineModel: OutlineModel

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var currentSymbols: [WorkspaceSymbolMatch] {
        projectViewModel.isOutlineSidebarDataReady ? projectViewModel.currentFileSymbols : []
    }

    private var activeSymbolID: String? {
        projectViewModel.isOutlineSidebarDataReady ? projectViewModel.activeCurrentFileSymbolID : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if !projectViewModel.isEditorNavigationModelReady {
                emptyStateView(message: "Preparing outline...")
            } else if !projectViewModel.isOutlineSidebarDataReady {
                emptyStateView(message: "Loading outline...")
            } else if currentSymbols.isEmpty {
                emptyStateView(message: "No symbols in the current file")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(currentSymbols) { symbol in
                            OutlineSymbolRow(
                                symbol: symbol,
                                isActive: activeSymbolID == symbol.id
                            ) {
                                projectViewModel.openWorkspaceSymbol(symbol)
                            }
                        }
                    }
                    .padding(.horizontal, RosewoodUI.spacing3)
                    .padding(.vertical, RosewoodUI.spacing2)
                }
            }
        }
        .background(themeColors.panelBackground)
        .accessibilityIdentifier("outline-sidebar")
        .onAppear {
            projectViewModel.requestOutlineSidebarData()
        }
        .onDisappear {
            projectViewModel.suspendOutlineSidebarData()
        }
    }

    private var headerView: some View {
        HStack(spacing: RosewoodUI.spacing3) {
            Label("Outline", systemImage: "list.bullet.indent")
                .font(RosewoodType.captionStrong)
                .foregroundColor(themeColors.subduedText)

            Text("\(currentSymbols.count)")
                .font(RosewoodType.monoMicro)
                .foregroundColor(themeColors.mutedText)

            Spacer()
        }
        .padding(.horizontal, RosewoodUI.spacing5)
        .padding(.vertical, RosewoodUI.spacing3)
    }

    private func emptyStateView(message: String) -> some View {
        VStack(spacing: RosewoodUI.spacing3) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 18))
                .foregroundColor(themeColors.mutedText)
            Text(message)
                .font(RosewoodType.caption)
                .foregroundColor(themeColors.mutedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OutlineSymbolRow: View {
    @EnvironmentObject private var configService: ConfigurationService

    let symbol: WorkspaceSymbolMatch
    let isActive: Bool
    let action: () -> Void

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: RosewoodUI.spacing3) {
                Image(systemName: symbol.iconName)
                    .font(RosewoodType.captionStrong)
                    .foregroundColor(isActive ? themeColors.accent : themeColors.mutedText)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol.name)
                        .font(RosewoodType.subheadline)
                        .foregroundColor(themeColors.foreground)
                        .lineLimit(1)

                    HStack(spacing: RosewoodUI.spacing2) {
                        Text(symbol.kindDisplayName)
                            .font(RosewoodType.caption)
                            .foregroundColor(themeColors.mutedText)

                        Text("Ln \(symbol.line)")
                            .font(RosewoodType.monoMicro)
                            .foregroundColor(themeColors.mutedText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, RosewoodUI.spacing3)
            .padding(.vertical, RosewoodUI.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? themeColors.rowSelection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("outline-symbol-row-\(symbol.name.replacingOccurrences(of: " ", with: "-"))")
        .accessibilityValue(isActive ? "active" : "inactive")
    }
}
