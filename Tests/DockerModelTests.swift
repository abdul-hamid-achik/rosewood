import Foundation
import Testing
@testable import Rosewood

@MainActor
struct DockerModelTests {
    @Test
    func defaultStateMatchesPreExtractionBehavior() {
        let model = DockerModel()

        #expect(model.dockerContainers.isEmpty)
        #expect(model.dockerImages.isEmpty)
        #expect(model.dockerVolumes.isEmpty)
        #expect(model.dockerComposeProjects.isEmpty)
        #expect(model.isRefreshingDocker == false)
        #expect(model.selectedDockerTab == .containers)
        #expect(model.selectedContainer == nil)
        #expect(model.dockerBadgeCount == nil)
        #expect(model.isDockerAvailable == false)

        if case .connecting = model.dockerConnectionState {
            // expected default
        } else {
            Issue.record("Expected default dockerConnectionState to be .connecting")
        }
    }
}
