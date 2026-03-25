import Foundation
import AppKit
import SwiftUI
import Highlightr

final class HighlightService {
    static let shared = HighlightService()
    static let defaultHighlightrThemeName = "nord"

    private var highlightr: Highlightr?
    private let highlightrFactory: () -> Highlightr?
    private(set) var currentHighlightrThemeName: String = HighlightService.defaultHighlightrThemeName

    init(highlightrFactory: @escaping () -> Highlightr? = { Highlightr() }) {
        self.highlightrFactory = highlightrFactory
        highlightr = Self.makeConfiguredHighlightr(
            using: highlightrFactory,
            themeName: Self.defaultHighlightrThemeName
        )
    }

    func makeHighlightr() -> Highlightr? {
        Self.makeConfiguredHighlightr(
            using: highlightrFactory,
            themeName: currentHighlightrThemeName
        )
    }

    func highlightedCode(_ code: String, language: String) -> AttributedString {
        guard let highlighted = highlight(code, as: language) else {
            return AttributedString(code)
        }

        return AttributedString(highlighted)
    }

    func highlightedAttributedString(
        _ code: String,
        language: String,
        themeColors: ThemeColors,
        font: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    ) -> NSAttributedString {
        let nsForeground = themeColors.nsForeground

        let highlighted: NSMutableAttributedString
        if let attributed = highlight(code, as: language) {
            highlighted = NSMutableAttributedString(attributedString: attributed)
            let fullRange = NSRange(location: 0, length: highlighted.length)
            highlighted.addAttribute(.font, value: font, range: fullRange)
            highlighted.removeAttribute(.backgroundColor, range: fullRange)
            if highlighted.length > 0 {
                highlighted.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                    guard value == nil else { return }
                    highlighted.addAttribute(.foregroundColor, value: nsForeground, range: range)
                }
            }
        } else {
            highlighted = NSMutableAttributedString(string: code, attributes: [
                .font: font,
                .foregroundColor: nsForeground
            ])
        }

        return highlighted
    }

    func availableLanguages() -> [String] {
        resolveHighlightr()?.supportedLanguages() ?? []
    }

    func setHighlightrTheme(to name: String) {
        currentHighlightrThemeName = name
        resolveHighlightr()?.setTheme(to: name)
    }

    func themeColors(for definition: ThemeDefinition) -> ThemeColors {
        switch definition.id {
        case "nord":
            return .nord
        case "github-light":
            return .githubLight
        case "dracula":
            return .dracula
        default:
            return .nord
        }
    }

    func themeColors() -> ThemeColors {
        return .nord
    }

    private func highlight(_ code: String, as language: String) -> NSAttributedString? {
        if let highlighted = highlight(code, as: language, using: resolveHighlightr()),
           shouldAcceptHighlightedResult(highlighted, language: language) {
            return highlighted
        }

        guard let rebuiltHighlightr = resolveHighlightr(rebuild: true),
              let highlighted = highlight(code, as: language, using: rebuiltHighlightr) else {
            return nil
        }

        return highlighted
    }

    private func resolveHighlightr(rebuild: Bool = false) -> Highlightr? {
        if rebuild || highlightr == nil {
            highlightr = Self.makeConfiguredHighlightr(
                using: highlightrFactory,
                themeName: currentHighlightrThemeName
            )
        }

        return highlightr
    }

    private static func makeConfiguredHighlightr(
        using factory: () -> Highlightr?,
        themeName: String
    ) -> Highlightr? {
        let instance = factory()
        instance?.setTheme(to: themeName)
        return instance
    }

    private func highlight(_ code: String, as language: String, using highlightr: Highlightr?) -> NSAttributedString? {
        highlightr?.highlight(code, as: language)
    }

    private func shouldAcceptHighlightedResult(_ attributed: NSAttributedString, language: String) -> Bool {
        guard language != "plaintext" else { return true }
        guard attributed.length > 0 else { return true }

        var distinctForegroundColors = Set<String>()
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, stop in
            guard range.length > 0,
                  let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            distinctForegroundColors.insert(color.hexString)
            if distinctForegroundColors.count > 1 {
                stop.pointee = true
            }
        }

        return distinctForegroundColors.count > 1
    }
}

