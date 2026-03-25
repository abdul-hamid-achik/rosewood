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

    private var indentLabel: String {
        "Spaces: \(configService.settings.editor.tabSize)"
    }

    private var wrapLabel: String {
        configService.settings.editor.wordWrap ? "Wrap On" : "Wrap Off"
    }

    private var shouldShowGitMetadata: Bool {
        projectViewModel.sidebarMode != .sourceControl && !projectViewModel.isGitDiffWorkspaceVisible
    }

    @ViewBuilder
    private var diagnosticsToggle: some View {
        let diagCount = projectViewModel.currentTabDiagnosticCount
        let workspaceDiagCount = projectViewModel.workspaceDiagnosticCount
        let hasCurrentProblems = diagCount.errors > 0 || diagCount.warnings > 0
        let hasWorkspaceProblems = workspaceDiagCount.errors > 0 || workspaceDiagCount.warnings > 0

        if hasCurrentProblems || hasWorkspaceProblems {
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

                    if hasWorkspaceProblems && projectViewModel.workspaceDiagnosticFileCount > 1 {
                        Text("WS \(workspaceDiagCount.errors + workspaceDiagCount.warnings)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(themeColors.accent)
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
            .accessibilityValue("\(diagCount.errors) current errors, \(diagCount.warnings) current warnings, \(workspaceDiagCount.errors) workspace errors, \(workspaceDiagCount.warnings) workspace warnings")
            .accessibilityIdentifier("statusbar-diagnostics-toggle")
        }
    }

    var body: some View {
        HStack {
            if let tab = projectViewModel.selectedTab {
                statusMonospaceText(tab.cursorPosition.description)
                    .accessibilityLabel(tab.cursorPosition.description)
                    .accessibilityValue(tab.cursorPosition.description)
                    .accessibilityIdentifier("statusbar-cursor-position")

                Spacer()

                statusText(indentLabel)
                    .accessibilityIdentifier("statusbar-indent-width")

                statusDivider

                statusText(wrapLabel)
                    .accessibilityIdentifier("statusbar-wrap-mode")

                statusDivider

                if let lineEndingLabel = projectViewModel.selectedTabLineEndingLabel {
                    statusText(lineEndingLabel)
                        .accessibilityIdentifier("statusbar-line-endings")

                    statusDivider
                }

                if let encodingLabel = projectViewModel.selectedTabEncodingLabel {
                    statusText(encodingLabel)
                        .accessibilityIdentifier("statusbar-file-encoding")

                    statusDivider
                }

                statusText(tab.language.capitalized)

                if shouldShowGitMetadata,
                   let branchName = projectViewModel.gitRepositoryStatus.branchName {
                    statusDivider

                    Label(branchName, systemImage: "arrow.triangle.branch")
                        .font(RosewoodType.caption)
                        .foregroundColor(themeColors.subduedText)
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel(branchName)
                        .accessibilityIdentifier("statusbar-git-branch")
                }

                if shouldShowGitMetadata,
                   let reviewLabel = projectViewModel.selectedGitChangeReviewLabel {
                    statusDivider

                    Label(reviewLabel, systemImage: "square.split.2x1")
                        .font(RosewoodType.caption)
                        .foregroundColor(themeColors.accent)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .accessibilityIdentifier("statusbar-git-review")
                }

                if let lspStatusText {
                    statusDivider

                    Label(lspStatusText, systemImage: "network")
                        .font(RosewoodType.caption)
                        .foregroundColor(lspStatusColor)
                        .labelStyle(.titleAndIcon)
                }

                if projectViewModel.currentTabDiagnosticCount.errors > 0
                    || projectViewModel.currentTabDiagnosticCount.warnings > 0
                    || projectViewModel.workspaceDiagnosticCount.errors > 0
                    || projectViewModel.workspaceDiagnosticCount.warnings > 0 {
                    statusDivider

                    diagnosticsToggle
                }

                if projectViewModel.debugSessionState != .idle {
                    statusDivider

                    statusText(projectViewModel.debugSessionState.statusText, color: themeColors.accent)
                }

                if let gitBlameText, !tab.isDirty {
                    statusDivider

                    Text(gitBlameText)
                        .font(RosewoodType.caption)
                        .foregroundColor(themeColors.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("statusbar-git-blame")
                }
            } else {
                Spacer()

                if projectViewModel.debugSessionState != .idle {
                    statusText(projectViewModel.debugSessionState.statusText, color: themeColors.accent)

                    if projectViewModel.workspaceDiagnosticCount.errors > 0
                        || projectViewModel.workspaceDiagnosticCount.warnings > 0
                        || (shouldShowGitMetadata && projectViewModel.gitRepositoryStatus.branchName != nil)
                        || (shouldShowGitMetadata && projectViewModel.selectedGitChangeReviewLabel != nil) {
                        statusDivider
                    }
                }

                if projectViewModel.workspaceDiagnosticCount.errors > 0
                    || projectViewModel.workspaceDiagnosticCount.warnings > 0 {
                    diagnosticsToggle

                    if shouldShowGitMetadata,
                       (projectViewModel.gitRepositoryStatus.branchName != nil
                        || projectViewModel.selectedGitChangeReviewLabel != nil) {
                        statusDivider
                    }
                }

                if shouldShowGitMetadata,
                   let branchName = projectViewModel.gitRepositoryStatus.branchName {
                    Label(branchName, systemImage: "arrow.triangle.branch")
                        .font(RosewoodType.caption)
                        .foregroundColor(themeColors.subduedText)
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel(branchName)
                        .accessibilityIdentifier("statusbar-git-branch")
                }

                if shouldShowGitMetadata,
                   let reviewLabel = projectViewModel.selectedGitChangeReviewLabel {
                    statusDivider

                    Label(reviewLabel, systemImage: "square.split.2x1")
                        .font(RosewoodType.caption)
                        .foregroundColor(themeColors.accent)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .accessibilityIdentifier("statusbar-git-review")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: RosewoodUI.statusBarHeight)
        .background(themeColors.gutterBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(themeColors.border)
                .frame(height: 1)
        }
    }

    private var statusDivider: some View {
        ThemedDivider(Axis.vertical)
            .frame(height: 12)
    }

    private func statusText(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(RosewoodType.caption)
            .foregroundColor(color ?? themeColors.subduedText)
    }

    private func statusMonospaceText(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(RosewoodType.monoCaption)
            .foregroundColor(color ?? themeColors.subduedText)
    }
}
