import Foundation

enum ContentType: Equatable {
    case text(isLarge: Bool)
    case image(format: ImageFormat)
    case binary(viewer: BinaryViewer)
    case excluded(reason: ExcludedReason)

    var isText: Bool {
        if case .text = self { return true }
        return false
    }

    var tabIconName: String {
        switch self {
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .binary(.hex):
            return "number.square"
        case .binary:
            return "externaldrive"
        case .excluded:
            return "nosign"
        }
    }

    var statusLabel: String {
        switch self {
        case .text(let isLarge):
            return isLarge ? "Large Text" : "Text"
        case .image(let format):
            return format.rawValue.uppercased() + " Image"
        case .binary(.hex):
            return "Binary Hex"
        case .binary(.placeholder):
            return "Binary"
        case .binary(.external):
            return "Binary External"
        case .excluded(let reason):
            switch reason {
            case .tooLarge:
                return "Too Large"
            case .binary:
                return "Binary"
            case .excludedExtension:
                return "Excluded"
            }
        }
    }
}

enum ImageFormat: String, CaseIterable, Equatable {
    case png
    case jpg
    case gif
    case svg
    case webp
    case bmp
    case ico
    case tiff
    case heic
    case raw
    case pdf
    case eps
}

enum BinaryViewer: Equatable {
    case hex
    case external
    case placeholder
}

enum ExcludedReason: Equatable {
    case tooLarge
    case binary
    case excludedExtension
}
