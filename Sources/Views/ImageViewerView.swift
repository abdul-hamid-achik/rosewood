import AppKit
import SwiftUI

struct ImageViewerView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let tab: EditorTab

    @State private var image: NSImage?
    @State private var zoomScale: CGFloat = 1

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(tab.fileName)
                    .font(RosewoodType.subheadlineStrong)
                    .foregroundColor(themeColors.foreground)

                if case .image(let format) = tab.contentType {
                    RosewoodHeaderChip(text: format.rawValue.uppercased(), tint: themeColors.accent)
                }

                if let fileData = tab.fileData {
                    RosewoodHeaderChip(text: ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file), tint: themeColors.mutedText)
                }

                Spacer()

                viewerAction(systemImage: "minus.magnifyingglass", enabled: zoomScale > 0.4) {
                    zoomScale = max(0.25, zoomScale - 0.25)
                }
                viewerAction(systemImage: "plus.magnifyingglass", enabled: zoomScale < 4) {
                    zoomScale = min(4, zoomScale + 0.25)
                }
                viewerAction(systemImage: "1.magnifyingglass", enabled: abs(zoomScale - 1) > 0.01) {
                    zoomScale = 1
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(themeColors.panelBackground)

            ThemedDivider()

            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .interpolation(.high)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 1200)
                            .scaleEffect(zoomScale)
                            .padding(24)
                    }
                    .background(themeColors.background)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundColor(themeColors.mutedText)
                        Text("Unable to render this image")
                            .font(RosewoodType.bodyStrong)
                            .foregroundColor(themeColors.subduedText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(themeColors.background)
                }
            }
        }
        .accessibilityIdentifier("image-viewer")
        .onAppear {
            if image == nil {
                if let fileData = tab.fileData, let nsImage = NSImage(data: fileData) {
                    image = nsImage
                } else if let filePath = tab.filePath {
                    image = NSImage(contentsOf: filePath)
                }
            }
        }
    }

    private func viewerAction(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        RosewoodPanelIconButton(systemImage: systemImage, tint: themeColors.mutedText, isEnabled: enabled, action: action)
    }
}
