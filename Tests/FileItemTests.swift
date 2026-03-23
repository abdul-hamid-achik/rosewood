import Foundation
import Testing
@testable import Rosewood

struct FileItemTests {

    @Test
    func fileExtensionIsLowercased() {
        let item = FileItem(
            name: "README.MD",
            path: URL(fileURLWithPath: "/tmp/README.MD"),
            isDirectory: false
        )

        #expect(item.fileExtension == "md")
    }

    @Test
    func fileExtensionForNoExtension() {
        let item = FileItem(
            name: "Makefile",
            path: URL(fileURLWithPath: "/tmp/Makefile"),
            isDirectory: false
        )

        #expect(item.fileExtension == "")
    }

    @Test
    func isHiddenDetectsDotPrefix() {
        let hidden = FileItem(
            name: ".gitignore",
            path: URL(fileURLWithPath: "/tmp/.gitignore"),
            isDirectory: false
        )
        let visible = FileItem(
            name: "main.swift",
            path: URL(fileURLWithPath: "/tmp/main.swift"),
            isDirectory: false
        )

        #expect(hidden.isHidden)
        #expect(!visible.isHidden)
    }

    @Test
    func directoryIconChangesWithExpansion() {
        let collapsed = FileItem(
            name: "Sources",
            path: URL(fileURLWithPath: "/tmp/Sources"),
            isDirectory: true,
            isExpanded: false
        )
        let expanded = FileItem(
            name: "Sources",
            path: URL(fileURLWithPath: "/tmp/Sources"),
            isDirectory: true,
            isExpanded: true
        )

        #expect(collapsed.iconName == "folder")
        #expect(expanded.iconName == "folder.fill")
    }

    @Test
    func swiftFileHasSwiftIcon() {
        let item = FileItem(
            name: "App.swift",
            path: URL(fileURLWithPath: "/tmp/App.swift"),
            isDirectory: false
        )

        #expect(item.iconName == "swift")
    }

    @Test
    func jsonFileHasCurlybracesIcon() {
        let item = FileItem(
            name: "package.json",
            path: URL(fileURLWithPath: "/tmp/package.json"),
            isDirectory: false
        )

        #expect(item.iconName == "curlybraces")
    }

    @Test
    func equalityIncludesExpandedState() {
        let collapsed = FileItem(
            name: "Sources",
            path: URL(fileURLWithPath: "/tmp/Sources"),
            isDirectory: true,
            isExpanded: false
        )
        let expanded = FileItem(
            name: "Sources",
            path: URL(fileURLWithPath: "/tmp/Sources"),
            isDirectory: true,
            isExpanded: true
        )

        #expect(collapsed != expanded)
    }

    @Test
    func equalityIncludesChildren() {
        let child = FileItem(
            name: "main.swift",
            path: URL(fileURLWithPath: "/tmp/Sources/main.swift"),
            isDirectory: false
        )
        let withChildren = FileItem(
            name: "Sources",
            path: URL(fileURLWithPath: "/tmp/Sources"),
            isDirectory: true,
            children: [child]
        )
        let withoutChildren = FileItem(
            name: "Sources",
            path: URL(fileURLWithPath: "/tmp/Sources"),
            isDirectory: true,
            children: []
        )

        #expect(withChildren != withoutChildren)
    }

    @Test
    func hashIsBasedOnId() {
        let item1 = FileItem(
            name: "file.swift",
            path: URL(fileURLWithPath: "/tmp/file.swift"),
            isDirectory: false
        )
        let item2 = FileItem(
            name: "file.swift",
            path: URL(fileURLWithPath: "/tmp/file.swift"),
            isDirectory: false
        )

        #expect(item1.hashValue == item2.hashValue)
    }

    @Test
    func languageMappingForShellScripts() {
        let sh = FileItem(name: "build.sh", path: URL(fileURLWithPath: "/tmp/build.sh"), isDirectory: false)
        let bash = FileItem(name: "run.bash", path: URL(fileURLWithPath: "/tmp/run.bash"), isDirectory: false)
        let zsh = FileItem(name: "setup.zsh", path: URL(fileURLWithPath: "/tmp/setup.zsh"), isDirectory: false)
        let zshrc = FileItem(name: ".zshrc", path: URL(fileURLWithPath: "/tmp/.zshrc"), isDirectory: false)
        let bashrc = FileItem(name: ".bashrc", path: URL(fileURLWithPath: "/tmp/.bashrc"), isDirectory: false)

        #expect(sh.iconName == "terminal")
        #expect(bash.iconName == "terminal")
        #expect(zsh.iconName == "terminal")
        #expect(zshrc.iconName == "terminal")
        #expect(bashrc.iconName == "terminal")
    }

    @Test
    func unknownExtensionFallsBackToDocText() {
        let item = FileItem(
            name: "data.xyz",
            path: URL(fileURLWithPath: "/tmp/data.xyz"),
            isDirectory: false
        )

        #expect(item.iconName == "doc.text")
    }
}
