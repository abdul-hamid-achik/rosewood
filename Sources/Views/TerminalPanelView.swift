import SwiftUI

struct TerminalPanelView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ThemedDivider()

            if projectViewModel.terminalSessions.isEmpty {
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

            if !projectViewModel.terminalSessions.isEmpty {
                sessionPicker
                
                Button {
                    projectViewModel.createTerminalSession()
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sessionPicker: some View {
        Menu {
            ForEach(projectViewModel.terminalSessions) { session in
                Button {
                    projectViewModel.selectTerminalSession(session.id)
                } label: {
                    HStack {
                        Text(session.displayName)
                        if session.id == projectViewModel.currentTerminalSessionId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            if let currentId = projectViewModel.currentTerminalSessionId {
                Button(role: .destructive) {
                    projectViewModel.closeTerminalSession(currentId)
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
        guard let currentId = projectViewModel.currentTerminalSessionId,
              let session = projectViewModel.terminalSessions.first(where: { $0.id == currentId }) else {
            return "Terminal"
        }
        return session.displayName
    }

    private var terminalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Terminal emulation requires SwiftTerm library.")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.mutedText)
                    .padding()
                
                if let currentId = projectViewModel.currentTerminalSessionId,
                   let session = projectViewModel.terminalSessions.first(where: { $0.id == currentId }) {
                    sessionInfo(session)
                }
            }
            .padding(12)
        }
    }

    private func sessionInfo(_ session: TerminalSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Session Type:")
                    .font(RosewoodType.captionStrong)
                    .foregroundColor(themeColors.mutedText)
                Text(session.type.displayName)
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.foreground)
            }
            
            HStack {
                Text("Created:")
                    .font(RosewoodType.captionStrong)
                    .foregroundColor(themeColors.mutedText)
                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.foreground)
            }
        }
        .padding(8)
        .background(themeColors.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundColor(themeColors.mutedText)
            
            Text("No terminals open")
                .font(RosewoodType.subheadline)
                .foregroundColor(themeColors.subduedText)
            
            Button("Open Terminal") {
                projectViewModel.openLocalTerminal()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}