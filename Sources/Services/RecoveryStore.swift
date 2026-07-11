import CryptoKit
import Foundation

struct RecoveryJournal: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let savedAt: Date
    let rootDirectoryPath: String?
    let tabs: [RecoveryTabState]

    init(
        schemaVersion: Int = RecoveryJournal.currentSchemaVersion,
        savedAt: Date = Date(),
        rootDirectoryPath: String?,
        tabs: [RecoveryTabState]
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.rootDirectoryPath = rootDirectoryPath
        self.tabs = tabs
    }

    func replacingTabs(_ tabs: [RecoveryTabState]) -> RecoveryJournal {
        RecoveryJournal(
            schemaVersion: schemaVersion,
            savedAt: savedAt,
            rootDirectoryPath: rootDirectoryPath,
            tabs: tabs
        )
    }
}

struct RecoveryTabState: Codable, Equatable, Sendable {
    let filePath: String?
    let fileName: String
    let content: String
    let originalContentFingerprint: String
    let cursorLine: Int
    let cursorColumn: Int
    let documentMetadata: FileDocumentMetadata
    let requiresExplicitSave: Bool
    let wasSelected: Bool
}

struct RecoverySaveReport: Equatable, Sendable {
    let wroteJournal: Bool
    let savedTabCount: Int
    let skippedFileNames: [String]
    let writeErrorDescription: String?

    init(
        wroteJournal: Bool,
        savedTabCount: Int,
        skippedFileNames: [String],
        writeErrorDescription: String? = nil
    ) {
        self.wroteJournal = wroteJournal
        self.savedTabCount = savedTabCount
        self.skippedFileNames = skippedFileNames
        self.writeErrorDescription = writeErrorDescription
    }

    static let disabled = RecoverySaveReport(
        wroteJournal: false,
        savedTabCount: 0,
        skippedFileNames: []
    )
}

