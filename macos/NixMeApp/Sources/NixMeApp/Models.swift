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
    let desiredSource: SourceInfo?
    let appliedSource: SourceInfo?
}

struct SourceInfo: Codable, Equatable {
    let revision: String
    let dirty: Bool
    let contentHash: String
    let lockHash: String
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
    let nixPackageDetails: [NixPackageMetadata]?
    let homebrew: HomebrewInventory
}

struct NixPackageMetadata: Codable, Hashable {
    let name: String
    let fullName: String
    let version: String?
    let description: String?
    let homepage: String?
    let license: String?
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

enum SoftwareKind: String, Codable, Hashable, CaseIterable {
    case nix
    case formula
    case cask
    case mas

    var label: String {
        switch self {
        case .nix: "Nix package"
        case .formula: "Homebrew formula"
        case .cask: "Homebrew application"
        case .mas: "Mac App Store application"
        }
    }

    var symbol: String {
        switch self {
        case .nix: "snowflake"
        case .formula: "terminal"
        case .cask: "macwindow"
        case .mas: "apple.logo"
        }
    }
}

struct SoftwareListItem: Identifiable, Hashable {
    let kind: SoftwareKind
    let name: String
    let displayName: String
    let desiredVersion: String?
    let appliedVersion: String?
    let installedVersions: [String]
    let storeId: Int?
    let embeddedDetails: PackageDetails?
    let isDesired: Bool
    let isApplied: Bool

    var id: String { "\(kind.rawValue):\(name)" }
}

struct PackageDetails: Codable, Hashable {
    let schemaVersion: Int
    let kind: SoftwareKind
    let name: String
    let displayName: String
    let description: String?
    let version: String?
    let installedVersions: [String]
    let homepage: String?
    let license: String?
    let publisher: String?
    let dependencies: [String]
    let storeId: Int?
}

enum SoftwareChangeKind: String, CaseIterable, Equatable {
    case versionChanged = "Version changed"
    case added = "Added"
    case removed = "Removed"
}

struct SoftwareDifference: Identifiable {
    let kind: SoftwareKind
    let name: String
    let change: SoftwareChangeKind
    let desiredVersion: String?
    let appliedVersion: String?
    let storeId: Int?

    var id: String { "\(kind.rawValue):\(name):\(change.rawValue)" }
}

extension ManagementSnapshot {
    var softwareDifferences: [SoftwareDifference] {
        guard configuration.applyState != "unknown" else { return [] }

        var differences = nixDifferences
        differences += setDifferences(
            desired: inventory.desired.homebrew.formulae,
            applied: inventory.applied.homebrew.formulae,
            kind: .formula
        )
        differences += setDifferences(
            desired: inventory.desired.homebrew.casks,
            applied: inventory.applied.homebrew.casks,
            kind: .cask
        )

        let desiredMAS = inventory.desired.homebrew.masApps
        let appliedMAS = inventory.applied.homebrew.masApps
        for name in Set(desiredMAS.keys).union(appliedMAS.keys).sorted() {
            switch (desiredMAS[name], appliedMAS[name]) {
            case let (.some(desired), .some(applied)) where desired != applied:
                differences.append(SoftwareDifference(kind: .mas, name: name, change: .versionChanged, desiredVersion: String(desired), appliedVersion: String(applied), storeId: desired))
            case let (.some(storeId), .none):
                differences.append(SoftwareDifference(kind: .mas, name: name, change: .added, desiredVersion: nil, appliedVersion: nil, storeId: storeId))
            case let (.none, .some(storeId)):
                differences.append(SoftwareDifference(kind: .mas, name: name, change: .removed, desiredVersion: nil, appliedVersion: nil, storeId: storeId))
            default:
                break
            }
        }
        return differences
    }

    var desiredSoftwareItems: [SoftwareListItem] {
        let installedFormulae = Dictionary(uniqueKeysWithValues: inventory.installed.homebrew.formulae.map { ($0.name, $0.versions) })
        let installedCasks = Dictionary(uniqueKeysWithValues: inventory.installed.homebrew.casks.map { ($0.name, $0.versions) })
        var items = nixItems(from: inventory.desired, applied: inventory.applied, isDesired: true)
        items += inventory.desired.homebrew.formulae.map {
            SoftwareListItem(kind: .formula, name: $0, displayName: $0, desiredVersion: nil, appliedVersion: nil, installedVersions: installedFormulae[$0] ?? [], storeId: nil, embeddedDetails: nil, isDesired: true, isApplied: inventory.applied.homebrew.formulae.contains($0))
        }
        items += inventory.desired.homebrew.casks.map {
            SoftwareListItem(kind: .cask, name: $0, displayName: $0, desiredVersion: nil, appliedVersion: nil, installedVersions: installedCasks[$0] ?? [], storeId: nil, embeddedDetails: nil, isDesired: true, isApplied: inventory.applied.homebrew.casks.contains($0))
        }
        items += inventory.desired.homebrew.masApps.map { name, storeId in
            SoftwareListItem(kind: .mas, name: name, displayName: name, desiredVersion: nil, appliedVersion: nil, installedVersions: [], storeId: storeId, embeddedDetails: nil, isDesired: true, isApplied: inventory.applied.homebrew.masApps[name] == storeId)
        }
        return items
    }

