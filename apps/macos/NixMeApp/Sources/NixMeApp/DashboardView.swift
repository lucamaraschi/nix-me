import AppKit
import SwiftUI

enum DashboardSection: String, Identifiable {
    case overview = "Overview"
    case configuration = "Config Map"
    case harness = "App Settings"
    case localAI = "Local AI"
    case software = "Apps & Packages"
    case configurationChanges = "Changes"
    case projects = "Projects"
    case updates = "Updates"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .configuration: "point.3.connected.trianglepath.dotted"
        case .harness: "checklist.checked"
        case .localAI: "cpu"
        case .software: "square.stack.3d.up"
        case .configurationChanges: "arrow.left.arrow.right"
        case .projects: "folder"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @State private var projectFilter = ProjectFilter.all
    @State private var selectedUpdateIDs = Set<String>()
    @State private var showingApplyConfirmation = false
    @State private var softwareScope = SoftwareScope.all

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedSection) {
                if store.snapshot == nil {
                    SidebarRow(
                        section: .overview,
                        title: "Get Started",
                        symbol: "wrench.and.screwdriver",
                        needsAttention: true
                    )
                } else {
                    SidebarRow(section: .overview)

                    Section {
                        SidebarRow(section: .software, count: store.snapshot?.softwareItems.count)
                        SidebarRow(
                            section: .configurationChanges,
                            count: store.snapshot?.softwareDifferences.count,
                            needsAttention: store.snapshot.map { $0.configuration.applyState != "current" } ?? false
                        )
                        SidebarRow(section: .updates, count: store.snapshot?.softwareUpdateCount)
                    } header: {
                        Text("SOFTWARE").oxideLabel()
                    }

                    Section {
                        SidebarRow(section: .projects, count: store.snapshot?.projectAttentionCount)
                        SidebarRow(
                            section: .harness,
                            count: store.snapshot?.appState?.differenceCount,
                            needsAttention: store.snapshot?.appState?.needsAttention ?? false
                        )
                        SidebarRow(
                            section: .localAI,
                            count: store.snapshot?.localAI?.remediation.count,
                            needsAttention: store.snapshot?.localAI?.needsAttention ?? false
                        )
                    } header: {
                        Text("WORKSPACE").oxideLabel()
                    }

                    Section {
                        SidebarRow(section: .configuration, count: store.configurationGraph?.activeNodes.count)
                    } header: {
                        Text("ADVANCED").oxideLabel()
                    }
                }
            }
            .navigationTitle("Nix Me")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .scrollContentBackground(.hidden)
            .background(OxidePalette.sidebar)
        } detail: {
            ZStack {
                OxideGridBackground()
                Group {
                    if let setupStatus = store.setupStatus, store.snapshot == nil {
                        ConfigurationSetupView(
                            status: setupStatus,
                            errorMessage: store.errorMessage,
                            isConfiguring: store.isConfiguring,
                            chooseConfiguration: store.chooseConfigurationDirectory,
                            cloneConfiguration: {
                                Task { await store.cloneDefaultConfiguration() }
                            },
                            updateConfiguration: {
                                Task { await store.updateConfigurationCheckout() }
                            },
                            openConfiguration: store.openConfiguration,
                            openInstallationGuide: store.openInstallationGuide,
                            recheck: {
                                Task { await store.refresh() }
                            }
                        )
                    } else if let snapshot = store.snapshot {
                        content(for: store.selectedSection, snapshot: snapshot)
                    } else {
                        ProgressView("Reading this Mac…")
                            .controlSize(.large)
                            .foregroundStyle(OxidePalette.secondary)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if store.snapshot != nil {
                        Menu {
                            Button("Open Configuration", systemImage: "folder") {
                                store.openConfiguration()
                            }
                            Button("Choose Configuration…", systemImage: "folder.badge.plus") {
                                store.chooseConfigurationDirectory()
                            }
                            if store.setupStatus?.canUpdateCheckout == true {
                                Divider()
                                Button("Update Configuration", systemImage: "arrow.down.circle") {
                                    Task { await store.updateConfigurationCheckout() }
                                }
                            }
                        } label: {
                            Label("Configuration", systemImage: "folder")
                        }
                        .help("Open, switch, or update the configuration checkout")
                        .disabled(store.isConfiguring)

                        if store.snapshot?.configuration.applyState != "current",
                           store.selectedSection != .overview,
                           store.selectedSection != .configurationChanges,
                           store.selectedSection != .harness,
                           store.selectedSection != .localAI {
                            Button("Apply", systemImage: "checkmark.circle") {
                                showingApplyConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(actionInProgress)
                        }

                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await store.refresh() }
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(actionInProgress)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(OxidePalette.green)
        .accentColor(OxidePalette.green)
        .toolbarBackground(OxidePalette.sidebar, for: .windowToolbar)
        .task { store.startMonitoring() }
        .alert(
            "Nix Me",
            isPresented: Binding(
                get: { store.updateNotice != nil },
                set: { if !$0 { store.clearUpdateNotice() } }
            )
        ) {
            if store.updateNoticeDetails != nil {
                Button("Copy Details") { store.copyUpdateNoticeDetails() }
            }
            Button("OK") { store.clearUpdateNotice() }
        } message: {
            Text(store.updateNotice ?? "")
        }
        .confirmationDialog(
            "Apply this configuration?",
            isPresented: $showingApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply Configuration") {
                store.selectedSection = .configurationChanges
                Task { await store.applyConfiguration() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Nix will build and activate the current configuration. macOS will request administrator approval. Software update checks will be skipped.")
        }
    }

    private var actionInProgress: Bool {
        store.isLoading || store.isUpdating || store.isApplying || store.isSyncingProjects
            || store.isSavingProject || store.isConfiguring || store.isCapturingSettings || store.isEnablingHarness
    }

    @ViewBuilder
    private func content(for section: DashboardSection, snapshot: ManagementSnapshot) -> some View {
        switch section {
        case .overview:
            OverviewView(
                snapshot: snapshot,
                openSoftware: { scope in
                    softwareScope = scope
                    store.selectedSection = .software
                },
                openUpdates: {
                    store.selectedSection = .updates
                },
                openProjects: {
                    projectFilter = snapshot.projectAttentionCount > 0 ? .attention : .all
                    store.selectedSection = .projects
                },
                openConfigurationChanges: {
                    store.selectedSection = .configurationChanges
                },
                applyConfiguration: { showingApplyConfirmation = true },
                isApplying: store.isApplying
            )
        case .configuration:
            ConfigurationView(
                graph: store.configurationGraph,
                error: store.configurationGraphError,
                host: snapshot.host,
                openFile: store.openConfigurationFile,
                revealFile: store.revealConfigurationFile
            )
        case .harness:
            HarnessStatusView(
                status: snapshot.appState,
                settings: snapshot.appStateSettings,
                hostname: snapshot.host.hostname,
                configurationApplyState: snapshot.configuration.applyState,
                isCapturing: store.isCapturingSettings,
                isEnabling: store.isEnablingHarness,
                isApplying: store.isApplying,
                harnessNotice: store.harnessNotice,
                appSettingsError: store.appSettingsError,
                previewSettings: store.previewAppSettings,
                saveSettings: store.saveAppSettings,
                clearSettingsError: store.clearAppSettingsError,
                enableHarness: store.enableHarness,
                applyConfiguration: { showingApplyConfirmation = true },
                revealFile: store.revealConfigurationFile
            )
        case .localAI:
            LocalAIStatusView(
                status: snapshot.localAI,
                operation: store.localAIModelOperation,
                isActionRunning: store.isLocalAIModelActionRunning,
                startDownload: { Task { await store.startLocalAIModelDownload() } },
                cancelDownload: { Task { await store.cancelLocalAIModelDownload() } },
                refreshOperation: { Task { await store.refreshLocalAIModelOperation() } }
            )
        case .software:
            SoftwareView(snapshot: snapshot, scope: $softwareScope, loadDetails: store.packageDetails)
        case .configurationChanges:
            ConfigurationChangesView(
                snapshot: snapshot,
                isApplying: store.isApplying,
                applyOperation: store.applyOperation,
                loadDetails: store.packageDetails,
                applyConfiguration: { showingApplyConfirmation = true },
                retryApply: { Task { await store.applyConfiguration() } },
                dismissApplyOperation: store.dismissApplyOperation,
                copyApplyDiagnostics: store.copyApplyDiagnostics
            )
        case .projects:
            ProjectsView(
                snapshot: snapshot,
                filter: $projectFilter,
                isSyncing: store.isSyncingProjects,
                isSavingProject: store.isSavingProject,
                activeProfiles: store.configurationGraph?.activeProfiles.map(\.displayName) ?? [],
                openProject: store.openProject,
                syncProjects: { Task { await store.syncProjects() } },
                previewProject: store.previewProject,
                saveProject: store.saveProject
            )
        case .updates:
            UpdatesView(
                snapshot: snapshot,
                selectedUpdateIDs: $selectedUpdateIDs,
                isUpdating: store.isUpdating,
                isApplying: store.isApplying,
                isRefreshing: store.isLoading,
                updatingItemCount: store.updatingItemCount,
                loadDetails: store.packageDetails,
                updateItems: { updates in
                    Task { await store.updateSoftware(updates) }
                }
            )
        }
    }
}

private struct ConfigurationSetupView: View {
    let status: ConfigurationSetupStatus
    let errorMessage: String?
    let isConfiguring: Bool
    let chooseConfiguration: () -> Void
    let cloneConfiguration: () -> Void
    let updateConfiguration: () -> Void
    let openConfiguration: () -> Void
    let openInstallationGuide: () -> Void
    let recheck: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(status.isReady ? .green.opacity(0.12) : .orange.opacity(0.12))
                        Image(systemName: status.isReady ? "checkmark.seal.fill" : "wrench.and.screwdriver.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(status.isReady ? .green : .orange)
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(setupTitle)
                            .font(.title2.weight(.semibold))
                        Text(setupSummary)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Recheck", systemImage: "arrow.clockwise", action: recheck)
                        .disabled(isConfiguring)
                }

                GroupBox("Configuration checkout") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: checkoutSymbol)
                                .font(.title3)
                                .foregroundStyle(checkoutColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(checkoutTitle)
                                    .font(.headline)
                                Text(status.checkoutMessage)
                                    .foregroundStyle(.secondary)
                                if let directory = status.configurationDirectory {
                                    Text(directory.path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            if status.canUpdateCheckout {
                                Button("Update Checkout", systemImage: "arrow.down.circle", action: updateConfiguration)
                                    .buttonStyle(.borderedProminent)
                            }
                            Button(chooseFolderLabel, systemImage: "folder", action: chooseConfiguration)
                                .buttonStyle(.bordered)
                            if status.checkoutState == .missing, status.canCloneToDefaultDestination {
                                Button("Clone from GitHub", systemImage: "arrow.down.circle", action: cloneConfiguration)
                                    .buttonStyle(.borderedProminent)
                            }
                            if status.configurationDirectory != nil {
                                Button("Open Folder", systemImage: "arrow.up.forward.app", action: openConfiguration)
                                    .buttonStyle(.bordered)
                            }
                        }
                        .disabled(isConfiguring)

                        if isConfiguring {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(status.checkoutState == .invalid ? "Updating checkout…" : "Cloning configuration…")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("System requirements") {
                    VStack(alignment: .leading, spacing: 12) {
                        if status.missingRequiredDependencies.isEmpty {
                            Label("All required commands are available", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("Optional integrations only affect the features that use them.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(status.missingRequiredDependencies.enumerated()), id: \.element.id) { index, dependency in
                                DependencyStatusRow(dependency: dependency)
                                if index < status.missingRequiredDependencies.count - 1 {
                                    Divider().padding(.leading, 36)
                                }
                            }
                        }

                        DisclosureGroup("Show detected commands") {
                            VStack(spacing: 0) {
                                ForEach(Array(status.dependencies.enumerated()), id: \.element.id) { index, dependency in
                                    DependencyStatusRow(dependency: dependency)
                                    if index < status.dependencies.count - 1 {
                                        Divider().padding(.leading, 36)
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Text("Nix Me never installs system dependencies without your confirmation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Installation Guide", systemImage: "book", action: openInstallationGuide)
                }
            }
            .frame(maxWidth: 760)
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setupSummary: String {
        switch status.checkoutState {
        case .ready:
            return status.missingOptionalDependencies.isEmpty
                ? "The configuration and all supported command integrations are available."
                : "Core management is ready. Optional integrations can be enabled below."
        case .missing:
            return "Connect your nix-me configuration to start managing this Mac."
        case .invalid:
            return status.canUpdateCheckout
                ? "The app is newer than the connected checkout. Update it, or choose a different nix-me folder."
                : "The connected folder is not a complete nix-me checkout. Choose a different folder to continue."
        }
    }

    private var setupTitle: String {
        switch status.checkoutState {
        case .ready: "Nix Me is ready"
        case .missing: "Connect Nix Me"
        case .invalid:
            status.canUpdateCheckout ? "Update your Nix Me checkout" : "Choose a valid Nix Me checkout"
        }
    }

    private var chooseFolderLabel: String {
        status.checkoutState == .invalid ? "Use Another Folder" : "Choose Existing Folder"
    }

    private var checkoutTitle: String {
        switch status.checkoutState {
        case .ready: "Configuration found"
        case .missing: "Configuration not found"
        case .invalid: status.canUpdateCheckout ? "Checkout is out of date" : "Checkout is incomplete"
        }
    }

    private var checkoutSymbol: String {
        switch status.checkoutState {
        case .ready: "checkmark.circle.fill"
        case .missing: "folder.badge.questionmark"
        case .invalid: "exclamationmark.triangle.fill"
        }
    }

    private var checkoutColor: Color {
        status.checkoutState == .ready ? .green : .orange
    }
}

private struct DependencyStatusRow: View {
    let dependency: CommandDependency

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: dependency.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(dependency.isAvailable ? .green : dependency.isRequired ? .orange : .secondary)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(dependency.displayName)
                        .font(.headline)
                    Text(dependency.isRequired ? "Required" : "Optional")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(dependency.isRequired ? .primary : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(dependency.purpose)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let executableURL = dependency.executableURL {
                    Text(executableURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                } else {
                    Text(dependency.remediation)
                        .font(.caption)
                        .foregroundStyle(dependency.isRequired ? .orange : .secondary)
                }
            }
            Spacer()
            Text(dependency.isAvailable ? "Available" : "Missing")
                .font(.caption.weight(.medium))
                .foregroundStyle(dependency.isAvailable ? .green : dependency.isRequired ? .orange : .secondary)
        }
        .padding(.vertical, 10)
    }
}

private struct SidebarRow: View {
    let section: DashboardSection
    var title: String? = nil
    var symbol: String? = nil
    var count: Int? = nil
    var needsAttention = false

    var body: some View {
        HStack {
            Label(title ?? section.rawValue, systemImage: symbol ?? section.symbol)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(OxidePalette.primary)
            Spacer()
            if let count, count > 0 {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(OxidePalette.panelRaised)
                    .overlay(Rectangle().stroke(OxidePalette.border))
            } else if needsAttention {
                Circle()
                    .fill(OxidePalette.amber)
                    .frame(width: 7, height: 7)
            }
        }
        .tag(section)
    }
}

private struct OverviewView: View {
    let snapshot: ManagementSnapshot
    let openSoftware: (SoftwareScope) -> Void
    let openUpdates: () -> Void
    let openProjects: () -> Void
    let openConfigurationChanges: () -> Void
    let applyConfiguration: () -> Void
    let isApplying: Bool
    @State private var showingConfigurationDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SYSTEM // \(snapshot.host.hostname.uppercased())")
                            .oxideLabel(color: OxidePalette.green)
                        Text(snapshot.host.machineName)
                            .font(.system(size: 36, weight: .semibold, design: .monospaced))
                            .foregroundStyle(OxidePalette.primary)
                        Text("@\(snapshot.host.hostname) · generation \(snapshot.configuration.generation.map(String.init) ?? "unknown") · \(snapshot.configuration.git?.branch ?? "no branch")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(OxidePalette.secondary)
                    }
                }

                OverviewStatusHero(
                    snapshot: snapshot,
                    isApplying: isApplying,
                    reviewChanges: openConfigurationChanges,
                    applyConfiguration: applyConfiguration
                )

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    spacing: 16
                ) {
                    SoftwareOverviewCard(snapshot: snapshot, openSoftware: openSoftware)
                    UpdatesOverviewCard(snapshot: snapshot, openUpdates: openUpdates)
                    ProjectsOverviewCard(snapshot: snapshot, openProjects: openProjects)
                    SystemHealthOverviewCard(snapshot: snapshot)
                }

                if !snapshot.warnings.isEmpty {
                    SectionCard(title: "Needs attention", symbol: "exclamationmark.triangle.fill") {
                        ForEach(snapshot.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                ConfigurationDetailsCard(
                    snapshot: snapshot,
                    isExpanded: $showingConfigurationDetails
                )
            }
            .padding(28)
        }
        .navigationTitle("Overview")
    }
}

private struct OverviewStatusHero: View {
    let snapshot: ManagementSnapshot
    let isApplying: Bool
    let reviewChanges: () -> Void
    let applyConfiguration: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Rectangle()
                    .fill(tint.opacity(0.12))
                    .overlay(Rectangle().stroke(tint.opacity(0.48)))
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 82, height: 82)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OxidePalette.primary)
                Text(summary)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(OxidePalette.secondary)
                HStack(spacing: 8) {
                    HeroMetadataPill(symbol: "point.3.connected.trianglepath.dotted", text: snapshot.configuration.git?.branch ?? "No branch")
                    HeroMetadataPill(symbol: "clock.arrow.circlepath", text: "Generation \(snapshot.configuration.generation.map(String.init) ?? "unknown")")
                }
            }

            Spacer(minLength: 20)

            if isApplying {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Applying…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if snapshot.configuration.applyState == "unknown" {
                Button("Establish Baseline", systemImage: "arrow.triangle.2.circlepath", action: applyConfiguration)
                    .buttonStyle(OxideButtonStyle(variant: .primary))
            } else if snapshot.configuration.applyState == "pending" {
                HStack {
                    Button("Review Changes", action: reviewChanges)
                        .buttonStyle(OxideButtonStyle(variant: .secondary))
                    Button("Apply", systemImage: "checkmark.circle", action: applyConfiguration)
                        .buttonStyle(OxideButtonStyle(variant: .primary))
                }
            }
        }
        .padding(24)
        .background(OxidePalette.panel.opacity(0.88))
        .overlay(Rectangle().stroke(tint.opacity(0.4), lineWidth: 1))
    }

    private var title: String {
        switch snapshot.configuration.applyState {
        case "current": "Everything is in sync"
        case "pending": "Changes are ready to apply"
        default: "Finish setting up this Mac"
        }
    }

    private var summary: String {
        guard snapshot.configuration.applyState != "unknown" else {
            return "Apply once to record the configuration currently active on this Mac."
        }
        let differences = snapshot.softwareDifferences
        if snapshot.configuration.applyState == "current" {
            return "The repository and active system configuration match."
        }
        if differences.isEmpty {
            return "Configuration files or project settings changed; no software selections changed."
        }
        return "\(differences.count) software change\(differences.count == 1 ? "" : "s") and configuration updates are waiting."
    }

    private var tint: Color {
        switch snapshot.configuration.applyState {
        case "current": .green
        case "pending": .orange
        default: .cyan
        }
    }

    private var symbol: String {
        switch snapshot.configuration.applyState {
        case "current": "checkmark.seal.fill"
        case "pending": "arrow.left.arrow.right.circle.fill"
        default: "sparkles"
        }
    }
}

private struct HeroMetadataPill: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(OxidePalette.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(OxidePalette.panelRaised)
            .overlay(Rectangle().stroke(OxidePalette.border))
    }
}

private struct SoftwareOverviewCard: View {
    let snapshot: ManagementSnapshot
    let openSoftware: (SoftwareScope) -> Void

    var body: some View {
        OverviewPanel(title: "Software", symbol: "square.stack.3d.up.fill", tint: .cyan) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.softwareItems.count, format: .number)
                    .font(.system(size: 42, weight: .semibold, design: .monospaced))
                Text("apps and packages")
                    .foregroundStyle(.secondary)
            }

            SoftwareCompositionBar(
                managed: snapshot.managedSoftwareCount,
                separate: snapshot.unmanagedSoftwareCount,
                missing: snapshot.missingSoftwareCount
            )

            VStack(spacing: 7) {
                OverviewLinkRow(label: "Managed", value: snapshot.managedSoftwareCount, color: .blue) {
                    openSoftware(.managed)
                }
                OverviewLinkRow(label: "Installed separately", value: snapshot.unmanagedSoftwareCount, color: .orange) {
                    openSoftware(.unmanaged)
                }
                if snapshot.missingSoftwareCount > 0 {
                    OverviewLinkRow(label: "Need installation", value: snapshot.missingSoftwareCount, color: .red) {
                        openSoftware(.missing)
                    }
                }
            }

            Button("View all software", systemImage: "arrow.right") {
                openSoftware(.all)
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct SoftwareCompositionBar: View {
    let managed: Int
    let separate: Int
    let missing: Int

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Color.blue.frame(width: geometry.size.width * fraction(managed))
                Color.orange.frame(width: geometry.size.width * fraction(separate))
                Color.red.frame(width: geometry.size.width * fraction(missing))
            }
        }
        .frame(height: 9)
        .background(OxidePalette.panelRaised)
        .accessibilityLabel("\(managed) managed, \(separate) installed separately, \(missing) need installation")
    }

    private var total: Double {
        Double(max(managed + separate + missing, 1))
    }

    private func fraction(_ value: Int) -> Double {
        Double(value) / total
    }
}

private struct UpdatesOverviewCard: View {
    let snapshot: ManagementSnapshot
    let openUpdates: () -> Void

    var body: some View {
        OverviewPanel(
            title: "Updates",
            symbol: snapshot.softwareUpdateCount == 0 ? "checkmark.circle.fill" : "arrow.down.circle.fill",
            tint: snapshot.softwareUpdateCount == 0 ? .green : .orange
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.softwareUpdateCount, format: .number)
                    .font(.system(size: 42, weight: .semibold, design: .monospaced))
                Text(snapshot.softwareUpdateCount == 0 ? "everything is current" : "updates available")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                OverviewMiniStat(label: "Homebrew", value: snapshot.updates.homebrew.count)
                OverviewMiniStat(label: "App Store", value: snapshot.updates.macAppStore.count)
                OverviewMiniStat(label: "Nix inputs", value: snapshot.updates.nixFlake.count)
            }

            Spacer(minLength: 8)

            Button(snapshot.softwareUpdateCount == 0 ? "Review update history" : "Review available updates", systemImage: "arrow.right", action: openUpdates)
                .buttonStyle(OxideButtonStyle(variant: .primary))
        }
    }
}

