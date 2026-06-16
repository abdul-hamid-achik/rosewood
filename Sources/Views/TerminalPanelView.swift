import SwiftUI

struct TerminalPanelView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject var terminalModel: TerminalModel
    @EnvironmentObject private var configService: ConfigurationService
    @ObservedObject private var terminalController = TerminalProcessController.shared

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ThemedDivider()

            if terminalModel.terminalSessions.isEmpty {
                emptyStateView
            } else {
                terminalContent
            }
        }
        .background(themeColors.panelBackground)
    }

    private var headerView: some View {
        HStack {
            Text("Terminal")
                .font(RosewoodType.subheadlineStrong)
                .foregroundColor(themeColors.subduedText)

            Spacer()

            if !terminalModel.terminalSessions.isEmpty {
                sessionPicker

                Button {
                    terminalModel.createTerminalSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(themeColors.mutedText)
                }
                .buttonStyle(.borderless)
                .help("New Terminal")
            }

            Button {
                projectViewModel.bottomPanel = nil
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

    private var sessionPicker: some View {
        Menu {
            ForEach(terminalModel.terminalSessions) { session in
                Button {
                    terminalModel.selectTerminalSession(session.id)
                } label: {
                    HStack {
                        Text(session.displayName)
                        if session.id == terminalModel.currentTerminalSessionId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            if let currentId = terminalModel.currentTerminalSessionId {
                Button(role: .destructive) {
                    terminalModel.closeTerminalSession(currentId)
                } label: {
                    Label("Close Current", systemImage: "xmark")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentSessionName)
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.foreground)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(themeColors.mutedText)
            }
        }
        .buttonStyle(.borderless)
    }

    private var currentSessionName: String {
        guard let currentId = terminalModel.currentTerminalSessionId,
              let session = terminalModel.terminalSessions.first(where: { $0.id == currentId }) else {
            return "Terminal"
        }
        return session.displayName
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let currentId = terminalModel.currentTerminalSessionId,
           let session = terminalModel.terminalSessions.first(where: { $0.id == currentId }) {
            ZStack {
                SwiftTermTerminalView(
                    session: session,
                    themeColors: themeColors,
                    font: configService.currentTerminalFont
                )
                .id(session.id)

                if let exitCode = terminalController.exitedSessions[session.id] {
                    exitedOverlay(session: session, exitCode: exitCode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func exitedOverlay(session: TerminalSession, exitCode: Int32?) -> some View {
        VStack(spacing: RosewoodUI.spacing4) {
            Text(exitCode.map { "Process exited (code \($0))" } ?? "Process exited")
                .font(RosewoodType.subheadlineStrong)
                .foregroundColor(themeColors.foreground)

            HStack(spacing: RosewoodUI.spacing3) {
                Button("Restart") {
                    terminalController.restart(session.id)
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    terminalModel.closeTerminalSession(session.id)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(RosewoodUI.spacing6)
        .background(themeColors.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium)
                .stroke(themeColors.border.opacity(RosewoodUI.borderOpacitySubtle), lineWidth: 1)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: RosewoodUI.spacing5) {
            RosewoodEmptyState(
                systemImage: "terminal",
                title: "No terminals open",
                subtitle: "Open a terminal to run commands in your project.",
                fillsHeight: false
            )

            Button("Open Terminal") {
                projectViewModel.openLocalTerminal()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
