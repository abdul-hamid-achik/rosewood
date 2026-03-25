import SwiftUI

struct DebugSidebarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sessionSection
                configurationSection
                breakpointSection
            }
            .padding(12)
        }
        .background(themeColors.panelBackground)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Session")

            HStack(spacing: 8) {
                Circle()
                    .fill(projectViewModel.debugSessionState == .idle ? themeColors.mutedText : themeColors.accent)
                    .frame(width: 8, height: 8)

                Text(debugSessionSummary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(themeColors.foreground)
            }

            HStack(spacing: 8) {
                Button(projectViewModel.debugPrimaryActionTitle) {
                    projectViewModel.startDebugging()
                }
                .buttonStyle(.borderedProminent)
                .tint(themeColors.accentStrong)
                .disabled(!projectViewModel.canStartDebugging)

                Button("Stop") {
                    projectViewModel.stopDebugging()
                }
                .buttonStyle(.bordered)
                .disabled(!projectViewModel.canStopDebugging)
            }

            Button(projectViewModel.isDebugPanelVisible ? "Hide Console" : "Show Console") {
                projectViewModel.toggleDebugPanel()
            }
            .buttonStyle(.borderless)
            .foregroundColor(themeColors.accent)

            if projectViewModel.canOpenCurrentDebugStopLocation {
                Button("Open Stop Location") {
                    projectViewModel.openCurrentDebugStopLocation()
                }
                .buttonStyle(.borderless)
                .foregroundColor(themeColors.warning)
            }

            if let helperText = debugSessionHelperText {
                Text(helperText)
                    .font(.system(size: 11))
                    .foregroundColor(themeColors.mutedText)
            }

            if let latestConsoleEntry = projectViewModel.debugConsoleEntries.last {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(latestConsoleEntry.kind.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(color(for: latestConsoleEntry.kind))

                        Text(latestConsoleEntry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(themeColors.mutedText)
                    }

                    Text(latestConsoleEntry.message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(themeColors.subduedText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(themeColors.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Configuration")

            if projectViewModel.rootDirectory == nil {
                Text("Open a folder to configure debugging.")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.subduedText)
            } else if let error = projectViewModel.debugConfigurationError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.danger)
            } else if projectViewModel.debugConfigurations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a launch config to `.rosewood.toml` to run or attach here.")
                        .font(.system(size: 12))
                        .foregroundColor(themeColors.subduedText)

                    if !projectViewModel.hasProjectConfigFile {
                        Button("Create Project Config") {
                            projectViewModel.createProjectConfig()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Picker(
                    "Configuration",
                    selection: Binding(
                        get: { projectViewModel.selectedDebugConfigurationName ?? "" },
                        set: { projectViewModel.selectDebugConfiguration(named: $0) }
                    )
                ) {
                    ForEach(projectViewModel.debugConfigurations) { configuration in
                        Text(configuration.name).tag(configuration.name)
                    }
                }
                .pickerStyle(.menu)

                if let configuration = projectViewModel.selectedDebugConfiguration {
                    VStack(alignment: .leading, spacing: 4) {
                        debugMetadata(label: "Adapter", value: configuration.adapter)
                        debugMetadata(label: "Program", value: configuration.program)
                        debugMetadata(label: "Working Dir", value: configuration.cwd ?? ".")
                        if let preLaunchTask = configuration.preLaunchTask, !preLaunchTask.isEmpty {
                            debugMetadata(label: "preLaunchTask", value: preLaunchTask)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(themeColors.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var breakpointSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Breakpoints")

            if projectViewModel.breakpoints.isEmpty {
                Text("Click the editor gutter to add a breakpoint.")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.subduedText)
            } else {
                ForEach(projectViewModel.breakpoints) { breakpoint in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(themeColors.danger)
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)

                        Button {
                            projectViewModel.openBreakpoint(breakpoint)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(breakpoint.fileName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(themeColors.foreground)
                                Text("Line \(breakpoint.line)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(themeColors.subduedText)
                                Text(breakpoint.directoryPath)
                                    .font(.system(size: 11))
                                    .foregroundColor(themeColors.mutedText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button {
                            projectViewModel.removeBreakpoint(breakpoint)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(themeColors.mutedText)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(themeColors.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(themeColors.subduedText)
    }

    private func color(for kind: DebugConsoleEntry.Kind) -> Color {
        switch kind {
        case .info:
            return themeColors.accent
        case .success:
            return themeColors.success
        case .warning:
            return themeColors.warning
        case .error:
            return themeColors.danger
        }
    }

    private var debugSessionSummary: String {
        if projectViewModel.debugSessionState != .idle {
            return projectViewModel.debugSessionState.statusText
        }

        if let selectedDebugConfigurationName = projectViewModel.selectedDebugConfigurationName {
            return selectedDebugConfigurationName
        }

        return "Not Configured"
    }

    private var debugSessionHelperText: String? {
        guard projectViewModel.debugSessionState == .idle else { return nil }

        if projectViewModel.rootDirectory == nil {
            return "Open a folder to enable launch configurations and breakpoints."
        }

        if projectViewModel.debugConfigurations.isEmpty {
            return "Create a `.rosewood.toml` file to define a launch configuration."
        }

        return "Start the selected configuration or inspect breakpoints below."
    }

    private func debugMetadata(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(themeColors.mutedText)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeColors.foreground)
                .textSelection(.enabled)
        }
    }
}
