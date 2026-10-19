import AppKit
import Foundation

enum ApplyOperationStatus: Equatable {
    case running
    case succeeded
    case failed
}

struct ApplyOperationState: Equatable {
    var status: ApplyOperationStatus
    var phase: ApplyActionPhase
    var message: String
    var diagnostics: String?
    let startedAt: Date
    var finishedAt: Date?

    var isRunning: Bool { status == .running }
}

@MainActor
final class DashboardStore: ObservableObject {
    @Published var selectedSection: DashboardSection = .overview
    @Published private(set) var snapshot: ManagementSnapshot?
    @Published private(set) var setupStatus: ConfigurationSetupStatus?
    @Published private(set) var configurationGraph: ConfigurationGraph?
    @Published private(set) var configurationGraphError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isUpdating = false
    @Published private(set) var isApplying = false
    @Published private(set) var isSyncingProjects = false
    @Published private(set) var isSavingProject = false
    @Published private(set) var isConfiguring = false
    @Published private(set) var isLocalAIModelActionRunning = false
    @Published private(set) var isCapturingSettings = false
    @Published private(set) var isEnablingHarness = false
    @Published private(set) var applyOperation: ApplyOperationState?
    @Published private(set) var localAIModelOperation: LocalAIModelOperation?
    @Published private(set) var updatingItemCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var updateNotice: String?
    @Published private(set) var updateNoticeDetails: String?
    @Published private(set) var harnessNotice: String?
    @Published private(set) var appSettingsError: String?

    private var client: ManagementAPIClient?
    private var monitoringTask: Task<Void, Never>?
    private var localAIModelMonitoringTask: Task<Void, Never>?
    private var localAIModelMonitoringID: UUID?

    func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let setupStatus = ConfigurationBootstrap.inspect()
        self.setupStatus = setupStatus

        guard setupStatus.isReady, let configurationDirectory = setupStatus.configurationDirectory else {
            client = nil
            snapshot = nil
            configurationGraph = nil
            configurationGraphError = nil
            isLoading = false
            return
        }

        do {
            let client: ManagementAPIClient
            if let existingClient = self.client,
               existingClient.configurationDirectory == configurationDirectory {
                client = existingClient
            } else {
                client = try ManagementAPIClient(configurationDirectory: configurationDirectory)
            }
            self.client = client
            let snapshot = try await client.snapshot()
            self.snapshot = snapshot
            do {
                configurationGraph = try await client.configurationGraph(
                    hostname: snapshot.host.hostname,
                    machineType: snapshot.host.machineType
                )
                configurationGraphError = nil
            } catch {
                configurationGraph = nil
                configurationGraphError = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func openConfiguration() {
        guard let directory = setupStatus?.configurationDirectory else { return }
        NSWorkspace.shared.open(directory)
    }

    func openInstallationGuide() {
        NSWorkspace.shared.open(ConfigurationBootstrap.installationGuideURL)
    }

    func chooseConfigurationDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose nix-me Configuration"
        panel.message = "Select the folder containing flake.nix."
        panel.prompt = "Use Configuration"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await configure(with: directory) }
    }

