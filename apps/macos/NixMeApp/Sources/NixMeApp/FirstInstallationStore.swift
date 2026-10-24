import Darwin
import Foundation
import SystemConfiguration

private enum FirstInstallationError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

struct InstallationProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
}

struct InstallationMachineConfiguration: Identifiable, Hashable {
    let id: String
    let hostname: String
    let machineName: String
    let username: String
    let machineType: String
    let profiles: [String]
}

enum FirstInstallationMachineSelection: Equatable {
    case existing(String)
    case createNew
}

enum FirstInstallationScreen: Int, CaseIterable {
    case welcome
    case configure
    case review
    case install
    case complete

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .configure: "Configure"
        case .review: "Review"
        case .install: "Install"
        case .complete: "Ready"
        }
    }
}

enum FirstInstallationPhase: Int, CaseIterable {
    case configuration
    case preparation
    case build
    case activation
    case verification

    var title: String {
        switch self {
        case .configuration: "Save configuration"
        case .preparation: "Prepare system"
        case .build: "Build software"
        case .activation: "Activate this Mac"
        case .verification: "Verify installation"
        }
    }

    var symbol: String {
        switch self {
        case .configuration: "doc.badge.plus"
        case .preparation: "checklist"
        case .build: "hammer"
        case .activation: "lock.shield"
        case .verification: "checkmark.seal"
        }
    }
}

@MainActor
final class FirstInstallationStore: ObservableObject {
    static let profiles = [
        InstallationProfile(id: "dev", name: "Development", summary: "Editors, languages, containers, and developer tools", symbol: "chevron.left.forwardslash.chevron.right"),
        InstallationProfile(id: "coding-agents", name: "Coding agents", summary: "AI-assisted development tools and command-line agents", symbol: "sparkles"),
        InstallationProfile(id: "work", name: "Work", summary: "Communication, meetings, documents, and cloud tools", symbol: "briefcase"),
        InstallationProfile(id: "personal", name: "Personal", summary: "Media, writing, streaming, and everyday applications", symbol: "person.crop.circle"),
        InstallationProfile(id: "maker", name: "Maker", summary: "3D printing, CAD, modeling, and fabrication tools", symbol: "wrench.and.screwdriver"),
        InstallationProfile(id: "hacking", name: "Security", summary: "Network analysis and security research tools", symbol: "lock.shield"),
        InstallationProfile(id: "ai", name: "AI", summary: "Hosted AI applications and supporting tools", symbol: "brain.head.profile"),
        InstallationProfile(id: "local-ai", name: "Local AI", summary: "Pi with private local inference through DS4", symbol: "cpu"),
    ]

    @Published var screen: FirstInstallationScreen = .welcome
    @Published var hostname: String
    @Published var machineName: String
    @Published var username: String
    @Published var machineType: String
    @Published var selectedProfiles: Set<String> = []
    @Published var appStateEnabled = false
    @Published private(set) var machineSelection: FirstInstallationMachineSelection?
    @Published private(set) var phase: FirstInstallationPhase = .configuration
    @Published private(set) var phaseMessage = ""
    @Published private(set) var isInstalling = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorDetails: String?

    let configurationDirectory: URL
    let setupStatus: ConfigurationSetupStatus
    let detectedHostname: String
    let availableMachines: [InstallationMachineConfiguration]

    private let detectedMachineName: String
    private let detectedUsername: String
    private let detectedMachineType: String

