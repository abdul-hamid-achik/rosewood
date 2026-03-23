import Foundation
import Testing
@testable import Rosewood

struct BreakpointStoreTests {
    @Test
    func toggledBreakpointsPersistPerProject() {
        let suiteName = "breakpoint-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = BreakpointStore(userDefaults: defaults, storageKey: "test.breakpoints")

        let projectRoot = URL(fileURLWithPath: "/tmp/project-a")
        let otherProjectRoot = URL(fileURLWithPath: "/tmp/project-b")
        let fileURL = projectRoot.appendingPathComponent("Sources/App.swift")

        _ = store.toggleBreakpoint(fileURL: fileURL, line: 12, projectRoot: projectRoot)

        #expect(store.breakpoints(for: projectRoot) == [
            Breakpoint(filePath: fileURL.standardizedFileURL.path, line: 12)
        ])
        #expect(store.breakpoints(for: otherProjectRoot).isEmpty)
    }

    @Test
    func movingDirectoryBreakpointsUpdatesDescendants() {
        let suiteName = "breakpoint-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = BreakpointStore(userDefaults: defaults, storageKey: "test.breakpoints")

        let projectRoot = URL(fileURLWithPath: "/tmp/project-a")
        let oldFolder = projectRoot.appendingPathComponent("Sources")
        let newFolder = projectRoot.appendingPathComponent("Core")

        store.setBreakpoints(
            [
                Breakpoint(filePath: oldFolder.appendingPathComponent("One.swift").path, line: 4),
                Breakpoint(filePath: oldFolder.appendingPathComponent("Nested/Two.swift").path, line: 9)
            ],
            for: projectRoot
        )

        let updated = store.moveBreakpoints(
            from: oldFolder,
            to: newFolder,
            includeDescendants: true,
            for: projectRoot
        )

        #expect(updated == [
            Breakpoint(filePath: newFolder.appendingPathComponent("Nested/Two.swift").path, line: 9),
            Breakpoint(filePath: newFolder.appendingPathComponent("One.swift").path, line: 4)
        ])
    }
}
