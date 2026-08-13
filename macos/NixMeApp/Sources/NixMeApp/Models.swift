import Foundation

struct ManagementSnapshot: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let host: Host
    let configuration: ConfigurationState
    let health: SystemHealth
    let inventory: Inventory
    let updates: Updates
    let projects: [Project]
    let warnings: [String]

    var desiredSoftwareCount: Int {
        inventory.desired.nixPackages.count
            + inventory.desired.homebrew.formulae.count
            + inventory.desired.homebrew.casks.count
            + inventory.desired.homebrew.masApps.count
    }

    var installedHomebrewCount: Int {
        inventory.installed.homebrew.formulae.count
            + inventory.installed.homebrew.casks.count
    }

    var projectAttentionCount: Int {
        projects.filter { $0.status != "current" }.count
    }

    var softwareUpdateCount: Int {
        updates.all.count
    }
}

struct Host: Codable {
    let hostname: String
    let machineName: String
    let machineType: String?
    let username: String
}

struct ConfigurationState: Codable {
    let path: String
    let exists: Bool
    let appliedManifestPath: String
    let applyState: String
    let generation: Int?
    let git: GitState?
}

struct GitState: Codable {
    let repository: Bool
    let branch: String?
    let revision: String?
    let dirty: Bool
    let upstream: String?
    let ahead: Int
    let behind: Int
    let remoteState: String
}

struct SystemHealth: Codable {
    let nix: ToolHealth
    let nixDarwin: ToolHealth
    let homebrew: ToolHealth
}

struct ToolHealth: Codable {
    let available: Bool
    let version: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decode(Bool.self, forKey: .available)
        version = try container.decodeIfPresent(String.self, forKey: .version)
    }

    private enum CodingKeys: String, CodingKey {
        case available
        case version
    }
}

struct Inventory: Codable {
    let desired: SoftwareInventory
    let applied: SoftwareInventory
    let installed: InstalledInventory
}

struct SoftwareInventory: Codable {
    let nixPackages: [String]
    let homebrew: HomebrewInventory
}

struct HomebrewInventory: Codable {
    let formulae: [String]
    let casks: [String]
    let masApps: [String: Int]
}

struct InstalledInventory: Codable {
    let homebrew: InstalledHomebrewInventory
}

struct InstalledHomebrewInventory: Codable {
    let formulae: [InstalledPackage]
    let casks: [InstalledPackage]
}

struct InstalledPackage: Codable, Identifiable {
    let name: String
    let versions: [String]

    var id: String { name }
}

struct Updates: Codable {
    let homebrew: [SoftwareUpdate]
    let macAppStore: [SoftwareUpdate]
    let nixFlake: [SoftwareUpdate]

    var all: [SoftwareUpdate] {
        nixFlake + homebrew + macAppStore
    }
}

struct SoftwareUpdate: Codable, Identifiable {
    let name: String
    let kind: String
    let installedVersions: [String]
    let availableVersion: String?
    let storeId: Int?

    var id: String { "\(kind):\(name)" }
}

struct Project: Codable, Identifiable {
    let name: String
    let url: String
    let path: String
    let branch: String?
    let remote: String
    let clone: Bool
    let update: Bool
    let absolutePath: String
    let present: Bool
    let isGitRepository: Bool
    let status: String
    let git: GitState?

    var id: String { name }
}
