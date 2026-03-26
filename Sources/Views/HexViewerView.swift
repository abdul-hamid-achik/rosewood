import AppKit
import SwiftUI

struct HexViewerView: View {
    @EnvironmentObject private var configService: ConfigurationService

    let tab: EditorTab

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    private var formattedHex: String {
        guard let fileData = tab.fileData else { return "" }
        return HexFormatter.formattedString(for: fileData)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(tab.fileName)
                    .font(RosewoodType.subheadlineStrong)
                    .foregroundColor(themeColors.foreground)

                RosewoodHeaderChip(text: "HEX", tint: themeColors.accent)

                if let fileData = tab.fileData {
                    RosewoodHeaderChip(text: ByteCountFormatter.string(fromByteCount: Int64(fileData.count), countStyle: .file), tint: themeColors.mutedText)
                }

                Spacer()

                Button("Open Externally") {
                    if let filePath = tab.filePath {
                        NSWorkspace.shared.open(filePath)
                    }
                }
                .buttonStyle(.borderless)
                .foregroundColor(themeColors.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(themeColors.panelBackground)

            ThemedDivider()

            HexTextView(text: formattedHex, themeColors: themeColors)
                .background(themeColors.background)
        }
        .accessibilityIdentifier("hex-viewer")
    }
}

private struct HexTextView: NSViewRepresentable {
    let text: String
    let themeColors: ThemeColors

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.backgroundColor = themeColors.nsBackground
        textView.textColor = themeColors.nsForeground
        textView.string = text
        textView.setAccessibilityLabel("Hex viewer")

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = themeColors.nsBackground
        scrollView.documentView = textView
        scrollView.setAccessibilityIdentifier("hex-viewer-scroll")
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.backgroundColor = themeColors.nsBackground
        if let textView = nsView.documentView as? NSTextView {
            textView.backgroundColor = themeColors.nsBackground
            textView.textColor = themeColors.nsForeground
            if textView.string != text {
                textView.string = text
            }
        }
    }
}

private enum HexFormatter {
    static func formattedString(for data: Data) -> String {
        let bytes = Array(data)
        var lines: [String] = []
        lines.reserveCapacity((bytes.count / 16) + 1)

        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let slice = bytes[offset..<min(offset + 16, bytes.count)]
            let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
            let paddedHex = hex.padding(toLength: 16 * 3 - 1, withPad: " ", startingAt: 0)
            let ascii = slice.map { byte -> String in
                let scalar = UnicodeScalar(byte)
                return (0x20...0x7E).contains(byte) ? String(Character(scalar)) : "."
            }.joined()
            lines.append(String(format: "%08X  %@  |%@|", offset, paddedHex, ascii))
        }

        return lines.joined(separator: "\n")
    }
}
