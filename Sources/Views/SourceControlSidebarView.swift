import SwiftUI

struct SourceControlSidebarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    // Observed so git status/changes re-render here (the data lives on GitModel now; the view model
    // no longer publishes on git change). Reads stay via projectViewModel forwarders.
    @EnvironmentObject private var gitModel: GitModel
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
        RosewoodSidebarCard(spacing: RosewoodUI.spacing3) {
            HStack(spacing: RosewoodUI.spacing3) {
                Label(projectViewModel.gitRepositoryStatus.branchName ?? "No Repository", systemImage: "arrow.triangle.branch")
                    .font(RosewoodType.subheadlineStrong)
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
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)
                    .accessibilityIdentifier("git-change-summary")
            } else if projectViewModel.rootDirectory != nil {
                Text("Git is available when the open folder is a repository.")
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)
            }
        }
        .padding(RosewoodUI.spacing3)
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
        } else if !projectViewModel.isGitToolAvailable {
            SourceControlEmptyStateView(
                iconName: "exclamationmark.triangle",
                title: "Git Not Available",
                message: "Git couldn’t be found on your PATH. Install Git (or make sure it’s on your PATH) to enable source control."
            )
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
            VStack(spacing: 0) {
                commitBox
                ThemedDivider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RosewoodUI.spacing6) {
                        ForEach(projectViewModel.gitChangeSections) { section in
                            SourceControlSectionView(section: section)
                        }
                    }
                    .padding(RosewoodUI.spacing3)
                }
            }
        }
    }

    private var commitBox: some View {
        VStack(alignment: .leading, spacing: RosewoodUI.spacing3) {
            TextField("Message (commits staged changes)", text: $gitModel.commitMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(RosewoodType.body)
                .foregroundColor(themeColors.foreground)
                .lineLimit(1...4)
                .padding(RosewoodUI.spacing3)
                .background(themeColors.background)
                .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall)
                        .stroke(themeColors.border.opacity(RosewoodUI.borderOpacitySubtle), lineWidth: 1)
                )

            Button {
                projectViewModel.commitStagedChanges()
            } label: {
                Label("Commit", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(themeColors.accent)
            .disabled(!projectViewModel.canCommitStagedChanges)
        }
        .padding(RosewoodUI.spacing4)
    }
}

private struct SourceControlSectionView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    // Observed so git status/changes re-render here (the data lives on GitModel now; the view model
    // no longer publishes on git change). Reads stay via projectViewModel forwarders.
    @EnvironmentObject private var gitModel: GitModel
    @EnvironmentObject private var configService: ConfigurationService

    let section: GitChangeSectionGroup

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RosewoodUI.spacing3) {
            HStack(spacing: RosewoodUI.spacing2) {
                Text(section.section.title.uppercased())
                    .font(RosewoodType.micro)
                    .kerning(0.6)
                    .foregroundColor(themeColors.mutedText)

                Text("\(section.files.count)")
                    .font(RosewoodType.monoMicro)
                    .foregroundColor(themeColors.mutedText)

                Spacer()
            }
            .padding(.horizontal, RosewoodUI.spacing2)

            VStack(spacing: 1) {
                ForEach(section.files) { changedFile in
                    SourceControlChangeRowView(
                        changedFile: changedFile,
                        rowIndex: projectViewModel.gitChangeIndex(for: changedFile)
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
    // Observed so git status/changes re-render here (the data lives on GitModel now; the view model
    // no longer publishes on git change). Reads stay via projectViewModel forwarders.
    @EnvironmentObject private var gitModel: GitModel
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
            HStack(spacing: RosewoodUI.spacing3) {
                kindBadge

                Text(fileName)
                    .font(RosewoodType.subheadline)
                    .foregroundColor(themeColors.foreground)
                    .lineLimit(1)
                    .layoutPriority(1)

                if let parentPath, !parentPath.isEmpty {
                    Text(parentPath)
                        .font(RosewoodType.caption)
                        .foregroundColor(themeColors.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: RosewoodUI.spacing3)

                if showInlineActions {
                    inlineActions
                }
            }
            .padding(.horizontal, RosewoodUI.spacing3)
            .frame(height: RosewoodUI.rowHeightCompact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(rowBorder)
        }
        .buttonStyle(.plain)
        .help(parentPath.map { "\($0)/\(fileName)" } ?? fileName)
        .accessibilityLabel(fileName)
        .accessibilityValue(changedFile.stateSummary)
        .accessibilityIdentifier("git-change-row-\(rowIndex)")
        .onHover { hovering in
            withAnimation(.rosewoodFast) {
                isHovering = hovering
            }
        }
    }

    private var kindBadge: some View {
        Text(changedFile.kind.shortLabel)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color(for: changedFile.kind))
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: RosewoodUI.radiusXSmall)
                    .fill(color(for: changedFile.kind).opacity(0.18))
            )
    }

    private var showInlineActions: Bool {
        isHovering || isSelected
    }

    @ViewBuilder
    private var inlineActions: some View {
        HStack(spacing: RosewoodUI.spacing2) {
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
    }

    private func quickActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        RosewoodPanelIconButton(systemImage: systemImage, tint: tint, isEnabled: true, action: action)
            .help(title)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall)
            .fill(
                isSelected ? themeColors.accentStrong.opacity(RosewoodUI.stateOpacitySelected) :
                    (isHovering ? themeColors.hoverBackground.opacity(RosewoodUI.stateOpacityHover) : Color.clear)
            )
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: RosewoodUI.radiusSmall)
            .stroke(
                isSelected ? themeColors.accent.opacity(RosewoodUI.borderOpacityMid) : Color.clear,
                lineWidth: 1
            )
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
