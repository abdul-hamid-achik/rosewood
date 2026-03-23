import AppKit
import Highlightr
import Testing
@testable import Rosewood

struct HighlightServiceTests {

    // MARK: - NSColor hex initialization

    @Test
    func nsColorHexParsesFullHexCorrectly() {
        let color = NSColor(hex: "#FF8800")
        let srgb = color.usingColorSpace(.sRGB)!

        #expect(Int(srgb.redComponent * 255) == 255)
        #expect(Int(srgb.greenComponent * 255) == 136)
        #expect(Int(srgb.blueComponent * 255) == 0)
    }

    @Test
    func nsColorHexHandlesNordBackground() {
        let color = NSColor(hex: "#2E3440")
        let srgb = color.usingColorSpace(.sRGB)!

        #expect(Int(srgb.redComponent * 255) == 0x2E)
        #expect(Int(srgb.greenComponent * 255) == 0x34)
        #expect(Int(srgb.blueComponent * 255) == 0x40)
    }

    @Test
    func nsColorHexHandlesNordForeground() {
        let color = NSColor(hex: "#ECEFF4")
        let srgb = color.usingColorSpace(.sRGB)!

        #expect(Int(srgb.redComponent * 255) == 0xEC)
        #expect(Int(srgb.greenComponent * 255) == 0xEF)
        #expect(Int(srgb.blueComponent * 255) == 0xF4)
    }

    @Test
    func nsColorHexStripsLeadingHash() {
        let withHash = NSColor(hex: "#88C0D0")
        let withoutHash = NSColor(hex: "88C0D0")
        let srgb1 = withHash.usingColorSpace(.sRGB)!
        let srgb2 = withoutHash.usingColorSpace(.sRGB)!

        #expect(srgb1.redComponent == srgb2.redComponent)
        #expect(srgb1.greenComponent == srgb2.greenComponent)
        #expect(srgb1.blueComponent == srgb2.blueComponent)
    }

    @Test
    func nsColorHexHandlesShortHex() {
        let color = NSColor(hex: "#F00")
        let srgb = color.usingColorSpace(.sRGB)!

        #expect(Int(srgb.redComponent * 255) == 255)
        #expect(Int(srgb.greenComponent * 255) == 0)
        #expect(Int(srgb.blueComponent * 255) == 0)
    }

    @Test
    func nsColorHexDefaultsToBlackForInvalidInput() {
        let color = NSColor(hex: "XYZ")
        let srgb = color.usingColorSpace(.sRGB)!

        #expect(srgb.redComponent == 0)
        #expect(srgb.greenComponent == 0)
        #expect(srgb.blueComponent == 0)
    }

    @Test
    func nsColorHexStringRoundTrips() {
        let original = "#5E81AC"
        let color = NSColor(hex: original)

        #expect(color.hexString == original)
    }

    // MARK: - ThemeColors

    @Test
    func themeColorsHaveDistinctBackgroundAndForeground() {
        let colors = ThemeColors()

        #expect(colors.backgroundHex != colors.foregroundHex)
        #expect(colors.nsBackground != colors.nsForeground)
    }

    @Test
    func themeColorsNSColorsAreInSRGBColorSpace() {
        let colors = ThemeColors()

        #expect(colors.nsBackground.usingColorSpace(.sRGB) != nil)
        #expect(colors.nsForeground.usingColorSpace(.sRGB) != nil)
        #expect(colors.nsAccent.usingColorSpace(.sRGB) != nil)
        #expect(colors.nsLineNumbers.usingColorSpace(.sRGB) != nil)
    }

    @Test
    func themeColorsForegroundHasHighContrastAgainstBackground() {
        let colors = ThemeColors()
        let fg = colors.nsForeground.usingColorSpace(.sRGB)!
        let bg = colors.nsBackground.usingColorSpace(.sRGB)!

        let fgLum = relativeLuminance(fg)
        let bgLum = relativeLuminance(bg)
        let lighter = max(fgLum, bgLum)
        let darker = min(fgLum, bgLum)
        let ratio = (lighter + 0.05) / (darker + 0.05)

        // WCAG AA requires 4.5:1 for normal text
        #expect(ratio >= 4.5, "Foreground/background contrast ratio \(ratio) is below WCAG AA minimum")
    }