    init(configurationDirectory: URL? = nil) {
        let status = ConfigurationBootstrap.inspect(configurationDirectory: configurationDirectory)
        setupStatus = status
        self.configurationDirectory = status.configurationDirectory ?? status.defaultCloneDestination

        let detectedHostname = Self.detectHostname()
        let detectedMachineName = Self.detectMachineName(fallback: detectedHostname)
        let detectedUsername = NSUserName()
        let detectedMachineType = Self.detectMachineType()
        let availableMachines = Self.machineConfigurations(
            in: self.configurationDirectory,
            fallbackUsername: detectedUsername
        )

        self.detectedHostname = detectedHostname
        self.detectedMachineName = detectedMachineName
        self.detectedUsername = detectedUsername
        self.detectedMachineType = detectedMachineType
        self.availableMachines = availableMachines

        if let suggestedID = Self.suggestedMachineID(
            in: availableMachines,
            detectedHostname: detectedHostname
        ), let suggested = availableMachines.first(where: { $0.id == suggestedID }) {
            machineSelection = .existing(suggested.id)
            hostname = suggested.id
            machineName = suggested.machineName
            username = suggested.username
            machineType = suggested.machineType
            selectedProfiles = Set(suggested.profiles)
        } else {
            machineSelection = nil
            hostname = detectedHostname
            machineName = detectedMachineName
            username = detectedUsername
            machineType = detectedMachineType
        }
    }

    var selectedExistingMachine: InstallationMachineConfiguration? {
        guard case let .existing(id) = machineSelection else { return nil }
        return availableMachines.first(where: { $0.id == id })
    }

    var isCreatingNewMachine: Bool {
        machineSelection == .createNew
    }

    var configurationExists: Bool {
        selectedExistingMachine != nil
    }

