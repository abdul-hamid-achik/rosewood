import Foundation
import Testing
@testable import Rosewood

struct EditorTabLSPTests {

    // MARK: - Document Version

    @Test
    func documentVersionDefault() {
        let tab = EditorTab()
        #expect(tab.documentVersion == 0)
    }

    @Test
    func documentVersionIncrement() {
        var tab = EditorTab()
        tab.documentVersion += 1
        #expect(tab.documentVersion == 1)
        tab.documentVersion += 1
        #expect(tab.documentVersion == 2)
    }

    @Test
    func documentVersionCustomInit() {
        let tab = EditorTab(documentVersion: 5)
        #expect(tab.documentVersion == 5)
    }

    // MARK: - Document URI

    @Test
    func documentURIWithFilePath() {
        let tab = EditorTab(filePath: URL(fileURLWithPath: "/Users/test/main.swift"))
        #expect(tab.documentURI != nil)
        #expect(tab.documentURI?.contains("file://") == true)
        #expect(tab.documentURI?.contains("main.swift") == true)
    }

    @Test
    func documentURINilForUntitled() {
        let tab = EditorTab()
        #expect(tab.documentURI == nil)
    }

    @Test
    func documentURIWithSpaces() {
        let tab = EditorTab(filePath: URL(fileURLWithPath: "/Users/test user/my project/main.swift"))
        #expect(tab.documentURI != nil)
        // URL should percent-encode spaces
        #expect(tab.documentURI?.contains("test%20user") == true || tab.documentURI?.contains("test user") == true)
    }

    // MARK: - New Language Extensions

    @Test
    func rustExtension() {
        #expect(EditorTab.languageFromExtension("rs") == "rust")
    }

    @Test
    func cExtensions() {
        #expect(EditorTab.languageFromExtension("c") == "c")
        #expect(EditorTab.languageFromExtension("h") == "c")
    }

    @Test
    func cppExtensions() {
        #expect(EditorTab.languageFromExtension("cpp") == "cpp")
        #expect(EditorTab.languageFromExtension("cc") == "cpp")
        #expect(EditorTab.languageFromExtension("cxx") == "cpp")
        #expect(EditorTab.languageFromExtension("hpp") == "cpp")
        #expect(EditorTab.languageFromExtension("hh") == "cpp")
    }

    @Test
    func phpExtension() {
        #expect(EditorTab.languageFromExtension("php") == "php")
    }

    @Test
    func zigExtension() {
        #expect(EditorTab.languageFromExtension("zig") == "zig")
    }

    @Test
    func javaExtension() {
        #expect(EditorTab.languageFromExtension("java") == "java")
    }

    @Test
    func luaExtension() {
        #expect(EditorTab.languageFromExtension("lua") == "lua")
    }

    @Test
    func dartExtension() {
        #expect(EditorTab.languageFromExtension("dart") == "dart")
    }

    @Test
    func haskellExtensions() {
        #expect(EditorTab.languageFromExtension("hs") == "haskell")
        #expect(EditorTab.languageFromExtension("lhs") == "haskell")
    }

    @Test
    func ocamlExtensions() {
        #expect(EditorTab.languageFromExtension("ml") == "ocaml")
        #expect(EditorTab.languageFromExtension("mli") == "ocaml")
    }

    @Test
    func cssExtension() {
        #expect(EditorTab.languageFromExtension("css") == "css")
    }

    @Test
    func htmlExtensions() {
        #expect(EditorTab.languageFromExtension("html") == "html")
        #expect(EditorTab.languageFromExtension("htm") == "html")
    }

    @Test
    func xmlExtensions() {
        #expect(EditorTab.languageFromExtension("xml") == "xml")
        #expect(EditorTab.languageFromExtension("xsl") == "xml")
    }

    @Test
    func sqlExtension() {
        #expect(EditorTab.languageFromExtension("sql") == "sql")
    }

    @Test
    func rExtension() {
        #expect(EditorTab.languageFromExtension("r") == "r")
    }

    @Test
    func scalaExtensions() {
        #expect(EditorTab.languageFromExtension("scala") == "scala")
        #expect(EditorTab.languageFromExtension("sc") == "scala")
    }

    // MARK: - Existing Extensions Unchanged

    @Test
    func existingExtensionsUnchanged() {
        #expect(EditorTab.languageFromExtension("swift") == "swift")
        #expect(EditorTab.languageFromExtension("py") == "python")
        #expect(EditorTab.languageFromExtension("go") == "go")
        #expect(EditorTab.languageFromExtension("rb") == "ruby")
        #expect(EditorTab.languageFromExtension("js") == "javascript")
        #expect(EditorTab.languageFromExtension("ts") == "typescript")
        #expect(EditorTab.languageFromExtension("jsx") == "javascript")
        #expect(EditorTab.languageFromExtension("tsx") == "typescript")
        #expect(EditorTab.languageFromExtension("vue") == "vue")
        #expect(EditorTab.languageFromExtension("kt") == "kotlin")
        #expect(EditorTab.languageFromExtension("ex") == "elixir")
        #expect(EditorTab.languageFromExtension("sh") == "bash")
        #expect(EditorTab.languageFromExtension("md") == "markdown")
        #expect(EditorTab.languageFromExtension("dockerfile") == "dockerfile")
        #expect(EditorTab.languageFromExtension("yml") == "yaml")
        #expect(EditorTab.languageFromExtension("json") == "json")
        #expect(EditorTab.languageFromExtension("toml") == "toml")
    }

    @Test
    func unknownExtensionReturnsPlaintext() {
        #expect(EditorTab.languageFromExtension("xyz") == "plaintext")
        #expect(EditorTab.languageFromExtension("") == "plaintext")
    }

    // MARK: - Language from tab

    @Test
    func languageFromTab() {
        let tab = EditorTab(filePath: URL(fileURLWithPath: "/test/main.rs"))
        #expect(tab.language == "rust")
    }

    @Test
    func languageFromTabNoPath() {
        let tab = EditorTab()
        #expect(tab.language == "plaintext")
    }
}
