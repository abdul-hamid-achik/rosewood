import Foundation

protocol FileServiceProtocol: AnyObject {
    var currentRootDirectory: URL? { get set }
    
    func readFile(at url: URL) throws -> String
    func readFileAsData(at url: URL) throws -> Data
    func readDocument(at url: URL) throws -> (content: String, metadata: FileDocumentMetadata)
    func writeDocument(content: String, metadata: FileDocumentMetadata, to url: URL) throws
    func createFile(named name: String, in directory: URL) throws -> URL
    func createDirectory(named name: String, in directory: URL) throws -> URL
    func deleteFile(at url: URL) throws
    func deleteDirectory(at url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func duplicateItem(at url: URL) throws -> URL
    func loadDirectoryTree(rootDirectory: URL, showHiddenFiles: Bool) async throws -> [FileItem]
    func detectContentType(at url: URL, settings: AppSettings.FileHandling) -> ContentType
    func searchProject(rootDirectory: URL, query: String, options: ProjectSearchOptions) async throws -> [ProjectSearchResult]
    func searchAndReplace(rootDirectory: URL, query: String, replacement: String, options: ProjectSearchOptions) async throws -> ProjectReplaceResult
    func undoReplace(transaction: ProjectReplaceTransaction) async throws -> ProjectReplaceUndoResult
}
