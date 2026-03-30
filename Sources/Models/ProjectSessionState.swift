import Foundation

struct ProjectSessionState: Codable, Equatable {
    let rootDirectoryPath: String?
    let expandedDirectoryPaths: [String]
    let openTabs: [ProjectSessionTabState]
    let selectedTabPath: String?
}

struct ProjectSessionTabState: Codable, Equatable {
    let filePath: String
    let fileName: String
    let cursorLine: Int?
    let cursorColumn: Int?
    let encodingRawValue: UInt?
    let encodingLabel: String?
    let lineEndingRawValue: String?
    let contentTypeKind: String?
    let contentTypeDetail: String?

    init(
        filePath: String,
        fileName: String,
        cursorLine: Int? = nil,
        cursorColumn: Int? = nil,
        encodingRawValue: UInt? = nil,
        encodingLabel: String? = nil,
        lineEndingRawValue: String? = nil,
        contentTypeKind: String? = nil,
        contentTypeDetail: String? = nil
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
        self.encodingRawValue = encodingRawValue
        self.encodingLabel = encodingLabel
        self.lineEndingRawValue = lineEndingRawValue
        self.contentTypeKind = contentTypeKind
        self.contentTypeDetail = contentTypeDetail
    }
}
