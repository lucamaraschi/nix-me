import AppKit
import SwiftUI

@main
struct NixMeApp: App {
    private static let launchesFirstInstallation =
        CommandLine.arguments.contains("--first-install")
        || (Bundle.main.object(forInfoDictionaryKey: "NixMeSetupOnly") as? Bool == true)

    @StateObject private var store = DashboardStore()
    @StateObject private var updater = AppUpdater()
    @StateObject private var installationPowerAssertion = InstallationPowerAssertion(
        enabled: Self.launchesFirstInstallation
    )
    @State private var isFirstInstallation = Self.launchesFirstInstallation
    @State private var isMenuBarExtraInserted = !Self.launchesFirstInstallation

    var body: some Scene {
        WindowGroup("Nix Me", id: "dashboard") {
            Group {
                if isFirstInstallation {
                    FirstInstallationView(
                        keepsMacAwake: installationPowerAssertion.isActive,
                        openDashboard: openManagedApplication
                    )
                } else {
                    DashboardView(store: store)
                }
            }
            .frame(
                minWidth: isFirstInstallation ? 1160 : 1040,
                minHeight: isFirstInstallation ? 760 : 680
            )
        }
        .defaultSize(
            width: Self.launchesFirstInstallation ? 1280 : 1180,
            height: Self.launchesFirstInstallation ? 840 : 760
        )
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
            NixMeMenuBarIcon(indicator: menuBarIndicator)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIndicator: MenuBarIndicator {
        let snapshot = store.snapshot
        return MenuBarIndicator.resolve(
            setupNeedsAttention: store.setupStatus?.isReady == false,
            hasError: store.errorMessage != nil || store.applyOperation?.status == .failed,
            isWorking: store.isLoading || store.isUpdating || store.isApplying || store.isSyncingProjects,
            hasCriticalFailure: snapshot?.appState?.lastApply.status == "failed",
            needsAttention: snapshot.map {
                $0.configuration.applyState != "current"
                    || $0.projectAttentionCount > 0
                    || $0.appState?.needsAttention == true
                    || $0.localAI?.needsAttention == true
            } ?? false,
            softwareUpdateCount: snapshot?.softwareUpdateCount ?? 0
        )
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
