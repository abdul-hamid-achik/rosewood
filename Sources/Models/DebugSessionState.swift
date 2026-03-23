import Foundation

enum DebugSessionState: Equatable {
    case idle
    case starting
    case running
    case paused
    case stopping
    case failed(String)

    var statusText: String {
        switch self {
        case .idle:
            return "Debug Idle"
        case .starting:
            return "Debug Starting"
        case .running:
            return "Debug Running"
        case .paused:
            return "Debug Paused"
        case .stopping:
            return "Debug Stopping"
        case .failed:
            return "Debug Failed"
        }
    }

    var isBusy: Bool {
        switch self {
        case .starting, .stopping:
            return true
        default:
            return false
        }
    }
}
