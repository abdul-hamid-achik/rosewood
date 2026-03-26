import AppKit
import SwiftUI

struct ImageViewerView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let tab: EditorTab

    @State private var zoomScale: CGFloat = 1

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var nsImage: NSImage? {
        if let fileData = tab.fileData, let nsImage = NSImage(data: fileData) {
            return nsImage
        }

        if let filePath = tab.filePath {
            return NSImage(contentsOf: filePath)
        }

        return nil
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
                if let nsImage {
                    ImageCanvasView(image: nsImage, zoomScale: zoomScale, themeColors: themeColors)
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
    }

    private func viewerAction(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        RosewoodPanelIconButton(systemImage: systemImage, tint: themeColors.mutedText, isEnabled: enabled, action: action)
    }
}

private struct ImageCanvasView: NSViewRepresentable {
    let image: NSImage
    let zoomScale: CGFloat
    let themeColors: ThemeColors

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: image.size))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = themeColors.nsBackground.cgColor
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.widthAnchor.constraint(equalToConstant: image.size.width),
            imageView.heightAnchor.constraint(equalToConstant: image.size.height)
        ])

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = themeColors.nsBackground
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8.0
        scrollView.documentView = contentView

        context.coordinator.imageView = imageView
        context.coordinator.documentView = contentView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.backgroundColor = themeColors.nsBackground
        nsView.magnification = zoomScale

        context.coordinator.imageView?.image = image
        context.coordinator.documentView?.frame = NSRect(origin: .zero, size: image.size)
        context.coordinator.imageView?.frame = NSRect(origin: .zero, size: image.size)
        context.coordinator.documentView?.layer?.backgroundColor = themeColors.nsBackground.cgColor
    }

    final class Coordinator {
        weak var imageView: NSImageView?
        weak var documentView: NSView?
        weak var scrollView: NSScrollView?
    }
}
