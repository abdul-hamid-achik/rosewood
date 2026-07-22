import Foundation
import Testing
@testable import Rosewood

struct DockerCLIParsingTests {
    private func serviceNames(from yaml: String) -> [String] {
        DockerCLI.parseComposeServiceNames(from: yaml).map(\.name)
    }

    // MARK: - parseComposeServiceNames: empty / malformed input

    @Test
    func emptyInputYieldsNoServices() {
        #expect(DockerCLI.parseComposeServiceNames(from: "").isEmpty)
    }

    @Test
    func inputWithoutServicesSectionYieldsNothing() {
        let yaml = "version: '3'\nvolumes:\n  data:\n    driver: local\n"
        #expect(DockerCLI.parseComposeServiceNames(from: yaml).isEmpty)
    }

    @Test
    func detectsServicesSectionMidFile() {
        let yaml = "version: '3'\nvolumes:\n  data:\nservices:\n  api:\n  worker:\n"
        #expect(serviceNames(from: yaml) == ["api", "worker"])
    }

    @Test
    func ignoresCommentLinesInsideServices() {
        let yaml = "services:\n  # database:\n  web:\n"
        #expect(serviceNames(from: yaml) == ["web"])
    }

    @Test
    func ignoresListItemLinesInsideServices() {
        let yaml = "services:\n  - web:\n  db:\n"
        #expect(serviceNames(from: yaml) == ["db"])
    }

    @Test
    func filtersVolumeAndNetworkNamedEntries() {
        let yaml = "services:\n  web:\n  volumes:\n  networks:\n"
        #expect(serviceNames(from: yaml) == ["web"])
    }

    @Test
    func parsesLoneCarriageReturnLineEndings() {
        // `Character.isNewline` matches a lone CR, so legacy Mac line endings still parse.
        let yaml = "services:\r  web:\r  db:\r"
        #expect(serviceNames(from: yaml) == ["web", "db"])
    }

    @Test
    func trimsWhitespaceAroundServiceName() {
        let yaml = "services:\n  web  :\n"
        #expect(serviceNames(from: yaml) == ["web"])
    }

    @Test
    func ignoresBareColonWithEmptyName() {
        let yaml = "services:\n  :\n  web:\n"
        #expect(serviceNames(from: yaml) == ["web"])
    }

    @Test
    func whitespaceOnlyLineTerminatesServicesSection() {
        // A whitespace-only line trims to empty, which ends the services block just like a
        // blank line, so `db` is never reached.
        let yaml = "services:\n  web:\n   \n  db:\n"
        #expect(serviceNames(from: yaml) == ["web"])
    }

    @Test
    func parsedServiceHasCreatedDefaults() {
        let services = DockerCLI.parseComposeServiceNames(from: "services:\n  web:\n")

        #expect(services.count == 1)
        #expect(services.first?.id == "web")
        #expect(services.first?.name == "web")
        #expect(services.first?.state == .created)
        #expect(services.first?.containerId == nil)
        #expect(services.first?.ports.isEmpty == true)
    }
}

struct DockerLogStreamBufferParsingTests {
    private func collectLines(_ build: (LogStreamBuffer, AsyncStream<LogLine>.Continuation) -> Void) async -> [LogLine] {
        let buffer = LogStreamBuffer(stream: .stdout)
        let (stream, continuation) = AsyncStream.makeStream(of: LogLine.self)
        build(buffer, continuation)
        continuation.finish()

        var lines: [LogLine] = []
        for await line in stream { lines.append(line) }
        return lines
    }

    @Test
    func flushEmitsTrailingPartialLine() async {
        let lines = await collectLines { buffer, continuation in
            buffer.append(Data("no-newline".utf8), into: continuation)
            buffer.flush(into: continuation)
        }
        #expect(lines.map(\.text) == ["no-newline"])
    }

    @Test
    func flushWithNoPendingDataYieldsNothing() async {
        let lines = await collectLines { buffer, continuation in
            buffer.append(Data("complete\n".utf8), into: continuation)
            buffer.flush(into: continuation)
        }
        #expect(lines.map(\.text) == ["complete"])
    }

    @Test
    func accumulatesPartialChunksUntilNewline() async {
        let lines = await collectLines { buffer, continuation in
            buffer.append(Data("hel".utf8), into: continuation)
            buffer.append(Data("lo\nwor".utf8), into: continuation)
            buffer.append(Data("ld\n".utf8), into: continuation)
        }
        #expect(lines.map(\.text) == ["hello", "world"])
    }

    @Test
    func tagsEmittedLinesWithTheirStream() async {
        let buffer = LogStreamBuffer(stream: .stderr)
        let (stream, continuation) = AsyncStream.makeStream(of: LogLine.self)
        buffer.append(Data("boom\n".utf8), into: continuation)
        continuation.finish()

        var lines: [LogLine] = []
        for await line in stream { lines.append(line) }

        #expect(lines.count == 1)
        #expect(lines.first?.stream == .stderr)
        #expect(lines.first?.text == "boom")
    }
}