private struct OverviewMiniStat: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.system(.headline, design: .monospaced).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(OxidePalette.panelRaised.opacity(0.72))
        .overlay(Rectangle().stroke(OxidePalette.border))
    }
}

private struct ProjectsOverviewCard: View {
    let snapshot: ManagementSnapshot
    let openProjects: () -> Void

    var body: some View {
        OverviewPanel(
            title: "Projects",
            symbol: snapshot.projectAttentionCount == 0 ? "folder.fill.badge.checkmark" : "folder.badge.questionmark",
            tint: snapshot.projectAttentionCount == 0 ? .green : .orange
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.projects.count, format: .number)
                    .font(.system(size: 42, weight: .semibold, design: .monospaced))
                Text("configured repositories")
                    .foregroundStyle(.secondary)
            }

            Label(
                snapshot.projectAttentionCount == 0
                    ? "Every project is synchronized"
                    : snapshot.projectAttentionCount == 1
                        ? "1 project needs attention"
                        : "\(snapshot.projectAttentionCount) projects need attention",
                systemImage: snapshot.projectAttentionCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .foregroundStyle(snapshot.projectAttentionCount == 0 ? .green : .orange)

            Spacer(minLength: 8)

            Button("Open projects", systemImage: "arrow.right", action: openProjects)
                .buttonStyle(OxideButtonStyle(variant: .secondary))
        }
    }
}

private struct SystemHealthOverviewCard: View {
    let snapshot: ManagementSnapshot

