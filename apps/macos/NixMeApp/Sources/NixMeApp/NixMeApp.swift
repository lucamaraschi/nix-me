import SwiftUI

@main
struct NixMeApp: App {
    @StateObject private var store = DashboardStore()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        WindowGroup("Nix Me", id: "dashboard") {
            DashboardView(store: store)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)

        MenuBarExtra {
            MenuBarView(store: store, updater: updater)
        } label: {
            if let snapshot = store.snapshot, snapshot.softwareUpdateCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("\(snapshot.softwareUpdateCount)")
                }
            } else if store.errorMessage != nil {
                Label("Nix Me", systemImage: "exclamationmark.triangle.fill")
            } else if let snapshot = store.snapshot,
                      snapshot.configuration.applyState != "current"
                      || snapshot.projectAttentionCount > 0
                      || snapshot.appState?.needsAttention == true
                      || snapshot.localAI?.needsAttention == true {
                Label("Nix Me", systemImage: "exclamationmark.circle.fill")
            } else {
                Label("Nix Me", systemImage: "checkmark.circle")
            }
        }
        .menuBarExtraStyle(.window)

        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
            }
        }
    }
}
