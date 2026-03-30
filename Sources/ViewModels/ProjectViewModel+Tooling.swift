import Foundation

extension ProjectViewModel {
    func updateGitToolAvailability(_ isAvailable: Bool) {
        isGitToolAvailable = isAvailable

        guard !isAvailable else { return }
        showDependencyWarningOnce(
            id: "git-unavailable",
            title: "Git Not Available",
            message: "Install Git or ensure it is on your PATH to use source control features."
        )
    }

    func updateRipgrepToolAvailability(_ isAvailable: Bool) {
        isRipgrepToolAvailable = isAvailable

        guard !isAvailable else { return }
        showDependencyWarningOnce(
            id: "ripgrep-unavailable",
            title: "ripgrep Not Available",
            message: "Install ripgrep (`rg`) for faster project search. Rosewood is using the slower built-in scanner."
        )
    }

    func showDependencyWarningOnce(id: String, title: String, message: String) {
        guard presentedDependencyWarningIDs.insert(id).inserted else { return }

        NotificationManager.shared.show(
            NotificationItem(
                type: .warning,
                title: title,
                message: message,
                duration: 6.0
            )
        )
    }
}
