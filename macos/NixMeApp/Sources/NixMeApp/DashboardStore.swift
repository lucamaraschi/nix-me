import AppKit
import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var snapshot: ManagementSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isUpdating = false
    @Published private(set) var updatingItemCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var updateNotice: String?

    private var client: ManagementAPIClient?
    private var monitoringTask: Task<Void, Never>?

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
            snapshot = try await client.snapshot()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func openConfiguration() {
        guard let snapshot else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.configuration.path))
    }

    func openProject(_ project: Project) {
        guard project.present else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: project.absolutePath))
    }

    func updateSoftware(_ updates: [SoftwareUpdate]) async {
        guard !updates.isEmpty, !isUpdating, !isLoading else { return }
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

    func clearUpdateNotice() {
        updateNotice = nil
    }
}
