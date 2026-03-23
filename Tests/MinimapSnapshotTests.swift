import AppKit
import Testing
@testable import Rosewood

struct MinimapSnapshotTests {
    @Test
    func snapshotNormalizesLineWidthsAndViewportRange() {
        let text = """
        short
        a much longer line for the minimap
        mid
        tail
        """

        let snapshot = MinimapSnapshot.make(
            text: text,
            visibleRect: NSRect(x: 0, y: 50, width: 200, height: 50),
            documentHeight: 200
        )

        #expect(snapshot.lineWidthFractions.count == 4)
        #expect(snapshot.lineWidthFractions[1] > snapshot.lineWidthFractions[0])
        #expect(snapshot.visibleStartLine == 2)
        #expect(snapshot.visibleEndLine == 2)
        #expect(snapshot.accessibilityValue == "2-2")
    }

    @Test
    func snapshotFallsBackForEmptyDocument() {
        let snapshot = MinimapSnapshot.make(
            text: "",
            visibleRect: .zero,
            documentHeight: 0
        )

        #expect(snapshot.lineWidthFractions == [0.12])
        #expect(snapshot.visibleStartLine == 1)
        #expect(snapshot.visibleEndLine == 1)
    }
}
