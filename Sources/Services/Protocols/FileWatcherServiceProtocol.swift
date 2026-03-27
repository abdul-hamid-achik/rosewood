import Foundation

protocol FileWatcherServiceProtocol: AnyObject {
    var watchedURLs: Set<URL> { get }
    
    func watch(url: URL)
    func unwatch(url: URL)
    func unwatchAll()
    func pauseWatching()
    func resumeWatching()
}