    // MARK: - HighlightService attributed string output

    @Test
    func highlightedAttributedStringContainsAllText() {
        let code = "let x = 42\nprint(x)"
        let result = HighlightService.shared.highlightedAttributedString(
            code,
            language: "swift",
            themeColors: ThemeColors()
        )

        #expect(result.string == code)
    }

    @Test
    func highlightedAttributedStringHasFont() {
        let code = "func hello() {}"
        let result = HighlightService.shared.highlightedAttributedString(
            code,
            language: "swift",
            themeColors: ThemeColors()
        )

        let attrs = result.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont

        #expect(font != nil)
        #expect(font?.pointSize == 13)
    }

    @Test
    func highlightedAttributedStringHasForegroundColor() {
        let code = "let x = 1"
        let result = HighlightService.shared.highlightedAttributedString(
            code,
            language: "swift",
            themeColors: ThemeColors()
        )

        let attrs = result.attributes(at: 0, effectiveRange: nil)
        let color = attrs[.foregroundColor] as? NSColor

        #expect(color != nil, "Foreground color must be present on the attributed string")
    }

    @Test
    func highlightedAttributedStringUsesMultipleForegroundColorsForSwiftSource() {
        let code = """
        import Foundation
        let value = 42
        print(value)
        """
        let result = HighlightService.shared.highlightedAttributedString(
            code,
            language: "swift",
            themeColors: ThemeColors()
        )

        var distinctColors = Set<String>()
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard range.length > 0,
                  let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            distinctColors.insert(color.hexString)
        }

