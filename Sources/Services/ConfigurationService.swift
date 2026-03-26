import Foundation
import AppKit
import TOMLKit

@MainActor
final class ConfigurationService: ObservableObject {
    static let shared = ConfigurationService()

    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var currentThemeColors: ThemeColors = .nord
    @Published private(set) var currentThemeDefinition: ThemeDefinition = .nord

    let userConfigURL: URL

    private(set) var projectConfigURL: URL?
    private var projectRoot: URL?
    private var fileWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var configReloadDebounceTask: Task<Void, Never>?
    private let configWatchQueue = DispatchQueue(label: "rosewood.configwatcher", qos: .utility)

    private let highlightService = HighlightService.shared

    var watchedConfigURLs: Set<URL> {
        Set(fileWatchers.keys)
    }

    init(userConfigURL: URL? = nil) {
        if let userConfigURL {
            self.userConfigURL = userConfigURL
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            self.userConfigURL = homeDir.appendingPathComponent(".config/rosewood/config.toml")
        }
    }

    deinit {
        for watcher in fileWatchers.values {
            watcher.cancel()
        }
        fileWatchers.removeAll()
        configReloadDebounceTask?.cancel()
    }

    func load() {
        var merged = AppSettings.default

        if let userConfig = loadUserConfig() {
            merged = merge(merged, userConfig)
        }

        if let projectConfig = loadProjectConfig(from: projectRoot) {
            merged = merge(merged, projectConfig)
        }

        settings = merged
        applyTheme(named: merged.theme.name)
        startWatchingConfigFiles()
    }

    func reload() {
        load()
    }

    func setProjectRoot(_ url: URL?) {
        stopWatchingConfigFiles()
        projectRoot = url

        if let url {
            projectConfigURL = url.appendingPathComponent(".rosewood.toml")
        } else {
            projectConfigURL = nil
        }

        load()
    }

    func hasProjectConfig() -> Bool {
        guard let projectConfigURL else { return false }
        return FileManager.default.fileExists(atPath: projectConfigURL.path)
    }

    func createDefaultProjectConfig() throws {
        guard let projectConfigURL else { return }

        let directory = projectConfigURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = TOMLEncoder()
        let tomlString = try encoder.encode(settings)
        try tomlString.write(to: projectConfigURL, atomically: true, encoding: .utf8)
    }

    func saveUserSettings() throws {
        let directory = userConfigURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = TOMLEncoder()
        let tomlString = try encoder.encode(settings)
        try tomlString.write(to: userConfigURL, atomically: true, encoding: .utf8)
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        applyTheme(named: newSettings.theme.name)
        try? saveUserSettings()
    }

    var font: NSFont {
        resolveFont(named: settings.editor.fontFamily, size: settings.editor.fontSize)
    }

    private func applyTheme(named name: String) {
        let definition = ThemeDefinition.builtInThemes.first { $0.id == name } ?? .nord
        currentThemeDefinition = definition
        currentThemeColors = highlightService.themeColors(for: definition)
        highlightService.setHighlightrTheme(to: definition.highlightrTheme)
    }

    private func loadUserConfig() -> AppSettings? {
        guard FileManager.default.fileExists(atPath: userConfigURL.path) else {
            return nil
        }

        do {
            let tomlString = try String(contentsOf: userConfigURL, encoding: .utf8)
            let config = try TOMLDecoder().decode(AppSettings.self, from: tomlString)
            return config
        } catch {
            print("Failed to load user config: \(error)")
            return nil
        }
    }

    private func loadProjectConfig(from: URL?) -> AppSettings? {
        guard let projectConfigURL = projectConfigURL else { return nil }
        guard FileManager.default.fileExists(atPath: projectConfigURL.path) else {
            return nil
        }

        do {
            let tomlString = try String(contentsOf: projectConfigURL, encoding: .utf8)
            let config = try TOMLDecoder().decode(AppSettings.self, from: tomlString)
            return config
        } catch {
            print("Failed to load project config: \(error)")
            return nil
        }
    }