struct ThemeColors: Equatable {
    var backgroundHex: String
    var foregroundHex: String
    var subduedTextHex: String
    var mutedTextHex: String
    var lineNumbersHex: String
    var cursorHex: String
    var selectionHex: String
    var gutterBackgroundHex: String
    var gutterDividerHex: String
    var panelBackgroundHex: String
    var elevatedBackgroundHex: String
    var hoverBackgroundHex: String
    var accentHex: String
    var accentStrongHex: String
    var successHex: String
    var warningHex: String
    var dangerHex: String
    var borderHex: String

    init(
        backgroundHex: String = "#2E3440",
        foregroundHex: String = "#ECEFF4",
        subduedTextHex: String = "#E5E9F0",
        mutedTextHex: String = "#A7B4CC",
        lineNumbersHex: String = "#7B88A1",
        cursorHex: String = "#D8DEE9",
        selectionHex: String = "#434C5E",
        gutterBackgroundHex: String = "#3B4252",
        gutterDividerHex: String = "#4C566A",
        panelBackgroundHex: String = "#3B4252",
        elevatedBackgroundHex: String = "#434C5E",
        hoverBackgroundHex: String = "#4C566A",
        accentHex: String = "#88C0D0",
        accentStrongHex: String = "#5E81AC",
        successHex: String = "#A3BE8C",
        warningHex: String = "#EBCB8B",
        dangerHex: String = "#BF616A",
        borderHex: String = "#4C566A"
    ) {
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.subduedTextHex = subduedTextHex
        self.mutedTextHex = mutedTextHex
        self.lineNumbersHex = lineNumbersHex
        self.cursorHex = cursorHex
        self.selectionHex = selectionHex
        self.gutterBackgroundHex = gutterBackgroundHex
        self.gutterDividerHex = gutterDividerHex
        self.panelBackgroundHex = panelBackgroundHex
        self.elevatedBackgroundHex = elevatedBackgroundHex
        self.hoverBackgroundHex = hoverBackgroundHex
        self.accentHex = accentHex
        self.accentStrongHex = accentStrongHex
        self.successHex = successHex
        self.warningHex = warningHex
        self.dangerHex = dangerHex
        self.borderHex = borderHex
    }

    static let nord = ThemeColors()
    static let githubLight = ThemeColors(
        backgroundHex: "#FFFFFF",
        foregroundHex: "#1F2328",
        subduedTextHex: "#57606A",
        mutedTextHex: "#6E7781",
        lineNumbersHex: "#9AA4AF",
        cursorHex: "#1F2328",
        selectionHex: "#DDEBFF",
        gutterBackgroundHex: "#F6F8FA",
        gutterDividerHex: "#D0D7DE",
        panelBackgroundHex: "#F6F8FA",
        elevatedBackgroundHex: "#FFFFFF",
        hoverBackgroundHex: "#EAEFF5",
        accentHex: "#0969DA",
        accentStrongHex: "#0550AE",
        successHex: "#1A7F37",
        warningHex: "#9A6700",
        dangerHex: "#CF222E",
        borderHex: "#D0D7DE"
    )
    static let dracula = ThemeColors(
        backgroundHex: "#282A36",
        foregroundHex: "#F8F8F2",
        subduedTextHex: "#E9E9F4",
        mutedTextHex: "#BDC1D6",
        lineNumbersHex: "#6272A4",
        cursorHex: "#F8F8F2",
        selectionHex: "#44475A",
        gutterBackgroundHex: "#21222C",
        gutterDividerHex: "#44475A",
        panelBackgroundHex: "#21222C",
        elevatedBackgroundHex: "#303341",
        hoverBackgroundHex: "#3A3D4B",
        accentHex: "#8BE9FD",
        accentStrongHex: "#BD93F9",
        successHex: "#50FA7B",
        warningHex: "#F1FA8C",
        dangerHex: "#FF5555",
        borderHex: "#44475A"
    )

