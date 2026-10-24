import AppKit
import SwiftUI

@main
struct NixMeApp: App {
    private static let launchesFirstInstallation =
        CommandLine.arguments.contains("--first-install")
        || (Bundle.main.object(forInfoDictionaryKey: "NixMeSetupOnly") as? Bool == true)

    @StateObject private var store = DashboardStore()
    @StateObject private var updater = AppUpdater()
    @State private var isFirstInstallation = Self.launchesFirstInstallation
    @State private var isMenuBarExtraInserted = !Self.launchesFirstInstallation

    var body: some Scene {
        WindowGroup("Nix Me", id: "dashboard") {
            Group {
                if isFirstInstallation {
                    FirstInstallationView(openDashboard: openManagedApplication)
                } else {
                    DashboardView(store: store)
                }
            }
            .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                if AppUpdater.canCheckForUpdates {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                }
            }
        }

        MenuBarExtra(isInserted: $isMenuBarExtraInserted) {
            MenuBarView(store: store, updater: updater)
        } label: {
            if let snapshot = store.snapshot, snapshot.softwareUpdateCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("\(snapshot.softwareUpdateCount)")
                }
            } else if store.setupStatus?.isReady == false || store.errorMessage != nil {
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
    }

    private func openManagedApplication() {
        let applications = [
            URL(fileURLWithPath: "/Applications/Nix Me.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Nix Me.app", isDirectory: true),
        ]
        guard let application = applications.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            showDashboardInCurrentApplication()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    NSApplication.shared.terminate(nil)
                } else {
                    showDashboardInCurrentApplication()
                }
            }
        }
    }

    private func showDashboardInCurrentApplication() {
        isFirstInstallation = false
        isMenuBarExtraInserted = true
        Task { await store.refresh() }
    }
}
