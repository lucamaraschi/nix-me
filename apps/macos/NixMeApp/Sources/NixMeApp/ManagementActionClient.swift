import Foundation

struct UpdateActionResponse: Codable {
    let schemaVersion: Int
    let success: Bool
    let requiresApply: Bool
    let results: [UpdateActionResult]
}

struct UpdateActionResult: Codable {
    let name: String
    let kind: String
    let success: Bool
    let message: String
}

struct ApplyActionResponse: Codable {
    let schemaVersion: Int
    let success: Bool
    let message: String
}

enum ApplyActionPhase: String, CaseIterable, Identifiable, Sendable {
    case preparing
    case building
    case activating
    case verifying

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preparing: "Prepare"
        case .building: "Build system"
        case .activating: "Authorize and activate"
        case .verifying: "Verify"
        }
    }

    var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

struct ApplyActionProgress: Equatable, Sendable {
    let phase: ApplyActionPhase
    let message: String
}

struct HarnessEnableResponse: Codable {
    let schemaVersion: Int
    let action: String
    let success: Bool
    let host: String
    let destination: String
    let enabled: Bool
    let changed: Bool
    let written: Bool
    let tracked: Bool
    let requiresApply: Bool
    let message: String
}

enum ProjectConfigurationScope: String, Codable, CaseIterable, Identifiable {
    case shared
    case profile
    case machine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shared: "All machines"
        case .profile: "Profile"
        case .machine: "This machine"
        }
    }
}

struct ProjectConfigurationInput: Encodable, Equatable {
    var name = ""
    var url = ""
    var path = ""
    var branch = ""
    var remote = "origin"
    var clone = true
    var update = true
    var scope = ProjectConfigurationScope.machine
    var profile: String?

    private enum CodingKeys: String, CodingKey {
        case name, url, path, branch, remote, clone, update, scope, profile
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .name)
        try container.encode(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .url)
        try container.encode(path.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .path)
        let normalizedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedBranch.isEmpty {
            try container.encodeNil(forKey: .branch)
        } else {
            try container.encode(normalizedBranch, forKey: .branch)
        }
        try container.encode(remote.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .remote)
        try container.encode(clone, forKey: .clone)
        try container.encode(update, forKey: .update)
        try container.encode(scope, forKey: .scope)
        if scope == .profile, let profile {
            try container.encode(profile, forKey: .profile)
        } else {
            try container.encodeNil(forKey: .profile)
        }
    }
}

struct ProjectConfigurationResponse: Codable {
    let schemaVersion: Int
    let action: String
    let success: Bool
    let name: String
    let scope: ProjectConfigurationScope
    let profile: String?
    let destination: String
    let changed: Bool
    let written: Bool
    let tracked: Bool
    let replaced: Bool
    let requiresSync: Bool
    let project: ProjectConfiguration
    let preview: String
    let message: String
}

struct ProjectConfiguration: Codable {
    let url: String
    let path: String
    let branch: String?
    let remote: String
    let clone: Bool
    let update: Bool
}

enum AppSettingsScope: String, Codable, CaseIterable, Identifiable {
    case shared
    case profile
    case machine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shared: "All machines"
        case .profile: "Profile"
        case .machine: "This machine"
        }
    }
}

struct AppSettingsCaptureResponse: Codable {
    let schemaVersion: Int
    let action: String
    let success: Bool
    let appId: String
    let scope: AppSettingsScope
    let profile: String?
    let destination: String
    let changed: Bool
    let written: Bool
    let tracked: Bool
    let preview: String
    let redaction: AppSettingsRedaction
    let captured: [AppSettingsCaptureEntry]
    let skipped: [AppSettingsSkippedEntry]
    let message: String
}

struct AppSettingsRedaction: Codable {
    let policy: String
    let count: Int
    let items: [AppSettingsRedactionItem]
}

struct AppSettingsRedactionItem: Codable, Identifiable {
    let path: String
    let reason: String
    let action: String

    var id: String { "\(path):\(reason)" }
}

struct AppSettingsCaptureEntry: Codable, Identifiable {
    let kind: String
    let bind: String
    let valueCount: Int

    var id: String { "\(kind):\(bind)" }
}

struct AppSettingsSkippedEntry: Codable, Identifiable {
    let kind: String
    let bind: String?
    let reason: String

