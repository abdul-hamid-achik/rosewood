import Foundation

enum LineEndingStyle: String, Codable, Equatable, Sendable, CaseIterable {
    case lf
    case crlf
    case cr

    var label: String {
        switch self {
        case .lf:
            return "LF"
        case .crlf:
            return "CRLF"
        case .cr:
            return "CR"
        }
    }

    var sequence: String {
        switch self {
        case .lf:
            return "\n"
        case .crlf:
            return "\r\n"
        case .cr:
            return "\r"
        }
    }

    static func detect(in text: String) -> LineEndingStyle {
        if text.contains("\r\n") {
            return .crlf
        }

        if text.contains("\n") {
            return .lf
        }

        if text.contains("\r") {
            return .cr
        }

        return .lf
    }
}

struct FileDocumentMetadata: Equatable, Codable, Sendable {
    var encodingRawValue: UInt
    var encodingLabel: String
    var lineEnding: LineEndingStyle

    init(
        encoding: String.Encoding = .utf8,
        encodingLabel: String? = nil,
        lineEnding: LineEndingStyle = .lf
    ) {
        self.encodingRawValue = encoding.rawValue
        self.encodingLabel = encodingLabel ?? encoding.displayLabel
        self.lineEnding = lineEnding
    }

    var encoding: String.Encoding {
        String.Encoding(rawValue: encodingRawValue)
    }

    static let utf8LF = FileDocumentMetadata()
}

extension String.Encoding {
    var displayLabel: String {
        switch self {
        case .utf8:
            return "UTF-8"
        case .utf16:
            return "UTF-16"
        case .utf16LittleEndian:
            return "UTF-16 LE"
        case .utf16BigEndian:
            return "UTF-16 BE"
        case .utf32:
            return "UTF-32"
        case .ascii:
            return "ASCII"
        case .isoLatin1:
            return "ISO Latin 1"
        case .windowsCP1252:
            return "Windows-1252"
        case .macOSRoman:
            return "Mac OS Roman"
        case .unicode:
            return "Unicode"
        default:
            return "Encoding \(rawValue)"
        }
    }
}
