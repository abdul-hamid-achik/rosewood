import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configService: ConfigurationService
    @Environment(\.dismiss) var dismiss

    @State private var fontSize: Double = 13
    @State private var fontFamily: String = "SF Mono"
    @State private var tabSize: Int = 4
    @State private var showLineNumbers: Bool = true
    @State private var showMinimap: Bool = true
    @State private var wordWrap: Bool = false
    @State private var autoSaveEnabled: Bool = true
    @State private var autoSaveDelay: Double = 2.0
    @State private var selectedThemeId: String = "nord"
    @State private var textSizeWarningKB: Int = 500
    @State private var textSizeLimitKB: Int = 5000
    @State private var largeFileThresholdKB: Int = 200
    @State private var binarySizeHexKB: Int = 100
    @State private var binarySizeWarningKB: Int = 1000
    @State private var imageSizeLimitMB: Int = 10
    @State private var dockerSocketPath: String = ""
    @State private var dockerEnabled: Bool = true
    @State private var dockerAutoDetectCompose: Bool = true
    @State private var dockerRefreshInterval: Int = 5
    @State private var dockerTerminalShell: String = "/bin/zsh"

    private let fontFamilies = [
        "SF Mono",
        "Menlo",
        "Monaco",
        "Courier",
        "Courier New",
        "Menlo-Regular"
    ]

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            ThemedDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    editorSection
                    autoSaveSection
                    fileHandlingSection
                    dockerSection
                    themeSection
                }
                .padding(24)
            }

            ThemedDivider()

            footerView
        }
        .frame(width: 520, height: 480)
        .background(themeColors.panelBackground)
        .onAppear { loadCurrentSettings() }
    }

    private var headerView: some View {
        HStack {
            Text("Settings")
                .font(RosewoodType.title)
                .foregroundColor(themeColors.foreground)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(themeColors.panelBackground)
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Editor")
                .font(RosewoodType.bodyStrong)
                .foregroundColor(themeColors.subduedText)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Font Size")
                        .font(RosewoodType.body)
                        .foregroundColor(themeColors.foreground)
                    Spacer()
                    Stepper(value: $fontSize, in: 10...24, step: 1) {
                        Text("\(Int(fontSize))")
                            .font(RosewoodType.monoBody)
                            .foregroundColor(themeColors.subduedText)
                            .frame(width: 30)
                    }
                }

                HStack {
                    Text("Font Family")
                        .font(RosewoodType.body)
                        .foregroundColor(themeColors.foreground)
                    Spacer()
                    Picker("", selection: $fontFamily) {
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                HStack {
                    Text("Tab Size")
                        .font(RosewoodType.body)
                        .foregroundColor(themeColors.foreground)
                    Spacer()
                    Stepper(value: $tabSize, in: 2...8, step: 1) {
                        Text("\(tabSize)")
                            .font(RosewoodType.monoBody)
                            .foregroundColor(themeColors.subduedText)
                            .frame(width: 30)
                    }
                }

                Toggle("Show Line Numbers", isOn: $showLineNumbers)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(themeColors.accent)

                Toggle("Show Minimap", isOn: $showMinimap)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(themeColors.accent)

                Toggle("Word Wrap", isOn: $wordWrap)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(themeColors.accent)
            }
            .padding(16)
            .rosewoodCard(themeColors, radius: RosewoodUI.radiusSmall)
        }
    }

    private var autoSaveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto-Save")
                .font(RosewoodType.bodyStrong)
                .foregroundColor(themeColors.subduedText)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Auto-Save", isOn: $autoSaveEnabled)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(themeColors.accent)

                HStack {
                    Text("Delay")
                        .font(RosewoodType.body)
                        .foregroundColor(autoSaveEnabled
                            ? themeColors.foreground
                            : themeColors.mutedText)
                    Spacer()
                    Slider(value: $autoSaveDelay, in: 0.5...10.0, step: 0.5)
                        .frame(width: 160)
                        .disabled(!autoSaveEnabled)
                    Text("\(String(format: "%.1f", autoSaveDelay))s")
                        .font(RosewoodType.monoBody)
                        .foregroundColor(themeColors.subduedText)
                        .frame(width: 40)
                }
            }
            .padding(16)
            .rosewoodCard(themeColors, radius: RosewoodUI.radiusSmall)
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(RosewoodType.bodyStrong)
                .foregroundColor(themeColors.subduedText)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Color Theme")
                        .font(RosewoodType.body)
                        .foregroundColor(themeColors.foreground)
                    Spacer()
                    Picker("", selection: $selectedThemeId) {
                        ForEach(ThemeDefinition.builtInThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }
            .padding(16)
            .rosewoodCard(themeColors, radius: RosewoodUI.radiusSmall)
        }
    }

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Docker")
                .font(RosewoodType.bodyStrong)
                .foregroundColor(themeColors.subduedText)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Docker Integration", isOn: $dockerEnabled)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(themeColors.accent)

                HStack {
                    Text("Docker Socket Path")
                        .font(RosewoodType.body)
                        .foregroundColor(dockerEnabled ? themeColors.foreground : themeColors.mutedText)
                    Spacer()
                    TextField("", text: $dockerSocketPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .disabled(!dockerEnabled)
                }

                Toggle("Auto-detect Compose Files", isOn: $dockerAutoDetectCompose)
                    .font(RosewoodType.body)
                    .foregroundColor(themeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(themeColors.accent)
                    .disabled(!dockerEnabled)

                HStack {
                    Text("Refresh Interval")
                        .font(RosewoodType.body)
                        .foregroundColor(dockerEnabled ? themeColors.foreground : themeColors.mutedText)
                    Spacer()
                    Stepper(value: $dockerRefreshInterval, in: 1...60, step: 1) {
                        Text("\(dockerRefreshInterval)s")
                            .font(RosewoodType.monoBody)
                            .foregroundColor(themeColors.subduedText)
                            .frame(width: 50)
                    }
                    .disabled(!dockerEnabled)
                }

                HStack {
                    Text("Terminal Shell")
                        .font(RosewoodType.body)
                        .foregroundColor(dockerEnabled ? themeColors.foreground : themeColors.mutedText)
                    Spacer()
                    TextField("", text: $dockerTerminalShell)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .disabled(!dockerEnabled)
                }

                Text("Leave socket path empty to auto-detect Docker socket location.")
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)
            }
            .padding(16)
            .rosewoodCard(themeColors, radius: RosewoodUI.radiusSmall)
        }
    }

    private var fileHandlingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Handling")
                .font(RosewoodType.bodyStrong)
                .foregroundColor(themeColors.subduedText)

            VStack(alignment: .leading, spacing: 12) {
                settingsStepperRow("Large file mode", value: $largeFileThresholdKB, range: 100...2000, suffix: "KB")
                settingsStepperRow("Text size limit", value: $textSizeLimitKB, range: 500...20000, suffix: "KB")
                settingsStepperRow("Hex viewer limit", value: $binarySizeHexKB, range: 16...1024, suffix: "KB")
                settingsStepperRow("Binary warning", value: $binarySizeWarningKB, range: 128...10000, suffix: "KB")
                settingsStepperRow("Image size limit", value: $imageSizeLimitMB, range: 1...100, suffix: "MB")

                Text("Large text files stay editable, but Rosewood can disable heavier affordances like the minimap to keep scrolling smooth.")
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)
            }
            .padding(16)
            .rosewoodCard(themeColors, radius: RosewoodUI.radiusSmall)
        }
    }

    private var footerView: some View {
        HStack {
            Button("Reset to Defaults") {
                loadDefaultSettings()
            }
            .foregroundColor(themeColors.danger)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                saveSettings()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(themeColors.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(themeColors.panelBackground)
    }

    private func loadCurrentSettings() {
        let settings = configService.settings
        fontSize = settings.editor.fontSize
        fontFamily = settings.editor.fontFamily
        tabSize = settings.editor.tabSize
        showLineNumbers = settings.editor.showLineNumbers
        showMinimap = settings.editor.showMinimap
        wordWrap = settings.editor.wordWrap
        autoSaveEnabled = settings.editor.autoSaveEnabled
        autoSaveDelay = settings.editor.autoSaveDelay
        selectedThemeId = settings.theme.name
        textSizeWarningKB = settings.fileHandling.textSizeWarningKB
        textSizeLimitKB = settings.fileHandling.textSizeLimitKB
        largeFileThresholdKB = settings.fileHandling.largeFileThresholdKB
        binarySizeHexKB = settings.fileHandling.binarySizeHexKB
        binarySizeWarningKB = settings.fileHandling.binarySizeWarningKB
        imageSizeLimitMB = settings.fileHandling.imageSizeLimitMB
        dockerSocketPath = settings.docker.socketPath
        dockerEnabled = settings.docker.enableDockerIntegration
        dockerAutoDetectCompose = settings.docker.autoDetectComposeFiles
        dockerRefreshInterval = settings.docker.refreshIntervalSeconds
        dockerTerminalShell = settings.docker.terminalShell
    }

    private func loadDefaultSettings() {
        let defaults = AppSettings.default
        fontSize = defaults.editor.fontSize
        fontFamily = defaults.editor.fontFamily
        tabSize = defaults.editor.tabSize
        showLineNumbers = defaults.editor.showLineNumbers
        showMinimap = defaults.editor.showMinimap
        wordWrap = defaults.editor.wordWrap
        autoSaveEnabled = defaults.editor.autoSaveEnabled
        autoSaveDelay = defaults.editor.autoSaveDelay
        selectedThemeId = defaults.theme.name
        textSizeWarningKB = defaults.fileHandling.textSizeWarningKB
        textSizeLimitKB = defaults.fileHandling.textSizeLimitKB
        largeFileThresholdKB = defaults.fileHandling.largeFileThresholdKB
        binarySizeHexKB = defaults.fileHandling.binarySizeHexKB
        binarySizeWarningKB = defaults.fileHandling.binarySizeWarningKB
        imageSizeLimitMB = defaults.fileHandling.imageSizeLimitMB
        dockerSocketPath = defaults.docker.socketPath
        dockerEnabled = defaults.docker.enableDockerIntegration
        dockerAutoDetectCompose = defaults.docker.autoDetectComposeFiles
        dockerRefreshInterval = defaults.docker.refreshIntervalSeconds
        dockerTerminalShell = defaults.docker.terminalShell
    }

    private func saveSettings() {
        var newSettings = configService.settings
        newSettings.editor.fontSize = fontSize
        newSettings.editor.fontFamily = fontFamily
        newSettings.editor.tabSize = tabSize
        newSettings.editor.showLineNumbers = showLineNumbers
        newSettings.editor.showMinimap = showMinimap
        newSettings.editor.wordWrap = wordWrap
        newSettings.editor.autoSaveEnabled = autoSaveEnabled
        newSettings.editor.autoSaveDelay = autoSaveDelay
        newSettings.theme.name = selectedThemeId
        newSettings.fileHandling.textSizeWarningKB = textSizeWarningKB
        newSettings.fileHandling.textSizeLimitKB = textSizeLimitKB
        newSettings.fileHandling.largeFileThresholdKB = largeFileThresholdKB
        newSettings.fileHandling.binarySizeHexKB = binarySizeHexKB
        newSettings.fileHandling.binarySizeWarningKB = binarySizeWarningKB
        newSettings.fileHandling.imageSizeLimitMB = imageSizeLimitMB
        newSettings.docker.socketPath = dockerSocketPath
        newSettings.docker.enableDockerIntegration = dockerEnabled
        newSettings.docker.autoDetectComposeFiles = dockerAutoDetectCompose
        newSettings.docker.refreshIntervalSeconds = dockerRefreshInterval
        newSettings.docker.terminalShell = dockerTerminalShell

        configService.updateSettings(newSettings)
        dismiss()
    }

    private func settingsStepperRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String
    ) -> some View {
        HStack {
            Text(title)
                .font(RosewoodType.body)
                .foregroundColor(themeColors.foreground)
            Spacer()
            Stepper(value: value, in: range, step: 1) {
                Text("\(value.wrappedValue)\(suffix)")
                    .font(RosewoodType.monoBody)
                    .foregroundColor(themeColors.subduedText)
                    .frame(width: 68, alignment: .trailing)
            }
        }
    }
}
