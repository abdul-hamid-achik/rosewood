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
            sectionTitle("Debugger")

            Text(projectViewModel.debugSessionState.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(themeColors.foreground)

            HStack(spacing: 8) {
                Button(projectViewModel.debugPrimaryActionTitle) {
                    projectViewModel.startDebugging()
                }
                .buttonStyle(.borderedProminent)
                .tint(themeColors.accentStrong)
                .disabled(!projectViewModel.canStartDebugging)

                Button("Reset") {
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
                    Text("No debug configurations were found in `.rosewood.toml`.")
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
