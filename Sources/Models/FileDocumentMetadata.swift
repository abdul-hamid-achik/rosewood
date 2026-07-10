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
        // Count each style rather than first-match-wins. The old logic returned .crlf if the file
        // contained even a single "\r\n", so a predominantly-LF file with one stray CRLF was
        // normalized entirely to CRLF on save — corrupting every other line.
        var crlfCount = 0
        var lfCount = 0
        var crCount = 0

        // Iterate Unicode scalars, NOT Characters: Swift treats "\r\n" as a single grapheme
        // cluster, so a Character compare against "\r"/"\n" would never match CRLF.
        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "\r" {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next] == "\n" {
                    crlfCount += 1
                    index = scalars.index(after: next)
                    continue
                }
                crCount += 1
            } else if scalar == "\n" {
                lfCount += 1
            }
            index = scalars.index(after: index)
        }

        if crlfCount == 0, lfCount == 0, crCount == 0 {
            return .lf
        }
        // Ties favor CRLF then LF, preserving the previous behavior for pure / evenly-mixed files.
        if crlfCount >= lfCount, crlfCount >= crCount {
            return .crlf
        }
        if lfCount >= crCount {
            return .lf
        }
        return .cr
    }
}

struct FileDocumentMetadata: Equatable, Hashable, Codable, Sendable {
    var encodingRawValue: UInt
    var encodingLabel: String
    var lineEnding: LineEndingStyle
    var hasUTF8ByteOrderMark: Bool

    init(
        encoding: String.Encoding = .utf8,
        encodingLabel: String? = nil,
        lineEnding: LineEndingStyle = .lf,
        hasUTF8ByteOrderMark: Bool = false
    ) {
        self.encodingRawValue = encoding.rawValue
        self.encodingLabel = encodingLabel ?? encoding.displayLabel
        self.lineEnding = lineEnding
        self.hasUTF8ByteOrderMark = hasUTF8ByteOrderMark
    }

    var encoding: String.Encoding {
        String.Encoding(rawValue: encodingRawValue)
    }

    static let utf8LF = FileDocumentMetadata()

    private enum CodingKeys: String, CodingKey {
        case encodingRawValue
        case encodingLabel
        case lineEnding
        case hasUTF8ByteOrderMark
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        encodingRawValue = try container.decode(UInt.self, forKey: .encodingRawValue)
        encodingLabel = try container.decode(String.self, forKey: .encodingLabel)
        lineEnding = try container.decode(LineEndingStyle.self, forKey: .lineEnding)
        hasUTF8ByteOrderMark = try container.decodeIfPresent(Bool.self, forKey: .hasUTF8ByteOrderMark) ?? false
    }
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