    func cloneDefaultConfiguration() async {
        guard !isConfiguring else { return }
        isConfiguring = true
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/nixpkgs", isDirectory: true)

        do {
            try await ConfigurationBootstrap.clone(to: destination)
            await configure(with: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
        isConfiguring = false
    }

    func updateConfigurationCheckout() async {
        guard
            !isConfiguring,
            setupStatus?.canUpdateCheckout == true,
            let directory = setupStatus?.configurationDirectory
        else { return }

        isConfiguring = true
        errorMessage = nil
        do {
            try await ConfigurationBootstrap.updateCheckout(at: directory)
            UserDefaults.standard.set(
                directory.path,
                forKey: ManagementAPIClient.configurationDirectoryDefaultsKey
            )
            isConfiguring = false
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            isConfiguring = false
        }
    }

    private func configure(with directory: URL) async {
        let resolved = directory.resolvingSymlinksInPath()
        guard ManagementAPIClient.isConfigurationDirectory(resolved) else {
            errorMessage = ConfigurationBootstrapError.invalidConfiguration(resolved.path).localizedDescription
            return
        }

        do {
            client = try ManagementAPIClient(configurationDirectory: resolved)
            UserDefaults.standard.set(resolved.path, forKey: ManagementAPIClient.configurationDirectoryDefaultsKey)
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openConfigurationFile(_ path: String) {
        guard let configurationGraph else { return }
        NSWorkspace.shared.open(
            URL(fileURLWithPath: configurationGraph.rootPath).appendingPathComponent(path)
        )
    }

    func revealConfigurationFile(_ path: String) {
        guard let configurationGraph else { return }
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileURL = expandedPath.hasPrefix("/")
            ? URL(fileURLWithPath: expandedPath)
            : URL(fileURLWithPath: configurationGraph.rootPath).appendingPathComponent(expandedPath)
        let revealURL = FileManager.default.fileExists(atPath: fileURL.path)
            ? fileURL
            : fileURL.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([
            revealURL
        ])
    }

    func openProject(_ project: Project) {
        guard project.present else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: project.absolutePath))
    }

    func packageDetails(for item: SoftwareListItem) async throws -> PackageDetails {
        let managementClient = try client ?? ManagementAPIClient()
        self.client = managementClient
        return try await managementClient.details(for: item)
    }

    func updateSoftware(_ updates: [SoftwareUpdate]) async {
        guard !updates.isEmpty, !isUpdating, !isApplying, !isLoading else { return }
        isUpdating = true
        updatingItemCount = updates.count
        updateNotice = nil
        var notice: String

        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            let response = try await actionClient.update(updates)
            let succeeded = response.results.filter(\.success).count
            let failed = response.results.count - succeeded
            var message = "Updated \(succeeded) of \(response.results.count) item\(response.results.count == 1 ? "" : "s")."
            if failed > 0 {
                let failedNames = response.results.filter { !$0.success }.map(\.name).joined(separator: ", ")
                message += " Failed: \(failedNames)."
            }
            if response.requiresApply && succeeded > 0 {
                message += " Nix input changes are ready and must still be applied."
            }
            notice = message
        } catch {
            notice = "Update failed: \(error.localizedDescription)"
        }

        await refresh()
        isUpdating = false
        updatingItemCount = 0
        updateNotice = notice
    }

    func applyConfiguration() async {
        guard !isApplying, !isUpdating, !isLoading, let snapshot else { return }
        selectedSection = .configurationChanges
        isApplying = true
        updateNotice = nil
        updateNoticeDetails = nil
        applyOperation = ApplyOperationState(
            status: .running,
            phase: .preparing,
            message: "Checking the host, configuration, and required tools",
            diagnostics: nil,
            startedAt: Date(),
            finishedAt: nil
        )
        var activationSucceeded = false

        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            let response = try await actionClient.apply(
                hostname: snapshot.host.hostname,
                username: snapshot.host.username,
                machineName: snapshot.host.machineName,
                machineType: snapshot.host.machineType,
                sourceRevision: snapshot.configuration.desiredSource?.revision,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.recordApplyProgress(progress)
                    }
                }
            )
            activationSucceeded = response.success
            if response.success {
                recordApplyProgress(ApplyActionProgress(
                    phase: .verifying,
                    message: "Activation finished; checking the running generation"
                ))
            } else {
                finishApplyFailure(details: response.message)
            }
        } catch {
            finishApplyFailure(details: error.localizedDescription)
        }

        await refresh()
        if activationSucceeded {
            switch self.snapshot?.configuration.applyState {
            case "current":
                finishApplySuccess(message: "Configuration applied and verified successfully.")
            case "pending":
                finishApplySuccess(
                    message: "The new generation is active, but the repository still contains unapplied changes."
                )
            default:
                finishApplySuccess(
                    message: "The new generation is active, but Nix Me could not verify its repository state."
                )
            }
        }
        isApplying = false
    }

    func dismissApplyOperation() {
        guard applyOperation?.isRunning == false else { return }
        applyOperation = nil
    }

    func copyApplyDiagnostics() {
        guard let diagnostics = applyOperation?.diagnostics, !diagnostics.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }

    private func recordApplyProgress(_ progress: ApplyActionProgress) {
        guard var operation = applyOperation, operation.isRunning else { return }
        guard progress.phase.order >= operation.phase.order else { return }
        operation.phase = progress.phase
        operation.message = progress.message
        applyOperation = operation
    }

    private func finishApplyFailure(details: String) {
        guard var operation = applyOperation else { return }
        operation.status = .failed
        operation.message = applyFailureSummary(details)
        operation.diagnostics = details
        operation.finishedAt = Date()
        applyOperation = operation
    }

    private func finishApplySuccess(message: String) {
        guard var operation = applyOperation else { return }
        operation.status = .succeeded
        operation.phase = .verifying
        operation.message = message
        operation.finishedAt = Date()
        applyOperation = operation
    }

    func syncProjects() async {
        guard !isSyncingProjects, !isApplying, !isUpdating, !isLoading, let snapshot else { return }
        isSyncingProjects = true
        updateNotice = nil
        var notice: String

        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            let response = try await actionClient.syncProjects(hostname: snapshot.host.hostname)
            notice = response.success ? "Projects synchronized successfully." : "Project sync failed: \(response.message)"
        } catch {
            notice = "Project sync failed: \(error.localizedDescription)"
        }

        await refresh()
        isSyncingProjects = false
        updateNotice = notice
    }

    func previewProject(_ project: ProjectConfigurationInput) async throws -> ProjectConfigurationResponse {
        guard !isSavingProject, let snapshot else {
            throw ManagementAPIError.invalidResponse("Project configuration is busy")
        }
        let managementClient = try client ?? ManagementAPIClient()
        self.client = managementClient
        let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
        return try await actionClient.previewProject(project, hostname: snapshot.host.hostname)
    }

    func saveProject(_ project: ProjectConfigurationInput) async throws -> ProjectConfigurationResponse {
        guard !isSavingProject, !isSyncingProjects, !isApplying, !isLoading, let snapshot else {
            throw ManagementAPIError.invalidResponse("Project configuration is busy")
        }
        isSavingProject = true
        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            let response = try await actionClient.saveProject(project, hostname: snapshot.host.hostname)
            await refresh()
            isSavingProject = false
            updateNotice = response.message
            return response
        } catch {
            isSavingProject = false
            throw error
        }
    }

    func enableHarness() async -> Bool {
        guard !isEnablingHarness, !isApplying, !isLoading, let snapshot else { return false }
        isEnablingHarness = true
        updateNotice = nil
        harnessNotice = nil

        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            let response = try await actionClient.enableHarness(hostname: snapshot.host.hostname)
            await refresh()
            isEnablingHarness = false
            harnessNotice = response.message
            return response.success
        } catch {
            isEnablingHarness = false
            updateNotice = "Could not enable the harness: \(error.localizedDescription)"
            return false
        }
    }

    func previewAppSettings(
        appId: String,
        scope: AppSettingsScope,
        profile: String?,
        confirmReviewedText: Bool
    ) async -> AppSettingsCaptureResponse? {
        guard !isCapturingSettings, let snapshot else { return nil }
        isCapturingSettings = true
        appSettingsError = nil
        defer { isCapturingSettings = false }
        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            return try await actionClient.previewSettings(
                appId: appId,
                scope: scope,
                profile: profile,
                hostname: snapshot.host.hostname,
                confirmReviewedText: confirmReviewedText
            )
        } catch {
            appSettingsError = appSettingsFailureMessage(error)
            return nil
        }
    }

    func saveAppSettings(
        appId: String,
        scope: AppSettingsScope,
        profile: String?,
        confirmReviewedText: Bool
    ) async -> AppSettingsCaptureResponse? {
        guard !isCapturingSettings, let snapshot else { return nil }
        isCapturingSettings = true
        appSettingsError = nil
        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            let response = try await actionClient.saveSettings(
                appId: appId,
                scope: scope,
                profile: profile,
                hostname: snapshot.host.hostname,
                confirmReviewedText: confirmReviewedText
            )
            harnessNotice = response.message
            isCapturingSettings = false
            await refresh()
            return response
        } catch {
            isCapturingSettings = false
            appSettingsError = appSettingsFailureMessage(error)
            return nil
        }
    }

    func clearAppSettingsError() {
        appSettingsError = nil
    }

    private func appSettingsFailureMessage(_ error: Error) -> String {
        if let apiError = error as? ManagementAPIError,
           case let .commandFailed(_, message) = apiError {
            return message
        }
        return error.localizedDescription
    }

    func refreshLocalAIModelOperation() async {
        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            localAIModelOperation = try await actionClient.localAIModelStatus().operation
            if localAIModelOperation?.isRunning == true {
                monitorLocalAIModelOperation()
            }
        } catch {
            updateNotice = "Could not read model operation status: \(error.localizedDescription)"
        }
    }

    func startLocalAIModelDownload() async {
        guard !isLocalAIModelActionRunning, localAIModelOperation?.isRunning != true else { return }
        isLocalAIModelActionRunning = true
        updateNotice = nil
        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            localAIModelOperation = try await actionClient.startLocalAIModel().operation
            if localAIModelOperation?.isRunning == true {
                monitorLocalAIModelOperation()
            } else if let operation = localAIModelOperation {
                updateNotice = operation.message
            }
        } catch {
            updateNotice = "Could not start the model download: \(error.localizedDescription)"
        }
        isLocalAIModelActionRunning = false
    }

    func cancelLocalAIModelDownload() async {
        guard !isLocalAIModelActionRunning, localAIModelOperation?.isRunning == true else { return }
        isLocalAIModelActionRunning = true
        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            localAIModelOperation = try await actionClient.cancelLocalAIModel().operation
            if localAIModelOperation?.isRunning == true {
                updateNotice = "Model download cancellation requested; waiting for the worker to stop."
                monitorLocalAIModelOperation()
            } else {
                stopLocalAIModelMonitoring()
                updateNotice = localAIModelOperation?.message ?? "Model download cancelled."
            }
        } catch {
            updateNotice = "Could not cancel the model download: \(error.localizedDescription)"
        }
        isLocalAIModelActionRunning = false
    }

    private func monitorLocalAIModelOperation() {
        let monitoringID = UUID()
        localAIModelMonitoringTask?.cancel()
        localAIModelMonitoringID = monitoringID
        localAIModelMonitoringTask = Task { [weak self] in
            defer {
                if self?.localAIModelMonitoringID == monitoringID {
                    self?.localAIModelMonitoringTask = nil
                    self?.localAIModelMonitoringID = nil
                }
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self, self.localAIModelMonitoringID == monitoringID else { return }
                do {
                    let managementClient = try self.client ?? ManagementAPIClient()
                    self.client = managementClient
                    let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
                    let operation = try await actionClient.localAIModelStatus().operation
                    guard !Task.isCancelled, self.localAIModelMonitoringID == monitoringID else { return }
                    self.localAIModelOperation = operation
                    if operation?.isRunning != true {
                        if let operation {
                            self.updateNotice = operation.message
                        }
                        await self.refresh()
                        return
                    }
                } catch {
                    self.updateNotice = "Could not monitor the model download: \(error.localizedDescription)"
                    return
                }
            }
        }
    }

    private func stopLocalAIModelMonitoring() {
        localAIModelMonitoringID = nil
        localAIModelMonitoringTask?.cancel()
        localAIModelMonitoringTask = nil
    }

    func clearUpdateNotice() {
        updateNotice = nil
        updateNoticeDetails = nil
    }

    func copyUpdateNoticeDetails() {
        guard let updateNoticeDetails else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(updateNoticeDetails, forType: .string)
    }

    private func applyFailureSummary(_ details: String) -> String {
        if details.contains("Syncing configured projects")
            || details.contains("Fetching updates") {
            return "Apply stopped while synchronizing projects. The system was not activated. "
                + "Review Projects, then retry Apply."
        }

        let ignoredPrefixes = [
            "Apply failed:",
            "nix-me API exited with code",
            "execution error:",
        ]
        let meaningfulLines = details
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !ignoredPrefixes.contains(where: line.hasPrefix)
                    && line.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil
            }
        let summary = meaningfulLines.suffix(3).joined(separator: "\n")
        return summary.isEmpty
            ? "Apply failed during activation. Copy the diagnostic details for more information."
            : "Apply failed during activation:\n\(summary)"
    }
}
