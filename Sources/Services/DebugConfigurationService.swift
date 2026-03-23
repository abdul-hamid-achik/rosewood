import Foundation
import TOMLKit

enum DebugConfigurationServiceError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case unreadableConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .unreadableConfiguration(let message):
            return message
        }
    }
}

final class DebugConfigurationService {
    func loadProjectConfiguration(for projectRoot: URL?) throws -> DebugProjectConfiguration {
        guard let projectRoot else { return .empty }

        let configURL = projectRoot.appendingPathComponent(".rosewood.toml")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .empty
        }

        do {
            let tomlString = try String(contentsOf: configURL, encoding: .utf8)
            let decoded = try TOMLDecoder().decode(DecodedProjectConfiguration.self, from: tomlString)
            let debugSection = decoded.debug
            return DebugProjectConfiguration(
                defaultConfiguration: debugSection?.defaultConfiguration,
                configurations: debugSection?.configurations ?? []
            )
        } catch let decodingError as DecodingError {
            throw DebugConfigurationServiceError.invalidConfiguration(
                "Could not decode the [debug] section in .rosewood.toml: \(decodingError.localizedDescription)"
            )
        } catch {
            throw DebugConfigurationServiceError.unreadableConfiguration(
                "Could not read .rosewood.toml: \(error.localizedDescription)"
            )
        }
    }
}

private struct DecodedProjectConfiguration: Decodable {
    let debug: DecodedDebugSection?
}

private struct DecodedDebugSection: Decodable {
    let defaultConfiguration: String?
    let configurations: [DebugConfiguration]?
}
