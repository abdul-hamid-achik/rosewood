import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    @ObservedObject private var lspService = LSPService.shared

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var lspStatus: LSPServerStatus? {
        guard let language = projectViewModel.selectedTab?.language,
              language != "plaintext",
              let serverConfig = LSPServerRegistry.configFor(language: language) else {
            return nil
        }
        return lspService.serverStatus[serverConfig.serverKey]
    }

    private var lspStatusText: String? {
        guard let lspStatus else { return nil }

        switch lspStatus {
        case .starting:
            return "LSP Starting"
        case .ready:
            return "LSP Ready"
        case .failed:
            return "LSP Failed"
        case .unavailable:
            return "LSP Unavailable"
        }
    }

    private var lspStatusColor: Color {
        guard let lspStatus else { return themeColors.subduedText }

        switch lspStatus {
        case .starting:
            return themeColors.warning
        case .ready:
            return themeColors.success
        case .failed:
            return themeColors.danger
        case .unavailable:
            return themeColors.subduedText
        }
    }

    private var gitBlameText: String? {
        guard let blame = projectViewModel.currentLineBlame else { return nil }
        return "\(blame.shortCommitHash) \(blame.author): \(blame.summary)"
    }

    var body: some View {
        HStack {
            if let tab = projectViewModel.selectedTab {
                Text(tab.cursorPosition.description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(themeColors.subduedText)

                Spacer()

                Text("UTF-8")
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.subduedText)

                Divider()
                    .frame(height: 12)

                Text(tab.language.capitalized)
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.subduedText)

                if let branchName = projectViewModel.gitRepositoryStatus.branchName {
                    Divider()
                        .frame(height: 12)

                    Label(branchName, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.subduedText)
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel(branchName)
                        .accessibilityIdentifier("statusbar-git-branch")
                }

                if let reviewLabel = projectViewModel.selectedGitChangeReviewLabel {
                    Divider()
                        .frame(height: 12)

                    Label(reviewLabel, systemImage: "square.split.2x1")
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.accent)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .accessibilityIdentifier("statusbar-git-review")
                }

                if let lspStatusText {
                    Divider()
                        .frame(height: 12)

                    Label(lspStatusText, systemImage: "network")
                        .font(.system(size: 11))
                        .foregroundColor(lspStatusColor)
                        .labelStyle(.titleAndIcon)
                }

                if projectViewModel.debugSessionState != .idle {
                    Divider()
                        .frame(height: 12)

                    Text(projectViewModel.debugSessionState.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.accent)
                }

                let diagCount = projectViewModel.currentTabDiagnosticCount
                if diagCount.errors > 0 || diagCount.warnings > 0 {
                    Divider()
                        .frame(height: 12)

                    Button {
                        projectViewModel.toggleDiagnosticsPanel()
                    } label: {
                        HStack(spacing: 8) {
                            if diagCount.errors > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                    Text("\(diagCount.errors)")
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(themeColors.danger)
                            }

                            if diagCount.warnings > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                    Text("\(diagCount.warnings)")
                                        .font(.system(size: 11))
                                }
                        .foregroundColor(themeColors.warning)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 18)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(projectViewModel.isDiagnosticsPanelVisible ? themeColors.hoverBackground.opacity(0.5) : Color.clear)
                        )
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .help(projectViewModel.isDiagnosticsPanelVisible ? "Hide Problems" : "Show Problems")
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Problems")
                    .accessibilityValue("\(diagCount.errors) errors, \(diagCount.warnings) warnings")
                    .accessibilityIdentifier("statusbar-diagnostics-toggle")
                }

                if let gitBlameText, !tab.isDirty {
                    Divider()
                        .frame(height: 12)

                    Text(gitBlameText)
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("statusbar-git-blame")
                }

                if projectViewModel.sidebarMode == .search, !projectViewModel.projectSearchQuery.isEmpty {
                    Divider()
                        .frame(height: 12)

                    Text("\(projectViewModel.projectSearchResults.count) Results")
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.subduedText)
                }
            } else {
                Text("Rosewood")
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.subduedText)

                Spacer()

                if projectViewModel.debugSessionState != .idle {
                    Text(projectViewModel.debugSessionState.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.accent)

                    Divider()
                        .frame(height: 12)
                }

                if let branchName = projectViewModel.gitRepositoryStatus.branchName {
                    Label(branchName, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.subduedText)
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel(branchName)
                        .accessibilityIdentifier("statusbar-git-branch")
                }

                if let reviewLabel = projectViewModel.selectedGitChangeReviewLabel {
                    Divider()
                        .frame(height: 12)

                    Label(reviewLabel, systemImage: "square.split.2x1")
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.accent)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .accessibilityIdentifier("statusbar-git-review")
                }

                if projectViewModel.sidebarMode == .search, !projectViewModel.projectSearchQuery.isEmpty {
                    if projectViewModel.gitRepositoryStatus.branchName != nil || projectViewModel.selectedGitChangeReviewLabel != nil {
                        Divider()
                            .frame(height: 12)
                    }

                    Text("\(projectViewModel.projectSearchResults.count) Results")
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.subduedText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(themeColors.gutterBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(themeColors.border)
                .frame(height: 1)
        }
    }
}
