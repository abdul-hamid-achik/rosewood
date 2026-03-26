import AppKit
import SwiftUI

struct BinaryPlaceholderView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let tab: EditorTab

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(tab.fileName)
                    .font(RosewoodType.subheadlineStrong)
                    .foregroundColor(themeColors.foreground)

                RosewoodHeaderChip(text: tab.contentType.statusLabel, tint: themeColors.accent)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(themeColors.panelBackground)

            ThemedDivider()

            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "externaldrive")
                    .font(.system(size: 42))
                    .foregroundColor(themeColors.mutedText)
                Text("This file is available in read-only binary mode")
                    .font(RosewoodType.bodyStrong)
                    .foregroundColor(themeColors.subduedText)
                Text("Open it in the default app or reveal it in Finder.")
                    .font(RosewoodType.subheadline)
                    .foregroundColor(themeColors.mutedText)
                HStack(spacing: 12) {
                    Button("Open Externally") {
                        if let filePath = tab.filePath {
                            NSWorkspace.shared.open(filePath)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeColors.accentStrong)

                    Button("Reveal in Finder") {
                        if let filePath = tab.filePath {
                            NSWorkspace.shared.activateFileViewerSelecting([filePath])
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themeColors.background)
        }
        .accessibilityIdentifier("binary-placeholder-view")
    }
}