    var installedSoftwareItems: [SoftwareListItem] {
        var items = nixItems(from: inventory.applied, applied: inventory.applied, isDesired: false)
        items += inventory.installed.homebrew.formulae.map {
            SoftwareListItem(kind: .formula, name: $0.name, displayName: $0.name, desiredVersion: nil, appliedVersion: nil, installedVersions: $0.versions, storeId: nil, embeddedDetails: nil, isDesired: inventory.desired.homebrew.formulae.contains($0.name), isApplied: inventory.applied.homebrew.formulae.contains($0.name))
        }
        items += inventory.installed.homebrew.casks.map {
            SoftwareListItem(kind: .cask, name: $0.name, displayName: $0.name, desiredVersion: nil, appliedVersion: nil, installedVersions: $0.versions, storeId: nil, embeddedDetails: nil, isDesired: inventory.desired.homebrew.casks.contains($0.name), isApplied: inventory.applied.homebrew.casks.contains($0.name))
        }
        return items
    }

    private var nixDifferences: [SoftwareDifference] {
        let desired = nixMetadata(inventory.desired)
        let applied = nixMetadata(inventory.applied)
        return Set(desired.keys).union(applied.keys).sorted().compactMap { name in
            switch (desired[name], applied[name]) {
            case let (.some(wanted), .some(active)) where wanted.version != active.version || wanted.fullName != active.fullName:
                SoftwareDifference(kind: .nix, name: name, change: .versionChanged, desiredVersion: wanted.version ?? wanted.fullName, appliedVersion: active.version ?? active.fullName, storeId: nil)
            case let (.some(wanted), .none):
                SoftwareDifference(kind: .nix, name: name, change: .added, desiredVersion: wanted.version, appliedVersion: nil, storeId: nil)
            case let (.none, .some(active)):
                SoftwareDifference(kind: .nix, name: name, change: .removed, desiredVersion: nil, appliedVersion: active.version, storeId: nil)
            default:
                nil
            }
        }
    }

    private func nixMetadata(_ software: SoftwareInventory) -> [String: NixPackageMetadata] {
        let details = software.nixPackageDetails ?? []
        if !details.isEmpty {
            return Dictionary(details.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return Dictionary(software.nixPackages.map { fullName in
            let components = legacyNixPackage(fullName)
            return (components.name, NixPackageMetadata(name: components.name, fullName: fullName, version: components.version, description: nil, homepage: nil, license: nil))
        }, uniquingKeysWith: { first, _ in first })
    }

    private func legacyNixPackage(_ fullName: String) -> (name: String, version: String?) {
        guard let separator = fullName.range(of: #"-(?=[0-9])"#, options: .regularExpression) else {
            return (fullName, nil)
        }
        return (
            String(fullName[..<separator.lowerBound]),
            String(fullName[separator.upperBound...])
        )
    }

    private func nixItems(from software: SoftwareInventory, applied: SoftwareInventory, isDesired: Bool) -> [SoftwareListItem] {
        let active = nixMetadata(applied)
        let wanted = nixMetadata(inventory.desired)
        return nixMetadata(software).values.map { package in
            let reference = wanted[package.name]
            let details = PackageDetails(
                schemaVersion: 1,
                kind: .nix,
                name: package.name,
                displayName: package.name,
                description: package.description ?? reference?.description,
                version: package.version,
                installedVersions: [],
                homepage: package.homepage ?? reference?.homepage,
                license: package.license ?? reference?.license,
                publisher: nil,
                dependencies: [],
                storeId: nil
            )
            return SoftwareListItem(
                kind: .nix,
                name: package.name,
                displayName: package.name,
                desiredVersion: package.version,
                appliedVersion: active[package.name]?.version,
                installedVersions: [],
                storeId: nil,
                embeddedDetails: details,
                isDesired: isDesired || wanted[package.name] != nil,
                isApplied: active[package.name] != nil
            )
        }
    }

    private func setDifferences(desired: [String], applied: [String], kind: SoftwareKind) -> [SoftwareDifference] {
        let desiredSet = Set(desired)
        let appliedSet = Set(applied)
        let added = desiredSet.subtracting(appliedSet).map {
            SoftwareDifference(kind: kind, name: $0, change: .added, desiredVersion: nil, appliedVersion: nil, storeId: nil)
        }
        let removed = appliedSet.subtracting(desiredSet).map {
            SoftwareDifference(kind: kind, name: $0, change: .removed, desiredVersion: nil, appliedVersion: nil, storeId: nil)
        }
        return (added + removed).sorted { $0.name < $1.name }
    }
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
