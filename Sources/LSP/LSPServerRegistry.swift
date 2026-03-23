import Foundation

struct LSPServerConfig: Sendable {
    let languageId: String
    let command: String
    let arguments: [String]
    let discoveryMethod: DiscoveryMethod
    /// Some languages share a server binary (e.g., JS and TS both use typescript-language-server).
    /// This key groups them so we only spawn one process.
    let serverKey: String

    enum DiscoveryMethod: Sendable {
        case xcrun(tool: String)
        case pathLookup(name: String)
        case xcrunOrPath(tool: String, fallbackName: String)
    }

    init(
        languageId: String,
        command: String,
        arguments: [String] = [],
        discoveryMethod: DiscoveryMethod,
        serverKey: String? = nil
    ) {
        self.languageId = languageId
        self.command = command
        self.arguments = arguments
        self.discoveryMethod = discoveryMethod
        self.serverKey = serverKey ?? languageId
    }
}

enum LSPServerRegistry {

    static let configs: [LSPServerConfig] = [
        // Swift — ships with Xcode
        LSPServerConfig(
            languageId: "swift",
            command: "sourcekit-lsp",
            discoveryMethod: .xcrun(tool: "sourcekit-lsp")
        ),
        // Python
        LSPServerConfig(
            languageId: "python",
            command: "pylsp",
            discoveryMethod: .pathLookup(name: "pylsp")
        ),
        // TypeScript
        LSPServerConfig(
            languageId: "typescript",
            command: "typescript-language-server",
            arguments: ["--stdio"],
            discoveryMethod: .pathLookup(name: "typescript-language-server"),
            serverKey: "typescript-language-server"
        ),
        // JavaScript (shares server with TypeScript)
        LSPServerConfig(
            languageId: "javascript",
            command: "typescript-language-server",
            arguments: ["--stdio"],
            discoveryMethod: .pathLookup(name: "typescript-language-server"),
            serverKey: "typescript-language-server"
        ),
        // Go
        LSPServerConfig(
            languageId: "go",
            command: "gopls",
            arguments: ["serve"],
            discoveryMethod: .pathLookup(name: "gopls")
        ),
        // Rust
        LSPServerConfig(
            languageId: "rust",
            command: "rust-analyzer",
            discoveryMethod: .pathLookup(name: "rust-analyzer")
        ),
        // C (shares server with C++)
        LSPServerConfig(
            languageId: "c",
            command: "clangd",
            discoveryMethod: .xcrunOrPath(tool: "clangd", fallbackName: "clangd"),
            serverKey: "clangd"
        ),
        // C++ (shares server with C)
        LSPServerConfig(
            languageId: "cpp",
            command: "clangd",
            discoveryMethod: .xcrunOrPath(tool: "clangd", fallbackName: "clangd"),
            serverKey: "clangd"
        ),
        // PHP
        LSPServerConfig(
            languageId: "php",
            command: "intelephense",
            arguments: ["--stdio"],
            discoveryMethod: .pathLookup(name: "intelephense")
        ),
        // Zig
        LSPServerConfig(
            languageId: "zig",
            command: "zls",
            discoveryMethod: .pathLookup(name: "zls")
        ),
        // Ruby
        LSPServerConfig(
            languageId: "ruby",
            command: "ruby-lsp",
            discoveryMethod: .pathLookup(name: "ruby-lsp")
        ),
        // Java
        LSPServerConfig(
            languageId: "java",
            command: "jdtls",
            discoveryMethod: .pathLookup(name: "jdtls")
        ),
        // Kotlin
        LSPServerConfig(
            languageId: "kotlin",
            command: "kotlin-language-server",
            discoveryMethod: .pathLookup(name: "kotlin-language-server")
        ),
        // Elixir
        LSPServerConfig(
            languageId: "elixir",
            command: "elixir-ls",
            discoveryMethod: .pathLookup(name: "elixir-ls")
        ),
        // Lua
        LSPServerConfig(
            languageId: "lua",
            command: "lua-language-server",
            discoveryMethod: .pathLookup(name: "lua-language-server")
        ),
        // Bash
        LSPServerConfig(
            languageId: "bash",
            command: "bash-language-server",
            arguments: ["start"],
            discoveryMethod: .pathLookup(name: "bash-language-server")
        ),
        // Dart
        LSPServerConfig(
            languageId: "dart",
            command: "dart",
            arguments: ["language-server", "--protocol=lsp"],
            discoveryMethod: .pathLookup(name: "dart")
        ),
        // Haskell
        LSPServerConfig(
            languageId: "haskell",
            command: "haskell-language-server-wrapper",
            arguments: ["--lsp"],
            discoveryMethod: .pathLookup(name: "haskell-language-server-wrapper")
        ),
        // OCaml
        LSPServerConfig(
            languageId: "ocaml",
            command: "ocamllsp",
            discoveryMethod: .pathLookup(name: "ocamllsp")
        ),
    ]

    private static var resolvedPaths: [String: String?] = [:]
    private static let lock = NSLock()

    static func configFor(language: String) -> LSPServerConfig? {
        configs.first { $0.languageId == language }
    }

    static func resolveServerPath(for config: LSPServerConfig) -> String? {
        lock.lock()
        if let cached = resolvedPaths[config.serverKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let path: String?
        switch config.discoveryMethod {
        case .xcrun(let tool):
            path = xcrunFind(tool)
        case .pathLookup(let name):
            path = whichFind(name)
        case .xcrunOrPath(let tool, let fallbackName):
            path = xcrunFind(tool) ?? whichFind(fallbackName)
        }

        lock.lock()
        resolvedPaths[config.serverKey] = path
        lock.unlock()

        return path
    }

    static func clearCache() {
        lock.lock()
        resolvedPaths.removeAll()
        lock.unlock()
    }

    // MARK: - Discovery

    private static func xcrunFind(_ tool: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", tool]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }

    private static func whichFind(_ name: String) -> String? {
        // Check common paths directly first (faster than which)
        let commonPaths = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "\(NSHomeDirectory())/.cargo/bin/\(name)",
            "/usr/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to `which`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        // Inherit a useful PATH
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.cargo/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }
}
