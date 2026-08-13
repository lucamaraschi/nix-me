import AppKit
import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var snapshot: ManagementSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

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
}
