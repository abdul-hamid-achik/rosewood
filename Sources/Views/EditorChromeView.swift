import SwiftUI

struct EditorBreadcrumbBar: View {
    @EnvironmentObject private var configService: ConfigurationService

    let segments: [EditorBreadcrumbSegment]
    let onSelectLine: (Int?) -> Void

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RosewoodUI.spacing2) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    Button {
                        onSelectLine(segment.line)
                    } label: {
                        HStack(spacing: RosewoodUI.spacing2) {
                            if let iconName = iconName(for: segment.kind) {
                                Image(systemName: iconName)
                                    .font(.system(size: 10, weight: .semibold))
                            }

                            Text(segment.title)
                                .font(segment.kind == .scope ? RosewoodType.caption : RosewoodType.captionStrong)
                        }
                        .foregroundColor(color(for: segment.kind))
                    }
                    .buttonStyle(.plain)

                    if index < segments.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(themeColors.mutedText)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func iconName(for kind: EditorBreadcrumbSegment.Kind) -> String? {
        switch kind {
        case .root:
            return "folder"
        case .directory:
            return nil
        case .file:
            return "doc.text"
        case .scope:
            return "text.alignleft"
        }
    }

    private func color(for kind: EditorBreadcrumbSegment.Kind) -> Color {
        switch kind {
        case .root:
            return themeColors.subduedText
        case .directory:
            return themeColors.mutedText
        case .file:
            return themeColors.foreground
        case .scope:
            return themeColors.accent
        }
    }
}

struct EditorStickyScopeBar: View {
    @EnvironmentObject private var configService: ConfigurationService

    let scopes: [EditorStickyScopeItem]
    let onSelectLine: (Int) -> Void

    private var themeColors: ThemeColors {
        configService.currentThemeColors
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RosewoodUI.spacing3) {
                ForEach(scopes) { scope in
                    Button {
                        onSelectLine(scope.line)
                    } label: {
                        HStack(spacing: RosewoodUI.spacing2) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 10, weight: .semibold))

                            Text(scope.title)
                                .font(RosewoodType.caption)
                                .lineLimit(1)

                            Text("Ln \(scope.line)")
                                .font(RosewoodType.monoMicro)
                        }
                        .foregroundColor(themeColors.subduedText)
                        .padding(.horizontal, RosewoodUI.spacing4)
                        .padding(.vertical, RosewoodUI.spacing2)
                        .background(themeColors.inactiveChipBackground)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
}
