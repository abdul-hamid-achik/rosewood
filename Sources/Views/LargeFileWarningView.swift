import SwiftUI

struct LargeFileWarningView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let tab: EditorTab

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle")
                    .foregroundColor(themeColors.warning)

                Text("Large file mode")
                    .font(RosewoodType.subheadlineStrong)
                    .foregroundColor(themeColors.foreground)

                Text("Minimap disabled for smoother scrolling")
                    .font(RosewoodType.caption)
                    .foregroundColor(themeColors.mutedText)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(themeColors.panelBackground)

            ThemedDivider()

            EditorView(tab: tab)
        }
        .accessibilityIdentifier("large-file-warning-view")
    }
}
