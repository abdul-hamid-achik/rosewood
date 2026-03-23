import Foundation

struct Breakpoint: Identifiable, Codable, Equatable, Hashable {
    var filePath: String
    var line: Int
    var isEnabled: Bool = true

    var id: String {
        "\(filePath):\(line)"
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var fileName: String {
        fileURL.lastPathComponent
    }

    var directoryPath: String {
        fileURL.deletingLastPathComponent().path
    }
}
