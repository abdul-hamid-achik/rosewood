import Foundation

final class FileWatcherService: ObservableObject {
    static let shared = FileWatcherService()

    private var watchers: [URL: DispatchSourceFileSystemObject] = [:]
    private let watchQueue: DispatchQueue

    // Standardized URLs whose change events should be ignored until the given deadline,
    // so the editor's own atomic writes are not reported back as external modifications.
    private var suppressedSelfWrites: [URL: Date] = [:]
    private let selfWriteSuppressionWindow: TimeInterval = 1.5

    var onExternalFileChange: ((URL) -> Void)?

    var watchedURLs: Set<URL> {
        Set(watchers.keys)
    }

    init(watchQueue: DispatchQueue = DispatchQueue(label: "rosewood.filewatcher", qos: .utility)) {
        self.watchQueue = watchQueue
    }

    deinit {
        unwatchAll()
    }

    func watch(url: URL) {
        let key = url.standardizedFileURL
        guard watchers[key] == nil else { return }
        startWatching(url: key)
    }

    func unwatch(url: URL) {
        let key = url.standardizedFileURL
        guard let source = watchers.removeValue(forKey: key) else { return }
        source.cancel()
    }

    func unwatchAll() {
        let urls = Array(watchers.keys)
        for url in urls {
            unwatch(url: url)
        }
    }

    /// Re-establish the watch on `url` after our own atomic write. Atomic writes replace
    /// the underlying inode, orphaning the previous file descriptor, so the watch must be
    /// rebuilt or subsequent external edits go undetected.
    func rewatch(url: URL) {
        unwatch(url: url)
        watch(url: url)
    }

    /// Suppress change notifications for `url` for a short window so an imminent atomic
    /// write performed by the editor is not surfaced as an external modification.
    func suppressSelfWrite(for url: URL) {
        let key = url.standardizedFileURL
        let deadline = Date().addingTimeInterval(selfWriteSuppressionWindow)
        watchQueue.async { [weak self] in
            self?.suppressedSelfWrites[key] = deadline
        }
    }

    private func startWatching(url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            print("Failed to open file for watching: \(url.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: watchQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = DispatchSource.FileSystemEvent(rawValue: source.data)
            guard events.contains(.write) || events.contains(.rename) || events.contains(.delete) else {
                return
            }

            // Runs on watchQueue, same as `suppressSelfWrite`, so this access is serialized.
            if let deadline = self.suppressedSelfWrites[url] {
                if Date() < deadline {
                    return
                }
                self.suppressedSelfWrites.removeValue(forKey: url)
            }

            DispatchQueue.main.async {
                self.onExternalFileChange?(url)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        watchers[url] = source
        source.resume()
    }
}
