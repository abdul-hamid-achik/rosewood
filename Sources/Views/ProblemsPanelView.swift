import SwiftUI

struct ProblemsPanelView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var diagnostics: [LSPDiagnostic] {
        projectViewModel.currentTabDiagnostics.sorted { lhs, rhs in
            if severityRank(lhs.severity) != severityRank(rhs.severity) {
                return severityRank(lhs.severity) < severityRank(rhs.severity)
            }
            if lhs.range.start.line != rhs.range.start.line {
                return lhs.range.start.line < rhs.range.start.line
            }
            return lhs.range.start.character < rhs.range.start.character
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .overlay(themeColors.border)

            if diagnostics.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(diagnostics.enumerated()), id: \.element.id) { index, diagnostic in
                            Button {
                                projectViewModel.openDiagnostic(diagnostic)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Image(systemName: iconName(for: diagnostic.severity))
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(color(for: diagnostic.severity))

                                        Text(title(for: diagnostic))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(themeColors.foreground)

                                        Spacer()

                                        Text("Ln \(diagnostic.range.start.line + 1), Col \(diagnostic.range.start.character + 1)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(themeColors.mutedText)
                                    }

                                    Text(diagnostic.message)
                                        .font(.system(size: 12))
                                        .foregroundColor(themeColors.foreground)
                                        .multilineTextAlignment(.leading)

                                    if let source = diagnostic.source, !source.isEmpty {
                                        Text(source)
                                            .font(.system(size: 10))
                                            .foregroundColor(themeColors.mutedText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(themeColors.elevatedBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(title(for: diagnostic)) at line \(diagnostic.range.start.line + 1)")
                            .accessibilityValue(diagnostic.message)
                            .accessibilityIdentifier("diagnostic-row-\(index)")
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minHeight: 150, idealHeight: 180, maxHeight: 240)
        .background(themeColors.panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("problems-panel")
    }

    private var headerView: some View {
        HStack {
            Text("Problems")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeColors.subduedText)
                .accessibilityIdentifier("problems-panel-title")

            Text("\(diagnostics.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeColors.mutedText)

            Spacer()

            Button {
                projectViewModel.toggleDiagnosticsPanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.mutedText)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("problems-panel-close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22))
                .foregroundColor(themeColors.success)
            Text("No problems in the current file.")
                .font(.system(size: 12))
                .foregroundColor(themeColors.subduedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconName(for severity: DiagnosticSeverity?) -> String {
        switch severity {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .information:
            return "info.circle.fill"
        case .hint, nil:
            return "lightbulb.fill"
        }
    }

    private func color(for severity: DiagnosticSeverity?) -> Color {
        switch severity {
        case .error:
            return themeColors.danger
        case .warning:
            return themeColors.warning
        case .information:
            return themeColors.accent
        case .hint, nil:
            return themeColors.success
        }
    }

    private func title(for diagnostic: LSPDiagnostic) -> String {
        switch diagnostic.severity {
        case .error:
            return "Error"
        case .warning:
            return "Warning"
        case .information:
            return "Info"
        case .hint, nil:
            return "Hint"
        }
    }

    private func severityRank(_ severity: DiagnosticSeverity?) -> Int {
        switch severity {
        case .error:
            return 0
        case .warning:
            return 1
        case .information:
            return 2
        case .hint, nil:
            return 3
        }
    }
}