    var id: String { "\(kind):\(bind ?? "none"):\(reason)" }
}

struct LocalAIModelActionResponse: Codable {
    let schemaVersion: Int
    let operation: LocalAIModelOperation?
}

struct LocalAIModelOperation: Codable, Equatable {
    let operationId: String
    let status: String
    let phase: String
    let message: String
    let startedAt: String
    let updatedAt: String
    let finishedAt: String?
    let processAlive: Bool?
    let model: LocalAIModelOperationModel
    let progress: LocalAIModelProgress
    let disk: LocalAIModelDisk
    let integrity: LocalAIModelIntegrity

    var isRunning: Bool { status == "running" }
}

struct LocalAIModelOperationModel: Codable, Equatable {
    let name: String
    let path: String
    let downloadTarget: String
}

struct LocalAIModelProgress: Codable, Equatable {
    let bytesDownloaded: Int64
    let expectedBytes: Int64
    let percent: Int
}

struct LocalAIModelDisk: Codable, Equatable {
    let requiredBytes: Int64
    let availableBytes: Int64
}

struct LocalAIModelIntegrity: Codable, Equatable {
    let status: String
    let expectedSha256: String?
    let actualSha256: String?
}

private struct UpdateActionRequest: Codable {
    let items: [SoftwareUpdate]
}

private struct LocalAIModelStartRequest: Codable {
    let expectedSha256: String?
}

private struct AppSettingsCaptureRequest: Codable {
    let appId: String
    let scope: AppSettingsScope
    let profile: String?
    let confirmReviewedText: Bool
}

struct ManagementActionClient {
    let configurationDirectory: URL
    let administratorRunner: URL
    let nixOverride: URL?

    init(
        configurationDirectory: URL,
        administratorRunner: URL = URL(fileURLWithPath: "/usr/bin/osascript"),
        nixOverride: URL? = nil
    ) {
        self.configurationDirectory = configurationDirectory
        self.administratorRunner = administratorRunner
        self.nixOverride = nixOverride
    }

    private var actionExecutable: URL {
        ManagementBackend.executable(
            named: "nix-me-action",
            configurationDirectory: configurationDirectory
        )
    }

