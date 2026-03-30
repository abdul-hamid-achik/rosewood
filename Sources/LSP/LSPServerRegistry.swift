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
    typealias DiscoveryResolver = @Sendable (String) -> String?

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
    private static var xcrunPaths: [String: String?] = [:]
    private static var pathLookupPaths: [String: String?] = [:]
    private static var xcrunResolver: DiscoveryResolver = { tool in
        defaultXcrunFind(tool)
    }
    private static var pathResolver: DiscoveryResolver = { name in
        defaultWhichFind(name)
    }
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
            path = cachedDiscoveryPath(for: tool, cache: &xcrunPaths, resolver: xcrunResolver)
        case .pathLookup(let name):
            path = cachedDiscoveryPath(for: name, cache: &pathLookupPaths, resolver: pathResolver)
        case .xcrunOrPath(let tool, let fallbackName):
            path = cachedDiscoveryPath(for: tool, cache: &xcrunPaths, resolver: xcrunResolver)
                ?? cachedDiscoveryPath(for: fallbackName, cache: &pathLookupPaths, resolver: pathResolver)
        }

        lock.lock()
        resolvedPaths[config.serverKey] = path
        lock.unlock()

        return path
    }

    static func clearCache() {
        lock.lock()
        resolvedPaths.removeAll()
        xcrunPaths.removeAll()
        pathLookupPaths.removeAll()
        lock.unlock()
    }

    static func prewarmServerPaths(for languages: some Sequence<String>) {
        let uniqueConfigs = Dictionary(
            grouping: languages.compactMap { configFor(language: $0) },
            by: \.serverKey
        ).compactMap { $0.value.first }

        for config in uniqueConfigs {
            _ = resolveServerPath(for: config)
        }
    }

    static func setDiscoveryResolversForTesting(
        xcrunResolver: @escaping DiscoveryResolver,
        pathResolver: @escaping DiscoveryResolver
    ) {
        lock.lock()
        self.xcrunResolver = xcrunResolver
        self.pathResolver = pathResolver
        resolvedPaths.removeAll()
        xcrunPaths.removeAll()
        pathLookupPaths.removeAll()
        lock.unlock()
    }

    static func resetDiscoveryResolvers() {
        lock.lock()
        xcrunResolver = { tool in defaultXcrunFind(tool) }
        pathResolver = { name in defaultWhichFind(name) }
        resolvedPaths.removeAll()
        xcrunPaths.removeAll()
        pathLookupPaths.removeAll()
        lock.unlock()
    }

    // MARK: - Discovery

    private static func cachedDiscoveryPath(
        for key: String,
        cache: inout [String: String?],
        resolver: DiscoveryResolver
    ) -> String? {
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = resolver(key)

        lock.lock()
        cache[key] = resolved
        lock.unlock()
        return resolved
    }

    private static func xcrunFind(_ tool: String) -> String? {
        defaultXcrunFind(tool)
    }

    private static func defaultXcrunFind(_ tool: String) -> String? {
        do {
            let result = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["--find", tool],
                timeout: 5.0
            )
            guard result.terminationStatus == 0 else { return nil }
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }

    private static func whichFind(_ name: String) -> String? {
        defaultWhichFind(name)
    }

    private static func defaultWhichFind(_ name: String) -> String? {
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
        do {
            let result = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/which"),
                arguments: [name],
                environment: env,
                timeout: 5.0
            )
            guard result.terminationStatus == 0 else { return nil }
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }
}
