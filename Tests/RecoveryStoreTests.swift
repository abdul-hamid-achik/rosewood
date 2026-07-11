import Foundation
import Testing
@testable import Rosewood

@Suite(.serialized)
struct RecoveryStoreTests {
    @Test
    func roundTripsJournalAndEnforcesPerTabLimit() throws {
        let directoryURL = temporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recovery.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = RecoveryStore(
            fileURL: fileURL,
            maxBytesPerTab: 32,
            maxJournalBytes: 4_096
        )
        let small = tabState(fileName: "Small.swift", content: "let value = 2\n")
        let large = tabState(fileName: "Large.swift", content: String(repeating: "x", count: 64))
        let journal = RecoveryJournal(
            savedAt: Date(timeIntervalSince1970: 123),
            rootDirectoryPath: "/tmp/project",
            tabs: [small, large]
        )

        let report = store.save(journal)
        let loaded = try #require(store.load())

        #expect(report.wroteJournal)
        #expect(report.savedTabCount == 1)
        #expect(report.skippedFileNames == ["Large.swift"])
        #expect(loaded.rootDirectoryPath == "/tmp/project")
        #expect(loaded.tabs == [small])
    }

    @Test
    func emptyJournalClearsPriorRecoveryData() {
        let directoryURL = temporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recovery.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = RecoveryStore(fileURL: fileURL)
        #expect(store.save(RecoveryJournal(rootDirectoryPath: nil, tabs: [tabState()])).wroteJournal)

        let report = store.save(RecoveryJournal(rootDirectoryPath: nil, tabs: []))

        #expect(report.wroteJournal == false)
        #expect(store.load() == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func corruptOrUnsupportedJournalFailsClosedAndIsQuarantined() throws {
        let directoryURL = temporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recovery.json")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = RecoveryStore(fileURL: fileURL)
        try Data("not-json".utf8).write(to: fileURL)

        #expect(store.load() == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        #expect(quarantinedFiles.contains { $0.lastPathComponent.contains(".invalid-") })

        let unsupported = RecoveryJournal(
            schemaVersion: RecoveryJournal.currentSchemaVersion + 1,
            rootDirectoryPath: nil,
            tabs: [tabState()]
        )
        try JSONEncoder().encode(unsupported).write(to: fileURL)

        #expect(store.load() == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
        let allQuarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        #expect(allQuarantinedFiles.contains { $0.lastPathComponent.contains(".unsupported-v") })
    }

    @Test
    func contentFingerprintIsStableAndSensitiveToChanges() {
        let first = RecoveryContentFingerprint.make(for: "let value = 1\n")
        let same = RecoveryContentFingerprint.make(for: "let value = 1\n")
        let changed = RecoveryContentFingerprint.make(for: "let value = 2\n")

        #expect(first == same)
        #expect(first != changed)
        #expect(first.count == 64)
    }

    @Test
    func supersededBackgroundSaveCannotRecreateClearedJournal() {
        let directoryURL = temporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recovery.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = RecoveryStore(fileURL: fileURL)
        let staleOperationID = store.reserveSaveOperation()

        store.clear()
        let report = store.save(
            RecoveryJournal(rootDirectoryPath: nil, tabs: [tabState()]),
            operationID: staleOperationID
        )

        #expect(report.wroteJournal == false)
        #expect(store.load() == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func allOversizedUpdatePreservesLastKnownGoodJournal() throws {
        let directoryURL = temporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recovery.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = RecoveryStore(
            fileURL: fileURL,
            maxBytesPerTab: 32,
            maxJournalBytes: 4_096
        )
        let prior = tabState(fileName: "Prior.swift", content: "let prior = 1\n")
        #expect(store.save(RecoveryJournal(rootDirectoryPath: nil, tabs: [prior])).wroteJournal)

        let report = store.save(RecoveryJournal(
            rootDirectoryPath: nil,
            tabs: [tabState(fileName: "Huge.swift", content: String(repeating: "x", count: 64))]
        ))

        #expect(report.wroteJournal == false)
        #expect(report.skippedFileNames == ["Huge.swift"])
        #expect(try #require(store.load()).tabs == [prior])
    }

    @Test
    func oversizedOnDiskJournalIsQuarantinedBeforeDecode() throws {
        let directoryURL = temporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recovery.json")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 128).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = RecoveryStore(fileURL: fileURL, maxJournalBytes: 64)

        #expect(store.load() == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        #expect(files.contains { $0.lastPathComponent.contains(".oversized-") })
    }

    @Test
    func liveStoresUseDistinctStablePathsPerWindowIdentifier() throws {
        let applicationSupportURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }

        let firstStore = RecoveryStore.live(
            identifier: "rosewood.session",
            applicationSupportURL: applicationSupportURL
        )
        let secondStore = RecoveryStore.live(
            identifier: "rosewood.session.window.2",
            applicationSupportURL: applicationSupportURL
        )
        let first = tabState(fileName: "First.swift", content: "let first = 1\n")
        let second = tabState(fileName: "Second.swift", content: "let second = 2\n")

        #expect(firstStore.save(RecoveryJournal(rootDirectoryPath: nil, tabs: [first])).wroteJournal)
        #expect(secondStore.save(RecoveryJournal(rootDirectoryPath: nil, tabs: [second])).wroteJournal)
        #expect(firstStore.load()?.tabs == [first])
        #expect(secondStore.load()?.tabs == [second])

        firstStore.clear()
        #expect(firstStore.load() == nil)
        #expect(secondStore.load()?.tabs == [second])
    }

    @Test
    func writeFailureIsNotMisreportedAsCapacityFailure() throws {
        let directoryURL = temporaryDirectory()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let blockingFileURL = directoryURL.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFileURL)
        let recoveryURL = blockingFileURL.appendingPathComponent("recovery.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let report = RecoveryStore(fileURL: recoveryURL).save(
            RecoveryJournal(rootDirectoryPath: nil, tabs: [tabState()])
        )

        #expect(report.wroteJournal == false)
        #expect(report.skippedFileNames.isEmpty)
        #expect(report.writeErrorDescription != nil)
    }

    @Test
    func saveAndLoadEnforceTheSameTabCountLimit() throws {
        let directoryURL = temporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recovery.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = RecoveryStore(
            fileURL: fileURL,
            maxJournalBytes: 100_000,
            maxTabCount: 3
        )
        let tabs = (1...5).map {
            tabState(fileName: "Tab\($0).swift", content: "let value = \($0)\n")
        }

        let report = store.save(RecoveryJournal(rootDirectoryPath: nil, tabs: tabs))
        let loaded = try #require(store.load())

        #expect(report.wroteJournal)
        #expect(report.savedTabCount == 3)
        #expect(report.skippedFileNames == ["Tab4.swift", "Tab5.swift"])
        #expect(loaded.tabs == Array(tabs.prefix(3)))
    }

    private func tabState(
        fileName: String = "Sample.swift",
        content: String = "let value = 2\n"
    ) -> RecoveryTabState {
        RecoveryTabState(
            filePath: "/tmp/\(fileName)",
            fileName: fileName,
            content: content,
            originalContentFingerprint: RecoveryContentFingerprint.make(for: "let value = 1\n"),
            cursorLine: 1,
            cursorColumn: 3,
            documentMetadata: .utf8LF,
            requiresExplicitSave: false,
            wasSelected: true
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
