import SwiftUI

struct ReferencesPanelView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .overlay(themeColors.border)

            if projectViewModel.referenceResults.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(projectViewModel.referenceResults.enumerated()), id: \.element.id) { index, result in
                            Button {
                                projectViewModel.openReferenceResult(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(result.path)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(themeColors.foreground)

                                        Spacer()

                                        Text("Ln \(result.line), Col \(result.column)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(themeColors.mutedText)
                                    }

                                    Text(result.lineText.isEmpty ? "No preview available" : result.lineText)
                                        .font(.system(size: 12))
                                        .foregroundColor(themeColors.subduedText)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(themeColors.elevatedBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Reference in \(result.path) at line \(result.line)")
                            .accessibilityValue(result.lineText)
                            .accessibilityIdentifier("reference-row-\(index)")
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minHeight: 150, idealHeight: 180, maxHeight: 240)
        .background(themeColors.panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("references-panel")
    }

    private var headerView: some View {
        HStack {
            Text("References")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeColors.subduedText)
                .accessibilityIdentifier("references-panel-title")

            Text("\(projectViewModel.referenceResults.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeColors.mutedText)

            Spacer()

            Button {
                projectViewModel.closeReferencesPanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.mutedText)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("references-panel-close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "scope")
                .font(.system(size: 22))
                .foregroundColor(themeColors.accent)
            Text("No references found.")
                .font(.system(size: 12))
                .foregroundColor(themeColors.subduedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
