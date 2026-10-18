import Foundation

enum ConfigurationBootstrapError: LocalizedError {
    case destinationExists(String)
    case missingDependency(String)
    case cloneFailed(String)
    case updateFailed(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let path):
            "The destination already exists at \(path). Choose that folder or move it before cloning."
        case .missingDependency(let command):
            "\(command) is required for this action. Install it, then try again."
        case .cloneFailed(let message):
            "Could not clone the configuration: \(message)"
        case .updateFailed(let message):
            "Could not update the configuration: \(message)"
        case .invalidConfiguration(let path):
            "\(path) is not a nix-me configuration. It must contain flake.nix."
        }
    }
}

enum ConfigurationCheckoutState: String, Equatable {
    case ready
    case missing
    case invalid
}

struct CommandDependency: Identifiable, Equatable {
    let command: String
    let displayName: String
    let purpose: String
    let isRequired: Bool
    let remediation: String
    let executableURL: URL?

    var id: String { command }
    var isAvailable: Bool { executableURL != nil }
}

struct ConfigurationSetupStatus: Equatable {
    let checkoutState: ConfigurationCheckoutState
    let configurationDirectory: URL?
    let checkoutMessage: String
    let defaultCloneDestination: URL
    let canCloneToDefaultDestination: Bool
    let canUpdateCheckout: Bool
    let dependencies: [CommandDependency]

    var missingRequiredDependencies: [CommandDependency] {
        dependencies.filter { $0.isRequired && !$0.isAvailable }
    }

    var missingOptionalDependencies: [CommandDependency] {
        dependencies.filter { !$0.isRequired && !$0.isAvailable }
    }

    var requiredIssueCount: Int {
        (checkoutState == .ready ? 0 : 1) + missingRequiredDependencies.count
    }

    var isReady: Bool {
        checkoutState == .ready && missingRequiredDependencies.isEmpty
    }
}

struct ConfigurationBootstrap {
    static let repositoryURL = "https://github.com/lucamaraschi/nix-me.git"
    static let installationGuideURL = URL(
        string: "https://github.com/lucamaraschi/nix-me#quick-start")!

    private struct DependencyDefinition {
        let command: String
        let displayName: String
        let purpose: String
        let isRequired: Bool
        let remediation: String
    }

    private static let dependencyDefinitions = [
        DependencyDefinition(
            command: "git",
            displayName: "Git",
            purpose: "Clone the configuration and report repository synchronization.",
            isRequired: true,
            remediation: "Install Apple's Command Line Tools with xcode-select --install."
        ),
        DependencyDefinition(
            command: "nix",
            displayName: "Nix",
            purpose: "Evaluate, build, and apply the desired system configuration.",
            isRequired: true,
            remediation: "Run the nix-me installer, then relaunch Nix Me."
        ),
        DependencyDefinition(
            command: "jq",
            displayName: "jq",
            purpose: "Run the machine-readable nix-me management API.",
            isRequired: true,
            remediation: "Apply the nix-me configuration; jq is included in the managed packages."
        ),
        DependencyDefinition(
            command: "make",
            displayName: "Make",
            purpose: "Activate the configuration from the dashboard.",
            isRequired: true,
            remediation: "Install Apple's Command Line Tools or apply the nix-me configuration."
        ),
        DependencyDefinition(
            command: "brew",
            displayName: "Homebrew",
            purpose: "Inspect and update Homebrew formulae and applications.",
            isRequired: false,
            remediation: "Install Homebrew or choose a profile that does not manage Homebrew software."
        ),
        DependencyDefinition(
            command: "mas",
            displayName: "Mac App Store CLI",
            purpose: "Inspect and update managed Mac App Store applications.",
            isRequired: false,
            remediation: "Apply a profile that installs mas to enable App Store updates."
        ),
        DependencyDefinition(
            command: "nix-me-apps",
            displayName: "Application-state engine",
            purpose: "Inspect and converge supported application preferences.",
            isRequired: false,
            remediation: "Enable the application-state profile and apply the configuration."
        ),
    ]

