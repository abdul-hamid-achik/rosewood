import SwiftUI

enum RosewoodUI {
    static let spacing2: CGFloat = 6
    static let spacing3: CGFloat = 8
    static let spacing4: CGFloat = 10
    static let spacing5: CGFloat = 12
    static let spacing6: CGFloat = 16
    static let spacing8: CGFloat = 24

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 10
    static let radiusLarge: CGFloat = 12

    static let rowHeightCompact: CGFloat = 22
    static let rowHeightRegular: CGFloat = 36
    static let toolbarHeight: CGFloat = 44
    static let statusBarHeight: CGFloat = 24
    static let sidebarRailWidth: CGFloat = 48
    static let defaultBottomPanelHeight: CGFloat = 220
}

enum RosewoodType {
    static let title = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let subheadline = Font.system(size: 12)
    static let subheadlineStrong = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionStrong = Font.system(size: 11, weight: .semibold)
    static let micro = Font.system(size: 10, weight: .semibold)
    static let monoBody = Font.system(size: 13, design: .monospaced)
    static let monoCaption = Font.system(size: 11, design: .monospaced)
    static let monoCaptionStrong = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let monoMicro = Font.system(size: 10, design: .monospaced)
}

struct ThemedDivider: View {
    @EnvironmentObject private var configService: ConfigurationService
    let axis: Axis

    init(_ axis: Axis = .horizontal) {
        self.axis = axis
    }

    var body: some View {
        Rectangle()
            .fill(configService.currentThemeColors.border)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

struct RosewoodSidebarCard<Content: View>: View {
    @EnvironmentObject private var configService: ConfigurationService

    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = RosewoodUI.spacing4, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RosewoodUI.spacing5)
        .rosewoodCard(configService.currentThemeColors, radius: RosewoodUI.radiusSmall)
    }
}

struct RosewoodHeaderChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(RosewoodType.monoMicro)
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }
}

struct RosewoodPanelIconButton: View {
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isEnabled ? tint : tint.opacity(0.45))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

extension View {
    func rosewoodCard(_ themeColors: ThemeColors, radius: CGFloat = RosewoodUI.radiusMedium) -> some View {
        background(themeColors.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(themeColors.border.opacity(0.55), lineWidth: 1)
            )
    }
}
