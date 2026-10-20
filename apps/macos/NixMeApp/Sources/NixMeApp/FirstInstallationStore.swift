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
    @Published private(set) var phase: FirstInstallationPhase = .configuration
    @Published private(set) var phaseMessage = ""
    @Published private(set) var isInstalling = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorDetails: String?

    let configurationDirectory: URL
    let setupStatus: ConfigurationSetupStatus

    init(configurationDirectory: URL? = nil) {
        let status = ConfigurationBootstrap.inspect(configurationDirectory: configurationDirectory)
        setupStatus = status
        self.configurationDirectory = status.configurationDirectory ?? status.defaultCloneDestination

        let detectedHostname = Self.detectHostname()
        hostname = detectedHostname
        machineName = Self.detectMachineName(fallback: detectedHostname)
        username = NSUserName()
        machineType = Self.detectMachineType()
    }

    var configurationExists: Bool {
        guard let contents = try? String(
            contentsOf: configurationDirectory.appendingPathComponent("flake.nix"),
            encoding: .utf8
        ) else { return false }
        return contents.contains("\"\(hostname)\" =")
    }

    var validationMessage: String? {
        if hostname.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) == nil {
            return "Hostname must use lowercase letters, numbers, and hyphens."
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
