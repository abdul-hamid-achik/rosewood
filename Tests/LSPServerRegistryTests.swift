import Foundation
import Testing
@testable import Rosewood

struct LSPServerRegistryTests {

    // MARK: - Server Config Lookup

    @Test
    func swiftServerConfig() {
        let config = LSPServerRegistry.configFor(language: "swift")
        #expect(config != nil)
        #expect(config?.command == "sourcekit-lsp")
        #expect(config?.serverKey == "swift")
    }

    @Test
    func pythonServerConfig() {
        let config = LSPServerRegistry.configFor(language: "python")
        #expect(config != nil)
        #expect(config?.command == "pylsp")
    }

    @Test
    func typeScriptServerConfig() {
        let config = LSPServerRegistry.configFor(language: "typescript")
        #expect(config != nil)
        #expect(config?.command == "typescript-language-server")
        #expect(config?.arguments == ["--stdio"])
    }

    @Test
    func javaScriptSharesTypeScriptServer() {
        let jsConfig = LSPServerRegistry.configFor(language: "javascript")
        let tsConfig = LSPServerRegistry.configFor(language: "typescript")
        #expect(jsConfig != nil)
        #expect(tsConfig != nil)
        #expect(jsConfig?.serverKey == tsConfig?.serverKey)
        #expect(jsConfig?.command == "typescript-language-server")
    }

    @Test
    func goServerConfig() {
        let config = LSPServerRegistry.configFor(language: "go")
        #expect(config != nil)
        #expect(config?.command == "gopls")
        #expect(config?.arguments == ["serve"])
    }

    @Test
    func rustServerConfig() {
        let config = LSPServerRegistry.configFor(language: "rust")
        #expect(config != nil)
        #expect(config?.command == "rust-analyzer")
    }

    @Test
    func cServerConfig() {
        let config = LSPServerRegistry.configFor(language: "c")
        #expect(config != nil)
        #expect(config?.command == "clangd")
        #expect(config?.serverKey == "clangd")
    }

    @Test
    func cppSharesCServer() {
        let cConfig = LSPServerRegistry.configFor(language: "c")
        let cppConfig = LSPServerRegistry.configFor(language: "cpp")
        #expect(cConfig != nil)
        #expect(cppConfig != nil)
        #expect(cConfig?.serverKey == cppConfig?.serverKey)
        #expect(cppConfig?.serverKey == "clangd")
    }

    @Test
    func phpServerConfig() {
        let config = LSPServerRegistry.configFor(language: "php")
        #expect(config != nil)
        #expect(config?.command == "intelephense")
        #expect(config?.arguments == ["--stdio"])
    }

    @Test
    func zigServerConfig() {
        let config = LSPServerRegistry.configFor(language: "zig")
        #expect(config != nil)
        #expect(config?.command == "zls")
    }

    @Test
    func rubyServerConfig() {
        let config = LSPServerRegistry.configFor(language: "ruby")
        #expect(config != nil)
        #expect(config?.command == "ruby-lsp")
    }

    @Test
    func javaServerConfig() {
        let config = LSPServerRegistry.configFor(language: "java")
        #expect(config != nil)
        #expect(config?.command == "jdtls")
    }

    @Test
    func kotlinServerConfig() {
        let config = LSPServerRegistry.configFor(language: "kotlin")
        #expect(config != nil)
        #expect(config?.command == "kotlin-language-server")
    }

    @Test
    func elixirServerConfig() {
        let config = LSPServerRegistry.configFor(language: "elixir")
        #expect(config != nil)
        #expect(config?.command == "elixir-ls")
    }

    @Test
    func luaServerConfig() {
        let config = LSPServerRegistry.configFor(language: "lua")
        #expect(config != nil)
        #expect(config?.command == "lua-language-server")
    }

    @Test
    func bashServerConfig() {
        let config = LSPServerRegistry.configFor(language: "bash")
        #expect(config != nil)
        #expect(config?.command == "bash-language-server")
        #expect(config?.arguments == ["start"])
    }

    @Test
    func dartServerConfig() {
        let config = LSPServerRegistry.configFor(language: "dart")
        #expect(config != nil)
        #expect(config?.command == "dart")
        #expect(config?.arguments == ["language-server", "--protocol=lsp"])
    }

    @Test
    func haskellServerConfig() {
        let config = LSPServerRegistry.configFor(language: "haskell")
        #expect(config != nil)
        #expect(config?.command == "haskell-language-server-wrapper")
        #expect(config?.arguments == ["--lsp"])
    }

    @Test
    func ocamlServerConfig() {
        let config = LSPServerRegistry.configFor(language: "ocaml")
        #expect(config != nil)
        #expect(config?.command == "ocamllsp")
    }

    // MARK: - Unknown Languages

    @Test
    func unknownLanguageReturnsNil() {
        #expect(LSPServerRegistry.configFor(language: "plaintext") == nil)
    }

    @Test
    func markdownReturnsNil() {
        #expect(LSPServerRegistry.configFor(language: "markdown") == nil)
    }

    @Test
    func jsonReturnsNil() {
        #expect(LSPServerRegistry.configFor(language: "json") == nil)
    }

    @Test
    func yamlReturnsNil() {
        #expect(LSPServerRegistry.configFor(language: "yaml") == nil)
    }

    @Test
    func tomlReturnsNil() {
        #expect(LSPServerRegistry.configFor(language: "toml") == nil)
    }

    @Test
    func dockerfileReturnsNil() {
        #expect(LSPServerRegistry.configFor(language: "dockerfile") == nil)
    }

    // MARK: - All Configs Have Required Fields

    @Test
    func allConfigsHaveNonEmptyLanguageId() {
        for config in LSPServerRegistry.configs {
            #expect(!config.languageId.isEmpty, "Config has empty languageId")
        }
    }

    @Test
    func allConfigsHaveNonEmptyCommand() {
        for config in LSPServerRegistry.configs {
            #expect(!config.command.isEmpty, "Config for \(config.languageId) has empty command")
        }
    }

    @Test
    func allConfigsHaveNonEmptyServerKey() {
        for config in LSPServerRegistry.configs {
            #expect(!config.serverKey.isEmpty, "Config for \(config.languageId) has empty serverKey")
        }
    }

    // MARK: - Discovery (xcrun for Swift should work on macOS with Xcode)

    @Test
    func xcrunDiscoveryForSwift() {
        LSPServerRegistry.clearCache()
        let config = LSPServerRegistry.configFor(language: "swift")!
        let path = LSPServerRegistry.resolveServerPath(for: config)
        // This test assumes Xcode is installed (which it is since we're building with it)
        #expect(path != nil)
        #expect(path?.contains("sourcekit-lsp") == true)
    }

    @Test
    func pathDiscoveryCachesResult() {
        LSPServerRegistry.clearCache()
        let config = LSPServerRegistry.configFor(language: "swift")!

        // First call resolves
        let path1 = LSPServerRegistry.resolveServerPath(for: config)

        // Second call should return cached result (same value)
        let path2 = LSPServerRegistry.resolveServerPath(for: config)

        #expect(path1 == path2)
    }

    // MARK: - Config Count

    @Test
    func totalConfigCount() {
        // 17 unique languages (JS and TS are separate configs even though they share a server)
        // c and cpp are also separate configs sharing clangd
        #expect(LSPServerRegistry.configs.count == 19)
    }

    @Test
    func uniqueLanguageIds() {
        let languageIds = LSPServerRegistry.configs.map(\.languageId)
        let uniqueIds = Set(languageIds)
        #expect(languageIds.count == uniqueIds.count, "Duplicate language IDs found")
    }
}
