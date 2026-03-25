import SwiftUI

struct DebugPanelView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ThemedDivider()

            if projectViewModel.debugConsoleEntries.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(projectViewModel.debugConsoleEntries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 10, design: .monospaced))
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
                            .padding(10)
                            .background(themeColors.elevatedBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 22))
                .foregroundColor(themeColors.mutedText)
            Text("Debugger output will appear here.")
                .font(RosewoodType.subheadline)
                .foregroundColor(themeColors.subduedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
