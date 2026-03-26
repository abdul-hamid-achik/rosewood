import SwiftUI
import Combine

struct NotificationBannerView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(notificationManager.notifications) { notification in
                NotificationBanner(item: notification)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.icon)
                .foregroundColor(item.type.color)
                .font(.system(size: 20, weight: .medium))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeColors.foreground)
                
                Text(item.message)
                    .font(.system(size: 12))
                    .foregroundColor(themeColors.subduedText)
                    .lineLimit(2)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeColors.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(themeColors.panelBackground.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.type.color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct NotificationButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
    }
}
