import SwiftUI

struct DebugSidebarView: View {
    @EnvironmentObject var projectViewModel: ProjectViewModel
    @EnvironmentObject private var configService: ConfigurationService
    @EnvironmentObject private var debugModel: DebugModel

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RosewoodUI.spacing6) {
                sessionSection
                configurationSection
                breakpointSection
            }
            .padding(RosewoodUI.spacing3)
        }
        .background(themeColors.panelBackground)
    }

    private var sessionSection: some View {
        RosewoodSidebarCard {
            sectionTitle("Session")

            HStack(alignment: .center, spacing: RosewoodUI.spacing4) {
                ZStack {
                    Circle()
                        .fill(sessionAccentColor.opacity(0.14))
                        .frame(width: 26, height: 26)

                    Image(systemName: sessionStatusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(sessionAccentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(debugSessionSummary)
                        .font(RosewoodType.bodyStrong)
                        .foregroundColor(themeColors.foreground)

                    if let sessionSecondaryText {
                        Text(sessionSecondaryText)
                            .font(.system(size: 11))
                            .foregroundColor(themeColors.mutedText)
                    }
                }

                Spacer(minLength: 0)

                if sessionStateChipText != nil {
                    headerChip(sessionStateChipText!, tint: sessionAccentColor)
                }
            }

            Button {
                performPrimaryDebugAction()
            } label: {
                Label(primaryDebugActionTitle, systemImage: primaryDebugActionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryDebugActionTint)
            .disabled(!canPerformPrimaryDebugAction)

            if debugModel.debugSessionState == .paused {
                HStack(spacing: RosewoodUI.spacing3) {
                    sessionInlineAction(title: "Continue", systemImage: "play.fill", tint: themeColors.success) {
                        projectViewModel.continueDebugging()
                    }
                    sessionInlineAction(title: "Step Over", systemImage: "arrow.turn.up.right", tint: themeColors.accent) {
                        projectViewModel.stepOverDebugging()
                    }
                    sessionInlineAction(title: "Step Into", systemImage: "arrow.down.to.line", tint: themeColors.accent) {
                        projectViewModel.stepIntoDebugging()
                    }
                    sessionInlineAction(title: "Step Out", systemImage: "arrow.up.to.line", tint: themeColors.accent) {
                        projectViewModel.stepOutDebugging()
                    }
                }
            } else if debugModel.debugSessionState == .running {
                HStack(spacing: RosewoodUI.spacing3) {
                    sessionInlineAction(title: "Pause", systemImage: "pause.fill", tint: themeColors.warning) {
                        projectViewModel.pauseDebugging()
                    }
                }
            }

            HStack(spacing: 8) {
                sessionInlineAction(
                    title: projectViewModel.isDebugPanelVisible ? "Hide Console" : "Show Console",
                    systemImage: projectViewModel.isDebugPanelVisible ? "rectangle.bottomthird.inset.filled" : "terminal",
                    tint: themeColors.accent
                ) {
                    projectViewModel.toggleDebugPanel()
                }

                sessionInlineAction(
                    title: projectViewModel.hasProjectConfigFile ? "Open Config" : "Create Config",
                    systemImage: projectViewModel.hasProjectConfigFile ? "doc.text" : "plus.square",
                    tint: themeColors.subduedText
                ) {
                    projectViewModel.openProjectConfig(createIfNeeded: !projectViewModel.hasProjectConfigFile)
                }

                if projectViewModel.canOpenCurrentDebugStopLocation {
                    sessionInlineAction(
                        title: "Open Stop Location",
                        systemImage: "location",
                        tint: themeColors.warning
                    ) {
                        projectViewModel.openCurrentDebugStopLocation()
                    }
                }
            }

            if let latestConsoleEntry = debugModel.debugConsoleEntries.last {
                VStack(alignment: .leading, spacing: RosewoodUI.spacing2) {
                    HStack(spacing: 8) {
                        headerChip(latestConsoleEntry.kind.rawValue.uppercased(), tint: color(for: latestConsoleEntry.kind))

                        Text(latestConsoleEntry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(RosewoodType.monoMicro)
                            .foregroundColor(themeColors.mutedText)
                    }

                    Text(latestConsoleEntry.message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(themeColors.subduedText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        }
    }

    private var configurationSection: some View {
        RosewoodSidebarCard {
            sectionTitle("Configuration")

            HStack(spacing: 8) {
                Text(configurationStatusTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeColors.foreground)

                Spacer()

                if projectViewModel.rootDirectory != nil {
                    Button(projectViewModel.hasProjectConfigFile ? "Open Config" : "Create & Open") {
                        projectViewModel.openProjectConfig(createIfNeeded: !projectViewModel.hasProjectConfigFile)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(themeColors.accent)
                }
            }

            if projectViewModel.rootDirectory == nil {
                Text("Open a folder to configure debugging.")
                    .font(RosewoodType.subheadline)
                    .foregroundColor(themeColors.subduedText)
            } else if let error = debugModel.debugConfigurationError {
                Text(error)
                    .font(RosewoodType.subheadline)
                    .foregroundColor(themeColors.danger)
            } else if debugModel.debugConfigurations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(projectViewModel.hasProjectConfigFile ? "Add a launch configuration to `.rosewood.toml`." : "Create `.rosewood.toml` to define launch configurations.")
                        .font(.system(size: 12))
                        .foregroundColor(themeColors.subduedText)
                }
            } else {
                Picker(
                    "Configuration",
                    selection: Binding(
                        get: { debugModel.selectedDebugConfigurationName ?? "" },
                        set: { projectViewModel.selectDebugConfiguration(named: $0) }
                    )
                ) {
                    ForEach(debugModel.debugConfigurations) { configuration in
                        Text(configuration.name).tag(configuration.name)
                    }
                }
                .pickerStyle(.menu)

                if let configuration = projectViewModel.selectedDebugConfiguration {
                    VStack(alignment: .leading, spacing: RosewoodUI.spacing3) {
                        HStack(spacing: RosewoodUI.spacing2) {
                            headerChip(configuration.adapter.uppercased(), tint: themeColors.accent)
                            if let preLaunchTask = configuration.preLaunchTask, !preLaunchTask.isEmpty {
                                headerChip("preLaunchTask", tint: themeColors.warning)
                            }
                        }

                        debugMetadata(label: "Program", value: configuration.program)
                        debugMetadata(label: "Working Dir", value: configuration.cwd ?? ".")
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var breakpointSection: some View {
        RosewoodSidebarCard {
            sectionTitle("Breakpoints")

            if projectViewModel.breakpoints.isEmpty {
                Text("No breakpoints yet. Use the editor gutter to add one.")
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.subduedText)
            } else {
                ForEach(projectViewModel.breakpoints) { breakpoint in
                    HStack(alignment: .top, spacing: RosewoodUI.spacing3) {
                        Circle()
                            .fill(themeColors.danger)
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)

                        Button {
                            projectViewModel.openBreakpoint(breakpoint)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(breakpoint.fileName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(themeColors.foreground)

                                    headerChip("Ln \(breakpoint.line)", tint: themeColors.subduedText)
                                }

                                Text(breakpoint.directoryPath)
                                    .font(.system(size: 11))
                                    .foregroundColor(themeColors.mutedText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        RosewoodPanelIconButton(systemImage: "xmark", tint: themeColors.mutedText, isEnabled: true) {
                            projectViewModel.removeBreakpoint(breakpoint)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(themeColors.subduedText)
    }

    private func headerChip(_ text: String, tint: Color) -> some View {
        RosewoodHeaderChip(text: text, tint: tint)
    }

    private func sessionInlineAction(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.borderless)
        .foregroundColor(tint)
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
        switch debugModel.debugSessionState {
        case .idle:
            return debugModel.selectedDebugConfigurationName == nil ? "Ready to Configure" : "Ready to Run"
        case .starting:
            return "Starting Session"
        case .running:
            return "Debug Session Running"
        case .paused:
            return "Paused on Breakpoint"
        case .stopping:
            return "Stopping Session"
        case .failed:
            return "Debug Start Failed"
        }
    }

    private var sessionSecondaryText: String? {
        switch debugModel.debugSessionState {
        case .idle, .failed:
            return debugModel.selectedDebugConfigurationName
        case .starting, .running, .paused, .stopping:
            return debugModel.selectedDebugConfigurationName
        }
    }

    private var configurationStatusTitle: String {
        if projectViewModel.rootDirectory == nil {
            return "No Workspace"
        }

        if debugModel.debugConfigurationError != nil {
            return "Config Error"
        }

        if debugModel.debugConfigurations.isEmpty {
            return projectViewModel.hasProjectConfigFile ? "No Launch Configurations" : "No Project Config"
        }

        return debugModel.selectedDebugConfigurationName ?? "Configuration"
    }

    private var sessionAccentColor: Color {
        switch debugModel.debugSessionState {
        case .idle:
            return themeColors.mutedText
        case .starting:
            return themeColors.accent
        case .running:
            return themeColors.success
        case .paused:
            return themeColors.warning
        case .stopping:
            return themeColors.warning
        case .failed:
            return themeColors.danger
        }
    }

    private var sessionStatusIcon: String {
        switch debugModel.debugSessionState {
        case .idle:
            return "circle.dashed"
        case .starting:
            return "arrow.triangle.2.circlepath"
        case .running:
            return "play.fill"
        case .paused:
            return "pause.fill"
        case .stopping:
            return "stop.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var sessionStateChipText: String? {
        switch debugModel.debugSessionState {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .failed:
            return "Failed"
        default:
            return nil
        }
    }

    private var primaryDebugActionTitle: String {
        switch debugModel.debugSessionState {
        case .idle, .failed:
            return "Start"
        case .starting:
            return "Starting..."
        case .running, .paused:
            return "Stop"
        case .stopping:
            return "Stopping..."
        }
    }

    private var primaryDebugActionIcon: String {
        switch debugModel.debugSessionState {
        case .idle, .failed:
            return "play.fill"
        case .starting:
            return "arrow.triangle.2.circlepath"
        case .running, .paused, .stopping:
            return "stop.fill"
        }
    }

    private var primaryDebugActionTint: Color {
        switch debugModel.debugSessionState {
        case .idle, .failed:
            return themeColors.accentStrong
        case .starting:
            return themeColors.accent
        case .running, .paused, .stopping:
            return themeColors.warning
        }
    }

    private var canPerformPrimaryDebugAction: Bool {
        switch debugModel.debugSessionState {
        case .idle, .failed:
            return projectViewModel.canStartDebugging
        case .starting, .stopping:
            return false
        case .running, .paused:
            return projectViewModel.canStopDebugging
        }
    }

    private func performPrimaryDebugAction() {
        switch debugModel.debugSessionState {
        case .idle, .failed:
            projectViewModel.startDebugging()
        case .running, .paused:
            projectViewModel.stopDebugging()
        case .starting, .stopping:
            break
        }
    }

    private func debugMetadata(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(RosewoodType.micro)
                .foregroundColor(themeColors.mutedText)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeColors.foreground)
                .textSelection(.enabled)
        }
    }
}