    var background: Color { Color(hex: backgroundHex) }
    var foreground: Color { Color(hex: foregroundHex) }
    var subduedText: Color { Color(hex: subduedTextHex) }
    var mutedText: Color { Color(hex: mutedTextHex) }
    var lineNumbers: Color { Color(hex: lineNumbersHex) }
    var cursor: Color { Color(hex: cursorHex) }
    var selection: Color { Color(hex: selectionHex) }
    var gutterBackground: Color { Color(hex: gutterBackgroundHex) }
    var gutterDivider: Color { Color(hex: gutterDividerHex) }
    var panelBackground: Color { Color(hex: panelBackgroundHex) }
    var elevatedBackground: Color { Color(hex: elevatedBackgroundHex) }
    var hoverBackground: Color { Color(hex: hoverBackgroundHex) }
    var accent: Color { Color(hex: accentHex) }
    var accentStrong: Color { Color(hex: accentStrongHex) }
    var success: Color { Color(hex: successHex) }
    var warning: Color { Color(hex: warningHex) }
    var danger: Color { Color(hex: dangerHex) }
    var border: Color { Color(hex: borderHex) }
    var overlayScrim: Color { isLightAppearance ? Color.black.opacity(0.16) : Color.black.opacity(0.46) }
    var shadowColor: Color { isLightAppearance ? Color.black.opacity(0.12) : Color.black.opacity(0.34) }
    var rowSelection: Color { isLightAppearance ? selection.opacity(0.9) : selection.opacity(0.55) }
    var inactiveChipBackground: Color { hoverBackground.opacity(isLightAppearance ? 0.65 : 0.32) }

    var nsBackground: NSColor { NSColor(hex: backgroundHex) }
    var nsForeground: NSColor { NSColor(hex: foregroundHex) }
    var nsSubduedText: NSColor { NSColor(hex: subduedTextHex) }
    var nsMutedText: NSColor { NSColor(hex: mutedTextHex) }
    var nsLineNumbers: NSColor { NSColor(hex: lineNumbersHex) }
    var nsCursor: NSColor { NSColor(hex: cursorHex) }
    var nsSelection: NSColor { NSColor(hex: selectionHex) }
    var nsGutterBackground: NSColor { NSColor(hex: gutterBackgroundHex) }
    var nsGutterDivider: NSColor { NSColor(hex: gutterDividerHex) }
    var nsPanelBackground: NSColor { NSColor(hex: panelBackgroundHex) }
    var nsElevatedBackground: NSColor { NSColor(hex: elevatedBackgroundHex) }
    var nsHoverBackground: NSColor { NSColor(hex: hoverBackgroundHex) }
    var nsAccent: NSColor { NSColor(hex: accentHex) }
    var nsAccentStrong: NSColor { NSColor(hex: accentStrongHex) }
    var nsSuccess: NSColor { NSColor(hex: successHex) }
    var nsWarning: NSColor { NSColor(hex: warningHex) }
    var nsDanger: NSColor { NSColor(hex: dangerHex) }
    var nsBorder: NSColor { NSColor(hex: borderHex) }

    var isLightAppearance: Bool {
        guard let background = nsBackground.usingColorSpace(.sRGB) else { return false }

        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        let luminance = 0.2126 * channel(background.redComponent)
            + 0.7152 * channel(background.greenComponent)
            + 0.0722 * channel(background.blueComponent)
        return luminance > 0.5
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: CGFloat
        switch hex.count {
        case 3:
            r = CGFloat((int >> 8) * 17) / 255
            g = CGFloat((int >> 4 & 0xF) * 17) / 255
            b = CGFloat((int & 0xF) * 17) / 255
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else {
            return "#000000"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    func adjustedForContrast(against background: NSColor, fallback: NSColor, minimumRatio: CGFloat) -> NSColor {
        guard let color = usingColorSpace(.sRGB), let background = background.usingColorSpace(.sRGB) else {
            return fallback
        }

        if color.contrastRatio(against: background) >= minimumRatio {
            return color
        }

        guard let fallback = fallback.usingColorSpace(.sRGB) else {
            return color
        }

        var candidate = color
        for step in stride(from: CGFloat(0.2), through: 1.0, by: 0.2) {
            candidate = color.blended(withFraction: step, of: fallback) ?? fallback
            if candidate.contrastRatio(against: background) >= minimumRatio {
                return candidate
            }
        }

        return fallback
    }

    private func contrastRatio(against other: NSColor) -> CGFloat {
        let lhs = relativeLuminance
        let rhs = other.relativeLuminance
        let lighter = max(lhs, rhs)
        let darker = min(lhs, rhs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: CGFloat {
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        let red = channel(redComponent)
        let green = channel(greenComponent)
        let blue = channel(blueComponent)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
