import Foundation

struct AppSettings: Codable, Equatable {
    struct Editor: Codable, Equatable {
        var fontSize: CGFloat = 13
        var fontFamily: String = "SF Mono"
        var tabSize: Int = 4
        var showLineNumbers: Bool = true
        var showMinimap: Bool = true
        var wordWrap: Bool = false
        var autoSaveDelay: TimeInterval = 2.0
        var autoSaveEnabled: Bool = true

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 13
            fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "SF Mono"
            tabSize = try container.decodeIfPresent(Int.self, forKey: .tabSize) ?? 4
            showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true
            showMinimap = try container.decodeIfPresent(Bool.self, forKey: .showMinimap) ?? true
            wordWrap = try container.decodeIfPresent(Bool.self, forKey: .wordWrap) ?? false
            autoSaveDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .autoSaveDelay) ?? 2.0
            autoSaveEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSaveEnabled) ?? true
        }
    }

    struct Theme: Codable, Equatable {
        var name: String = "nord"

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "nord"
        }
    }

    struct FileHandling: Codable, Equatable {
        var textSizeWarningKB: Int = 500
        var textSizeLimitKB: Int = 5000
        var largeFileThresholdKB: Int = 200
        var binarySizeHexKB: Int = 100
        var binarySizeWarningKB: Int = 1000
        var imageSizeLimitMB: Int = 10
        var excludedBinaryExtensions: [String] = ["exe", "dll", "o", "a", "so", "dylib"]

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            textSizeWarningKB = try container.decodeIfPresent(Int.self, forKey: .textSizeWarningKB) ?? 500
            textSizeLimitKB = try container.decodeIfPresent(Int.self, forKey: .textSizeLimitKB) ?? 5000
            largeFileThresholdKB = try container.decodeIfPresent(Int.self, forKey: .largeFileThresholdKB) ?? 200
            binarySizeHexKB = try container.decodeIfPresent(Int.self, forKey: .binarySizeHexKB) ?? 100
            binarySizeWarningKB = try container.decodeIfPresent(Int.self, forKey: .binarySizeWarningKB) ?? 1000
            imageSizeLimitMB = try container.decodeIfPresent(Int.self, forKey: .imageSizeLimitMB) ?? 10
            excludedBinaryExtensions = try container.decodeIfPresent([String].self, forKey: .excludedBinaryExtensions)
                ?? ["exe", "dll", "o", "a", "so", "dylib"]
        }
    }

    struct Docker: Codable, Equatable {
        var socketPath: String = ""
        var enableDockerIntegration: Bool = true
        var autoDetectComposeFiles: Bool = true
        var composeFilePatterns: [String] = [
            "docker-compose.yml",
            "docker-compose.yaml",
            "compose.yml",
            "compose.yaml"
        ]
        var terminalFont: String = "SF Mono"
        var terminalFontSize: Int = 12
        var terminalShell: String = "/bin/zsh"
        var logLineLimit: Int = 500
        var logFollowInterval: Int = 100
        var refreshIntervalSeconds: Int = 5
        var maxReconnectAttempts: Int = 10
        var composeScanDepth: Int = 1

        var resolvedSocketPath: String {
            if !socketPath.isEmpty { return socketPath }

            if let dockerHost = ProcessInfo.processInfo.environment["DOCKER_HOST"],
               dockerHost.hasPrefix("unix://") {
                return String(dockerHost.dropFirst(7))
            }

            let homeDockerPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent(".docker/run/docker.sock")
            if FileManager.default.fileExists(atPath: homeDockerPath) {
                return homeDockerPath
            }

            return "/var/run/docker.sock"
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            socketPath = try container.decodeIfPresent(String.self, forKey: .socketPath) ?? ""
            enableDockerIntegration = try container.decodeIfPresent(Bool.self, forKey: .enableDockerIntegration) ?? true
            autoDetectComposeFiles = try container.decodeIfPresent(Bool.self, forKey: .autoDetectComposeFiles) ?? true
            composeFilePatterns = try container.decodeIfPresent([String].self, forKey: .composeFilePatterns) ?? Self().composeFilePatterns
            terminalFont = try container.decodeIfPresent(String.self, forKey: .terminalFont) ?? "SF Mono"
            terminalFontSize = try container.decodeIfPresent(Int.self, forKey: .terminalFontSize) ?? 12
            terminalShell = try container.decodeIfPresent(String.self, forKey: .terminalShell) ?? "/bin/zsh"
            logLineLimit = try container.decodeIfPresent(Int.self, forKey: .logLineLimit) ?? 500
            logFollowInterval = try container.decodeIfPresent(Int.self, forKey: .logFollowInterval) ?? 100
            refreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? 5
            maxReconnectAttempts = try container.decodeIfPresent(Int.self, forKey: .maxReconnectAttempts) ?? 10
            composeScanDepth = try container.decodeIfPresent(Int.self, forKey: .composeScanDepth) ?? 1
        }

        private enum CodingKeys: String, CodingKey {
            case socketPath = "socket_path"
            case enableDockerIntegration = "enable_docker_integration"
            case autoDetectComposeFiles = "auto_detect_compose_files"
            case composeFilePatterns = "compose_file_patterns"
            case terminalFont = "terminal_font"
            case terminalFontSize = "terminal_font_size"
            case terminalShell = "terminal_shell"
            case logLineLimit = "log_line_limit"
            case logFollowInterval = "log_follow_interval"
            case refreshIntervalSeconds = "refresh_interval_seconds"
            case maxReconnectAttempts = "max_reconnect_attempts"
            case composeScanDepth = "compose_scan_depth"
        }
    }

    var editor: Editor = Editor()
    var theme: Theme = Theme()
    var fileHandling: FileHandling = FileHandling()
    var docker: Docker = Docker()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        editor = try container.decodeIfPresent(Editor.self, forKey: .editor) ?? Editor()
        theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? Theme()
        fileHandling = try container.decodeIfPresent(FileHandling.self, forKey: .fileHandling) ?? FileHandling()
        docker = try container.decodeIfPresent(Docker.self, forKey: .docker) ?? Docker()
    }

    static let `default` = AppSettings()
}
