import SwiftUI

struct OutlineSidebarView: View {
    @EnvironmentObject private var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if projectViewModel.currentFileSymbols.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(projectViewModel.currentFileSymbols) { symbol in
                            OutlineSymbolRow(
                                symbol: symbol,
                                isActive: projectViewModel.activeCurrentFileSymbolID == symbol.id
                            ) {
                                projectViewModel.openWorkspaceSymbol(symbol)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(themeColors.panelBackground)
        .accessibilityIdentifier("outline-sidebar")
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Label("Outline", systemImage: "list.bullet.indent")
                .font(RosewoodType.captionStrong)
                .foregroundColor(themeColors.subduedText)

            Text("\(projectViewModel.currentFileSymbols.count)")
                .font(RosewoodType.monoMicro)
                .foregroundColor(themeColors.mutedText)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 18))
                .foregroundColor(themeColors.mutedText)
            Text("No symbols in the current file")
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
            HStack(spacing: 8) {
                Image(systemName: symbol.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isActive ? themeColors.accent : themeColors.mutedText)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol.name)
                        .font(RosewoodType.subheadline)
                        .foregroundColor(themeColors.foreground)
                        .lineLimit(1)

                    HStack(spacing: 6) {
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
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? themeColors.rowSelection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("outline-symbol-row-\(symbol.name.replacingOccurrences(of: " ", with: "-"))")
        .accessibilityValue(isActive ? "active" : "inactive")
    }
}
