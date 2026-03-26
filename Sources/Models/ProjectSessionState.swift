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
    let content: String
    let originalContent: String
    let isDirty: Bool
    let encodingRawValue: UInt?
    let encodingLabel: String?
    let lineEndingRawValue: String?
    let contentTypeKind: String?
    let contentTypeDetail: String?

    init(
        filePath: String,
        fileName: String,
        content: String,
        originalContent: String,
        isDirty: Bool,
        encodingRawValue: UInt? = nil,
        encodingLabel: String? = nil,
        lineEndingRawValue: String? = nil,
        contentTypeKind: String? = nil,
        contentTypeDetail: String? = nil
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.content = content
        self.originalContent = originalContent
        self.isDirty = isDirty
        self.encodingRawValue = encodingRawValue
        self.encodingLabel = encodingLabel
        self.lineEndingRawValue = lineEndingRawValue
        self.contentTypeKind = contentTypeKind
        self.contentTypeDetail = contentTypeDetail
    }
}
