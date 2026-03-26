import SwiftUI

struct SourceControlSidebarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ThemedDivider()

            contentView
        }
        .background(themeColors.panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source-control-sidebar")
    }

    private var headerView: some View {
        RosewoodSidebarCard(spacing: 8) {
            HStack(spacing: 8) {
                Label(projectViewModel.gitRepositoryStatus.branchName ?? "No Repository", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeColors.foreground)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel(projectViewModel.gitRepositoryStatus.branchName ?? "No Repository")
                    .accessibilityIdentifier("git-branch-label")

                Spacer()

                Button {
                    projectViewModel.refreshGitState()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(themeColors.mutedText)
                }
                .buttonStyle(.borderless)
                .help("Refresh Git Status")
                .disabled(projectViewModel.rootDirectory == nil)
            }

            if projectViewModel.gitRepositoryStatus.isRepository {
                Text(changeSummaryText)
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.mutedText)
                    .accessibilityIdentifier("git-change-summary")
            } else if projectViewModel.rootDirectory != nil {
                Text("Git is available when the open folder is a repository.")
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.mutedText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var changeSummaryText: String {
        let status = projectViewModel.gitRepositoryStatus

        if status.changedFiles.isEmpty {
            return "Working tree clean"
        }

        return "\(status.changedFiles.count) changed file\(status.changedFiles.count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private var contentView: some View {
        if projectViewModel.rootDirectory == nil {
            SourceControlEmptyStateView(
                iconName: "folder",
                title: "No Folder Open",
                message: "Open a project folder to inspect Git changes."
            )
        } else if projectViewModel.isRefreshingGitStatus && !projectViewModel.gitRepositoryStatus.isRepository {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Checking repository status...")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.subduedText)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !projectViewModel.gitRepositoryStatus.isRepository {
            SourceControlEmptyStateView(
                iconName: "arrow.triangle.branch",
                title: "Not a Git Repository",
                message: "The current folder does not contain a `.git` directory."
            )
        } else if projectViewModel.gitRepositoryStatus.changedFiles.isEmpty {
            SourceControlEmptyStateView(
                iconName: "checkmark.circle",
                title: "Working Tree Clean",
                message: "There are no local Git changes right now."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(projectViewModel.gitRepositoryStatus.changeSections) { section in
                        SourceControlSectionView(section: section)
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct SourceControlSectionView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    let section: GitChangeSectionGroup

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(section.section.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundColor(themeColors.mutedText)

                RosewoodHeaderChip(text: "\(section.files.count)", tint: themeColors.mutedText)

                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(section.files) { changedFile in
                    SourceControlChangeRowView(
                        changedFile: changedFile,
                        rowIndex: projectViewModel.gitRepositoryStatus.changedFiles.firstIndex(of: changedFile) ?? 0
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("git-section-\(section.section.id)")
    }
}

private struct SourceControlChangeRowView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    let changedFile: GitChangedFile
    let rowIndex: Int

    @State private var isHovering = false

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var isSelected: Bool {
        projectViewModel.selectedGitDiffPath == changedFile.path
    }

    private var fileName: String {
        (changedFile.path as NSString).lastPathComponent
    }

    private var parentPath: String? {
        let parent = (changedFile.path as NSString).deletingLastPathComponent
        return parent == "." ? nil : parent
    }

    var body: some View {
        Button {
            projectViewModel.openGitChangedFile(changedFile)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                kindBadge

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(fileName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(themeColors.foreground)
                            .lineLimit(1)

                        if !showInlineActions {
                            stateBadge
                        }
                    }

                    if let parentPath, !parentPath.isEmpty {
                        Text(parentPath)
                            .font(.system(size: 11))
                            .foregroundColor(themeColors.mutedText)
                            .lineLimit(1)
                    }

                    if let previousPath = changedFile.previousPath {
                        Label("from \(previousPath)", systemImage: "arrow.turn.down.right")
                            .font(.system(size: 11))
                            .foregroundColor(themeColors.mutedText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if showInlineActions {
                    inlineActions
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(themeColors.mutedText.opacity(isSelected || isHovering ? 0.9 : 0.45))
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(rowBorder)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fileName)
        .accessibilityValue(changedFile.stateSummary)
        .accessibilityIdentifier("git-change-row-\(rowIndex)")
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var kindBadge: some View {
        Text(changedFile.kind.shortLabel)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color(for: changedFile.kind))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(color(for: changedFile.kind).opacity(0.14))
            )
    }

    private var stateBadge: some View {
        Text(changedFile.stateSummary)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(stateTint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(stateTint.opacity(0.12))
            )
    }

    private var stateTint: Color {
        switch changedFile.section {
        case .conflicted:
            return themeColors.danger
        case .staged:
            return themeColors.success
        case .changes:
            return themeColors.warning
        case .untracked:
            return themeColors.accent
        }
    }

    private var showInlineActions: Bool {
        isHovering || isSelected
    }

    @ViewBuilder
    private var inlineActions: some View {
        HStack(spacing: 6) {
            quickActionButton(
                title: "Open In Editor",
                systemImage: "doc.text",
                tint: themeColors.accent
            ) {
                projectViewModel.openGitChangedFileInEditor(changedFile)
            }

            if changedFile.canStage {
                quickActionButton(
                    title: "Stage Change",
                    systemImage: "square.and.arrow.down",
                    tint: themeColors.success
                ) {
                    projectViewModel.stageGitChange(changedFile)
                }
            }

            if changedFile.canUnstage {
                quickActionButton(
                    title: "Unstage Change",
                    systemImage: "arrow.uturn.backward",
                    tint: themeColors.warning
                ) {
                    projectViewModel.unstageGitChange(changedFile)
                }
            }

            if changedFile.canDiscard {
                quickActionButton(
                    title: changedFile.kind == .untracked ? "Delete File" : "Discard Changes",
                    systemImage: changedFile.kind == .untracked ? "trash" : "arrow.counterclockwise",
                    tint: themeColors.danger
                ) {
                    projectViewModel.discardGitChange(changedFile)
                }
            }
        }
        .padding(.top, 1)
    }

    private func quickActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                isSelected ? themeColors.accentStrong.opacity(0.72) :
                    (isHovering ? themeColors.hoverBackground.opacity(0.28) : themeColors.elevatedBackground.opacity(0.78))
            )
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected ? themeColors.accent.opacity(0.8) : themeColors.border.opacity(0.4), lineWidth: 1)
    }

    private func color(for kind: GitChangeKind) -> Color {
        switch kind {
        case .modified:
            return themeColors.warning
        case .added, .copied:
            return themeColors.success
        case .deleted:
            return themeColors.danger
        case .renamed:
            return themeColors.accent
        case .untracked:
            return themeColors.accent
        case .conflicted:
            return themeColors.danger
        }
    }
}

private struct SourceControlEmptyStateView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let iconName: String
    let title: String
    let message: String

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundColor(themeColors.mutedText)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(themeColors.foreground)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(themeColors.subduedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