    static func inspect(
        configurationDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        savedDirectory: String? = UserDefaults.standard.string(
            forKey: ManagementAPIClient.configurationDirectoryDefaultsKey
        ),
        commandSearchDirectories: [URL]? = nil
    ) -> ConfigurationSetupStatus {
        let fileManager = FileManager.default
        let defaultCloneDestination =
            homeDirectory
            .appendingPathComponent(".config/nixpkgs", isDirectory: true)
        let configuredCandidates =
            configurationDirectory.map { [$0] }
            ?? preferredCandidates(
                environment: environment,
                homeDirectory: homeDirectory,
                savedDirectory: savedDirectory
            )
        let candidates =
            configurationDirectory.map { [$0] }
            ?? allCandidates(
                environment: environment,
                homeDirectory: homeDirectory,
                currentDirectory: currentDirectory,
                savedDirectory: savedDirectory
            )

        let validDirectory = candidates.first(where: ManagementAPIClient.isConfigurationDirectory)
            .map(normalize)
        let invalidDirectory =
            validDirectory == nil
            ? configuredCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }).map(
                normalize)
            : nil

        let checkoutState: ConfigurationCheckoutState
        let checkoutMessage: String
        let discoveredDirectory: URL?
        if let validDirectory {
            checkoutState = .ready
            checkoutMessage = "Connected to a valid nix-me configuration."
            discoveredDirectory = validDirectory
        } else if let invalidDirectory {
            checkoutState = .invalid
            checkoutMessage = invalidCheckoutMessage(at: invalidDirectory, fileManager: fileManager)
            discoveredDirectory = invalidDirectory
        } else {
            checkoutState = .missing
            checkoutMessage =
                "No nix-me configuration checkout was found. Choose an existing checkout or clone one from GitHub."
            discoveredDirectory = nil
        }

        let searchDirectories =
            commandSearchDirectories
            ?? executableSearchDirectories(environment: environment, homeDirectory: homeDirectory)
        let dependencies = dependencyDefinitions.map { definition in
            CommandDependency(
                command: definition.command,
                displayName: definition.displayName,
                purpose: definition.purpose,
                isRequired: definition.isRequired,
                remediation: definition.remediation,
                executableURL: executableURL(
                    for: definition.command,
                    searchDirectories: searchDirectories,
                    fileManager: fileManager
                )
            )
        }
        let gitIsAvailable = dependencies.first(where: { $0.command == "git" })?.isAvailable == true
        let canUpdateCheckout = gitIsAvailable
            && discoveredDirectory.map {
                fileManager.fileExists(atPath: $0.appendingPathComponent(".git").path)
            } == true

        return ConfigurationSetupStatus(
            checkoutState: checkoutState,
            configurationDirectory: discoveredDirectory,
            checkoutMessage: checkoutMessage,
            defaultCloneDestination: defaultCloneDestination,
            canCloneToDefaultDestination: !fileManager.fileExists(atPath: defaultCloneDestination.path),
            canUpdateCheckout: canUpdateCheckout,
            dependencies: dependencies
        )
    }

    static func clone(to destination: URL) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            throw ConfigurationBootstrapError.destinationExists(destination.path)
        }
        guard
            let git = executableURL(
                for: "git",
                searchDirectories: executableSearchDirectories(
                    environment: ProcessInfo.processInfo.environment,
                    homeDirectory: fileManager.homeDirectoryForCurrentUser
                ),
                fileManager: fileManager
            )
        else {
            throw ConfigurationBootstrapError.missingDependency("Git")
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let errors = Pipe()
                process.executableURL = git
                process.arguments = ["clone", repositoryURL, destination.path]
                process.standardError = errors

                do {
                    try process.run()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        let message =
                            String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Git exited with an error"
                        try? FileManager.default.removeItem(at: destination)
                        continuation.resume(throwing: ConfigurationBootstrapError.cloneFailed(message))
                        return
                    }
                    continuation.resume(returning: ())
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func updateCheckout(at directory: URL, gitURL: URL? = nil) async throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path) else {
            throw ConfigurationBootstrapError.updateFailed(
                "\(directory.path) is not a Git checkout. Choose another folder instead."
            )
        }
        guard
            let git = gitURL ?? executableURL(
                for: "git",
                searchDirectories: executableSearchDirectories(
                    environment: ProcessInfo.processInfo.environment,
                    homeDirectory: fileManager.homeDirectoryForCurrentUser
                ),
                fileManager: fileManager
            )
        else {
            throw ConfigurationBootstrapError.missingDependency("Git")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = git
                process.arguments = ["-C", directory.path, "pull", "--rebase", "--autostash"]
                process.standardOutput = output
                process.standardError = output

                do {
                    try process.run()
                    let outputData = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        let gitOutput = String(data: outputData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let message = gitOutput.flatMap { $0.isEmpty ? nil : $0 }
                            ?? "Git exited with an error"
                        continuation.resume(
                            throwing: ConfigurationBootstrapError.updateFailed(message)
                        )
                        return
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func preferredCandidates(
        environment: [String: String],
        homeDirectory: URL,
        savedDirectory: String?
    ) -> [URL] {
        var candidates: [URL] = []
        if let configuredPath = environment["NIX_ME_CONFIG_DIR"], !configuredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: configuredPath))
        }
        if let savedDirectory, !savedDirectory.isEmpty {
            candidates.append(URL(fileURLWithPath: savedDirectory))
        }
        candidates.append(homeDirectory.appendingPathComponent(".config/nixpkgs", isDirectory: true))
        candidates.append(homeDirectory.appendingPathComponent("src/lm/nix-me", isDirectory: true))
        return unique(candidates)
    }

    private static func allCandidates(
        environment: [String: String],
        homeDirectory: URL,
        currentDirectory: URL,
        savedDirectory: String?
    ) -> [URL] {
        var candidates: [URL] = []
        if let configuredPath = environment["NIX_ME_CONFIG_DIR"], !configuredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: configuredPath))
        }
        if let savedDirectory, !savedDirectory.isEmpty {
            candidates.append(URL(fileURLWithPath: savedDirectory))
        }
        candidates.append(currentDirectory)
        candidates.append(homeDirectory.appendingPathComponent(".config/nixpkgs", isDirectory: true))
        candidates.append(homeDirectory.appendingPathComponent("src/lm/nix-me", isDirectory: true))
        return unique(candidates)
    }

    private static func executableSearchDirectories(
        environment: [String: String],
        homeDirectory: URL
    ) -> [URL] {
        let username = environment["USER"] ?? NSUserName()
        var paths = [
            "/run/current-system/sw/bin",
            "/etc/profiles/per-user/\(username)/bin",
            "/nix/var/nix/profiles/default/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        if let environmentPath = environment["PATH"] {
            paths.append(contentsOf: environmentPath.split(separator: ":").map(String.init))
        }
        paths.append(homeDirectory.appendingPathComponent(".nix-profile/bin").path)
        return unique(paths.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    private static func executableURL(
        for command: String,
        searchDirectories: [URL],
        fileManager: FileManager
    ) -> URL? {
        searchDirectories
            .map { $0.appendingPathComponent(command) }
            .first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    private static func invalidCheckoutMessage(at directory: URL, fileManager: FileManager) -> String {
        var missing: [String] = []
        if !fileManager.fileExists(atPath: directory.appendingPathComponent("flake.nix").path) {
            missing.append("flake.nix")
        }
        let detail = missing.isEmpty ? "required files" : missing.joined(separator: " and ")
        return "The checkout at \(directory.path) is incomplete or outdated; it is missing \(detail)."
    }

    private static func normalize(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
