import Foundation

enum FirstInstallationSessionSelection: String, Codable {
    case existing
    case createNew
}

struct FirstInstallationSession: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let configurationDirectory: String
    let selection: FirstInstallationSessionSelection
    let hostname: String
    let machineName: String
    let username: String
    let machineType: String
    let selectedProfiles: [String]
    let appStateEnabled: Bool
    let installAttempted: Bool
}

final class FirstInstallationSessionPersistence {
    private static let key = "NixMeFirstInstallationSession"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for configurationDirectory: URL) -> FirstInstallationSession? {
        guard let data = defaults.data(forKey: Self.key),
              let session = try? JSONDecoder().decode(FirstInstallationSession.self, from: data),
              session.schemaVersion == FirstInstallationSession.schemaVersion,
              session.configurationDirectory == Self.normalizedPath(configurationDirectory)
        else { return nil }

        return session
    }

    func save(_ session: FirstInstallationSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    static func normalizedPath(_ directory: URL) -> String {
        directory.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
