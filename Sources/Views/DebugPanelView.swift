import SwiftUI

struct DebugPanelView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    @EnvironmentObject private var debugModel: DebugModel

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ThemedDivider()

            if debugModel.debugConsoleEntries.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RosewoodUI.spacing3) {
                        ForEach(debugModel.debugConsoleEntries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: RosewoodUI.spacing3) {
                                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(RosewoodType.monoMicro)
                                        .foregroundColor(themeColors.mutedText)

                                    Text(entry.kind.rawValue.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(color(for: entry.kind))
                                }

                                Text(entry.message)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(themeColors.foreground)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(RosewoodUI.spacing4)
                            .background(themeColors.elevatedBackground)
                            .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall))
                        }
                    }
                    .padding(RosewoodUI.spacing5)
                }
            }
        }
        .background(themeColors.panelBackground)
    }

    private var headerView: some View {
        HStack {
            Text("Debug Console")
                .font(RosewoodType.subheadlineStrong)
                .foregroundColor(themeColors.subduedText)

            Spacer()

            Button("Clear") {
                projectViewModel.clearDebugConsole()
            }
            .buttonStyle(.borderless)
            .foregroundColor(themeColors.accent)

            Button {
                projectViewModel.toggleDebugPanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.mutedText)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, RosewoodUI.spacing5)
        .padding(.vertical, RosewoodUI.spacing3)
    }

    private var emptyStateView: some View {
        RosewoodEmptyState(systemImage: "terminal", title: "Debugger output will appear here.")
    }

    private func color(for kind: DebugConsoleEntry.Kind) -> Color {
        switch kind {
        case .info:
            return themeColors.accent
        case .success:
            return themeColors.success
        case .warning:
            return themeColors.warning
        case .error:
            return themeColors.danger
        }
    }
}
