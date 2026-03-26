import SwiftUI

struct DockerLogsPanelView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    
    @State private var logLines: [LogLine] = []
    @State private var isStreaming: Bool = false
    @State private var autoScroll: Bool = true
    
    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            ThemedDivider()
            
            if logLines.isEmpty && !isStreaming {
                emptyStateView
            } else {
                logContentView
            }
        }
        .background(themeColors.panelBackground)
        .onAppear {
            startStreamingLogs()
        }
        .onDisappear {
            stopStreamingLogs()
        }
    }
    
    private var headerView: some View {
        HStack {
            if let container = projectViewModel.selectedContainer {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(for: container.status))
                        .frame(width: 8, height: 8)
                    
                    Text(container.displayName)
                        .font(RosewoodType.subheadlineStrong)
                        .foregroundColor(themeColors.foreground)
                        .lineLimit(1)
                    
                    Text(container.status.displayText)
                        .font(RosewoodType.micro)
                        .foregroundColor(statusColor(for: container.status))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(for: container.status).opacity(0.12))
                        .clipShape(Capsule())
                }
            } else {
                Text("Container Logs")
                    .font(RosewoodType.subheadlineStrong)
                    .foregroundColor(themeColors.subduedText)
            }
            
            Spacer()
            
            Button {
                clearLogs()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.mutedText)
            }
            .buttonStyle(.borderless)
            .help("Clear Logs")
            
            Button {
                autoScroll.toggle()
            } label: {
                Image(systemName: autoScroll ? "scroll.fill" : "scroll")
                    .font(.system(size: 11))
                    .foregroundColor(autoScroll ? themeColors.accent : themeColors.mutedText)
            }
            .buttonStyle(.borderless)
            .help(autoScroll ? "Disable Auto-scroll" : "Enable Auto-scroll")
            
            Button {
                projectViewModel.bottomPanel = nil
                projectViewModel.selectedContainer = nil
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
    
    private var logContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(logLines) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(streamColor(for: line.stream))
                                .frame(width: 6, height: 6)
                                .padding(.top, 4)
                            
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(themeColors.foreground)
                                .textSelection(.enabled)
                        }
                        .id(line.id)
                    }
                    
                    if isStreaming {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Streaming...")
                                .font(.system(size: 10))
                                .foregroundColor(themeColors.mutedText)
                        }
                        .id("streaming-indicator")
                    }
                }
                .padding(8)
            }
            .onChange(of: logLines.count) { _ in
                if autoScroll, let lastId = logLines.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            if isStreaming {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading logs...")
                    .font(RosewoodType.subheadline)
                    .foregroundColor(themeColors.subduedText)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 28))
                    .foregroundColor(themeColors.mutedText)
                Text("No logs to display")
                    .font(RosewoodType.subheadline)
                    .foregroundColor(themeColors.subduedText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func startStreamingLogs() {
        guard let container = projectViewModel.selectedContainer else { return }
        
        isStreaming = true
        logLines = []
        
        Task {
            let stream = projectViewModel.getLogStream(for: container.id, tail: 500)
            for await line in stream {
                await MainActor.run {
                    logLines.append(line)
                    
                    if logLines.count > 10000 {
                        logLines.removeFirst(logLines.count - 10000)
                    }
                }
            }
            
            await MainActor.run {
                isStreaming = false
            }
        }
    }
    
    private func stopStreamingLogs() {
        isStreaming = false
    }
    
    private func clearLogs() {
        logLines = []
    }
    
    private func statusColor(for status: DockerContainerStatus) -> Color {
        switch status {
        case .running:
            return themeColors.success
        case .paused:
            return themeColors.warning
        case .restarting:
            return themeColors.accent
        case .created, .exited:
            return themeColors.mutedText
        case .dead, .removing:
            return themeColors.danger
        }
    }
    
    private func streamColor(for stream: LogStream) -> Color {
        switch stream {
        case .stdout:
            return themeColors.success
        case .stderr:
            return themeColors.danger
        }
    }
}