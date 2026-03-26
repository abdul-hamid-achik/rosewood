import SwiftUI
import Combine

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notifications: [NotificationItem] = []
    
    private init() {}
    
    func show(_ item: NotificationItem) {
        notifications.append(item)
        
        // Auto-dismiss after duration (unless it's an error)
        if item.autoDismiss {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(item.duration * 1_000_000_000))
                await dismiss(item.id)
            }
        }
    }
    
    func dismiss(_ id: UUID) {
        notifications.removeAll { $0.id == id }
    }
}

struct NotificationItem: Identifiable {
    let id = UUID()
    let type: NotificationType
    let title: String
    let message: String
    let actions: [NotificationAction]
    let duration: Double
    let autoDismiss: Bool
    
    init(
        type: NotificationType = .info,
        title: String,
        message: String,
        actions: [NotificationAction] = [],
        duration: Double = 5.0,
        autoDismiss: Bool = true
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.actions = actions
        self.duration = duration
        self.autoDismiss = autoDismiss
    }
}

enum NotificationType {
    case info, success, warning, error
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct NotificationAction {
    let title: String
    let action: () -> Void
}
