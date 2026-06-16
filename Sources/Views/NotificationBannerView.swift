import SwiftUI
import Combine

struct NotificationBannerView: View {
    @StateObject private var notificationManager = NotificationManager.shared

    var body: some View {
        VStack(spacing: RosewoodUI.spacing3) {
            ForEach(notificationManager.notifications) { notification in
                NotificationBanner(item: notification)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, RosewoodUI.spacing6)
        .padding(.top, RosewoodUI.spacing3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }
}

struct NotificationBanner: View {
    let item: NotificationItem
    @EnvironmentObject private var configService: ConfigurationService

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    // Source the accent from the active theme so banners match Nord/Dracula/GitHub Light
    // instead of fixed system colors.
    private var tint: Color {
        switch item.type {
        case .info: return themeColors.accent
        case .success: return themeColors.success
        case .warning: return themeColors.warning
        case .error: return themeColors.danger
        }
    }

    var body: some View {
        HStack(spacing: RosewoodUI.spacing5) {
            Image(systemName: item.type.icon)
                .foregroundColor(tint)
                .font(.system(size: 18, weight: .medium))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(RosewoodType.bodyStrong)
                    .foregroundColor(themeColors.foreground)

                Text(item.message)
                    .font(RosewoodType.subheadline)
                    .foregroundColor(themeColors.subduedText)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: RosewoodUI.spacing3) {
                ForEach(item.actions.indices, id: \.self) { index in
                    let action = item.actions[index]
                    Button(action.title) {
                        action.action()
                        NotificationManager.shared.dismiss(item.id)
                    }
                    .buttonStyle(NotificationButtonStyle(color: themeColors.accent))
                }

                Button {
                    NotificationManager.shared.dismiss(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(themeColors.mutedText)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(themeColors.hoverBackground.opacity(RosewoodUI.stateOpacityHover))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, RosewoodUI.spacing6)
        .padding(.vertical, RosewoodUI.spacing5)
        .background(
            RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium)
                .fill(themeColors.panelBackground.opacity(0.96))
                .shadow(color: themeColors.shadowColor, radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RosewoodUI.radiusMedium)
                .stroke(tint.opacity(RosewoodUI.borderOpacitySubtle), lineWidth: 1)
        )
    }
}

struct NotificationButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RosewoodType.subheadlineStrong)
            .foregroundColor(color)
            .padding(.horizontal, RosewoodUI.spacing5)
            .padding(.vertical, RosewoodUI.spacing2)
            .background(
                RoundedRectangle(cornerRadius: RosewoodUI.radiusXSmall)
                    .fill(color.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
    }
}