enum RecoveryContentFingerprint {
    static func make(for content: String) -> String {
        SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Stores the last dirty editor buffers independently from normal session preferences.
///
/// The store is synchronous; callers move routine save/load work off the main actor. Generation
/// checks use a short lock that is separate from file I/O, so reserving the next edit checkpoint
/// never waits behind a large journal write. Atomic replacement leaves either the prior valid
/// journal or the new one, never a partially-written JSON document.
final class RecoveryStore: @unchecked Sendable {
    static let disabled = RecoveryStore(fileURL: nil)

    static func live(
        identifier: String = "rosewood.session",
        applicationSupportURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> RecoveryStore {
        let resolvedApplicationSupportURL = applicationSupportURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let journalName = "\(RecoveryContentFingerprint.make(for: identifier)).json"
        let fileURL = resolvedApplicationSupportURL
            .appendingPathComponent("Rosewood", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent(journalName, isDirectory: false)
        return RecoveryStore(fileURL: fileURL, fileManager: fileManager)
    }

    let isEnabled: Bool

    private let fileURL: URL?
    private let fileManager: FileManager
    private let maxBytesPerTab: Int
    private let maxJournalBytes: Int
    private let maxTabCount: Int
    private let loadDelayNanoseconds: UInt64
    private let generationLock = NSLock()
    private let fileIOLock = NSLock()
    private var latestOperationID: UInt64 = 0

    init(
        fileURL: URL?,
        fileManager: FileManager = .default,
        maxBytesPerTab: Int = 5_000_000,
        maxJournalBytes: Int = 20_000_000,
        maxTabCount: Int = 200,
        loadDelayNanoseconds: UInt64 = 0
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.maxBytesPerTab = max(maxBytesPerTab, 1)
        self.maxJournalBytes = max(maxJournalBytes, 1)
        self.maxTabCount = max(maxTabCount, 1)
        self.loadDelayNanoseconds = loadDelayNanoseconds
        self.isEnabled = fileURL != nil
    }

    func load() -> RecoveryJournal? {
        if loadDelayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(loadDelayNanoseconds) / 1_000_000_000)
        }
        return withFileIOLock { () -> RecoveryJournal? in
            guard let fileURL, fileManager.fileExists(atPath: fileURL.path) else { return nil }
            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard fileSize <= maxJournalBytes else {
                quarantineLocked(fileURL, reason: "oversized")
                return nil
            }
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                  let journal = try? JSONDecoder().decode(RecoveryJournal.self, from: data) else {
                quarantineLocked(fileURL, reason: "invalid")
                return nil
            }
            guard journal.schemaVersion == RecoveryJournal.currentSchemaVersion else {
                quarantineLocked(fileURL, reason: "unsupported-v\(journal.schemaVersion)")
                return nil
            }
            guard !journal.tabs.isEmpty else {
                _ = clearLocked()
                return nil
            }
            guard journal.tabs.count <= maxTabCount,
                  journal.tabs.allSatisfy({ $0.content.utf8.count <= maxBytesPerTab }) else {
                quarantineLocked(fileURL, reason: "unsafe")
                return nil
            }
            return journal
        }
    }

    @discardableResult
    func save(_ journal: RecoveryJournal) -> RecoverySaveReport {
        let operationID = reserveSaveOperation()
        return save(journal, operationID: operationID)
    }

    /// Reserves the next journal mutation before a debounced/background save begins.
    /// A later reservation or clear invalidates this operation, preventing an older detached
    /// writer from recreating recovery data after a clean shutdown or newer edit.
    func reserveSaveOperation() -> UInt64 {
        withGenerationLock {
            latestOperationID &+= 1
            return latestOperationID
        }
    }

    @discardableResult
    func save(_ journal: RecoveryJournal, operationID: UInt64) -> RecoverySaveReport {
        guard isCurrent(operationID), let fileURL else { return .disabled }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        guard !journal.tabs.isEmpty else {
            return withFileIOLock {
                guard isCurrent(operationID) else { return .disabled }
                let clearErrorDescription = clearLocked()
                return RecoverySaveReport(
                    wroteJournal: false,
                    savedTabCount: 0,
                    skippedFileNames: [],
                    writeErrorDescription: clearErrorDescription
                )
            }
        }

        guard let emptyJournalData = try? encoder.encode(journal.replacingTabs([])) else {
            return RecoverySaveReport(
                wroteJournal: false,
                savedTabCount: 0,
                skippedFileNames: [],
                writeErrorDescription: "The recovery journal could not be encoded."
            )
        }

        var acceptedTabs: [RecoveryTabState] = []
        var skippedFileNames: [String] = []
        var encodedSize = emptyJournalData.count
        for tab in journal.tabs {
            guard acceptedTabs.count < maxTabCount,
                  tab.content.utf8.count <= maxBytesPerTab,
                  let encodedTab = try? encoder.encode(tab) else {
                skippedFileNames.append(tab.fileName)
                continue
            }

            let separatorBytes = acceptedTabs.isEmpty ? 0 : 1
            guard encodedSize + encodedTab.count + separatorBytes <= maxJournalBytes else {
                skippedFileNames.append(tab.fileName)
                continue
            }

            acceptedTabs.append(tab)
            encodedSize += encodedTab.count + separatorBytes
        }

        guard !acceptedTabs.isEmpty,
              let encodedJournal = try? encoder.encode(journal.replacingTabs(acceptedTabs)),
              encodedJournal.count <= maxJournalBytes else {
            // A non-empty update that exceeds the safety limits must not destroy the prior
            // last-known-good snapshot. The caller can warn and ask for an explicit save.
            return RecoverySaveReport(
                wroteJournal: false,
                savedTabCount: 0,
                skippedFileNames: skippedFileNames
            )
        }

        return withFileIOLock {
            guard isCurrent(operationID) else { return .disabled }
            do {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try encodedJournal.write(to: fileURL, options: .atomic)
                return RecoverySaveReport(
                    wroteJournal: true,
                    savedTabCount: acceptedTabs.count,
                    skippedFileNames: skippedFileNames
                )
            } catch {
                return RecoverySaveReport(
                    wroteJournal: false,
                    savedTabCount: 0,
                    skippedFileNames: [],
                    writeErrorDescription: error.localizedDescription
                )
            }
        }
    }

    @discardableResult
    func clear() -> Bool {
        withGenerationLock {
            latestOperationID &+= 1
        }
        return withFileIOLock {
            clearLocked() == nil
        }
    }

    private func clearLocked() -> String? {
        guard let fileURL, fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            try fileManager.removeItem(at: fileURL)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func quarantineLocked(_ sourceURL: URL, reason: String) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var destinationURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).\(reason)-\(timestamp).json", isDirectory: false)
        var suffix = 1
        while fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = sourceURL.deletingLastPathComponent()
                .appendingPathComponent(
                    "\(baseName).\(reason)-\(timestamp)-\(suffix).json",
                    isDirectory: false
                )
            suffix += 1
        }
        try? fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func isCurrent(_ operationID: UInt64) -> Bool {
        withGenerationLock { operationID == latestOperationID }
    }

    private func withGenerationLock<T>(_ body: () -> T) -> T {
        generationLock.lock()
        defer { generationLock.unlock() }
        return body()
    }

    private func withFileIOLock<T>(_ body: () -> T) -> T {
        fileIOLock.lock()
        defer { fileIOLock.unlock() }
        return body()
    }
}