    func update(_ items: [SoftwareUpdate]) async throws -> UpdateActionResponse {
        let action = actionExecutable
        let request = try JSONEncoder().encode(UpdateActionRequest(items: items))
        let data = try await run(action: action, command: "update", request: request)

        do {
            let response = try JSONDecoder().decode(UpdateActionResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported action schema version \(response.schemaVersion)")
            }
            return response
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    func apply(
        hostname: String,
        username: String,
        machineName: String = "",
        machineType: String? = nil,
        sourceRevision: String? = nil,
        control: InstallationRunControl? = nil,
        onProgress: @escaping @Sendable (ApplyActionProgress) -> Void = { _ in },
        onEvent: @escaping @Sendable (ApplyActionEvent) -> Void = { _ in }
    ) async throws -> ApplyActionResponse {
        let action = actionExecutable
        onProgress(ApplyActionProgress(
            phase: .preparing,
            message: "Checking the host, configuration, and required tools"
        ))
        onEvent(.command(
            InstallerShell.command(executable: "/bin/bash", arguments: [action.path, "apply"]),
            phase: .preparing
        ))
        if !actionSupportsUserBuildApply(action) {
            return try await applyLegacyConfiguration(
                hostname: hostname,
                username: username,
                machineName: machineName,
                machineType: machineType,
                sourceRevision: sourceRevision,
                control: control,
                onProgress: onProgress,
                onEvent: onEvent
            )
        }
        let streamDecoder = ApplyActionStreamDecoder(
            initialPhase: .preparing,
            onProgress: onProgress,
            onEvent: onEvent
        )
        var applyEnvironment = [
            "NIX_ME_HOSTNAME": hostname,
            "NIX_ME_USERNAME": username,
            "NIX_ME_MACHINE_NAME": machineName,
            "NIX_ME_MACHINE_TYPE": machineType ?? "",
            "NIX_ME_SOURCE_REVISION": sourceRevision ?? ""
        ]
        if let control {
            applyEnvironment["NIX_ME_INSTALL_CONTROL_FILE"] = control.controlFile.path
        }
        let data = try await run(
            action: action,
            command: "apply",
            request: Data(),
            additionalEnvironment: applyEnvironment,
            control: control,
            onStandardErrorLine: { line in streamDecoder.receive(line) }
        )

        do {
            let response = try JSONDecoder().decode(ApplyActionResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported action schema version \(response.schemaVersion)")
            }
            return response
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    private func actionSupportsUserBuildApply(_ action: URL) -> Bool {
        guard let contents = try? String(contentsOf: action, encoding: .utf8) else { return false }
        return contents.contains("NIX_ME_USER_BUILD_APPLY=1")
    }

    private func applyLegacyConfiguration(
        hostname: String,
        username: String,
        machineName: String,
        machineType: String?,
        sourceRevision: String?,
        control: InstallationRunControl?,
        onProgress: @escaping @Sendable (ApplyActionProgress) -> Void,
        onEvent: @escaping @Sendable (ApplyActionEvent) -> Void
    ) async throws -> ApplyActionResponse {
        onProgress(ApplyActionProgress(
            phase: .building,
            message: "Evaluating the configuration and building the new system generation"
        ))
        let system = try await buildLegacySystem(
            hostname: hostname,
            username: username,
            machineName: machineName,
            machineType: machineType,
            sourceRevision: sourceRevision,
            control: control,
            onEvent: onEvent
        )
        if control?.currentState.isPaused == true {
            onProgress(ApplyActionProgress(
                phase: .building,
                message: "Paused before privileged activation"
            ))
            try await control?.waitIfPaused()
        }
        onProgress(ApplyActionProgress(
            phase: .activating,
            message: "Build complete; approve the macOS prompt to activate this generation"
        ))
        return try await activateLegacySystem(
            system,
            username: username,
            control: control,
            onEvent: onEvent
        )
    }

    static func applyProgress(from line: String) -> ApplyActionProgress? {
        let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3,
              fields[0] == "NIX_ME_PROGRESS",
              let phase = ApplyActionPhase(rawValue: String(fields[1]))
        else { return nil }
        return ApplyActionProgress(phase: phase, message: String(fields[2]))
    }

    private func buildLegacySystem(
        hostname: String,
        username: String,
        machineName: String,
        machineType: String?,
        sourceRevision: String?,
        control: InstallationRunControl?,
        onEvent: @escaping @Sendable (ApplyActionEvent) -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let nixCandidates = [nixOverride].compactMap { $0 } + [
            URL(fileURLWithPath: "/run/current-system/sw/bin/nix"),
            URL(fileURLWithPath: "/nix/var/nix/profiles/default/bin/nix"),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".nix-profile/bin/nix"),
        ]
        guard let nix = nixCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else {
            throw ManagementAPIError.invalidResponse("nix is unavailable")
        }
        let allowNonStorePath = nixOverride != nil
        let arguments = [
            "--extra-experimental-features", "nix-command flakes",
            "build", "--json", "--no-link", "--impure", "--log-format", "internal-json",
            "path:\(configurationDirectory.path)#darwinConfigurations.\(hostname).system",
        ]
        let environmentPrefix = [
            "HOSTNAME=\(InstallerShell.quote(hostname))",
            "USERNAME=\(InstallerShell.quote(username))",
            "MACHINE_NAME=\(InstallerShell.quote(machineName))",
            "MACHINE_TYPE=\(InstallerShell.quote(machineType ?? ""))",
            "NIX_ME_SOURCE_REVISION=\(InstallerShell.quote(sourceRevision ?? ""))",
        ].joined(separator: " ")
        onEvent(.command(
            "env \(environmentPrefix) \(InstallerShell.command(executable: nix.path, arguments: arguments))",
            phase: .building
        ))

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()

                do {
                    process.executableURL = nix
                    process.arguments = arguments
                    process.currentDirectoryURL = configurationDirectory
                    process.standardOutput = output
                    process.standardError = errors
                    var environment = RuntimeEnvironment.process
                    environment["HOSTNAME"] = hostname
                    environment["USERNAME"] = username
                    environment["MACHINE_NAME"] = machineName
                    environment["MACHINE_TYPE"] = machineType ?? ""
                    environment["NIX_ME_SOURCE_REVISION"] = sourceRevision ?? ""
                    process.environment = environment

                    try process.run()
                    try control?.register(process)
                    let streamDecoder = ApplyActionStreamDecoder(
                        initialPhase: .building,
                        onProgress: { _ in },
                        onEvent: onEvent
                    )
                    let errorCollector = ActionErrorCollector { line in
                        streamDecoder.receive(line)
                    }
                    let errorDrain = DispatchGroup()
                    errorDrain.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        while true {
                            let data = errors.fileHandleForReading.availableData
                            guard !data.isEmpty else { break }
                            errorCollector.append(data)
                        }
                        errorCollector.finish()
                        errorDrain.leave()
                    }
                    let outputData = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    control?.unregister(process)
                    errorDrain.wait()
                    let errorData = errorCollector.data
                    if control?.currentState == .stopping || control?.currentState == .stopped {
                        continuation.resume(throwing: InstallationControlError.stopped)
                        return
                    }
                    guard process.terminationStatus == 0 else {
                        let message = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let buildMessage = message.flatMap { $0.isEmpty ? nil : $0 }
                        continuation.resume(
                            throwing: ManagementAPIError.commandFailed(
                                process.terminationStatus,
                                buildMessage ?? "Configuration build failed"
                            )
                        )
                        return
                    }

                    guard
                        let payload = try JSONSerialization.jsonObject(with: outputData)
                            as? [[String: Any]],
                        let outputs = payload.first?["outputs"] as? [String: Any],
                        let outPath = outputs["out"] as? String
                    else {
                        continuation.resume(
                            throwing: ManagementAPIError.invalidResponse(
                                "Nix did not return the built system path"
                            )
                        )
                        return
                    }
                    let system = URL(fileURLWithPath: outPath).standardizedFileURL
                    let rebuild = system.appendingPathComponent("sw/bin/darwin-rebuild")
                    guard
                        (allowNonStorePath || system.path.hasPrefix("/nix/store/")),
                        FileManager.default.isExecutableFile(atPath: rebuild.path)
                    else {
                        continuation.resume(
                            throwing: ManagementAPIError.invalidResponse(
                                "Nix returned an invalid system path"
                            )
                        )
                        return
                    }
                    continuation.resume(returning: system)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func activateLegacySystem(
        _ system: URL,
        username: String,
        control: InstallationRunControl?,
        onEvent: @escaping @Sendable (ApplyActionEvent) -> Void
    ) async throws -> ApplyActionResponse {
        let script = [
            "on run argv",
            "set systemPath to item 1 of argv",
            "set userName to item 2 of argv",
            "set rebuildPath to systemPath & \"/sw/bin/darwin-rebuild\"",
            ##"set commandText to "env HOME=/var/root USER=root LOGNAME=root PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin nix-env -p /nix/var/nix/profiles/system --set " & quoted form of systemPath & " && env HOME=/var/root USER=root LOGNAME=root PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin SUDO_USER=" & quoted form of userName & " USERNAME=" & quoted form of userName & " " & quoted form of rebuildPath & " activate""##,
            "with timeout of 86400 seconds",
            "do shell script commandText with administrator privileges",
            "end timeout",
            "end run",
        ]
        let activationCommand = "env HOME=/var/root USER=root LOGNAME=root nix-env -p /nix/var/nix/profiles/system --set \(InstallerShell.quote(system.path)) && env HOME=/var/root USER=root LOGNAME=root SUDO_USER=\(InstallerShell.quote(username)) USERNAME=\(InstallerShell.quote(username)) \(InstallerShell.quote(system.appendingPathComponent("sw/bin/darwin-rebuild").path)) activate"
        onEvent(.command(activationCommand, phase: .activating))

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = administratorRunner
                process.arguments = script.flatMap { ["-e", $0] } + [
                    "--",
                    system.path,
                    username,
                ]
                process.standardOutput = output
                process.standardError = output

                do {
                    try process.run()
                    try control?.register(process)
                    let outputData = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    control?.unregister(process)
                    if control?.currentState == .stopping || control?.currentState == .stopped {
                        continuation.resume(throwing: InstallationControlError.stopped)
                        return
                    }
                    let message = String(data: outputData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let outputMessage = message.flatMap { $0.isEmpty ? nil : $0 }
                    outputMessage?.split(separator: "\n", omittingEmptySubsequences: false).forEach { line in
                        let value = String(line)
                        onEvent(.output(value, phase: .activating))
                        if let package = ApplyActionEventParser.package(from: value) {
                            onEvent(.package(package, phase: .activating))
                        }
                    }
                    guard process.terminationStatus == 0 else {
                        continuation.resume(
                            throwing: ManagementAPIError.commandFailed(
                                process.terminationStatus,
                                outputMessage ?? "Configuration apply failed"
                            )
                        )
                        return
                    }
                    continuation.resume(
                        returning: ApplyActionResponse(
                            schemaVersion: 1,
                            success: true,
                            message: outputMessage ?? "Configuration applied successfully"
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func syncProjects(hostname: String) async throws -> ApplyActionResponse {
        let action = actionExecutable
        let data = try await run(
            action: action,
            command: "sync-projects",
            request: Data(),
            additionalEnvironment: ["NIX_ME_HOSTNAME": hostname]
        )

        do {
            return try JSONDecoder().decode(ApplyActionResponse.self, from: data)
        } catch {
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    func previewProject(
        _ project: ProjectConfigurationInput,
        hostname: String
    ) async throws -> ProjectConfigurationResponse {
        try await runProject(command: "project-preview", project: project, hostname: hostname)
    }

    func saveProject(
        _ project: ProjectConfigurationInput,
        hostname: String
    ) async throws -> ProjectConfigurationResponse {
        try await runProject(command: "project-save", project: project, hostname: hostname)
    }

    private func runProject(
        command: String,
        project: ProjectConfigurationInput,
        hostname: String
    ) async throws -> ProjectConfigurationResponse {
        let action = actionExecutable
        let request = try JSONEncoder().encode(project)
        let data = try await run(
            action: action,
            command: command,
            request: request,
            additionalEnvironment: ["NIX_ME_HOSTNAME": hostname]
        )
        do {
            let response = try JSONDecoder().decode(ProjectConfigurationResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported project action schema version \(response.schemaVersion)")
            }
            return response
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    func enableHarness(hostname: String) async throws -> HarnessEnableResponse {
        let action = actionExecutable
        let data = try await run(
            action: action,
            command: "harness-enable",
            request: Data(),
            additionalEnvironment: ["NIX_ME_HOSTNAME": hostname]
        )
        do {
            let response = try JSONDecoder().decode(HarnessEnableResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported harness action schema version \(response.schemaVersion)")
            }
            return response
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    func previewSettings(
        appId: String,
        scope: AppSettingsScope,
        profile: String?,
        hostname: String,
        confirmReviewedText: Bool
    ) async throws -> AppSettingsCaptureResponse {
        try await runSettings(
            command: "settings-preview",
            appId: appId,
            scope: scope,
            profile: profile,
            hostname: hostname,
            confirmReviewedText: confirmReviewedText
        )
    }

    func saveSettings(
        appId: String,
        scope: AppSettingsScope,
        profile: String?,
        hostname: String,
        confirmReviewedText: Bool
    ) async throws -> AppSettingsCaptureResponse {
        try await runSettings(
            command: "settings-save",
            appId: appId,
            scope: scope,
            profile: profile,
            hostname: hostname,
            confirmReviewedText: confirmReviewedText
        )
    }

    private func runSettings(
        command: String,
        appId: String,
        scope: AppSettingsScope,
        profile: String?,
        hostname: String,
        confirmReviewedText: Bool
    ) async throws -> AppSettingsCaptureResponse {
        let action = actionExecutable
        let request = try JSONEncoder().encode(
            AppSettingsCaptureRequest(
                appId: appId,
                scope: scope,
                profile: scope == .profile ? profile : nil,
                confirmReviewedText: confirmReviewedText
            )
        )
        let data = try await run(
            action: action,
            command: command,
            request: request,
            additionalEnvironment: ["NIX_ME_HOSTNAME": hostname]
        )
        do {
            let response = try JSONDecoder().decode(AppSettingsCaptureResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported settings action schema version \(response.schemaVersion)")
            }
            return response
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    func startLocalAIModel(expectedSha256: String? = nil) async throws -> LocalAIModelActionResponse {
        let request = try JSONEncoder().encode(LocalAIModelStartRequest(expectedSha256: expectedSha256))
        return try await runLocalAIModel(command: "local-ai-model-start", request: request)
    }

    func localAIModelStatus() async throws -> LocalAIModelActionResponse {
        try await runLocalAIModel(command: "local-ai-model-status", request: Data())
    }

    func cancelLocalAIModel() async throws -> LocalAIModelActionResponse {
        try await runLocalAIModel(command: "local-ai-model-cancel", request: Data())
    }

    private func runLocalAIModel(command: String, request: Data) async throws -> LocalAIModelActionResponse {
        let action = actionExecutable
        let data = try await run(action: action, command: command, request: request)
        do {
            let response = try JSONDecoder().decode(LocalAIModelActionResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported local-AI action schema version \(response.schemaVersion)")
            }
            return response
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    private func run(
        action: URL,
        command: String,
        request: Data,
        additionalEnvironment: [String: String] = [:],
        control: InstallationRunControl? = nil,
        onStandardErrorLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let input = Pipe()
                let output = Pipe()
                let errors = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [action.path, command]
                process.currentDirectoryURL = configurationDirectory
                process.standardInput = input
                process.standardOutput = output
                process.standardError = errors

                var environment = RuntimeEnvironment.process
                environment["NIX_ME_CONFIG_DIR"] = configurationDirectory.path
                if let engine = ManagementBackend.bundledExecutable(named: "nix-me-apps") {
                    environment["NIX_ME_APP_STATE_ENGINE"] = engine.path
                }
                environment.merge(additionalEnvironment) { _, new in new }
                process.environment = environment

                do {
                    try process.run()
                    try control?.register(process)
                    input.fileHandleForWriting.write(request)
                    try input.fileHandleForWriting.close()
                    let errorCollector = ActionErrorCollector(onLine: onStandardErrorLine)
                    let errorDrain = DispatchGroup()
                    errorDrain.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        while true {
                            // Read whatever is currently available so progress markers are
                            // delivered immediately instead of waiting for a full buffer or EOF.
                            let data = errors.fileHandleForReading.availableData
                            guard !data.isEmpty else { break }
                            errorCollector.append(data)
                        }
                        errorCollector.finish()
                        errorDrain.leave()
                    }
                    let outputData = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    control?.unregister(process)
                    errorDrain.wait()
                    let errorData = errorCollector.data

                    if control?.currentState == .stopping || control?.currentState == .stopped {
                        continuation.resume(throwing: InstallationControlError.stopped)
                        return
                    }

                    guard process.terminationStatus == 0 else {
                        let stderrMessage = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let structuredMessage = (try? JSONSerialization.jsonObject(with: outputData))
                            .flatMap { $0 as? [String: Any] }?["error"] as? [String: Any]
                        let message = structuredMessage?["message"] as? String
                            ?? (stderrMessage?.isEmpty == false ? stderrMessage : nil)
                            ?? "Unknown action error"
                        continuation.resume(throwing: ManagementAPIError.commandFailed(process.terminationStatus, message))
                        return
                    }
                    continuation.resume(returning: outputData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class ApplyActionStreamDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private let onProgress: @Sendable (ApplyActionProgress) -> Void
    private let onEvent: @Sendable (ApplyActionEvent) -> Void
    private var phase: ApplyActionPhase
    private var nixActivities: [UInt64: ApplyPackageProgress] = [:]
    private var activePackages: [ApplyPackageManager: ApplyPackageProgress] = [:]

    init(
        initialPhase: ApplyActionPhase,
        onProgress: @escaping @Sendable (ApplyActionProgress) -> Void,
        onEvent: @escaping @Sendable (ApplyActionEvent) -> Void
    ) {
        phase = initialPhase
        self.onProgress = onProgress
        self.onEvent = onEvent
    }

    func receive(_ line: String) {
        if let progress = ManagementActionClient.applyProgress(from: line) {
            lock.lock()
            phase = progress.phase
            lock.unlock()
            onProgress(progress)
            return
        }
        if let command = ApplyActionEventParser.command(from: line) {
            onEvent(command)
            return
        }

        lock.lock()
        let currentPhase = phase
        lock.unlock()
        onEvent(.output(line, phase: currentPhase))

        let nixEvents = nixPackageEvents(from: line)
        if !nixEvents.isEmpty {
            nixEvents.forEach { onEvent(.package($0, phase: currentPhase)) }
            return
        }
        if let parsedPackage = ApplyActionEventParser.package(from: line) {
            lock.lock()
            let package: ApplyPackageProgress
            if parsedPackage.manager == .homebrew,
               parsedPackage.state == .complete,
               let active = activePackages[.homebrew]
            {
                package = ApplyPackageProgress(
                    manager: .homebrew,
                    name: active.name,
                    state: .complete,
                    detail: parsedPackage.detail,
                    fractionCompleted: 1
                )
            } else {
                package = parsedPackage
            }
            if package.state == .complete || package.state == .failed {
                activePackages.removeValue(forKey: package.manager)
            } else {
                activePackages[package.manager] = package
            }
            lock.unlock()
            onEvent(.package(package, phase: currentPhase))
            return
        }
        if let package = packagePercentageEvent(from: line) {
            onEvent(.package(package, phase: currentPhase))
        }
    }

    private func nixPackageEvents(from line: String) -> [ApplyPackageProgress] {
        guard line.hasPrefix("@nix "),
              let data = String(line.dropFirst(5)).data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = payload["action"] as? String
        else { return [] }

        if action == "msg", let message = payload["msg"] as? String {
            return message.split(separator: "\n").compactMap {
                ApplyActionEventParser.package(from: String($0))
            }
        }

        guard let id = (payload["id"] as? NSNumber)?.uint64Value else { return [] }

        lock.lock()
        defer { lock.unlock() }

        switch action {
        case "start":
            guard let text = payload["text"] as? String,
                  let package = ApplyActionEventParser.package(from: text)
            else { return [] }
            nixActivities[id] = package
            activePackages[.nix] = package
            return [package]
        case "result":
            guard let package = nixActivities[id],
                  (payload["type"] as? NSNumber)?.intValue == 105,
                  let fields = payload["fields"] as? [Any],
                  fields.count >= 2,
                  let completed = fields[0] as? NSNumber,
                  let expected = fields[1] as? NSNumber,
                  expected.doubleValue > 0
            else { return [] }
            let updated = ApplyPackageProgress(
                manager: package.manager,
                name: package.name,
                state: package.state,
                detail: package.detail,
                fractionCompleted: completed.doubleValue / expected.doubleValue
            )
            nixActivities[id] = updated
            activePackages[.nix] = updated
            return [updated]
        case "stop":
            guard let package = nixActivities.removeValue(forKey: id) else { return [] }
            let completed = ApplyPackageProgress(
                manager: package.manager,
                name: package.name,
                state: .complete,
                detail: package.detail,
                fractionCompleted: 1
            )
            if activePackages[.nix]?.id == package.id {
                activePackages.removeValue(forKey: .nix)
            }
            return [completed]
        default:
            return []
        }
    }

    private func packagePercentageEvent(from line: String) -> ApplyPackageProgress? {
        guard let match = line.range(
            of: #"(?<![0-9])[0-9]{1,3}(?:\.[0-9]+)?%"#,
            options: .regularExpression
        ), let percent = Double(line[match].dropLast()) else { return nil }

        lock.lock()
        defer { lock.unlock() }
        guard let package = activePackages[.homebrew] ?? activePackages[.nix] else { return nil }
        let updated = ApplyPackageProgress(
            manager: package.manager,
            name: package.name,
            state: package.state,
            detail: line,
            fractionCompleted: percent / 100
        )
        activePackages[package.manager] = updated
        return updated
    }
}

private final class ActionErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let onLine: (@Sendable (String) -> Void)?
    private var collected = Data()
    private var pending = Data()

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    func append(_ chunk: Data) {
        var lines: [String] = []
        lock.lock()
        collected.append(chunk)
        pending.append(chunk)
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[..<newline]
            pending.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func finish() {
        lock.lock()
        let finalLine = pending.isEmpty ? nil : String(data: pending, encoding: .utf8)
        pending.removeAll()
        lock.unlock()
        if let finalLine { onLine?(finalLine) }
    }
}
