import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configService: ConfigurationService
    @Environment(\.dismiss) var dismiss

    @State private var fontSize: Double = 13
    @State private var fontFamily: String = "SF Mono"
    @State private var tabSize: Int = 4
    @State private var showLineNumbers: Bool = true
    @State private var wordWrap: Bool = false
    @State private var autoSaveEnabled: Bool = true
    @State private var autoSaveDelay: Double = 2.0
    @State private var selectedThemeId: String = "nord"

    private let fontFamilies = [
        "SF Mono",
        "Menlo",
        "Monaco",
        "Courier",
        "Courier New",
        "Menlo-Regular"
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    editorSection
                    autoSaveSection
                    themeSection
                }
                .padding(24)
            }

            Divider()

            footerView
        }
        .frame(width: 520, height: 480)
        .onAppear { loadCurrentSettings() }
    }

    private var headerView: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(configService.currentThemeColors.panelBackground)
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Editor")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(configService.currentThemeColors.subduedText)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Font Size")
                        .font(.system(size: 13))
                        .foregroundColor(configService.currentThemeColors.foreground)
                    Spacer()
                    Stepper(value: $fontSize, in: 10...24, step: 1) {
                        Text("\(Int(fontSize))")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(configService.currentThemeColors.subduedText)
                            .frame(width: 30)
                    }
                }

                HStack {
                    Text("Font Family")
                        .font(.system(size: 13))
                        .foregroundColor(configService.currentThemeColors.foreground)
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
                        .font(.system(size: 13))
                        .foregroundColor(configService.currentThemeColors.foreground)
                    Spacer()
                    Stepper(value: $tabSize, in: 2...8, step: 1) {
                        Text("\(tabSize)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(configService.currentThemeColors.subduedText)
                            .frame(width: 30)
                    }
                }

                Toggle("Show Line Numbers", isOn: $showLineNumbers)
                    .font(.system(size: 13))
                    .foregroundColor(configService.currentThemeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(configService.currentThemeColors.accent)

                Toggle("Word Wrap", isOn: $wordWrap)
                    .font(.system(size: 13))
                    .foregroundColor(configService.currentThemeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(configService.currentThemeColors.accent)
            }
            .padding(16)
            .background(configService.currentThemeColors.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var autoSaveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto-Save")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(configService.currentThemeColors.subduedText)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Auto-Save", isOn: $autoSaveEnabled)
                    .font(.system(size: 13))
                    .foregroundColor(configService.currentThemeColors.foreground)
                    .toggleStyle(.switch)
                    .tint(configService.currentThemeColors.accent)

                HStack {
                    Text("Delay")
                        .font(.system(size: 13))
                        .foregroundColor(autoSaveEnabled
                            ? configService.currentThemeColors.foreground
                            : configService.currentThemeColors.mutedText)
                    Spacer()
                    Slider(value: $autoSaveDelay, in: 0.5...10.0, step: 0.5)
                        .frame(width: 160)
                        .disabled(!autoSaveEnabled)
                    Text("\(String(format: "%.1f", autoSaveDelay))s")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(configService.currentThemeColors.subduedText)
                        .frame(width: 40)
                }
            }
            .padding(16)
            .background(configService.currentThemeColors.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(configService.currentThemeColors.subduedText)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Color Theme")
                        .font(.system(size: 13))
                        .foregroundColor(configService.currentThemeColors.foreground)
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
            .background(configService.currentThemeColors.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footerView: some View {
        HStack {
            Button("Reset to Defaults") {
                loadDefaultSettings()
            }
            .foregroundColor(configService.currentThemeColors.danger)

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
            .tint(configService.currentThemeColors.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(configService.currentThemeColors.panelBackground)
    }

    private func loadCurrentSettings() {
        let settings = configService.settings
        fontSize = settings.editor.fontSize
        fontFamily = settings.editor.fontFamily
        tabSize = settings.editor.tabSize
        showLineNumbers = settings.editor.showLineNumbers
        wordWrap = settings.editor.wordWrap
        autoSaveEnabled = settings.editor.autoSaveEnabled
        autoSaveDelay = settings.editor.autoSaveDelay
        selectedThemeId = settings.theme.name
    }

    private func loadDefaultSettings() {
        let defaults = AppSettings.default
        fontSize = defaults.editor.fontSize
        fontFamily = defaults.editor.fontFamily
        tabSize = defaults.editor.tabSize
        showLineNumbers = defaults.editor.showLineNumbers
        wordWrap = defaults.editor.wordWrap
        autoSaveEnabled = defaults.editor.autoSaveEnabled
        autoSaveDelay = defaults.editor.autoSaveDelay
        selectedThemeId = defaults.theme.name
    }

    private func saveSettings() {
        var newSettings = configService.settings
        newSettings.editor.fontSize = fontSize
        newSettings.editor.fontFamily = fontFamily
        newSettings.editor.tabSize = tabSize
        newSettings.editor.showLineNumbers = showLineNumbers
        newSettings.editor.wordWrap = wordWrap
        newSettings.editor.autoSaveEnabled = autoSaveEnabled
        newSettings.editor.autoSaveDelay = autoSaveDelay
        newSettings.theme.name = selectedThemeId

        configService.updateSettings(newSettings)
        dismiss()
    }
}