        #expect(
            distinctColors.count > 1,
            "Swift highlighting should produce more than one foreground color, got \(distinctColors)"
        )
    }

    @Test
    func highlightedAttributedStringKeepsTokenColorsDistinctFromBaseForeground() {
        let code = "let alpha = 1"
        let colors = ThemeColors()
        let result = HighlightService.shared.highlightedAttributedString(
            code,
            language: "swift",
            themeColors: colors
        )

        let baseForeground = colors.nsForeground.usingColorSpace(.sRGB)?.hexString ?? colors.nsForeground.hexString
        var foundNonBaseForeground = false
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard range.length > 0,
                  let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            if color.hexString != baseForeground {
                foundNonBaseForeground = true
            }
        }

        #expect(foundNonBaseForeground, "Expected at least one syntax token color distinct from the base foreground")
    }

    @Test
    func highlightedAttributedStringHasNoBackgroundColorAttribute() {
        let code = "struct Foo { var bar: Int }"
        let result = HighlightService.shared.highlightedAttributedString(
            code,
            language: "swift",
            themeColors: ThemeColors()
        )

        let fullRange = NSRange(location: 0, length: result.length)
        var foundBackground = false
        result.enumerateAttribute(.backgroundColor, in: fullRange) { value, _, _ in
            if value != nil {
                foundBackground = true
            }
        }

        #expect(!foundBackground, "Highlighted text should not have .backgroundColor attributes")
    }

    @Test
    func highlightedAttributedStringForegroundIsVisibleAgainstBackground() {
        let code = "import Foundation"
        let colors = ThemeColors()
        let result = HighlightService.shared.highlightedAttributedString(
            code,
            language: "swift",
            themeColors: colors
        )
        let bg = colors.nsBackground.usingColorSpace(.sRGB)!

        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard let fg = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            let fgLum = relativeLuminance(fg)
            let bgLum = relativeLuminance(bg)
            let lighter = max(fgLum, bgLum)
            let darker = min(fgLum, bgLum)
            let ratio = (lighter + 0.05) / (darker + 0.05)

            #expect(
                ratio >= 3.0,
                "Foreground color at range \(range) has contrast ratio \(ratio) < 3.0 against background"
            )
        }
    }

    @Test
    func highlightedAttributedStringFallbackForUnknownLanguage() {
        let code = "hello world"
        let colors = ThemeColors()
        let result = HighlightService.shared.highlightedAttributedString(
            code,
            language: "nonexistent-language-12345",
            themeColors: colors
        )

        #expect(result.string == code)
        let attrs = result.attributes(at: 0, effectiveRange: nil)
        #expect(attrs[.font] is NSFont)
        #expect(attrs[.foregroundColor] is NSColor)
    }

    @Test
    func highlightedAttributedStringHandlesEmptyString() {
        let result = HighlightService.shared.highlightedAttributedString(
            "",
            language: "swift",
            themeColors: ThemeColors()
        )

        #expect(result.string == "")
    }

    @Test
    func highlightServiceRecoversWhenInitialHighlightrCreationFails() {
        var attempts = 0
        let service = HighlightService(
            highlightrFactory: {
                attempts += 1
                if attempts == 1 {
                    return nil
                }
                return Highlightr()
            }
        )

        let result = service.highlightedAttributedString(
            "let alpha = 1",
            language: "swift",
            themeColors: ThemeColors()
        )

        var distinctColors = Set<String>()
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard range.length > 0,
                  let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            distinctColors.insert(color.hexString)
        }

        #expect(attempts >= 2, "Highlightr should be rebuilt after an initial initialization failure")
        #expect(result.string == "let alpha = 1")
        #expect(distinctColors.count > 1, "Recovered syntax highlighting should restore token colors")
    }

    @Test
    func highlightServiceRebuildsWhenCachedHighlighterReturnsFlatText() throws {
        let highlightr = try #require(FlakyHighlightr())
        let service = HighlightService(highlightrFactory: { highlightr })

        let result = service.highlightedAttributedString(
            "let alpha = 1",
            language: "swift",
            themeColors: ThemeColors()
        )

        var distinctColors = Set<String>()
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard range.length > 0,
                  let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            distinctColors.insert(color.hexString)
        }

        #expect(highlightr.highlightCallCount >= 2, "Flat highlight output should trigger a rebuild and retry")
        #expect(distinctColors.count > 1, "Retry should restore multiple syntax token colors")
    }

    // MARK: - Contrast adjustment

    @Test
    func adjustedForContrastReturnsOriginalWhenSufficient() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let fallback = NSColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1)

        let result = white.adjustedForContrast(against: black, fallback: fallback, minimumRatio: 4.5)
        let srgb = result.usingColorSpace(.sRGB)!

        #expect(srgb.redComponent > 0.99, "Should return original white, not fallback")
    }

    @Test
    func adjustedForContrastBlendsToCorrectedColor() {
        // Dark gray on dark background — low contrast
        let darkGray = NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        let darkBg = NSColor(srgbRed: 0.18, green: 0.2, blue: 0.25, alpha: 1)
        let lightFallback = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)

        let result = darkGray.adjustedForContrast(against: darkBg, fallback: lightFallback, minimumRatio: 3.8)
        let srgb = result.usingColorSpace(.sRGB)!

        // Result should be lighter than the original dark gray
        let originalBrightness = 0.2
        let resultBrightness = Double(srgb.redComponent + srgb.greenComponent + srgb.blueComponent) / 3.0
        #expect(resultBrightness > originalBrightness, "Adjusted color should be lighter")
    }

    // MARK: - Helpers

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent) + 0.0722 * channel(color.blueComponent)
    }
}

private final class FlakyHighlightr: Highlightr {
    var highlightCallCount = 0

    override func highlight(_ code: String, as languageName: String? = nil, fastRender: Bool = true) -> NSAttributedString? {
        highlightCallCount += 1
        if highlightCallCount == 1 {
            return NSAttributedString(
                string: code,
                attributes: [
                    .foregroundColor: NSColor(hex: "#D8DEE9")
                ]
            )
        }

        return super.highlight(code, as: languageName, fastRender: fastRender)
    }
}
