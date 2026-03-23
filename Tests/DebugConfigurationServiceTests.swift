import Foundation
import Testing
@testable import Rosewood

struct DebugConfigurationServiceTests {
    @Test
    func missingProjectConfigReturnsEmptyDebugConfiguration() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let service = DebugConfigurationService()
        let configuration = try service.loadProjectConfiguration(for: rootURL)

        #expect(configuration == .empty)
    }

    @Test
    func parsesDebugConfigurationsFromProjectConfig() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = rootURL.appendingPathComponent(".rosewood.toml")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        [debug]
        defaultConfiguration = "Debug App"

        [[debug.configurations]]
        name = "Debug App"
        adapter = "lldb"
        program = ".build/debug/App"
        cwd = "."
        args = ["--flag"]
        stopOnEntry = false
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let service = DebugConfigurationService()
        let configuration = try service.loadProjectConfiguration(for: rootURL)

        #expect(configuration.defaultConfiguration == "Debug App")
        #expect(configuration.configurations.count == 1)
        #expect(configuration.configurations.first?.adapter == "lldb")
        #expect(configuration.configurations.first?.args == ["--flag"])
    }

    @Test
    func invalidDebugConfigurationSurfacesReadableError() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = rootURL.appendingPathComponent(".rosewood.toml")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try """
        [debug]
        defaultConfiguration = "Broken"

        [[debug.configurations]]
        name = "Broken"
        adapter = "lldb"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let service = DebugConfigurationService()

        #expect(throws: DebugConfigurationServiceError.self) {
            _ = try service.loadProjectConfiguration(for: rootURL)
        }
    }
}
