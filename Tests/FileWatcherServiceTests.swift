import Foundation
import Testing
@testable import Rosewood

/// A single-shot promise for a file-change callback. The watcher delivers events on the
/// main queue, which may fire before or after the test starts awaiting; this type buffers
/// the value so the ordering does not matter.
private final class EventPromise: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL?, Never>?
    private var value: URL?
    private var done = false

    func fulfill(_ url: URL?) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        done = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: url)
        } else {
            value = url
            lock.unlock()
        }
    }

    func wait() async -> URL? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if done {
                let value = value
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

@Suite(.serialized)
struct FileWatcherServiceTests {
    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
    }

    /// Installs a change callback on `service` that fulfils a promise, plus a timeout that
    /// fulfils it with `nil` so a missing event does not hang the test.
    private func armCallback(on service: FileWatcherService, timeout: TimeInterval) -> EventPromise {
        let promise = EventPromise()
        service.onExternalFileChange = { url in promise.fulfill(url) }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { promise.fulfill(nil) }
        return promise
    }

    private func modifyFile(at url: URL) throws {
        // Non-atomic write modifies the inode in place, producing a `.write` vnode event.
        try "modified-\(UUID().uuidString)".write(to: url, atomically: false, encoding: .utf8)
    }

    @Test
    func watchRegistersStandardizedURL() throws {
        let url = temporaryFileURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = FileWatcherService()
        service.watch(url: url)

        #expect(service.watchedURLs.contains(url.standardizedFileURL))
        service.unwatchAll()
    }

    @Test
    func watchIsIdempotent() throws {
        let url = temporaryFileURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = FileWatcherService()
        service.watch(url: url)
        service.watch(url: url)

        #expect(service.watchedURLs.count == 1)
        service.unwatchAll()
    }

    @Test
    func externalWriteFiresCallback() async throws {
        let url = temporaryFileURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = FileWatcherService()
        service.watch(url: url)
        let promise = armCallback(on: service, timeout: 5.0)

        // Give the dispatch source a moment to resume before the edit lands.
        try await Task.sleep(nanoseconds: 150_000_000)
        try modifyFile(at: url)

        let changed = await promise.wait()
        #expect(changed == url.standardizedFileURL)
        service.unwatchAll()
    }

    @Test
    func unwatchStopsNotifications() async throws {
        let url = temporaryFileURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = FileWatcherService()
        service.watch(url: url)
        try await Task.sleep(nanoseconds: 150_000_000)

        service.unwatch(url: url)
        #expect(service.watchedURLs.isEmpty)

        let promise = armCallback(on: service, timeout: 0.8)
        try modifyFile(at: url)

        let changed = await promise.wait()
        #expect(changed == nil)
    }

    @Test
    func unwatchAllClearsEveryWatcher() throws {
        let first = temporaryFileURL()
        let second = temporaryFileURL()
        try "a".write(to: first, atomically: true, encoding: .utf8)
        try "b".write(to: second, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let service = FileWatcherService()
        service.watch(url: first)
        service.watch(url: second)
        #expect(service.watchedURLs.count == 2)

        service.unwatchAll()
        #expect(service.watchedURLs.isEmpty)
    }

    @Test
    func rewatchKeepsASingleLiveWatcher() throws {
        let url = temporaryFileURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = FileWatcherService()
        service.watch(url: url)
        service.rewatch(url: url)

        #expect(service.watchedURLs.count == 1)
        #expect(service.watchedURLs.contains(url.standardizedFileURL))
        service.unwatchAll()
    }

    @Test
    func rewatchedFileStillReportsExternalWrites() async throws {
        let url = temporaryFileURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = FileWatcherService()
        service.watch(url: url)
        service.rewatch(url: url)

        let promise = armCallback(on: service, timeout: 5.0)
        try await Task.sleep(nanoseconds: 150_000_000)
        try modifyFile(at: url)

        let changed = await promise.wait()
        #expect(changed == url.standardizedFileURL)
        service.unwatchAll()
    }

    @Test
    func suppressSelfWriteSwallowsImminentWrite() async throws {
        let url = temporaryFileURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let service = FileWatcherService()
        service.watch(url: url)
        try await Task.sleep(nanoseconds: 150_000_000)

        service.suppressSelfWrite(for: url)
        // Let the suppression register on the watch queue before the edit lands.
        try await Task.sleep(nanoseconds: 50_000_000)

        // Timeout stays inside the 1.5s suppression window, so a suppressed event cannot
        // slip through after the window expires.
        let promise = armCallback(on: service, timeout: 1.0)
        try modifyFile(at: url)

        let changed = await promise.wait()
        #expect(changed == nil)
        service.unwatchAll()
    }
}