    private func merge(_ base: AppSettings, _ override: AppSettings) -> AppSettings {
        var result = base

        result.editor.fontSize = override.editor.fontSize
        result.editor.fontFamily = override.editor.fontFamily
        result.editor.tabSize = override.editor.tabSize
        result.editor.showLineNumbers = override.editor.showLineNumbers
        result.editor.showMinimap = override.editor.showMinimap
        result.editor.wordWrap = override.editor.wordWrap
        result.editor.autoSaveDelay = override.editor.autoSaveDelay
        result.editor.autoSaveEnabled = override.editor.autoSaveEnabled

        result.theme.name = override.theme.name

        result.fileHandling.textSizeWarningKB = override.fileHandling.textSizeWarningKB
        result.fileHandling.textSizeLimitKB = override.fileHandling.textSizeLimitKB
        result.fileHandling.largeFileThresholdKB = override.fileHandling.largeFileThresholdKB
        result.fileHandling.binarySizeHexKB = override.fileHandling.binarySizeHexKB
        result.fileHandling.binarySizeWarningKB = override.fileHandling.binarySizeWarningKB
        result.fileHandling.imageSizeLimitMB = override.fileHandling.imageSizeLimitMB
        result.fileHandling.excludedBinaryExtensions = override.fileHandling.excludedBinaryExtensions

        result.docker.socketPath = override.docker.socketPath
        result.docker.enableDockerIntegration = override.docker.enableDockerIntegration
        result.docker.autoDetectComposeFiles = override.docker.autoDetectComposeFiles
        result.docker.composeFilePatterns = override.docker.composeFilePatterns
        result.docker.terminalFont = override.docker.terminalFont
        result.docker.terminalFontSize = override.docker.terminalFontSize
        result.docker.terminalShell = override.docker.terminalShell
        result.docker.logLineLimit = override.docker.logLineLimit
        result.docker.logFollowInterval = override.docker.logFollowInterval
        result.docker.refreshIntervalSeconds = override.docker.refreshIntervalSeconds
        result.docker.maxReconnectAttempts = override.docker.maxReconnectAttempts
        result.docker.composeScanDepth = override.docker.composeScanDepth

        return result
    }

    private func startWatchingConfigFiles() {
        stopWatchingConfigFiles()

        watchFile(at: userConfigURL)

        if let projectConfigURL {
            watchFile(at: projectConfigURL)
        }
    }

    private func stopWatchingConfigFiles() {
        for watcher in fileWatchers.values {
            watcher.cancel()
        }
        fileWatchers.removeAll()
    }

    private func watchFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        if let watcher = fileWatchers.removeValue(forKey: url) {
            watcher.cancel()
        }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: configWatchQueue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleConfigReload()
        }

        source.setCancelHandler {
            close(fd)
        }

        fileWatchers[url] = source
        source.resume()
    }

    private func scheduleConfigReload() {
        configReloadDebounceTask?.cancel()
        configReloadDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.reload()
            }
        }
    }

    private func resolveFont(named family: String, size: CGFloat) -> NSFont {
        let trimmedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [String]

        switch trimmedFamily {
        case "SF Mono":
            candidates = ["SFMono-Regular", ".SFMono-Regular", ".SF NS Mono"]
        case "Menlo":
            candidates = ["Menlo-Regular", "Menlo"]
        case "Monaco":
            candidates = ["Monaco"]
        case "Courier":
            candidates = ["Courier"]
        case "Courier New":
            candidates = ["CourierNewPSMT", "Courier New"]
        case "Menlo-Regular":
            candidates = ["Menlo-Regular", "Menlo"]
        default:
            candidates = [trimmedFamily]
        }

        for candidate in candidates where !candidate.isEmpty {
            if let font = NSFont(name: candidate, size: size) {
                return font
            }
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
