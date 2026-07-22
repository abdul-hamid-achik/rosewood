import Foundation
import Testing
@testable import Rosewood

@Suite(.serialized)
@MainActor
struct NotificationManagerTests {
    private var manager: NotificationManager { NotificationManager.shared }

    private func clearAll() {
        manager.notifications.removeAll()
    }

    @Test
    func showAppendsNotification() {
        clearAll()
        defer { clearAll() }

        let item = NotificationItem(type: .success, title: "Saved", message: "File written")
        manager.show(item)

        #expect(manager.notifications.count == 1)
        #expect(manager.notifications.first?.title == "Saved")
        #expect(manager.notifications.first?.message == "File written")
        #expect(manager.notifications.first?.type.icon == "checkmark.circle.fill")
    }

    @Test
    func showAccumulatesMultipleNotifications() {
        clearAll()
        defer { clearAll() }

        manager.show(NotificationItem(title: "One", message: "1"))
        manager.show(NotificationItem(title: "Two", message: "2"))
        manager.show(NotificationItem(title: "Three", message: "3"))

        #expect(manager.notifications.count == 3)
        #expect(manager.notifications.map(\.title) == ["One", "Two", "Three"])
    }

    @Test
    func dismissRemovesOnlyMatchingNotification() {
        clearAll()
        defer { clearAll() }

        let keep = NotificationItem(title: "Keep", message: "stays")
        let remove = NotificationItem(title: "Remove", message: "goes")
        manager.show(keep)
        manager.show(remove)
        #expect(manager.notifications.count == 2)

        manager.dismiss(remove.id)

        #expect(manager.notifications.count == 1)
        #expect(manager.notifications.first?.id == keep.id)
        #expect(manager.notifications.first?.title == "Keep")
    }

    @Test
    func dismissWithUnknownIdIsNoOp() {
        clearAll()
        defer { clearAll() }

        manager.show(NotificationItem(title: "Present", message: "here"))
        manager.dismiss(UUID())

        #expect(manager.notifications.count == 1)
    }

    @Test
    func autoDismissRemovesNotificationAfterDuration() async {
        clearAll()
        defer { clearAll() }

        let item = NotificationItem(title: "Transient", message: "bye", duration: 0.2, autoDismiss: true)
        manager.show(item)
        #expect(manager.notifications.count == 1)

        try? await Task.sleep(nanoseconds: 600_000_000)

        #expect(manager.notifications.isEmpty)
    }

    @Test
    func nonAutoDismissNotificationPersists() async {
        clearAll()
        defer { clearAll() }

        let item = NotificationItem(title: "Sticky", message: "stays", duration: 0.2, autoDismiss: false)
        manager.show(item)

        try? await Task.sleep(nanoseconds: 500_000_000)

        #expect(manager.notifications.count == 1)
        #expect(manager.notifications.first?.title == "Sticky")
    }

    @Test
    func notificationItemDefaults() {
        let item = NotificationItem(title: "T", message: "M")

        #expect(item.type.icon == NotificationType.info.icon)
        #expect(item.duration == 5.0)
        #expect(item.autoDismiss == true)
        #expect(item.actions.isEmpty)
    }

    @Test
    func notificationTypeIcons() {
        #expect(NotificationType.info.icon == "info.circle.fill")
        #expect(NotificationType.success.icon == "checkmark.circle.fill")
        #expect(NotificationType.warning.icon == "exclamationmark.triangle.fill")
        #expect(NotificationType.error.icon == "xmark.octagon.fill")
    }
}