    var body: some View {
        OverviewPanel(title: "System health", symbol: "waveform.path.ecg", tint: healthTint) {
            Text(allAvailable ? "Core services are ready" : "A core service needs attention")
                .font(.title3.weight(.semibold))

            VStack(spacing: 9) {
                OverviewHealthRow(name: "Nix", health: snapshot.health.nix)
                OverviewHealthRow(name: "nix-darwin", health: snapshot.health.nixDarwin)
                OverviewHealthRow(name: "Homebrew", health: snapshot.health.homebrew)
            }

            Spacer(minLength: 8)

            Text("Service versions and configuration details are available below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var allAvailable: Bool {
        snapshot.health.nix.available && snapshot.health.nixDarwin.available && snapshot.health.homebrew.available
    }

    private var healthTint: Color {
        allAvailable ? .green : .orange
    }
}

private struct OverviewHealthRow: View {
    let name: String
    let health: ToolHealth

    var body: some View {
        HStack {
            Image(systemName: health.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(health.available ? .green : .orange)
            Text(name)
                .fontWeight(.medium)
            Spacer()
            Text(health.version ?? (health.available ? "Ready" : "Unavailable"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct OverviewLinkRow: View {
    let label: String
    let value: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                Spacer()
                Text(value, format: .number)
                    .font(.body.monospacedDigit().weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct OverviewPanel<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(tint)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding(20)
        .background(OxidePalette.panel.opacity(0.86))
        .overlay(Rectangle().stroke(tint.opacity(0.28), lineWidth: 1))
    }
}

private struct ConfigurationDetailsCard: View {
    let snapshot: ManagementSnapshot
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 11) {
                Divider()
                DetailRow(label: "Apply state", value: applyLabel)
                DetailRow(label: "Git branch", value: snapshot.configuration.git?.branch ?? "Unavailable")
                DetailRow(label: "Remote", value: remoteSummary)
                DetailRow(label: "Working tree", value: snapshot.configuration.git?.dirty == true ? "Uncommitted changes" : "Clean")
                DetailRow(label: "Repository revision", value: shortRevision(snapshot.configuration.desiredSource?.revision))
                DetailRow(label: "Machine revision", value: shortRevision(snapshot.configuration.appliedSource?.revision))
                DetailRow(label: "Location", value: snapshot.configuration.path)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configuration details")
                        .font(.headline)
                    Text("\(snapshot.configuration.git?.branch ?? "No branch") · \(shortRevision(snapshot.configuration.desiredSource?.revision))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(OxidePalette.panel.opacity(0.84))
        .overlay(Rectangle().stroke(OxidePalette.border))
    }

    private var applyLabel: String {
        switch snapshot.configuration.applyState {
        case "current": "System is current"
        case "pending": "Changes need applying"
        default: "Baseline needed"
        }
    }

    private var remoteSummary: String {
        guard let git = snapshot.configuration.git else { return "Unavailable" }
        return switch git.remoteState {
        case "upToDate": "Up to date"
        case "ahead": "\(git.ahead) commit\(git.ahead == 1 ? "" : "s") to push"
        case "behind": "\(git.behind) commit\(git.behind == 1 ? "" : "s") to pull"
        case "diverged": "Diverged: \(git.ahead) ahead, \(git.behind) behind"
        case "noUpstream": "No upstream branch"
        default: "Unavailable"
        }
    }

    private func shortRevision(_ revision: String?) -> String {
        guard let revision, revision != "unknown" else { return "Unavailable" }
        let clean = revision.replacingOccurrences(of: "-dirty", with: "")
        return String(clean.prefix(9)) + (revision.hasSuffix("-dirty") ? " (modified)" : "")
    }
}

private struct HarnessStatusView: View {
    private enum ApplicationFilter: String, CaseIterable, Identifiable {
        case exportable
        case privateState
        case manual
        case all

        var id: Self { self }
    }

    let status: AppStateStatus?
    let settings: AppStateSettingsCatalog?
    let hostname: String
    let configurationApplyState: String
    let isCapturing: Bool
    let isEnabling: Bool
    let isApplying: Bool
    let harnessNotice: String?
    let appSettingsError: String?
    let previewSettings: (String, AppSettingsScope, String?, Bool) async -> AppSettingsCaptureResponse?
    let saveSettings: (String, AppSettingsScope, String?, Bool) async -> AppSettingsCaptureResponse?
    let clearSettingsError: () -> Void
    let enableHarness: () async -> Bool
    let applyConfiguration: () -> Void
    let revealFile: (String) -> Void

    @State private var selectedApplicationID = ""
    @State private var selectedScope = AppSettingsScope.shared
    @State private var selectedProfile = ""
    @State private var capturePreview: AppSettingsCaptureResponse?
    @State private var applicationSearch = ""
    @State private var applicationFilter = ApplicationFilter.exportable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Application state")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text("Inspect managed state and save reviewed settings into this configuration")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(label: statusLabel, color: statusColor, symbol: statusSymbol)
                }

                if let status {
                    harnessSetupCard

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        HarnessMetricCard(
                            title: "Configured integrations",
                            value: status.configuredRecipeCount,
                            symbol: "list.bullet.rectangle",
                            tint: status.configuredRecipeCount == nil ? .secondary : .blue
                        )
                        HarnessMetricCard(
                            title: "Configuration drift",
                            value: status.driftCount,
                            symbol: "arrow.left.arrow.right",
                            tint: countTint(status.driftCount)
                        )
                        HarnessMetricCard(
                            title: "Manual residue",
                            value: status.manualResidueCount,
                            symbol: "hand.raised.fill",
                            tint: countTint(status.manualResidueCount)
                        )
                        HarnessMetricCard(
                            title: "Verified integrations",
                            value: status.verification.verifiedRecipeCount,
                            symbol: "checkmark.seal.fill",
                            tint: status.verification.verifiedRecipeCount == nil ? .secondary : .green
                        )
                        HarnessMetricCard(
                            title: "Unverified integrations",
                            value: status.verification.unverifiedRecipeCount,
                            symbol: "questionmark.diamond.fill",
                            tint: countTint(status.verification.unverifiedRecipeCount)
                        )
                    }

                    SectionCard(title: "Engine", symbol: "gearshape.2.fill") {
                        Label(
                            status.engine.available ? "Engine ready" : "Engine unavailable",
                            systemImage: status.engine.available ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(status.engine.available ? .green : .orange)
                        Text(engineDescription(status.engine))
                            .foregroundStyle(.secondary)
                    }

                    SectionCard(title: "Last apply", symbol: "clock.arrow.circlepath") {
                        if status.lastApply.status == nil {
                            Label("No apply history yet", systemImage: "clock.badge.questionmark")
                                .font(.headline)
                            Text("Apply the configuration once to activate the harness and record its first result.")
                                .foregroundStyle(.secondary)
                        } else {
                            DetailRow(label: "Result", value: applyResult(status.lastApply.status))
                            DetailRow(label: "Time", value: applyTime(status.lastApply.time))
                            DetailRow(label: "Message", value: status.lastApply.message ?? "No message")
                        }
                    }

                    settingsCaptureCard

                    SectionCard(title: "Notes and warnings", symbol: "info.circle.fill") {
                        if displayWarnings.isEmpty {
                            Label("No harness warnings", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            ForEach(displayWarnings, id: \.self) { warning in
                                if isVerificationWarning(warning) {
                                    Label(friendlyWarning(warning), systemImage: "info.circle.fill")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Label(warning, systemImage: "exclamationmark.circle")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Harness status unavailable", systemImage: "questionmark.circle")
                    } description: {
                        Text("This snapshot predates the optional app-state status contract. Refresh after updating the management API.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(28)
        }
        .navigationTitle("App Settings")
        .onAppear(perform: initializeSettingsSelection)
        .onChange(of: settings?.applications.filter(\.installed).map(\.id) ?? []) { _, _ in
            initializeSettingsSelection()
        }
        .onChange(of: selectedApplicationID) { _, _ in
            capturePreview = nil
            clearSettingsError()
        }
        .onChange(of: selectedScope) { _, _ in
            capturePreview = nil
            clearSettingsError()
        }
        .onChange(of: selectedProfile) { _, _ in
            capturePreview = nil
            clearSettingsError()
        }
        .onChange(of: applicationFilter) { _, _ in selectFirstVisibleApplication() }
        .onChange(of: applicationSearch) { _, _ in selectFirstVisibleApplication() }
    }

    @ViewBuilder
    private var harnessSetupCard: some View {
        if let settings, !settings.enabled {
            SectionCard(title: "Set up the harness", symbol: "switch.2") {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ready to enable", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("The app-state engine is already installed with Nix Me. Enable it for this Mac, then review the standard administrator prompt to apply it now.")
                        .foregroundStyle(.secondary)
                    Text("This changes config/app-state/machines/\(hostname)/enabled. It does not stage, commit, or push the repository change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Enable and Apply…", systemImage: "power") {
                            Task {
                                if await enableHarness() {
                                    applyConfiguration()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isEnabling || isApplying)

                        if isEnabling {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating configuration…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else if settings?.enabled == true && configurationApplyState != "current" {
            SectionCard(title: "Finish harness setup", symbol: "checkmark.circle.badge.questionmark") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The harness is enabled for this Mac, but the running system still uses the previous configuration.")
                        .foregroundStyle(.secondary)
                    Text("Applying activates the harness and creates its first status history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let harnessNotice {
                        Label(harnessNotice, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Apply Configuration", systemImage: "checkmark.circle") {
                        applyConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying || isEnabling)
                }
            }
        }
    }

    @ViewBuilder
    private var settingsCaptureCard: some View {
        SectionCard(title: "Applications", symbol: "square.grid.2x2.fill") {
            if let settings, !installedApplications.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Apps in this list can convert current settings into harness JSON. Reviewed-source apps ask before reading the file; select any app to see its exact boundary.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(installedApplicationCount) installed · \(exportableApplicationCount) exportable · \(privateApplicationCount) private · \(managedApplicationCount) integrations")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Applications", selection: $applicationFilter) {
                                Text("Exportable \(exportableApplicationCount)")
                                    .tag(ApplicationFilter.exportable)
                                Text("Private \(privateApplicationCount)")
                                    .tag(ApplicationFilter.privateState)
                                Text("Manual \(manualApplicationCount)")
                                    .tag(ApplicationFilter.manual)
                                Text("All \(installedApplicationCount)")
                                    .tag(ApplicationFilter.all)
                            }
                            .pickerStyle(.segmented)

                            Text(applicationFilterDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Search this list", text: $applicationSearch)
                                .textFieldStyle(.roundedBorder)

                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    if filteredApplications.isEmpty {
                                        ContentUnavailableView.search(text: applicationSearch)
                                            .frame(maxWidth: .infinity, minHeight: 220)
                                    } else {
                                        ForEach(filteredApplications) { application in
                                            applicationListRow(application)
                                        }
                                    }
                                }
                            }
                            .frame(minWidth: 270, idealWidth: 310, maxWidth: 340, minHeight: 390, maxHeight: 500)
                        }

                        Divider()

                        if let application = selectedApplication {
                            applicationDetails(application, settings: settings)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        } else {
                            ContentUnavailableView {
                                Label("Select an application", systemImage: "app.dashed")
                            } description: {
                                Text("Choose an application to inspect its loaded configuration and export boundary.")
                            }
                            .frame(maxWidth: .infinity, minHeight: 390)
                        }
                    }
                }
            } else if settings == nil {
                ContentUnavailableView {
                    Label("Settings catalog unavailable", systemImage: "questionmark.folder")
                } description: {
                    Text("Refresh after updating the app-state engine and management API.")
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ContentUnavailableView {
                    Label("No applications found", systemImage: "tray")
                } description: {
                    Text("Applications installed in /Applications or ~/Applications will appear here after refresh.")
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
    }

    private func applicationListRow(_ application: AppStateSettingsApplication) -> some View {
        let selected = application.id == selectedApplicationID
        return Button {
            selectedApplicationID = application.id
        } label: {
            HStack(spacing: 11) {
                applicationIcon(application, size: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(application.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(application.bundleId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if application.configured {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .help("Saved configuration loaded")
                }

                Label(applicationListLabel(application), systemImage: applicationListSymbol(application))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(applicationListColor(application))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(applicationListColor(application).opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                selected ? Color.accentColor.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(application.name), \(applicationListLabel(application))")
        .accessibilityHint(application.configured ? "Saved configuration loaded" : "No saved configuration loaded")
    }

    @ViewBuilder
    private func applicationDetails(
        _ application: AppStateSettingsApplication,
        settings: AppStateSettingsCatalog
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                applicationIcon(application, size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.name)
                        .font(.title2.weight(.semibold))
                    Text(application.bundleId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                StatusBadge(
                    label: application.installed ? "Installed" : "Not installed",
                    color: application.installed ? .green : .secondary,
                    symbol: application.installed ? "checkmark.circle.fill" : "minus.circle"
                )
            }

            HStack(spacing: 8) {
                ApplicationPill(
                    label: application.recipeAvailable ? "Integration available" : "Integration needed",
                    color: application.recipeAvailable ? .blue : .orange
                )
                if application.privateState == nil {
                    if application.configured {
                        ApplicationPill(
                            label: "\(application.configurationSources.count) loaded \(application.configurationSources.count == 1 ? "source" : "sources")",
                            color: .green
                        )
                    } else {
                        ApplicationPill(label: "No saved settings", color: .secondary)
                    }
                }
                if let readiness = application.privateReadinessLabel {
                    ApplicationPill(
                        label: "Private state · \(readiness)",
                        color: privateStateColor(application.privateState?.readiness ?? .unknown)
                    )
                } else if application.capturable {
                    ApplicationPill(
                        label: application.requiresExportConfirmation ? "Review before saving" : "Exportable to harness",
                        color: application.requiresExportConfirmation ? .orange : .green
                    )
                } else if application.managedPaths.isEmpty, application.recipeAvailable {
                    ApplicationPill(label: "Not exportable", color: .orange)
                } else if application.recipeAvailable {
                    ApplicationPill(label: "Manual authoring only", color: .secondary)
                }
            }

            harnessExportCard(application, settings: settings)

            if let appSettingsError {
                appSettingsErrorCard(appSettingsError)
            }

            if let capturePreview {
                settingsPreview(capturePreview)
            }

            if application.privateState == nil {
                if let appPath = application.appPath {
                    configurationReferenceRow(
                        label: "Application",
                        path: appPath,
                        symbol: "app.fill",
                        revealable: false
                    )
                }

                if let recipePath = application.recipePath {
                    configurationReferenceRow(
                        label: "Management integration",
                        path: recipePath,
                        symbol: "doc.badge.gearshape",
                        revealable: true
                    )
                }

                ForEach(application.managedPaths, id: \.self) { path in
                    configurationReferenceRow(
                        label: "Managed configuration",
                        path: path,
                        symbol: "doc.text.fill",
                        revealable: true
                    )
                }

                if !application.manualSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Manual setup")
                            .font(.headline)
                        ForEach(Array(application.manualSteps.enumerated()), id: \.offset) { index, step in
                            Label(step, systemImage: "\(index + 1).circle.fill")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if application.privateState == nil {
                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Loaded configuration")
                        .font(.headline)
                    if application.configurationSources.isEmpty {
                        Text(application.recipeAvailable
                            ? "The integration is ready, but no shared, active-profile, machine, or built-in settings are currently loaded."
                            : "This installed application does not have a Nix Me management integration yet, so no settings configuration is loaded.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(application.configurationSources) { source in
                            configurationReferenceRow(
                                label: source.label,
                                path: source.path,
                                symbol: configurationSourceSymbol(source.scope),
                                revealable: true
                            )
                        }
                    }
                }

            }
        }
    }

    private func appSettingsErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text("Preview could not be created")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Nothing was saved. Resolve the issue above, then try the preview again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss", action: clearSettingsError)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func harnessExportCard(
        _ application: AppStateSettingsApplication,
        settings: AppStateSettingsCatalog
    ) -> some View {
        if let privateState = application.privateState {
            VStack(alignment: .leading, spacing: 10) {
                Label("Private state", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(privateStateColor(privateState.readiness))
                HStack(spacing: 8) {
                    Image(systemName: privateStateSymbol(privateState.readiness))
                    Text(application.privateReadinessLabel ?? "Unknown")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(privateStateColor(privateState.readiness))
                Text(privateState.exclusionReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                privateStateColor(privateState.readiness).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
        } else if application.capturable {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    application.requiresExportConfirmation ? "Review source, then save" : "Save current settings",
                    systemImage: application.requiresExportConfirmation ? "doc.text.magnifyingglass" : "square.and.arrow.up.fill"
                )
                    .font(.headline)
                    .foregroundStyle(application.requiresExportConfirmation ? .orange : .green)
                Text(application.requiresExportConfirmation
                    ? "Nix Me has not read this file. Choose where the settings should apply, then explicitly allow a local preview. Nothing is uploaded or saved until you choose Save to Harness."
                    : "Choose where these settings should apply, preview the portable values, then save them to the harness. Nothing is written during preview.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if application.exportableSettings.count > 4 {
                    DisclosureGroup("\(application.exportableSettings.count) exportable settings") {
                        exportableSettingsList(application)
                            .padding(.top, 8)
                    }
                    .font(.callout.weight(.semibold))
                } else if !application.exportableSettings.isEmpty {
                    exportableSettingsList(application)
                } else {
                    ForEach(application.captureKinds, id: \.self) { kind in
                        Label(exportKindDescription(kind), systemImage: exportKindSymbol(kind))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                settingsCaptureControls(application, settings: settings)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (application.requiresExportConfirmation ? Color.orange : Color.green).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
        } else if application.recipeAvailable, !application.managedPaths.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Manual authoring only", systemImage: "doc.badge.ellipsis")
                    .font(.headline)
                Text("Nix Me can apply the managed file paths shown below, but it will not read unstructured or executable content back into the harness. Edit the harness settings manually; there is no Save action for this app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else if application.recipeAvailable {
            VStack(alignment: .leading, spacing: 8) {
                Label("Not exportable", systemImage: "nosign")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("This integration intentionally exposes no portable settings. Credentials, licenses, cloud state, and opaque application data stay on this Mac; use the manual setup instructions instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Export unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("No management integration defines a safe export boundary for this application, so Nix Me cannot read or save its settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func exportableSettingsList(_ application: AppStateSettingsApplication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(application.exportableSettings) { setting in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: exportSettingSymbol(setting.kind))
                        .frame(width: 17)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(setting.label)
                            .font(.callout.weight(.medium))
                        Text(setting.source)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if setting.requiresConfirmation == true {
                            Label("Not read until you choose Allow Read & Show Preview", systemImage: "hand.raised.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func exportSettingSymbol(_ kind: String) -> String {
        switch kind {
        case "preference": "switch.2"
        case "file": "doc.text.fill"
        case "command": "list.bullet.rectangle"
        default: "square.and.arrow.up"
        }
    }

    private func exportKindSymbol(_ kind: String) -> String {
        switch kind {
        case "defaults": "switch.2"
        case "file": "doc.text.fill"
        case "command": "list.bullet.rectangle"
        default: "square.and.arrow.up"
        }
    }

    private func exportKindDescription(_ kind: String) -> String {
        switch kind {
        case "defaults": "Declared application preferences"
        case "file": "Structured settings file"
        case "command": "Application-managed list"
        default: kind
        }
    }

    @ViewBuilder
    private func settingsCaptureControls(
        _ application: AppStateSettingsApplication,
        settings: AppStateSettingsCatalog
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !application.installed {
                Label("Install this application before exporting its current settings.", systemImage: "arrow.down.app")
                    .foregroundStyle(.secondary)
            } else if !application.recipeAvailable {
                Label("A management integration is required before Nix Me can safely read or apply this application's settings.", systemImage: "doc.badge.plus")
                    .foregroundStyle(.orange)
            } else if !application.capturable {
                Label(nonCapturableDescription(application), systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text("1. Choose where these settings apply")
                    .font(.callout.weight(.semibold))

                Picker("Scope", selection: $selectedScope) {
                    ForEach(availableScopes) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 430)

                if selectedScope == .profile {
                    Picker("Profile", selection: $selectedProfile) {
                        ForEach(settings.activeProfiles, id: \.self) { profile in
                            Text(profile).tag(profile)
                        }
                    }
                    .frame(maxWidth: 300)
                }

                Text(scopeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(application.requiresExportConfirmation
                        ? "2. Allow a local read and review the preview"
                        : "2. Review the preview")
                        .font(.callout.weight(.semibold))
                    Text(application.requiresExportConfirmation
                        ? "This reads the exact source file shown above into Nix Me. The contents stay on this Mac and are not written to the harness yet."
                        : "Nix Me reads only the portable settings listed above. The preview is not written to the harness.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(
                        application.requiresExportConfirmation
                            ? "Allow Read & Show Preview"
                            : "Show Settings Preview",
                        systemImage: application.requiresExportConfirmation
                            ? "hand.thumbsup.fill"
                            : "doc.text.magnifyingglass"
                    ) {
                        Task {
                            capturePreview = await previewSettings(
                                application.id,
                                selectedScope,
                                selectedScope == .profile ? selectedProfile : nil,
                                application.requiresExportConfirmation
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCapturing || invalidProfileSelection)

                    if isCapturing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Reading exportable settings…")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("3. Inspect the complete preview, then choose Save to Harness.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func configurationReferenceRow(
        label: String,
        path: String,
        symbol: String,
        revealable: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            if revealable {
                Button("Reveal", systemImage: "folder") {
                    revealFile(path)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Reveal \(path)")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func applicationIcon(_ application: AppStateSettingsApplication, size: CGFloat) -> some View {
        if let path = application.appPath, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: application.recipeAvailable ? "app.fill" : "app.dashed")
                .font(.system(size: size * 0.58, weight: .medium))
                .foregroundStyle(application.recipeAvailable ? Color.accentColor : Color.secondary)
                .frame(width: size, height: size)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: size * 0.22))
        }
    }

    @ViewBuilder
    private func settingsPreview(_ preview: AppSettingsCaptureResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.destination)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Text(preview.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(
                    label: preview.written ? "Saved" : (preview.changed ? "Changes found" : "Already current"),
                    color: preview.written || !preview.changed ? .green : .blue,
                    symbol: preview.written || !preview.changed ? "checkmark.circle.fill" : "pencil.circle.fill"
                )
            }

            if !preview.tracked {
                Label(
                    "This settings file is local to this checkout. Apply uses it immediately; commit it when you want to share it.",
                    systemImage: "info.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(preview.captured.reduce(0) { $0 + $1.valueCount }) captured values", systemImage: "checkmark.circle")
                if preview.redaction.count > 0 {
                    Label("\(preview.redaction.count) secrets omitted", systemImage: "hand.raised.fill")
                        .foregroundStyle(.orange)
                }
                if !preview.skipped.isEmpty {
                    Label("\(preview.skipped.count) unsupported sources", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            ScrollView {
                Text(preview.preview)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxHeight: 230)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            }

            if !preview.skipped.isEmpty {
                DisclosureGroup("Skipped sources") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(preview.skipped) { item in
                            Text("\(item.bind ?? item.kind): \(item.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            HStack {
                Button("Save to Harness", systemImage: "square.and.arrow.down") {
                    Task {
                        capturePreview = await saveSettings(
                            selectedApplicationID,
                            selectedScope,
                            selectedScope == .profile ? selectedProfile : nil,
                            selectedApplication?.requiresExportConfirmation == true
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCapturing || !preview.changed || preview.written)

                if preview.written || !preview.changed {
                    Button("Reveal File", systemImage: "folder") {
                        revealFile(preview.destination)
                    }
                }
            }
        }
    }

    private var filteredApplications: [AppStateSettingsApplication] {
        let applications = installedApplications.filter { application in
            switch applicationFilter {
            case .exportable:
                application.settingsCategory == .exportable
            case .privateState:
                application.settingsCategory == .privateState
            case .manual:
                application.settingsCategory == .manual
            case .all:
                true
            }
        }
        let query = applicationSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? applications : applications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleId.localizedCaseInsensitiveContains(query)
        }
        return matches.sorted {
            let leftRank = applicationCapabilityRank($0)
            let rightRank = applicationCapabilityRank($1)
            if leftRank != rightRank { return leftRank < rightRank }
            if $0.configured != $1.configured { return $0.configured }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var selectedApplication: AppStateSettingsApplication? {
        installedApplications.first { $0.id == selectedApplicationID }
    }

    private var installedApplications: [AppStateSettingsApplication] {
        settings?.applications.filter(\.installed) ?? []
    }

    private var installedApplicationCount: Int {
        installedApplications.count
    }

    private var managedApplicationCount: Int {
        installedApplications.filter(\.recipeAvailable).count
    }

    private var exportableApplicationCount: Int {
        installedApplications.filter { $0.settingsCategory == .exportable }.count
    }

    private var privateApplicationCount: Int {
        installedApplications.filter { $0.settingsCategory == .privateState }.count
    }

    private var manualApplicationCount: Int {
        installedApplications.filter { $0.settingsCategory == .manual }.count
    }

    private var unsupportedApplicationCount: Int {
        installedApplications.filter { $0.settingsCategory == .unsupported }.count
    }

    private var applicationFilterDescription: String {
        switch applicationFilter {
        case .exportable:
            "Settings that Nix Me can read, preview, and save into the harness."
        case .privateState:
            "Private integrations report readiness without exposing account identity, credentials, sessions, or command output."
        case .manual:
            "Integrated apps that require manual setup or manual configuration-file authoring."
        case .all:
            "Includes \(unsupportedApplicationCount) installed apps without a management integration."
        }
    }

    private var availableScopes: [AppSettingsScope] {
        guard settings?.activeProfiles.isEmpty == false else { return [.shared, .machine] }
        return AppSettingsScope.allCases
    }

    private var invalidProfileSelection: Bool {
        selectedScope == .profile && selectedProfile.isEmpty
    }

    private var scopeDescription: String {
        switch selectedScope {
        case .shared:
            "Shared settings apply to every machine using this configuration."
        case .profile:
            "Profile settings apply only when the \(selectedProfile.isEmpty ? "selected" : selectedProfile) profile is active."
        case .machine:
            "Machine settings apply only to \(hostname) and override shared and profile settings."
        }
    }

    private func initializeSettingsSelection() {
        selectFirstVisibleApplication()
        let profiles = settings?.activeProfiles ?? []
        if !profiles.contains(selectedProfile) {
            selectedProfile = profiles.first ?? ""
        }
        if selectedScope == .profile && profiles.isEmpty {
            selectedScope = .shared
        }
    }

    private func selectFirstVisibleApplication() {
        let applications = filteredApplications
        if !applications.contains(where: { $0.id == selectedApplicationID }) {
            selectedApplicationID = applications.first?.id ?? ""
        }
    }

    private func applicationCapabilityRank(_ application: AppStateSettingsApplication) -> Int {
        if application.capturable { return 0 }
        if application.privateState != nil { return 1 }
        if application.recipeAvailable, !application.managedPaths.isEmpty { return 2 }
        if application.recipeAvailable { return 3 }
        return 4
    }

    private func applicationListLabel(_ application: AppStateSettingsApplication) -> String {
        if application.requiresExportConfirmation { return "Review first" }
        if application.capturable { return "Exportable" }
        if let readiness = application.privateReadinessLabel { return "Private · \(readiness)" }
        if application.recipeAvailable, !application.managedPaths.isEmpty { return "Manual file" }
        return "Not exportable"
    }

    private func applicationListSymbol(_ application: AppStateSettingsApplication) -> String {
        if application.requiresExportConfirmation { return "doc.text.magnifyingglass" }
        if application.capturable { return "square.and.arrow.up.fill" }
        if application.privateState != nil { return "lock.shield.fill" }
        if application.recipeAvailable, !application.managedPaths.isEmpty { return "doc.badge.ellipsis" }
        return "nosign"
    }

    private func applicationListColor(_ application: AppStateSettingsApplication) -> Color {
        if application.requiresExportConfirmation { return .orange }
        if application.capturable { return .green }
        if let privateState = application.privateState {
            return privateStateColor(privateState.readiness)
        }
        if application.recipeAvailable, !application.managedPaths.isEmpty { return .secondary }
        return .orange
    }

    private func privateStateColor(_ readiness: AppStatePrivateReadiness) -> Color {
        switch readiness {
        case .ready: .green
        case .notReady: .orange
        case .unknown: .secondary
        }
    }

    private func privateStateSymbol(_ readiness: AppStatePrivateReadiness) -> String {
        switch readiness {
        case .ready: "checkmark.circle.fill"
        case .notReady: "exclamationmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private func nonCapturableDescription(_ application: AppStateSettingsApplication) -> String {
        if application.managedPaths.isEmpty {
            return "This app keeps credentials, cloud state, licenses, or opaque data outside a safe portable boundary. Follow the documented manual setup; Nix Me will not copy that state into the repository."
        }
        return "This app uses an unstructured configuration file. Nix Me can apply reviewed settings, but it will not automatically capture opaque or executable content."
    }

    private func configurationSourceSymbol(_ scope: String) -> String {
        switch scope {
        case "builtIn": "shippingbox.fill"
        case "shared": "desktopcomputer"
        case "profile": "person.crop.circle"
        case "machine": "laptopcomputer"
        case "external": "doc.badge.plus"
        default: "doc.fill"
        }
    }

    private var statusLabel: String {
        guard let status else { return "Status unavailable" }
        if settings?.enabled == true && configurationApplyState != "current" {
            return "Ready to apply"
        }
        if !status.engine.available { return "Engine unavailable" }
        if status.hasUnavailableCounts { return "Status incomplete" }
        if status.hasDifferences { return "Differences found" }
        if status.verification.unverifiedRecipeCount.map({ $0 > 0 }) == true {
            return "Verification needed"
        }
        if status.lastApply.status == "failed" { return "Last apply failed" }
        if status.lastApply.status == "partial" { return "Last apply partial" }
        if !status.warnings.isEmpty { return "Needs attention" }
        return "In sync"
    }

    private var statusColor: Color {
        guard let status else { return .secondary }
        if settings?.enabled == true && configurationApplyState != "current" {
            return .blue
        }
        return status.needsAttention ? .orange : .green
    }

    private var statusSymbol: String {
        guard let status else { return "questionmark.circle.fill" }
        if settings?.enabled == true && configurationApplyState != "current" {
            return "arrow.down.circle.fill"
        }
        return status.needsAttention ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }

    private var displayWarnings: [String] {
        guard let status else { return [] }
        return status.warnings.filter { warning in
            guard status.lastApply.status == nil else { return true }
            return warning != "The last app-state apply status is unavailable"
                && warning != "The persisted app-state status is unavailable"
        }
    }

    private func countTint(_ count: Int?) -> Color {
        guard let count else { return .secondary }
        return count == 0 ? .green : .orange
    }

    private func applyResult(_ result: String?) -> String {
        switch result {
        case "succeeded": "Succeeded"
        case "partial": "Partially succeeded"
        case "failed": "Failed"
        case let result?: result.capitalized
        case nil: "Never applied"
        }
    }

    private func applyTime(_ value: String?) -> String {
        guard let value else { return "Not yet" }
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func engineDescription(_ engine: AppStateEngine) -> String {
        guard engine.available else {
            return "The application-state engine is not installed in the active system configuration."
        }
        return "nix-me-apps \(engine.version ?? "version unavailable") is installed and responding."
    }

    private func friendlyWarning(_ warning: String) -> String {
        let prefix = "recipe "
        let suffix = " is unverified"
        guard warning.hasPrefix(prefix), warning.hasSuffix(suffix) else { return warning }
        let start = warning.index(warning.startIndex, offsetBy: prefix.count)
        let end = warning.index(warning.endIndex, offsetBy: -suffix.count)
        let recipe = warning[start..<end].replacingOccurrences(of: "-", with: " ").capitalized
        return "\(recipe) is configured but has not completed end-to-end UI verification. This does not block Apply."
    }

    private func isVerificationWarning(_ warning: String) -> Bool {
        warning.hasPrefix("recipe ") && warning.hasSuffix(" is unverified")
    }

}

private struct LocalAIStatusView: View {
    let status: LocalAIStatus?
    let operation: LocalAIModelOperation?
    let isActionRunning: Bool
    let startDownload: () -> Void
    let cancelDownload: () -> Void
    let refreshOperation: () -> Void
    @State private var confirmingDownload = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DS4 + Pi")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text(status?.summary ?? "Local AI status is not present in this snapshot")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(label: healthLabel, color: healthColor, symbol: healthSymbol)
                }

                if let status {
                    SectionCard(title: "Operational status", symbol: "waveform.path.ecg") {
                        DetailRow(label: "DS4 checkout", value: stateLabel(status.ds4Checkout.state.rawValue))
                        DetailRow(label: "pi-ds4 checkout", value: stateLabel(status.piDs4Checkout.state.rawValue))
                        DetailRow(label: "Extension link", value: stateLabel(status.extension.state.rawValue))
                        DetailRow(label: "Runtime build", value: stateLabel(status.runtime.state.rawValue))
                        DetailRow(label: status.model.name, value: stateLabel(status.model.state.rawValue))
                        DetailRow(label: "DS4 server", value: stateLabel(status.server.state.rawValue))
                        DetailRow(label: "Harness configuration", value: configurationLabel(status.configuration))
                    }

                    SectionCard(title: "Remediation", symbol: "wrench.and.screwdriver.fill") {
                        if status.remediation.isEmpty {
                            Label("No action needed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            ForEach(status.remediation, id: \.self) { remediation in
                                Label(remediation, systemImage: "arrow.right.circle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text("Refresh is read-only. Model downloads and lifecycle operations remain explicit actions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SectionCard(title: "Model lifecycle", symbol: "externaldrive.badge.arrow.down") {
                        if let operation {
                            DetailRow(label: "Operation", value: stateLabel(operation.status))
                            DetailRow(label: "Phase", value: stateLabel(operation.phase))
                            DetailRow(label: "Integrity", value: integrityLabel(operation.integrity.status))
                            if operation.isRunning {
                                ProgressView(value: Double(operation.progress.percent), total: 100) {
                                    Text(operation.message)
                                } currentValueLabel: {
                                    Text("\(operation.progress.percent)%")
                                }
                                Text("\(byteCount(operation.progress.bytesDownloaded)) of approximately \(byteCount(operation.progress.expectedBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Cancel download", role: .destructive, action: cancelDownload)
                                    .disabled(isActionRunning)
                            } else {
                                Text(operation.message)
                                    .foregroundStyle(operation.status == "failed" ? .red : .secondary)
                            }
                        } else {
                            Text("No model lifecycle operation has been started on this Mac.")
                                .foregroundStyle(.secondary)
                        }

                        if operation?.isRunning != true {
                            Button(status.model.state == .present ? "Reinstall model…" : "Download model…") {
                                confirmingDownload = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isActionRunning || status.ds4Checkout.state != .ready)
                        }

                        Text("A download starts only after confirmation. The existing model remains available until the new artifact passes any configured checksum and is installed atomically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Local AI status unavailable", systemImage: "questionmark.circle")
                    } description: {
                        Text("This snapshot predates the optional local-AI status contract. Refresh after updating the management API.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(28)
        }
        .navigationTitle("Local AI")
        .task { refreshOperation() }
        .confirmationDialog(
            status?.model.state == .present ? "Reinstall the local model?" : "Download the local model?",
            isPresented: $confirmingDownload,
            titleVisibility: .visible
        ) {
            Button(status?.model.state == .present ? "Reinstall Model" : "Download Model") {
                startDownload()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This explicitly starts a large download after a disk-space preflight. You can monitor or cancel it from this view.")
        }
    }

    private var healthLabel: String {
        guard let status else { return "Unavailable" }
        return stateLabel(status.health.rawValue)
    }

    private var healthColor: Color {
        switch status?.health {
        case .healthy: .green
        case .degraded: .orange
        case .unavailable, nil: .secondary
        }
    }

    private var healthSymbol: String {
        switch status?.health {
        case .healthy: "checkmark.circle.fill"
        case .degraded: "exclamationmark.circle.fill"
        case .unavailable, nil: "questionmark.circle.fill"
        }
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func integrityLabel(_ value: String) -> String {
        switch value {
        case "verified": "SHA-256 verified"
        case "mismatch": "Checksum mismatch"
        case "notProvided": "No checksum provided"
        case "notChecked": "Not checked"
        case "pending": "Pending"
        default: stateLabel(value)
        }
    }

    private func configurationLabel(_ configuration: LocalAIConfigurationStatus) -> String {
        switch configuration.state {
        case .current:
            "Current"
        case .drifted:
            "\(configuration.driftCount ?? 0) difference\(configuration.driftCount == 1 ? "" : "s")"
        case .unavailable:
            "Unavailable"
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "notBuilt": "Not built"
        case "mislinked": "Mislinked"
        default: state.capitalized
        }
    }
}

private struct SoftwareView: View {
    let snapshot: ManagementSnapshot
    @Binding var scope: SoftwareScope
    let loadDetails: (SoftwareListItem) async throws -> PackageDetails
    @State private var selectedItem: SoftwareListItem?
    @State private var details: PackageDetails?
    @State private var detailsError: String?
    @State private var isLoadingDetails = false
    @State private var query = ""
    @State private var filter = SoftwareFilter.all

    var body: some View {
        VStack(spacing: 0) {
            SoftwareInventoryHeader(
                itemCount: filteredItems.count,
                totalCount: allItems.count,
                managedCount: snapshot.managedSoftwareCount,
                unmanagedCount: snapshot.unmanagedSoftwareCount,
                missingCount: snapshot.missingSoftwareCount,
                scope: $scope,
                filter: $filter
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    SoftwareListSection(
                        title: "Applications",
                        subtitle: "Mac apps you can launch and use",
                        symbol: "macwindow.on.rectangle",
                        tint: .teal,
                        items: applicationItems,
                        baselineAvailable: baselineAvailable,
                        selectedItem: $selectedItem
                    )
                    SoftwareListSection(
                        title: "Command-line tools",
                        subtitle: "Developer tools and utilities available in your shell",
                        symbol: "terminal.fill",
                        tint: .orange,
                        items: commandLineItems,
                        baselineAvailable: baselineAvailable,
                        selectedItem: $selectedItem
                    )
                    SoftwareListSection(
                        title: "System packages",
                        subtitle: "Packages provided by the active Nix configuration",
                        symbol: "snowflake",
                        tint: .blue,
                        items: systemItems,
                        baselineAvailable: baselineAvailable,
                        selectedItem: $selectedItem
                    )
                }
                .padding(22)
            }
        }
        .navigationTitle("Apps & Packages")
        .searchable(text: $query, placement: .toolbar, prompt: "Search apps and packages")
        .overlay {
            if filteredItems.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "No matching software",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Choose another state or source filter.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .inspector(isPresented: Binding(
            get: { selectedItem != nil },
            set: { if !$0 { selectedItem = nil } }
        )) {
            PackageDetailsPanel(
                item: selectedItem,
                details: details,
                error: detailsError,
                isLoading: isLoadingDetails,
                baselineAvailable: snapshot.configuration.applyState != "unknown"
            )
                .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }
        .task(id: selectedItem?.id) {
            details = nil
            detailsError = nil
            guard let selectedItem else { return }
            isLoadingDetails = true
            do {
                details = try await loadDetails(selectedItem)
            } catch {
                detailsError = error.localizedDescription
            }
            isLoadingDetails = false
        }
    }

    private var filteredItems: [SoftwareListItem] {
        allItems.filter { item in
            let matchesScope = scope.matches(item)
            let matchesFilter = filter.kind == nil || item.kind == filter.kind
            let matchesQuery = query.isEmpty
                || item.displayName.localizedCaseInsensitiveContains(query)
                || item.libraryDisplayName.localizedCaseInsensitiveContains(query)
                || item.kind.label.localizedCaseInsensitiveContains(query)
            return matchesScope && matchesFilter && matchesQuery
        }
    }

    private var allItems: [SoftwareListItem] {
        snapshot.softwareItems
    }

    private var applicationItems: [SoftwareListItem] {
        filteredItems.filter { $0.kind == .cask || $0.kind == .mas }
    }

    private var commandLineItems: [SoftwareListItem] {
        filteredItems.filter { $0.kind == .formula }
    }

    private var systemItems: [SoftwareListItem] {
        filteredItems.filter { $0.kind == .nix }
    }

    private var baselineAvailable: Bool {
        snapshot.configuration.applyState != "unknown"
    }
}

private enum SoftwareScope: String, CaseIterable, Identifiable {
    case all = "Everything"
    case managed = "Managed"
    case unmanaged = "Installed separately"
    case missing = "Needs install"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .all: "All software"
        case .managed: "Managed by Nix Me"
        case .unmanaged: "Installed separately"
        case .missing: "Waiting to install"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .managed: "checkmark.seal.fill"
        case .unmanaged: "person.crop.circle.badge.checkmark"
        case .missing: "arrow.down.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .all: OxidePalette.cyan
        case .managed: OxidePalette.green
        case .unmanaged: OxidePalette.amber
        case .missing: OxidePalette.red
        }
    }

    func matches(_ item: SoftwareListItem) -> Bool {
        switch self {
        case .all: true
        case .managed: item.isDesired
        case .unmanaged: !item.isDesired && item.isInstalled
        case .missing: item.isDesired && !item.isInstalled
        }
    }
}

private enum SoftwareFilter: String, CaseIterable, Identifiable {
    case all = "All types"
    case nix = "Nix"
    case formula = "Command-line"
    case cask = "Applications"
    case mas = "App Store"

    var id: String { rawValue }

    var kind: SoftwareKind? {
        switch self {
        case .all: nil
        case .nix: .nix
        case .formula: .formula
        case .cask: .cask
        case .mas: .mas
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .nix: "snowflake"
        case .formula: "terminal"
        case .cask: "macwindow"
        case .mas: "apple.logo"
        }
    }
}

private struct SoftwareInventoryHeader: View {
    let itemCount: Int
    let totalCount: Int
    let managedCount: Int
    let unmanagedCount: Int
    let missingCount: Int
    @Binding var scope: SoftwareScope
    @Binding var filter: SoftwareFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your software library")
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OxidePalette.primary)
                    Text("Browse everything on this Mac and see at a glance who manages it.")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(OxidePalette.secondary)
                }

                Spacer()

                Text(countLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                SoftwareScopeLens(
                    scope: .all,
                    count: totalCount,
                    isSelected: scope == .all,
                    action: { scope = .all }
                )
                SoftwareScopeLens(
                    scope: .managed,
                    count: managedCount,
                    isSelected: scope == .managed,
                    action: { scope = .managed }
                )
                SoftwareScopeLens(
                    scope: .unmanaged,
                    count: unmanagedCount,
                    isSelected: scope == .unmanaged,
                    action: { scope = .unmanaged }
                )
                SoftwareScopeLens(
                    scope: .missing,
                    count: missingCount,
                    isSelected: scope == .missing,
                    action: { scope = .missing }
                )

                Spacer()
            }

            HStack(spacing: 8) {
                Text("Show")
                    .oxideLabel()

                ForEach(SoftwareFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        Label(option.rawValue, systemImage: option.symbol)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(filter == option ? OxidePalette.green.opacity(0.14) : Color.clear)
                            .overlay {
                                Rectangle()
                                    .stroke(
                                        filter == option ? OxidePalette.green.opacity(0.52) : OxidePalette.border,
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Label("Select an item for details", systemImage: "sidebar.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(22)
        .background(OxidePalette.panel.opacity(0.88))
        .overlay(alignment: .bottom) { Rectangle().fill(OxidePalette.border).frame(height: 1) }
    }

    private var countLabel: String {
        if itemCount == totalCount {
            return "\(totalCount) item\(totalCount == 1 ? "" : "s")"
        }
        return "Showing \(itemCount) of \(totalCount)"
    }
}

private struct SoftwareScopeLens: View {
    let scope: SoftwareScope
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: scope.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(scope.tint)
                Text(scope.shortLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(count, format: .number)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? scope.tint : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scope.tint.opacity(isSelected ? 0.15 : 0.07))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(isSelected || isHovered
            ? scope.tint.opacity(isSelected ? 0.12 : 0.06)
            : OxidePalette.panelRaised.opacity(0.72))
        .overlay {
            Rectangle()
                .stroke(isSelected ? scope.tint.opacity(0.65) : OxidePalette.border, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(scope.rawValue), \(count)")
    }
}

private struct SoftwareListSection: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let items: [SoftwareListItem]
    let baselineAvailable: Bool
    @Binding var selectedItem: SoftwareListItem?
    @State private var isExpanded = true

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 34, height: 34)
                            .background(tint.opacity(0.13))
                            .overlay(Rectangle().stroke(tint.opacity(0.28)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(items.count, format: .number)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(OxidePalette.panelRaised)
                            .overlay(Rectangle().stroke(OxidePalette.border))

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Rectangle().fill(OxidePalette.border).frame(height: 1)

                    ForEach(sortedItems) { item in
                        SoftwareLibraryRow(
                            item: item,
                            baselineAvailable: baselineAvailable,
                            isSelected: selectedItem == item,
                            action: { selectedItem = item }
                        )

                        if item.id != sortedItems.last?.id {
                            Rectangle().fill(OxidePalette.border).frame(height: 1)
                                .padding(.leading, 72)
                        }
                    }
                }
            }
            .background(OxidePalette.panel.opacity(0.86))
            .overlay(Rectangle().stroke(tint.opacity(0.24), lineWidth: 1))
        }
    }

    private var sortedItems: [SoftwareListItem] {
        items.sorted {
            $0.libraryDisplayName.localizedCaseInsensitiveCompare($1.libraryDisplayName) == .orderedAscending
        }
    }
}

private struct SoftwareLibraryRow: View {
    let item: SoftwareListItem
    let baselineAvailable: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                SoftwareArtwork(item: item, tint: kindColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.libraryDisplayName)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Image(systemName: item.kind.symbol)
                        Text(sourceLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let version = displayVersion {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Version")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(version)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 190, alignment: .trailing)
                }

                SoftwareStateBadge(label: status.label, color: status.color)

                Image(systemName: isSelected ? "sidebar.right" : "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? kindColor : Color.secondary.opacity(0.5))
                    .frame(width: 18)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? kindColor.opacity(0.12) : isHovered ? Color.primary.opacity(0.045) : Color.clear
        )
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(item.libraryDisplayName), \(status.label)")
        .accessibilityHint("Show software details")
    }

    private var status: (label: String, color: Color) {
        if item.kind == .nix && !baselineAvailable {
            return item.isDesired ? ("Managed", OxidePalette.green) : ("Status unknown", .secondary)
        }
        if item.isDesired {
            return item.isInstalled ? ("Managed", OxidePalette.green) : ("Needs installation", OxidePalette.red)
        }
        return ("Installed separately", OxidePalette.amber)
    }

    private var kindColor: Color {
        switch item.kind {
        case .nix: .blue
        case .formula: .orange
        case .cask: .teal
        case .mas: .indigo
        }
    }

    private var sourceLabel: String {
        switch item.kind {
        case .nix: "Nix system package"
        case .formula: "Homebrew command-line tool"
        case .cask: "Homebrew application"
        case .mas: "Mac App Store"
        }
    }

    private var displayVersion: String? {
        item.desiredVersion ?? item.installedVersions.first
    }
}

private struct SoftwareArtwork: View {
    let item: SoftwareListItem
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let visual = InstalledApplicationCatalog.visual(for: item) {
                Image(nsImage: visual.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if item.kind == .cask || item.kind == .mas {
                    Text(String(item.libraryDisplayName.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: item.kind.symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Image(systemName: item.kind == .mas ? "apple.logo" : item.kind.symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 19, height: 19)
                .background(.white, in: Circle())
                .offset(x: 4, y: 4)
        }
        .frame(width: 42, height: 42)
        .shadow(color: tint.opacity(0.2), radius: 4, y: 2)
    }
}

private struct InstalledApplicationVisual {
    let name: String
    let icon: NSImage
}

private enum InstalledApplicationCatalog {
    private struct ApplicationBundle {
        let name: String
        let path: String
    }

    private static let aliases = [
        "codexapp": "codex",
        "dockerdesktop": "docker",
        "github": "githubdesktop",
        "iawriter": "iawriter",
        "microsoftteams": "microsoftteams",
        "pdfexpert": "pdfexpert",
        "wiresharkapp": "wireshark"
    ]

    private static let commandOnlyCasks = Set(["1password-cli", "claude-code", "codex"])

    private static let bundles: [String: ApplicationBundle] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        var discovered: [String: ApplicationBundle] = [:]

        for root in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                let name = url.deletingPathExtension().lastPathComponent
                discovered[normalize(name)] = ApplicationBundle(name: name, path: url.path)
            }
        }

        return discovered
    }()

    static func visual(for item: SoftwareListItem) -> InstalledApplicationVisual? {
        guard item.kind == .cask || item.kind == .mas else { return nil }
        guard !commandOnlyCasks.contains(item.name.lowercased()) else { return nil }
        let normalizedNames = [item.displayName, item.name].map(normalize)

        for name in normalizedNames {
            let lookup = aliases[name] ?? name
            guard let bundle = bundles[lookup] else { continue }
            return InstalledApplicationVisual(
                name: bundle.name,
                icon: NSWorkspace.shared.icon(forFile: bundle.path)
            )
        }

        return nil
    }

    private static func normalize(_ value: String) -> String {
        String(value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
}

private extension SoftwareListItem {
    var libraryDisplayName: String {
        let preferredNames = [
            "bambu-studio": "Bambu Studio",
            "codex": "Codex CLI",
            "codex-app": "Codex",
            "hiddenbar": "Hidden Bar",
            "openscad": "OpenSCAD",
            "wireshark-app": "Wireshark"
        ]
        if let preferredName = preferredNames[name.lowercased()] {
            return preferredName
        }
        if let visual = InstalledApplicationCatalog.visual(for: self) {
            return visual.name
        }
        guard kind == .cask else { return displayName }

        let knownTerms = [
            "ai": "AI",
            "api": "API",
            "cli": "CLI",
            "github": "GitHub",
            "iterm2": "iTerm2",
            "macos": "macOS",
            "obs": "OBS",
            "pdf": "PDF",
            "ssh": "SSH",
            "vpn": "VPN",
            "vscode": "VS Code",
            "xcode": "Xcode",
            "1password": "1Password"
        ]
        return displayName
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { word in
                let value = String(word)
                return knownTerms[value.lowercased()] ?? value.capitalized
            }
            .joined(separator: " ")
    }
}

private struct SoftwareStateBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct ConfigurationChangesView: View {
    let snapshot: ManagementSnapshot
    let isApplying: Bool
    let applyOperation: ApplyOperationState?
    let loadDetails: (SoftwareListItem) async throws -> PackageDetails
    let applyConfiguration: () -> Void
    let retryApply: () -> Void
    let dismissApplyOperation: () -> Void
    let copyApplyDiagnostics: () -> Void
    @State private var selectedItem: SoftwareListItem?
    @State private var details: PackageDetails?
    @State private var detailsError: String?
    @State private var isLoadingDetails = false
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            ChangeSummaryHeader(
                snapshot: snapshot,
                isApplying: isApplying,
                applyConfiguration: applyConfiguration
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let applyOperation {
                        ApplyOperationCard(
                            operation: applyOperation,
                            retry: retryApply,
                            dismiss: dismissApplyOperation,
                            copyDiagnostics: copyApplyDiagnostics
                        )
                    }
                    ConfigurationComparisonCard(snapshot: snapshot)
                    ConfigurationImpactCard(snapshot: snapshot)

                    if let changes = snapshot.configuration.changes,
                       !filteredFiles.isEmpty {
                        ChangedConfigurationFilesCard(
                            files: filteredFiles,
                            isComplete: changes.filesComplete
                        )
                    }

                    if snapshot.softwareDifferences.isEmpty {
                        NoSoftwareSelectionChangesCard()
                    } else {
                        ForEach(SoftwareChangeKind.allCases, id: \.self) { change in
                            DifferenceSection(
                                change: change,
                                differences: filteredDifferences.filter { $0.change == change },
                                item: { item(for: $0) },
                                select: { selectedItem = $0 }
                            )
                        }
                    }

                    if !query.isEmpty,
                       filteredDifferences.isEmpty,
                       filteredFiles.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Pending Changes")
        .searchable(text: $query, placement: .toolbar, prompt: "Search pending changes")
        .inspector(isPresented: Binding(
            get: { selectedItem != nil },
            set: { if !$0 { selectedItem = nil } }
        )) {
            PackageDetailsPanel(
                item: selectedItem,
                details: details,
                error: detailsError,
                isLoading: isLoadingDetails,
                baselineAvailable: snapshot.configuration.applyState != "unknown"
            )
                .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }
        .task(id: selectedItem?.id) {
            details = nil
            detailsError = nil
            guard let selectedItem else { return }
            isLoadingDetails = true
            do {
                details = try await loadDetails(selectedItem)
            } catch {
                detailsError = error.localizedDescription
            }
            isLoadingDetails = false
        }
    }

    private var filteredDifferences: [SoftwareDifference] {
        guard !query.isEmpty else { return snapshot.softwareDifferences }
        return snapshot.softwareDifferences.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.kind.label.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredFiles: [ConfigurationChangedFile] {
        let files = snapshot.configuration.changes?.files ?? []
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.path.localizedCaseInsensitiveContains(query)
                || $0.statusLabel.localizedCaseInsensitiveContains(query)
        }
    }

    private func item(for difference: SoftwareDifference) -> SoftwareListItem {
        let id = "\(difference.kind.rawValue):\(difference.name)"
        if let item = snapshot.desiredSoftwareItems.first(where: { $0.id == id })
            ?? snapshot.installedSoftwareItems.first(where: { $0.id == id }) {
            return item
        }
        return SoftwareListItem(
            kind: difference.kind,
            name: difference.name,
            displayName: difference.name,
            desiredVersion: difference.desiredVersion,
            appliedVersion: difference.appliedVersion,
            installedVersions: [],
            storeId: difference.storeId,
            embeddedDetails: nil,
            isDesired: difference.change != .removed,
            isApplied: difference.change != .added
        )
    }
}

private struct ApplyOperationCard: View {
    let operation: ApplyOperationState
    let retry: () -> Void
    let dismiss: () -> Void
    let copyDiagnostics: () -> Void
    @State private var showsDiagnostics = false

    var body: some View {
        SectionCard(title: title, symbol: symbol) {
            HStack(alignment: .top, spacing: 14) {
                statusIcon
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(operation.message)
                        .font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedLabel(at: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if operation.isRunning {
                    Text("Step \(operation.phase.order + 1) of \(ApplyActionPhase.allCases.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if operation.isRunning {
                ProgressView(
                    value: Double(operation.phase.order),
                    total: Double(ApplyActionPhase.allCases.count)
                )
                .progressViewStyle(.linear)
            }

            VStack(spacing: 0) {
                ForEach(ApplyActionPhase.allCases) { phase in
                    applyStep(phase)
                    if phase != ApplyActionPhase.allCases.last { Divider() }
                }
            }

            if operation.status == .failed, let diagnostics = operation.diagnostics {
                DisclosureGroup("Diagnostic details", isExpanded: $showsDiagnostics) {
                    ScrollView {
                        Text(diagnostics)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 220)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 8)
                }
            }

            if !operation.isRunning {
                HStack {
                    if operation.status == .failed {
                        Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                            .buttonStyle(.borderedProminent)
                        Button("Copy Diagnostics", systemImage: "doc.on.doc", action: copyDiagnostics)
                    }
                    Spacer()
                    Button("Dismiss", action: dismiss)
                }
            }
        }
    }

    private var title: String {
        switch operation.status {
        case .running: "Applying configuration"
        case .succeeded: "Configuration applied"
        case .failed: "Apply stopped"
        }
    }

    private var symbol: String {
        switch operation.status {
        case .running: "gearshape.2.fill"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch operation.status {
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private func applyStep(_ phase: ApplyActionPhase) -> some View {
        HStack(spacing: 12) {
            stepIcon(for: phase)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(phase.title)
                    .fontWeight(phase == operation.phase ? .semibold : .regular)
                if phase == operation.phase {
                    Text(stepDetail(for: phase))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func stepIcon(for phase: ApplyActionPhase) -> some View {
        if operation.status == .succeeded || phase.order < operation.phase.order {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if phase == operation.phase, operation.status == .failed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if phase == operation.phase, operation.status == .running {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    private func stepDetail(for phase: ApplyActionPhase) -> String {
        if operation.status == .failed { return "Stopped here. Expand diagnostics below for the full output." }
        if operation.status == .succeeded { return "Verified against the running system." }
        if phase == .building { return "Nix evaluation and builds can take several minutes; elapsed time remains visible above." }
        return operation.message
    }

    private func elapsedLabel(at date: Date) -> String {
        let end = operation.finishedAt ?? date
        let elapsed = max(0, Int(end.timeIntervalSince(operation.startedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let duration = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        return operation.isRunning ? "Running for \(duration)" : "Finished after \(duration)"
    }
}

private struct ChangeSummaryHeader: View {
    let snapshot: ManagementSnapshot
    let isApplying: Bool
    let applyConfiguration: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: snapshot.configuration.applyState == "current" ? "checkmark.circle.fill" : "arrow.left.arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(snapshot.configuration.applyState == "current" ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle).font(.headline)
                Text(statusDetail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if snapshot.configuration.applyState != "current" {
                if isApplying {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Build & Apply", action: applyConfiguration)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var statusTitle: String {
        switch snapshot.configuration.applyState {
        case "current": "This Mac matches the desired configuration"
        case "pending": "Review what will change on this Mac"
        default: "Create this Mac's active baseline"
        }
    }

    private var statusDetail: String {
        switch snapshot.configuration.applyState {
        case "current":
            return "The latest successful build uses the current checkout."
        case "pending":
            return "Build a new macOS generation from the desired checkout, then activate it."
        default:
            return "Build once to record which repository state is active on this Mac."
        }
    }
}

private struct ConfigurationComparisonCard: View {
    let snapshot: ManagementSnapshot

    var body: some View {
        SectionCard(title: "Desired vs active", symbol: "arrow.left.arrow.right") {
            HStack(alignment: .top, spacing: 22) {
                ConfigurationSide(
                    title: "Desired configuration",
                    badge: "Will be built",
                    symbol: "doc.text.fill",
                    primary: snapshot.configuration.path,
                    secondary: sourceDescription(snapshot.configuration.desiredSource),
                    tint: .blue
                )

                Image(systemName: "arrow.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 26)

                ConfigurationSide(
                    title: "Active on this Mac",
                    badge: snapshot.configuration.generation.map { "Generation \($0)" } ?? "No baseline",
                    symbol: "desktopcomputer",
                    primary: snapshot.configuration.appliedManifestPath,
                    secondary: sourceDescription(snapshot.configuration.appliedSource),
                    tint: snapshot.configuration.applyState == "current" ? .green : .orange
                )
            }

            Divider()

            Text("The desired configuration is the repository checkout Nix Me reads. The active configuration is the last generation successfully built and activated on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceDescription(_ source: SourceInfo?) -> String {
        guard let source else { return "Source revision unavailable" }
        let revision = source.revision == "unknown" ? "Unknown revision" : String(source.revision.prefix(12))
        return source.dirty ? "\(revision) · includes uncommitted files" : revision
    }
}

private struct ConfigurationSide: View {
    let title: String
    let badge: String
    let symbol: String
    let primary: String
    let secondary: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.headline)
                Spacer(minLength: 8)
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12), in: Capsule())
            }
            Text(primary)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(primary)
            Text(secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConfigurationImpactCard: View {
    let snapshot: ManagementSnapshot

    var body: some View {
        SectionCard(title: "What Build & Apply affects", symbol: "list.bullet.clipboard.fill") {
            if impacts.isEmpty {
                Label(noImpactMessage, systemImage: noImpactSymbol)
                    .foregroundStyle(snapshot.configuration.applyState == "current" ? .green : .secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(impacts.enumerated()), id: \.element.id) { index, impact in
                        ChangeImpactRow(impact: impact)
                        if index < impacts.count - 1 { Divider() }
                    }
                }
            }

            if snapshot.configuration.applyState == "pending",
               snapshot.configuration.changes == nil {
                Label(
                    "A detailed breakdown is unavailable from the installed management API. The source revisions below still show why an apply is required.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var impacts: [ConfigurationImpact] {
        guard snapshot.configuration.applyState == "pending" else { return [] }
        guard let changes = snapshot.configuration.changes else {
            return [ConfigurationImpact(
                id: "repository",
                title: "Repository configuration",
                detail: "The desired checkout differs from the active generation.",
                symbol: "doc.badge.ellipsis",
                tint: .orange
            )]
        }

        var values: [ConfigurationImpact] = []
        if changes.softwareChanged || !snapshot.softwareDifferences.isEmpty {
            let count = snapshot.softwareDifferences.count
            values.append(ConfigurationImpact(
                id: "software",
                title: "Managed software",
                detail: count > 0
                    ? "\(count) package selection or version change\(count == 1 ? "" : "s")."
                    : "The evaluated software selection changed.",
                symbol: "shippingbox.fill",
                tint: .blue
            ))
        }
        if changes.projectsChanged {
            values.append(ConfigurationImpact(
                id: "projects",
                title: "Project definitions",
                detail: "The repositories selected for this Mac changed.",
                symbol: "folder.fill.badge.gearshape",
                tint: .pink
            ))
        }
        if changes.appSettingsChanged {
            values.append(ConfigurationImpact(
                id: "app-settings",
                title: "Managed app settings",
                detail: "Application-state enablement, profiles, or settings sources changed.",
                symbol: "switch.2",
                tint: .teal
            ))
        }
        if changes.flakeInputsChanged {
            values.append(ConfigurationImpact(
                id: "flake-inputs",
                title: "Nix dependencies",
                detail: "One or more pinned flake inputs changed.",
                symbol: "link.badge.plus",
                tint: .purple
            ))
        }
        if changes.repositoryChanged {
            let detail: String
            if changes.filesComplete {
                detail = "\(changes.files.count) repository file\(changes.files.count == 1 ? "" : "s") differ from the active generation."
            } else {
                detail = "Repository content differs; an exact file list cannot be reconstructed from the last apply."
            }
            values.append(ConfigurationImpact(
                id: "repository",
                title: "Configuration repository",
                detail: detail,
                symbol: "doc.on.doc.fill",
                tint: .orange
            ))
        }
        return values
    }

    private var noImpactMessage: String {
        snapshot.configuration.applyState == "current"
            ? "Nothing is pending. The desired checkout is active on this Mac."
            : "The first build will establish the active baseline for this Mac."
    }

    private var noImpactSymbol: String {
        snapshot.configuration.applyState == "current" ? "checkmark.circle.fill" : "record.circle"
    }
}

private struct ConfigurationImpact: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
}

private struct ChangeImpactRow: View {
    let impact: ConfigurationImpact

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: impact.symbol)
                .foregroundStyle(impact.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(impact.title).fontWeight(.semibold)
                Text(impact.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct ChangedConfigurationFilesCard: View {
    let files: [ConfigurationChangedFile]
    let isComplete: Bool
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        SectionCard(title: "Changed files · \(files.count)", symbol: "doc.text.magnifyingglass") {
            Text(isComplete
                ? "Files that differ from the clean revision used by the active generation."
                : "Current checkout evidence. The last apply included uncommitted files, so some entries may already be active.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(groups) { group in
                    DisclosureGroup(isExpanded: expansionBinding(for: group.id)) {
                        VStack(spacing: 0) {
                            ForEach(group.files) { file in
                                HStack(spacing: 12) {
                                    Text(file.statusLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(statusColor(file))
                                        .frame(width: 64, alignment: .leading)
                                    Text(file.path)
                                        .font(.callout.monospaced())
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                if file.id != group.files.last?.id { Divider() }
                            }
                        }
                        .padding(.leading, 28)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: group.symbol)
                                .foregroundStyle(group.tint)
                                .frame(width: 22)
                            Text(group.title).fontWeight(.semibold)
                            Spacer()
                            Text("\(group.files.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    if group.id != groups.last?.id { Divider() }
                }
            }
        }
    }

    private var groups: [ChangedFileGroup] {
        Dictionary(grouping: files, by: ChangedFileGroup.category(for:))
            .map { category, files in
                ChangedFileGroup(category: category, files: files.sorted { $0.path < $1.path })
            }
            .sorted { $0.category.rawValue < $1.category.rawValue }
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(id) },
            set: { expanded in
                if expanded { expandedGroups.insert(id) }
                else { expandedGroups.remove(id) }
            }
        )
    }

    private func statusColor(_ file: ConfigurationChangedFile) -> Color {
        switch file.status.first {
        case "A": .green
        case "D": .red
        default: .orange
        }
    }
}

private struct ChangedFileGroup: Identifiable {
    enum Category: Int, Hashable {
        case systemConfiguration
        case appSettings
        case projects
        case management
        case macApp
        case automation
        case documentation
        case other
    }

    let category: Category
    let files: [ConfigurationChangedFile]

    var id: String { title }

    var title: String {
        switch category {
        case .systemConfiguration: "System configuration"
        case .appSettings: "Application settings harness"
        case .projects: "Project configuration"
        case .management: "Management API and CLI"
        case .macApp: "macOS app"
        case .automation: "Build and release automation"
        case .documentation: "Documentation"
        case .other: "Other repository files"
        }
    }

    var symbol: String {
        switch category {
        case .systemConfiguration: "gearshape.2.fill"
        case .appSettings: "switch.2"
        case .projects: "folder.fill"
        case .management: "terminal.fill"
        case .macApp: "macwindow"
        case .automation: "hammer.fill"
        case .documentation: "book.closed.fill"
        case .other: "doc.fill"
        }
    }

    var tint: Color {
        switch category {
        case .systemConfiguration: .orange
        case .appSettings: .teal
        case .projects: .pink
        case .management: .indigo
        case .macApp: .blue
        case .automation: .purple
        case .documentation: .secondary
        case .other: .secondary
        }
    }

    static func category(for file: ConfigurationChangedFile) -> Category {
        let path = file.path
        if path == "flake.nix" || path == "flake.lock" || path == "Makefile" || path.hasPrefix("nix/") {
            return .systemConfiguration
        }
        if path.hasPrefix("config/app-state/") || path.hasPrefix("packages/app-state/") {
            return .appSettings
        }
        if path.hasPrefix("config/projects/") || path.hasPrefix("projects/") {
            return .projects
        }
        if path.hasPrefix("packages/management-api/") || path.hasPrefix("apps/cli/") {
            return .management
        }
        if path.hasPrefix("apps/macos/") {
            return .macApp
        }
        if path.hasPrefix(".github/") || path.hasPrefix("tools/") || path.hasPrefix("tests/") {
            return .automation
        }
        if path.hasPrefix("docs/") || path.hasSuffix("README.md") || path == "README.md" {
            return .documentation
        }
        return .other
    }
}

private struct NoSoftwareSelectionChangesCard: View {
    var body: some View {
        SectionCard(title: "Managed software", symbol: "shippingbox.fill") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No package-selection changes")
                        .fontWeight(.semibold)
                    Text("Build & Apply will not add, remove, or switch versions in the managed software list. Available package upgrades are reviewed separately under Updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

private struct DifferenceSection: View {
    let change: SoftwareChangeKind
    let differences: [SoftwareDifference]
    let item: (SoftwareDifference) -> SoftwareListItem
    let select: (SoftwareListItem) -> Void

    var body: some View {
        if !differences.isEmpty {
            SectionCard(title: "\(change.rawValue) · \(differences.count)", symbol: changeSymbol) {
                ForEach(differences) { difference in
                    let software = item(difference)
                    Button {
                        select(software)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: difference.kind.symbol)
                                .foregroundStyle(changeColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(difference.name).font(.headline)
                                Text(difference.kind.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            differenceValue(difference)
                            StatusBadge(label: change.rawValue, color: changeColor, symbol: changeSymbol)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func differenceValue(_ difference: SoftwareDifference) -> some View {
        if difference.change == .versionChanged {
            Text(difference.appliedVersion ?? "Unknown")
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
            Text(difference.desiredVersion ?? "Latest")
                .fontWeight(.medium)
        }
    }

    private var changeColor: Color {
        switch change {
        case .versionChanged: .orange
        case .added: .green
        case .removed: .red
        }
    }

    private var changeSymbol: String {
        switch change {
        case .versionChanged: "arrow.left.arrow.right"
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        }
    }
}

private struct PackageDetailsPanel: View {
    let item: SoftwareListItem?
    let details: PackageDetails?
    let error: String?
    let isLoading: Bool
    let baselineAvailable: Bool

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        SoftwareArtwork(item: item, tint: tint(for: item.kind))
                        Text(item.libraryDisplayName)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                        Text(item.kind.label)
                            .foregroundStyle(.secondary)
                    }

                    if isLoading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading package details…").foregroundStyle(.secondary)
                        }
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else if let details {
                        if let description = details.description, !description.isEmpty {
                            Text(description)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        } else {
                            Text("No package description is available.")
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                        VStack(spacing: 10) {
                            InspectorRow(label: "Repository", value: item.desiredVersion ?? (item.isDesired ? "Managed" : "Not managed"))
                            InspectorRow(label: "On this Mac", value: machineVersion(item))
                            InspectorRow(label: "Latest", value: details.version ?? "Unavailable")
                            if let license = details.license, !license.isEmpty {
                                InspectorRow(label: "License", value: license)
                            }
                            if let publisher = details.publisher, !publisher.isEmpty {
                                InspectorRow(label: "Publisher", value: publisher)
                            }
                            if let storeId = details.storeId ?? item.storeId {
                                InspectorRow(label: "Store ID", value: String(storeId))
                            }
                        }

                        Divider()
                        PackageDeclarationChain(
                            item: item,
                            declarations: details.declarationChain ?? []
                        )

                        if !details.dependencies.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Dependencies").font(.headline)
                                Text(details.dependencies.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if let homepage = details.homepage, let url = URL(string: homepage) {
                            Divider()
                            Link("Open Package Homepage", destination: url)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func machineVersion(_ item: SoftwareListItem) -> String {
        if let version = item.appliedVersion ?? item.installedVersions.first {
            return version
        }
        if item.kind == .nix && !baselineAvailable {
            return "Baseline unavailable"
        }
        return item.isInstalled ? "Installed" : "Not installed"
    }

    private func tint(for kind: SoftwareKind) -> Color {
        switch kind {
        case .nix: .blue
        case .formula: .orange
        case .cask: .teal
        case .mas: .indigo
        }
    }
}

private struct PackageDeclarationChain: View {
    let item: SoftwareListItem
    let declarations: [PackageDeclaration]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Configuration chain", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            if declarations.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.isDesired ? "Declaration source unavailable" : "Not declared by this configuration")
                            .fontWeight(.medium)
                        Text(item.isDesired
                            ? "Nix Me could not trace this managed item to a configuration file."
                            : "This item is installed on the Mac but is not part of the active Nix Me configuration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: item.isDesired ? "questionmark.circle" : "externaldrive.badge.questionmark")
                        .foregroundStyle(item.isDesired ? .orange : .secondary)
                }
            } else {
                Text("Declaration sources, ordered from the broadest layer to the most specific.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(declarations.enumerated()), id: \.element.id) { index, declaration in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(declarationTint(declaration.scope).opacity(0.16))
                            Text(String(index + 1))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(declarationTint(declaration.scope))
                        }
                        .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(declaration.label)
                                .fontWeight(.medium)
                            Text(declaration.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if let declaredAs = declaration.declaredAs,
                               declaredAs != item.name {
                                Text("Declared as \(declaredAs)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func declarationTint(_ scope: String) -> Color {
        switch scope {
        case "base": .blue
        case "module": .teal
        case "machineType": .purple
        case "profile": .orange
        case "machine": .green
        default: .secondary
        }
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct ConfigurationDriftCard: View {
    let snapshot: ManagementSnapshot
    let isApplying: Bool
    let reviewChanges: () -> Void
    let applyConfiguration: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isApplying {
                ProgressView().controlSize(.small)
            } else if snapshot.configuration.applyState == "unknown" {
                Button("Establish Baseline", action: applyConfiguration)
                    .buttonStyle(.borderedProminent)
            } else if snapshot.configuration.applyState == "pending" {
                if snapshot.softwareDifferences.isEmpty {
                    Button("Apply", action: applyConfiguration)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Review Changes", action: reviewChanges)
                        .buttonStyle(.bordered)
                    Button("Apply", action: applyConfiguration)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(18)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var title: String {
        switch snapshot.configuration.applyState {
        case "current": "Repository and this Mac match"
        case "pending": "Repository differs from this Mac"
        default: "Machine baseline is not available"
        }
    }

    private var summary: String {
        guard snapshot.configuration.applyState != "unknown" else {
            return "Apply once to record the configuration currently active on this Mac."
        }
        let differences = snapshot.softwareDifferences
        guard !differences.isEmpty else {
            return snapshot.configuration.applyState == "current"
                ? "The desired configuration is active."
                : "Configuration files or project settings changed; no software list entries changed."
        }
        let changed = differences.filter { $0.change == .versionChanged }.count
        let added = differences.filter { $0.change == .added }.count
        let removed = differences.filter { $0.change == .removed }.count
        return [
            changed > 0 ? "\(changed) version change\(changed == 1 ? "" : "s")" : nil,
            added > 0 ? "\(added) added" : nil,
            removed > 0 ? "\(removed) removed" : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var tint: Color {
        switch snapshot.configuration.applyState {
        case "current": .green
        case "pending": .orange
        default: .secondary
        }
    }

    private var symbol: String {
        switch snapshot.configuration.applyState {
        case "current": "checkmark.seal.fill"
        case "pending": "arrow.left.arrow.right.circle.fill"
        default: "questionmark.circle.fill"
        }
    }
}

private struct ProjectsView: View {
    let snapshot: ManagementSnapshot
    @Binding var filter: ProjectFilter
    let isSyncing: Bool
    let isSavingProject: Bool
    let activeProfiles: [String]
    let openProject: (Project) -> Void
    let syncProjects: () -> Void
    let previewProject: (ProjectConfigurationInput) async throws -> ProjectConfigurationResponse
    let saveProject: (ProjectConfigurationInput) async throws -> ProjectConfigurationResponse
    @State private var showingAddProject = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Projects", selection: $filter) {
                    ForEach(ProjectFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                Button("Add Project", systemImage: "plus") {
                    showingAddProject = true
                }
                .disabled(isSyncing || isSavingProject)

                if isSyncing {
                    ProgressView().controlSize(.small)
                    Text("Syncing…").foregroundStyle(.secondary)
                } else {
                    Button("Sync Projects", systemImage: "arrow.triangle.2.circlepath", action: syncProjects)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            if filteredProjects.isEmpty {
                ContentUnavailableView(
                    filter == .attention ? "No projects need attention" : "No projects configured",
                    systemImage: filter == .attention ? "checkmark.circle" : "folder",
                    description: Text(filter == .attention
                        ? "All configured repositories are current."
                        : "Add a repository to this machine, a profile, or every machine.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredProjects) { project in
                    HStack(spacing: 14) {
                        Image(systemName: project.present ? "folder.fill" : "folder.badge.questionmark")
                            .font(.title2)
                            .foregroundStyle(project.present ? Color.accentColor : .orange)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name).font(.headline)
                            Text(projectDetails(project))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(project.absolutePath)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        StatusBadge(label: projectStatus(project), color: projectColor(project), symbol: projectSymbol(project))
                        if project.present {
                            Button("Open") { openProject(project) }
                        } else {
                            Text("Sync to clone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("Projects")
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet(
                hostname: snapshot.host.hostname,
                activeProfiles: activeProfiles,
                previewProject: previewProject,
                saveProject: saveProject
            )
        }
    }

    private var filteredProjects: [Project] {
        switch filter {
        case .all: snapshot.projects
        case .attention: snapshot.projects.filter { $0.status != "current" }
        }
    }

    private func projectDetails(_ project: Project) -> String {
        guard let git = project.git else {
            return project.present ? "Not a Git repository" : "Repository has not been cloned"
        }
        let branch = git.branch ?? "detached HEAD"
        if git.ahead > 0 || git.behind > 0 {
            return "\(branch) · \(git.ahead) ahead · \(git.behind) behind"
        }
        return branch
    }

    private func projectStatus(_ project: Project) -> String {
        switch project.status {
        case "current": "Current"
        case "missing": "Not cloned"
        case "changes": "Local changes"
        case "ahead": "Ahead"
        case "behind": "Behind"
        case "diverged": "Diverged"
        case "noUpstream": "No upstream"
        default: "Check repository"
        }
    }

    private func projectColor(_ project: Project) -> Color {
        project.status == "current" ? .green : .orange
    }

    private func projectSymbol(_ project: Project) -> String {
        project.status == "current" ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }
}

private struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let hostname: String
    let activeProfiles: [String]
    let previewProject: (ProjectConfigurationInput) async throws -> ProjectConfigurationResponse
    let saveProject: (ProjectConfigurationInput) async throws -> ProjectConfigurationResponse

    @State private var project = ProjectConfigurationInput()
    @State private var preview: ProjectConfigurationResponse?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview == nil ? "Add a project" : "Review project")
                        .font(.title2.bold())
                    Text("Save a repository declaration now. Cloning happens only when you run Sync Projects.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    projectDetails
                    projectScope
                    projectOptions

                    if let preview {
                        review(preview)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                if preview == nil {
                    Button("Review Project") { reviewProject() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canReview || isWorking)
                } else {
                    Button("Back") {
                        preview = nil
                        errorMessage = nil
                    }
                    .disabled(isWorking)
                    Button(preview?.replaced == true ? "Update Configuration" : "Add to Configuration") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
                }
            }
            .padding(20)
        }
        .frame(width: 680, height: preview == nil ? 650 : 760)
        .onAppear {
            if project.profile == nil {
                project.profile = activeProfiles.sorted().first
            }
        }
        .onChange(of: project) { _, _ in
            preview = nil
            errorMessage = nil
        }
    }

    private var projectDetails: some View {
        GroupBox("Repository") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Git URL")
                    TextField("https://github.com/owner/repository.git", text: $project.url)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Color.clear.frame(width: 90, height: 1)
                    HStack {
                        Button("Use URL Defaults", systemImage: "wand.and.stars") {
                            applyURLDefaults()
                        }
                        .disabled(repositoryCoordinates == nil)
                        Text("Fills the project name and local folder from the URL.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Name")
                    TextField("repository", text: $project.name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Local folder")
                    TextField("src/owner/repository", text: $project.path)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Branch")
                    TextField("Default branch", text: $project.branch)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(10)
        }
    }

    private var projectScope: some View {
        GroupBox("Configuration scope") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Scope", selection: $project.scope) {
                    ForEach(ProjectConfigurationScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if project.scope == .profile {
                    if activeProfiles.isEmpty {
                        Label("No active profiles were found for this Mac.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Picker("Profile", selection: profileSelection) {
                            ForEach(activeProfiles.sorted(), id: \.self) { profile in
                                Text(profile).tag(profile)
                            }
                        }
                        .frame(maxWidth: 280)
                    }
                }

                Text(scopeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private var projectOptions: some View {
        GroupBox("Sync behavior") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Clone when the folder is missing", isOn: $project.clone)
                Toggle("Fetch and fast-forward when the repository exists", isOn: $project.update)
                LabeledContent("Remote") {
                    TextField("origin", text: $project.remote)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }
            .padding(10)
        }
    }

    private func review(_ response: ProjectConfigurationResponse) -> some View {
        GroupBox("Configuration change") {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    response.replaced ? "Updates an existing project" : "Adds a new project",
                    systemImage: response.replaced ? "arrow.triangle.2.circlepath" : "plus.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(response.replaced ? .orange : .green)

                LabeledContent("File", value: response.destination)
                LabeledContent("Project", value: response.name)
                LabeledContent("Repository", value: response.project.url)
                LabeledContent("Local folder", value: "~/\(response.project.path)")
                if let branch = response.project.branch {
                    LabeledContent("Branch", value: branch)
                }

                DisclosureGroup("JSON preview") {
                    ScrollView(.horizontal) {
                        Text(response.preview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(10)
        }
    }

    private var profileSelection: Binding<String> {
        Binding(
            get: { project.profile ?? activeProfiles.sorted().first ?? "" },
            set: { project.profile = $0 }
        )
    }

    private var scopeExplanation: String {
        switch project.scope {
        case .shared:
            "Saved to shared.json and applied to every machine using this configuration."
        case .profile:
            "Saved under the selected profile and applied only when that profile is active."
        case .machine:
            "Saved for \(hostname) only."
        }
    }

    private var canReview: Bool {
        !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !project.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !project.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !project.remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (project.scope != .profile || project.profile?.isEmpty == false)
    }

    private var repositoryCoordinates: (owner: String, name: String)? {
        var value = project.url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }

        let repositoryPath: String
        if let url = URL(string: value), url.scheme != nil {
            repositoryPath = url.path
        } else if let colon = value.firstIndex(of: ":"), value[..<colon].contains("@") {
            repositoryPath = String(value[value.index(after: colon)...])
        } else {
            return nil
        }

        let components = repositoryPath.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        let owner = components[components.count - 2]
        let name = components[components.count - 1]
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        return (owner, name)
    }

    private func applyURLDefaults() {
        guard let coordinates = repositoryCoordinates else { return }
        project.name = slug(coordinates.name)
        project.path = "src/\(slug(coordinates.owner))/\(slug(coordinates.name))"
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func reviewProject() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                preview = try await previewProject(project)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func save() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                _ = try await saveProject(project)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}

private enum ProjectFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case attention = "Needs Attention"

    var id: String { rawValue }
}

private struct UpdatesView: View {
    let snapshot: ManagementSnapshot
    @Binding var selectedUpdateIDs: Set<String>
    let isUpdating: Bool
    let isApplying: Bool
    let isRefreshing: Bool
    let updatingItemCount: Int
    let loadDetails: (SoftwareListItem) async throws -> PackageDetails
    let updateItems: ([SoftwareUpdate]) -> Void
    @State private var pendingBatch: [SoftwareUpdate] = []
    @State private var showingConfirmation = false
    @State private var query = ""
    @State private var selectedItem: SoftwareListItem?
    @State private var details: PackageDetails?
    @State private var detailsError: String?
    @State private var isLoadingDetails = false

    var body: some View {
        VStack(spacing: 0) {
            updateToolbar

            List {
                UpdateSection(title: "Nix inputs", symbol: "snowflake", updates: filtered(snapshot.updates.nixFlake), selectedUpdateIDs: $selectedUpdateIDs, actionsDisabled: actionsDisabled, inspect: inspect, updateOne: updateOne)
                UpdateSection(title: "Homebrew formulae", symbol: "terminal", updates: formulaUpdates, selectedUpdateIDs: $selectedUpdateIDs, actionsDisabled: actionsDisabled, inspect: inspect, updateOne: updateOne)
                UpdateSection(title: "Homebrew applications", symbol: "macwindow", updates: caskUpdates, selectedUpdateIDs: $selectedUpdateIDs, actionsDisabled: actionsDisabled, inspect: inspect, updateOne: updateOne)
                UpdateSection(title: "Mac App Store", symbol: "apple.logo", updates: filtered(snapshot.updates.macAppStore), selectedUpdateIDs: $selectedUpdateIDs, actionsDisabled: actionsDisabled, inspect: inspect, updateOne: updateOne)
            }
        }
        .navigationTitle("Updates")
        .searchable(text: $query, placement: .toolbar, prompt: "Search updates")
        .inspector(isPresented: Binding(
            get: { selectedItem != nil },
            set: { if !$0 { selectedItem = nil } }
        )) {
            PackageDetailsPanel(
                item: selectedItem,
                details: details,
                error: detailsError,
                isLoading: isLoadingDetails,
                baselineAvailable: snapshot.configuration.applyState != "unknown"
            )
            .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }
        .task(id: selectedItem?.id) {
            details = nil
            detailsError = nil
            guard let selectedItem else { return }
            isLoadingDetails = true
            do {
                details = try await loadDetails(selectedItem)
            } catch {
                detailsError = error.localizedDescription
            }
            isLoadingDetails = false
        }
        .overlay {
            if snapshot.updates.all.isEmpty {
                ContentUnavailableView(
                    "Everything is current",
                    systemImage: "checkmark.seal.fill",
                    description: Text("No Nix, Homebrew, or Mac App Store updates are currently available.")
                )
            } else if allUpdates.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .confirmationDialog(
            "Update \(pendingBatch.count) selected item\(pendingBatch.count == 1 ? "" : "s")?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Update \(pendingBatch.count) Item\(pendingBatch.count == 1 ? "" : "s")") {
                updateItems(pendingBatch)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Homebrew packages will be upgraded together. App Store updates may request administrator approval. Nix updates change flake.lock and require a later apply.")
        }
        .onChange(of: snapshot.updates.all.map(\.id)) { _, availableIDs in
            selectedUpdateIDs.formIntersection(Set(availableIDs))
        }
    }

    private var updateToolbar: some View {
        HStack(spacing: 10) {
            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                Text("Updating \(updatingItemCount) item\(updatingItemCount == 1 ? "" : "s")…")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(selectedVisibleIDs.count) selected")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(allVisibleSelected ? "Clear" : "Select All") {
                let visibleIDs = Set(allUpdates.map(\.id))
                if allVisibleSelected {
                    selectedUpdateIDs.subtract(visibleIDs)
                } else {
                    selectedUpdateIDs.formUnion(visibleIDs)
                }
            }
            .disabled(actionsDisabled || allUpdates.isEmpty)

            Button("Update Selected") {
                confirm(allUpdates.filter { selectedUpdateIDs.contains($0.id) })
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionsDisabled || selectedVisibleIDs.isEmpty)

            Button(query.isEmpty ? "Update All" : "Update Results") {
                confirm(allUpdates)
            }
            .disabled(actionsDisabled || allUpdates.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var allUpdates: [SoftwareUpdate] {
        filtered(snapshot.updates.all)
    }

    private var selectedVisibleIDs: Set<String> {
        selectedUpdateIDs.intersection(Set(allUpdates.map(\.id)))
    }

    private var allVisibleSelected: Bool {
        !allUpdates.isEmpty && selectedVisibleIDs.count == allUpdates.count
    }

    private var actionsDisabled: Bool {
        isUpdating || isApplying || isRefreshing
    }

    private var formulaUpdates: [SoftwareUpdate] {
        filtered(snapshot.updates.homebrew.filter { $0.kind == "formula" })
    }

    private var caskUpdates: [SoftwareUpdate] {
        filtered(snapshot.updates.homebrew.filter { $0.kind == "cask" })
    }

    private func updateOne(_ update: SoftwareUpdate) {
        updateItems([update])
    }

    private func confirm(_ updates: [SoftwareUpdate]) {
        pendingBatch = updates
        showingConfirmation = true
    }

    private func inspect(_ update: SoftwareUpdate) {
        guard let kind = SoftwareKind(rawValue: update.kind) else { return }
        let managed = switch kind {
        case .formula: snapshot.inventory.desired.homebrew.formulae.contains(update.name)
        case .cask: snapshot.inventory.desired.homebrew.casks.contains(update.name)
        case .mas: snapshot.inventory.desired.homebrew.masApps[update.name] != nil
        case .nix: true
        }
        selectedItem = SoftwareListItem(
            kind: kind,
            name: update.name,
            displayName: update.name,
            desiredVersion: nil,
            appliedVersion: nil,
            installedVersions: update.installedVersions,
            storeId: update.storeId,
            embeddedDetails: nil,
            isDesired: managed,
            isApplied: true
        )
    }

    private func filtered(_ updates: [SoftwareUpdate]) -> [SoftwareUpdate] {
        guard !query.isEmpty else { return updates }
        return updates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.kind.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct UpdateSection: View {
    let title: String
    let symbol: String
    let updates: [SoftwareUpdate]
    @Binding var selectedUpdateIDs: Set<String>
    let actionsDisabled: Bool
    let inspect: (SoftwareUpdate) -> Void
    let updateOne: (SoftwareUpdate) -> Void

    var body: some View {
        if !updates.isEmpty {
            Section("\(title) · \(updates.count)") {
                ForEach(updates) { update in
                    HStack(spacing: 14) {
                        Toggle("Select \(update.name)", isOn: selectionBinding(for: update))
                            .labelsHidden()
                            .disabled(actionsDisabled)
                        Image(systemName: symbol)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(update.name).font(.headline)
                            Text(updateSource(update))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(update.installedVersions.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                        Text(update.availableVersion ?? "Latest")
                            .fontWeight(.medium)
                            .frame(minWidth: 70, alignment: .leading)
                        if update.kind != "nixFlake" {
                            Button("Details", systemImage: "info.circle") { inspect(update) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .help("Show package details")
                        }
                        Button("Update") { updateOne(update) }
                            .disabled(actionsDisabled)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func selectionBinding(for update: SoftwareUpdate) -> Binding<Bool> {
        Binding(
            get: { selectedUpdateIDs.contains(update.id) },
            set: { selected in
                if selected {
                    selectedUpdateIDs.insert(update.id)
                } else {
                    selectedUpdateIDs.remove(update.id)
                }
            }
        )
    }

    private func updateSource(_ update: SoftwareUpdate) -> String {
        switch update.kind {
        case "nixFlake": "Pinned flake input"
        case "formula": "Homebrew formula"
        case "cask": "Homebrew application"
        case "mas": "Mac App Store application"
        default: update.kind
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: Int
    let symbol: String
    let tint: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(tint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isHovered ? tint : Color.secondary.opacity(0.45))
                }
                Text(value, format: .number)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                Text(title)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(OxidePalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? tint.opacity(0.1) : OxidePalette.panel.opacity(0.86))
        .overlay {
            Rectangle()
                .stroke(isHovered ? tint.opacity(0.62) : OxidePalette.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Open details")
    }
}

private struct HarnessMetricCard: View {
    let title: String
    let value: Int?
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            if let value {
                Text(value, format: .number)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
            } else {
                Text("Unavailable")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OxidePalette.secondary)
            }
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(OxidePalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(OxidePalette.panel.opacity(0.86))
        .overlay(Rectangle().stroke(OxidePalette.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value.map(String.init) ?? "unavailable")")
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(0.35)
                .foregroundStyle(OxidePalette.primary)
            Rectangle().fill(OxidePalette.border).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(OxidePalette.panel.opacity(0.84))
        .overlay(Rectangle().stroke(OxidePalette.border))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct HealthRow: View {
    let name: String
    let health: ToolHealth

    var body: some View {
        HStack {
            Label(name, systemImage: health.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(health.available ? .primary : .secondary)
            Spacer()
            Text(health.version ?? (health.available ? "Available" : "Unavailable"))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusBadge: View {
    let label: String
    let color: Color
    let symbol: String

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .overlay(Rectangle().stroke(color.opacity(0.32)))
    }
}

private struct ApplicationPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .overlay(Rectangle().stroke(color.opacity(0.28)))
    }
}
