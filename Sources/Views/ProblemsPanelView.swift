import SwiftUI

struct ProblemsPanelView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var diagnostics: [LSPDiagnostic] {
        projectViewModel.orderedCurrentTabDiagnostics
    }

    private var workspaceDiagnostics: [WorkspaceDiagnosticItem] {
        projectViewModel.orderedWorkspaceDiagnostics
    }

    private var showsWorkspaceScope: Bool {
        projectViewModel.hasWorkspaceDiagnostics
    }

    private var hasVisibleProblems: Bool {
        switch projectViewModel.diagnosticsPanelScope {
        case .currentFile:
            return !diagnostics.isEmpty
        case .workspace:
            return !workspaceDiagnostics.isEmpty
        }
    }

    private var summaryText: String {
        let counts: (errors: Int, warnings: Int)
        switch projectViewModel.diagnosticsPanelScope {
        case .currentFile:
            counts = projectViewModel.currentTabDiagnosticCount
        case .workspace:
            counts = projectViewModel.workspaceDiagnosticCount
        }
        let parts = [
            counts.errors == 1 ? "1 error" : "\(counts.errors) errors",
            counts.warnings == 1 ? "1 warning" : "\(counts.warnings) warnings"
        ]
        return parts.joined(separator: " · ")
    }

    private var visibleProblemCount: Int {
        switch projectViewModel.diagnosticsPanelScope {
        case .currentFile:
            diagnostics.count
        case .workspace:
            workspaceDiagnostics.count
        }
    }

    private var scopeSummaryText: String? {
        guard projectViewModel.diagnosticsPanelScope == .workspace else { return nil }
        let fileCount = projectViewModel.workspaceDiagnosticFileCount
        return "\(fileCount) file\(fileCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ThemedDivider()

            if !hasVisibleProblems {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if projectViewModel.diagnosticsPanelScope == .currentFile {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(diagnostics.enumerated()), id: \.element.id) { index, diagnostic in
                                    diagnosticRow(diagnostic, index: index)
                                        .id(diagnostic.id)
                                }
                            }
                            .padding(12)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(workspaceDiagnostics.enumerated()), id: \.element.id) { index, diagnostic in
                                    workspaceDiagnosticRow(diagnostic, index: index)
                                        .id(diagnostic.id)
                                }
                            }
                            .padding(12)
                        }
                    }
                    .onAppear {
                        scrollToActiveDiagnostic(using: proxy)
                    }
                    .onChange(of: projectViewModel.activeProblemScrollID) { _, _ in
                        scrollToActiveDiagnostic(using: proxy)
                    }
                }
            }
        }
        .background(themeColors.panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("problems-panel")
    }

    private var headerView: some View {
        HStack {
            Text("Problems")
                .font(RosewoodType.subheadlineStrong)
                .foregroundColor(themeColors.subduedText)
                .accessibilityIdentifier("problems-panel-title")

            Text("\(visibleProblemCount)")
                .font(RosewoodType.monoCaption)
                .foregroundColor(themeColors.mutedText)

            Text(summaryText)
                .font(RosewoodType.caption)
                .foregroundColor(themeColors.mutedText)
                .accessibilityIdentifier("problems-panel-summary")

            if let scopeSummaryText {
                Text(scopeSummaryText)
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)
                    .accessibilityIdentifier("problems-panel-scope-summary")
            }

            if let currentProblemPositionText = projectViewModel.currentProblemPositionText {
                Text(currentProblemPositionText)
                    .font(RosewoodType.monoCaption)
                    .foregroundColor(themeColors.accent)
                    .accessibilityLabel(currentProblemPositionText)
                    .accessibilityValue(currentProblemPositionText)
                    .accessibilityIdentifier("problems-panel-position")
            }

            Spacer()

            if showsWorkspaceScope {
                scopeButton(
                    title: "File",
                    isSelected: projectViewModel.diagnosticsPanelScope == .currentFile,
                    accessibilityIdentifier: "problems-scope-current-file"
                ) {
                    projectViewModel.setDiagnosticsPanelScope(.currentFile)
                }

                scopeButton(
                    title: "Workspace",
                    isSelected: projectViewModel.diagnosticsPanelScope == .workspace,
                    accessibilityIdentifier: "problems-scope-workspace"
                ) {
                    projectViewModel.setDiagnosticsPanelScope(.workspace)
                }
            }

            Button {
                projectViewModel.openPreviousProblem()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.mutedText)
            }
            .buttonStyle(.borderless)
            .disabled(!projectViewModel.canNavigateProblems)
            .accessibilityIdentifier("problems-panel-previous")

            Button {
                projectViewModel.openNextProblem()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeColors.mutedText)
            }
            .buttonStyle(.borderless)
            .disabled(!projectViewModel.canNavigateProblems)
            .accessibilityIdentifier("problems-panel-next")

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
            Text(projectViewModel.diagnosticsPanelScope == .workspace ? "No problems in the workspace." : "No problems in the current file.")
                .font(RosewoodType.subheadline)
                .foregroundColor(themeColors.subduedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func diagnosticRow(_ diagnostic: LSPDiagnostic, index: Int) -> some View {
        let isActive = projectViewModel.isActiveDiagnostic(diagnostic)

        return Button {
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

                    if isActive {
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 9))
                            .foregroundColor(themeColors.accent)
                            .accessibilityHidden(true)
                    }

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
            .background(isActive ? themeColors.hoverBackground : themeColors.elevatedBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? themeColors.accent : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title(for: diagnostic)) at line \(diagnostic.range.start.line + 1)")
        .accessibilityValue(isActive ? "Active problem. \(diagnostic.message)" : diagnostic.message)
        .accessibilityIdentifier("diagnostic-row-\(index)")
    }

    private func workspaceDiagnosticRow(_ diagnostic: WorkspaceDiagnosticItem, index: Int) -> some View {
        let isActive = projectViewModel.activeWorkspaceDiagnostic?.id == diagnostic.id

        return Button {
            projectViewModel.openWorkspaceDiagnostic(diagnostic)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: diagnostic.diagnostic.severity))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color(for: diagnostic.diagnostic.severity))

                    Text(diagnostic.displayPath)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(themeColors.foreground)
                        .lineLimit(1)

                    if isActive {
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 9))
                            .foregroundColor(themeColors.accent)
                            .accessibilityHidden(true)
                    }

                    Spacer()

                    Text("Ln \(diagnostic.lineNumber), Col \(diagnostic.columnNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeColors.mutedText)
                }

                Text(diagnostic.diagnostic.message)
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.foreground)
                    .multilineTextAlignment(.leading)

                if !diagnostic.lineText.isEmpty {
                    Text(diagnostic.lineText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(themeColors.mutedText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isActive ? themeColors.hoverBackground : themeColors.elevatedBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? themeColors.accent : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(diagnostic.displayPath) at line \(diagnostic.lineNumber)")
        .accessibilityValue(isActive ? "Active problem. \(diagnostic.diagnostic.message)" : diagnostic.diagnostic.message)
        .accessibilityIdentifier("workspace-diagnostic-row-\(index)")
    }

    private func scopeButton(
        title: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? themeColors.background : themeColors.subduedText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? themeColors.accent : themeColors.hoverBackground.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func scrollToActiveDiagnostic(using proxy: ScrollViewProxy) {
        guard let activeProblemScrollID = projectViewModel.activeProblemScrollID else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(activeProblemScrollID, anchor: .center)
        }
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
}
