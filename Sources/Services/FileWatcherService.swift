import Foundation

final class FileWatcherService: ObservableObject {
    static let shared = FileWatcherService()

    private var watchers: [URL: DispatchSourceFileSystemObject] = [:]
    private let watchQueue: DispatchQueue

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
        guard watchers[url] == nil else { return }
        startWatching(url: url)
    }

    func unwatch(url: URL) {
        guard let source = watchers.removeValue(forKey: url) else { return }
        source.cancel()
    }

    func unwatchAll() {
        let urls = Array(watchers.keys)
        for url in urls {
            unwatch(url: url)
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
            if events.contains(.write) || events.contains(.rename) || events.contains(.delete) {
                DispatchQueue.main.async {
                    self.onExternalFileChange?(url)
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        watchers[url] = source
        source.resume()
    }
}