    var validationMessage: String? {
        guard machineSelection != nil else {
            return "Choose a saved machine configuration or create a new one."
        }
        if hostname.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) == nil {
            return "Hostname must use lowercase letters, numbers, and hyphens."
        }
        if isCreatingNewMachine && availableMachines.contains(where: { $0.id == hostname }) {
            return "A saved configuration named \(hostname) already exists. Select it above instead."
        }
        if machineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give this Mac a display name."
        }
        if username.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) == nil {
            return "Username contains unsupported characters."
        }
        return nil
    }

    func toggleProfile(_ profile: InstallationProfile) {
        if selectedProfiles.contains(profile.id) {
            selectedProfiles.remove(profile.id)
        } else {
            selectedProfiles.insert(profile.id)
        }
    }

    func selectExistingMachine(_ machine: InstallationMachineConfiguration) {
        machineSelection = .existing(machine.id)
        hostname = machine.id
        machineName = machine.machineName
        username = machine.username
        machineType = machine.machineType
        selectedProfiles = Set(machine.profiles)
        appStateEnabled = false
    }

    func selectNewMachine() {
        machineSelection = .createNew
        hostname = detectedHostname
        machineName = detectedMachineName
        username = detectedUsername
        machineType = detectedMachineType
        selectedProfiles = []
        appStateEnabled = false
    }

    func continueFromWelcome() {
        screen = .configure
    }

    func continueFromConfiguration() {
        guard validationMessage == nil else { return }
        screen = .review
    }

    func goBack() {
        switch screen {
        case .configure: screen = .welcome
        case .review: screen = .configure
        case .install where !isInstalling: screen = .review
        default: break
        }
    }

    func install() async {
        guard !isInstalling, validationMessage == nil else { return }
        isInstalling = true
        errorMessage = nil
        errorDetails = nil
        phase = .configuration
        phaseMessage = configurationExists
            ? "Using the existing configuration for \(hostname)"
            : "Creating the machine and profile configuration"
        screen = .install

        do {
            try await createMachineConfiguration()
            phase = .preparation
            phaseMessage = "Checking the generated configuration and required tools"

            let actionClient = ManagementActionClient(configurationDirectory: configurationDirectory)
            let response = try await actionClient.apply(
                hostname: hostname,
                username: username,
                machineName: machineName,
                machineType: machineType,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.record(progress)
                    }
                }
            )
            guard response.success else {
                throw FirstInstallationError.failed(response.message)
            }

            phase = .verification
            phaseMessage = "Confirming the active host and system generation"
            try await verifyInstallation()
            Self.recordSuccessfulInstallation()
            phaseMessage = "The managed system is active and ready"
            isInstalling = false
            screen = .complete
        } catch {
            isInstalling = false
            errorMessage = "\(phase.title) could not finish. \(Self.errorSummary(error))"
            errorDetails = error.localizedDescription
        }
    }

    private func createMachineConfiguration() async throws {
        guard !configurationExists else { return }

        let script = configurationDirectory
            .appendingPathComponent("tools/installation/create-machine.sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            throw ManagementAPIError.invalidResponse("The machine configuration helper is missing or not executable.")
        }

        let profileOrder = Self.profiles.map(\.id)
        let profiles = profileOrder.filter(selectedProfiles.contains)
        let arguments = [
            script.path,
            hostname,
            machineType,
            machineName,
            username,
            appStateEnabled ? "true" : "false",
        ] + profiles

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = arguments
                process.currentDirectoryURL = self.configurationDirectory
                process.standardOutput = output
                process.standardError = output
                var environment = RuntimeEnvironment.process
                environment["NIX_ME_CONFIG_DIR"] = self.configurationDirectory.path
                process.environment = environment

                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        let message = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: ManagementAPIError.commandFailed(
                            process.terminationStatus,
                            message.flatMap { $0.isEmpty ? nil : $0 } ?? "Could not create the machine configuration"
                        ))
                        return
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func verifyInstallation() async throws {
        let snapshot = try await ManagementAPIClient(
            configurationDirectory: configurationDirectory
        ).snapshot()

        guard snapshot.host.hostname == hostname else {
            throw FirstInstallationError.failed(
                "The active configuration is for \(snapshot.host.hostname), not \(hostname)."
            )
        }
        guard snapshot.configuration.applyState == "current" else {
            throw FirstInstallationError.failed(
                "Activation finished, but the applied system does not match the configuration checkout."
            )
        }
        guard snapshot.health.nix.available, snapshot.health.nixDarwin.available else {
            throw FirstInstallationError.failed(
                "Activation finished, but Nix or nix-darwin is not available in the active system."
            )
        }
    }

    private func record(_ progress: ApplyActionProgress) {
        guard progress.phase.order + 1 >= phase.rawValue else { return }
        switch progress.phase {
        case .preparing: phase = .preparation
        case .building: phase = .build
        case .activating: phase = .activation
        case .verifying: phase = .verification
        }
        phaseMessage = progress.message
    }

    private static func detectHostname() -> String {
        let raw = SCDynamicStoreCopyLocalHostName(nil) as String? ?? "my-mac"
        let normalized = raw.lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "my-mac" : normalized
    }

    private static func detectMachineName(fallback: String) -> String {
        var encoding = CFStringEncoding(CFStringBuiltInEncodings.UTF8.rawValue)
        let name = (SCDynamicStoreCopyComputerName(nil, &encoding) as String?)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

    private static func detectMachineType() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "macbook"
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return "macbook"
        }
        let model = String(cString: buffer)
        return machineType(forHardwareModel: model)
    }

    nonisolated static func machineType(forHardwareModel model: String) -> String {
        if model.localizedCaseInsensitiveContains("Virtual") { return "vm" }
        if model.localizedCaseInsensitiveContains("MacBookPro") { return "macbook-pro" }
        if model.localizedCaseInsensitiveContains("Macmini") { return "macmini" }
        return "macbook"
    }

    nonisolated static func suggestedMachineID(
        in machines: [InstallationMachineConfiguration],
        detectedHostname: String
    ) -> String? {
        machines.first(where: { $0.id == detectedHostname })?.id
    }

    nonisolated static func recordSuccessfulInstallation(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let markerPath = environment["NIX_ME_SETUP_COMPLETION_MARKER"],
              !markerPath.isEmpty
        else { return }

        _ = FileManager.default.createFile(
            atPath: markerPath,
            contents: Data(),
            attributes: nil
        )
    }

    nonisolated static func machineConfigurations(
        in configurationDirectory: URL,
        fallbackUsername: String
    ) -> [InstallationMachineConfiguration] {
        let flakeURL = configurationDirectory.appendingPathComponent("flake.nix")
        guard let source = try? String(contentsOf: flakeURL, encoding: .utf8) else { return [] }

        let defaultUsername = firstCapture(
            "(?m)^\\s*defaultUsername\\s*=\\s*\"([^\"]+)\"",
            in: source
        ) ?? fallbackUsername
        let hostPattern = "(?m)^\\s*\"([^\"]+)\"\\s*=\\s*mkDarwinSystem\\s*\\{"
        guard let hostExpression = try? NSRegularExpression(pattern: hostPattern) else { return [] }
        let sourceRange = NSRange(source.startIndex..., in: source)
        let sourceString = source as NSString

        return hostExpression.matches(in: source, range: sourceRange).compactMap { match in
            guard match.numberOfRanges == 2,
                  let idRange = Range(match.range(at: 1), in: source),
                  let block = balancedBlock(
                    in: sourceString,
                    openingBraceLocation: NSMaxRange(match.range) - 1
                  )
            else { return nil }

            let id = String(source[idRange])
            let hostname = firstCapture(
                "(?m)^\\s*hostname\\s*=\\s*\"([^\"]+)\"",
                in: block
            ) ?? id
            let machineName = firstCapture(
                "(?m)^\\s*machineName\\s*=\\s*\"([^\"]+)\"",
                in: block
            ) ?? hostname
            let machineType = firstCapture(
                "(?m)^\\s*machineType\\s*=\\s*\"([^\"]+)\"",
                in: block
            ) ?? "macbook"
            let explicitUsername = firstCapture(
                "(?m)^\\s*username\\s*=\\s*\"([^\"]+)\"",
                in: block
            )
            let usesEnvironmentUsername = block.range(
                of: "(?m)^\\s*username\\s*=\\s*username\\s*;",
                options: .regularExpression
            ) != nil
            let username = explicitUsername
                ?? (usesEnvironmentUsername ? fallbackUsername : defaultUsername)

            return InstallationMachineConfiguration(
                id: id,
                hostname: hostname,
                machineName: machineName,
                username: username,
                machineType: machineType,
                profiles: profileNames(in: block)
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private nonisolated static func firstCapture(_ pattern: String, in source: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: source,
                range: NSRange(source.startIndex..., in: source)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: source)
        else { return nil }
        return String(source[range])
    }

    private nonisolated static func profileNames(in block: String) -> [String] {
        let pattern = "\\./nix/hosts/profiles/([A-Za-z0-9_-]+)\\.nix"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>()
        return expression.matches(
            in: block,
            range: NSRange(block.startIndex..., in: block)
        ).compactMap { match in
            guard let range = Range(match.range(at: 1), in: block) else { return nil }
            let name = String(block[range])
            return seen.insert(name).inserted ? name : nil
        }
    }

    private nonisolated static func balancedBlock(
        in source: NSString,
        openingBraceLocation: Int
    ) -> String? {
        guard openingBraceLocation >= 0, openingBraceLocation < source.length else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var inComment = false

        for location in openingBraceLocation..<source.length {
            let character = source.character(at: location)
            if inComment {
                if character == 10 || character == 13 { inComment = false }
                continue
            }
            if inString {
                if escaped {
                    escaped = false
                } else if character == 92 {
                    escaped = true
                } else if character == 34 {
                    inString = false
                }
                continue
            }
            if character == 35 {
                inComment = true
            } else if character == 34 {
                inString = true
            } else if character == 123 {
                depth += 1
            } else if character == 125 {
                depth -= 1
                if depth == 0 {
                    return source.substring(
                        with: NSRange(
                            location: openingBraceLocation,
                            length: location - openingBraceLocation + 1
                        )
                    )
                }
            }
        }
        return nil
    }

    nonisolated static func errorSummary(_ error: Error) -> String {
        let details: String
        if case let ManagementAPIError.commandFailed(_, message) = error {
            details = message
        } else {
            details = error.localizedDescription
        }

        let lines = details.split(whereSeparator: { $0.isNewline }).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let concreteFailureMarkers = [
            "failed", "fatal:", "permission denied", "operation not permitted", "not found",
        ]
        let summary = lines.reversed().first(where: { line in
            concreteFailureMarkers.contains(where: line.localizedCaseInsensitiveContains)
        }) ?? lines.reversed().first(where: {
            $0.localizedCaseInsensitiveContains("error:")
        }) ?? lines.first ?? "Review the technical details and retry."
        return summary.replacingOccurrences(
            of: "^error:\\s*",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
