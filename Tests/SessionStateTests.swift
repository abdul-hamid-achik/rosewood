import Foundation
import Testing
@testable import Rosewood

struct SessionStateTests {
    @Test
    func sessionStateRoundTripsThroughCoding() throws {
        let session = ProjectSessionState(
            rootDirectoryPath: "/tmp/project",
            expandedDirectoryPaths: ["/tmp/project/Sources", "/tmp/project/Tests"],
            openTabs: [
                ProjectSessionTabState(
                    filePath: "/tmp/project/Sources/main.swift",
                    fileName: "main.swift",
                    content: "print(\"hello\")",
                    originalContent: "print(\"hi\")",
                    isDirty: true
                )
            ],
            selectedTabPath: "/tmp/project/Sources/main.swift"
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ProjectSessionState.self, from: data)

        #expect(decoded == session)
    }
}
