import AppKit
import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published var selectedSection: DashboardSection = .overview
    @Published private(set) var snapshot: ManagementSnapshot?
    @Published private(set) var configurationGraph: ConfigurationGraph?
    @Published private(set) var configurationGraphError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isUpdating = false
    @Published private(set) var isApplying = false
    @Published private(set) var isSyncingProjects = false
    @Published private(set) var isConfiguring = false
    @Published private(set) var isLocalAIModelActionRunning = false
    @Published private(set) var localAIModelOperation: LocalAIModelOperation?
    @Published private(set) var updatingItemCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var updateNotice: String?

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

        do {
            let client = try client ?? ManagementAPIClient()
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
        guard let snapshot else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.configuration.path))
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
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: configurationGraph.rootPath).appendingPathComponent(path)
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
        isApplying = true
        updateNotice = nil
        var notice: String

        do {
            let managementClient = try client ?? ManagementAPIClient()
            self.client = managementClient
            let actionClient = ManagementActionClient(configurationDirectory: managementClient.configurationDirectory)
            let response = try await actionClient.apply(
                hostname: snapshot.host.hostname,
                username: snapshot.host.username
            )
            notice = response.success
                ? "Configuration applied successfully."
                : "Apply failed: \(response.message)"
        } catch {
            notice = "Apply failed: \(error.localizedDescription)"
        }

        await refresh()
        isApplying = false
        updateNotice = notice
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
    }
}
