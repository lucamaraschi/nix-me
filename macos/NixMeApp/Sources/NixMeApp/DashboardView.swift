import SwiftUI

private enum DashboardSection: String, Identifiable {
    case overview = "Overview"
    case managedSoftware = "Managed"
    case installedSoftware = "Installed"
    case configurationChanges = "Changes"
    case projects = "Projects"
    case updates = "Updates"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .managedSoftware: "shippingbox"
        case .installedSoftware: "internaldrive"
        case .configurationChanges: "arrow.left.arrow.right"
        case .projects: "folder"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @State private var selection: DashboardSection? = .overview
    @State private var projectFilter = ProjectFilter.all
    @State private var selectedUpdateIDs = Set<String>()
    @State private var showingApplyConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                SidebarRow(section: .overview)

                Section("Software") {
                    SidebarRow(section: .managedSoftware, count: store.snapshot?.desiredSoftwareCount)
                    SidebarRow(section: .installedSoftware, count: store.snapshot?.installedSoftwareItems.count)
                    SidebarRow(
                        section: .configurationChanges,
                        count: store.snapshot?.softwareDifferences.count,
                        needsAttention: store.snapshot.map { $0.configuration.applyState != "current" } ?? false
                    )
                }

                Section("Maintenance") {
                    SidebarRow(section: .projects, count: store.snapshot?.projectAttentionCount)
                    SidebarRow(section: .updates, count: store.snapshot?.softwareUpdateCount)
                }
            }
            .navigationTitle("Nix Me")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Group {
                if let snapshot = store.snapshot {
                    content(for: selection ?? .overview, snapshot: snapshot)
                } else if let errorMessage = store.errorMessage {
                    ContentUnavailableView(
                        "Configuration unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("Reading this Mac…")
                        .controlSize(.large)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Open Configuration", systemImage: "folder") {
                        store.openConfiguration()
                    }
                    .disabled(store.snapshot == nil)

                    if store.snapshot?.configuration.applyState != "current",
                       selection != .overview,
                       selection != .configurationChanges {
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
        .task { store.startMonitoring() }
        .alert(
            "Nix Me",
            isPresented: Binding(
                get: { store.updateNotice != nil },
                set: { if !$0 { store.clearUpdateNotice() } }
            )
        ) {
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
                Task { await store.applyConfiguration() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Nix will build and activate the current configuration. macOS will request administrator approval. Software update checks will be skipped.")
        }
    }

    private var actionInProgress: Bool {
        store.isLoading || store.isUpdating || store.isApplying || store.isSyncingProjects
    }

    @ViewBuilder
    private func content(for section: DashboardSection, snapshot: ManagementSnapshot) -> some View {
        switch section {
        case .overview:
            OverviewView(
                snapshot: snapshot,
                openManagedSoftware: {
                    selection = .managedSoftware
                },
                openInstalledSoftware: {
                    selection = .installedSoftware
                },
                openUpdates: {
                    selection = .updates
                },
                openProjectAttention: {
                    projectFilter = .attention
                    selection = .projects
                },
                openConfigurationChanges: {
                    selection = .configurationChanges
                },
                applyConfiguration: { showingApplyConfirmation = true },
                isApplying: store.isApplying
            )
        case .managedSoftware:
            SoftwareView(snapshot: snapshot, mode: .managed, loadDetails: store.packageDetails)
        case .installedSoftware:
            SoftwareView(snapshot: snapshot, mode: .installed, loadDetails: store.packageDetails)
        case .configurationChanges:
            ConfigurationChangesView(
                snapshot: snapshot,
                isApplying: store.isApplying,
                loadDetails: store.packageDetails,
                applyConfiguration: { showingApplyConfirmation = true }
            )
        case .projects:
            ProjectsView(
                snapshot: snapshot,
                filter: $projectFilter,
                isSyncing: store.isSyncingProjects,
                openProject: store.openProject,
                syncProjects: { Task { await store.syncProjects() } }
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

private struct SidebarRow: View {
    let section: DashboardSection
    var count: Int? = nil
    var needsAttention = false

    var body: some View {
        HStack {
            Label(section.rawValue, systemImage: section.symbol)
            Spacer()
            if let count, count > 0 {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            } else if needsAttention {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
            }
        }
        .tag(section)
    }
}

private struct OverviewView: View {
    let snapshot: ManagementSnapshot
    let openManagedSoftware: () -> Void
    let openInstalledSoftware: () -> Void
    let openUpdates: () -> Void
    let openProjectAttention: () -> Void
    let openConfigurationChanges: () -> Void
    let applyConfiguration: () -> Void
    let isApplying: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.host.machineName)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text("@\(snapshot.host.hostname) · generation \(snapshot.configuration.generation.map(String.init) ?? "unknown")")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(label: applyLabel, color: applyColor, symbol: applySymbol)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    MetricCard(title: "Managed software", value: snapshot.desiredSoftwareCount, symbol: "shippingbox.fill", tint: .blue, action: openManagedSoftware)
                    MetricCard(title: "Homebrew installed", value: snapshot.installedHomebrewCount, symbol: "mug.fill", tint: .orange, action: openInstalledSoftware)
                    MetricCard(title: "Available updates", value: snapshot.softwareUpdateCount, symbol: "arrow.down.circle.fill", tint: snapshot.softwareUpdateCount == 0 ? .green : .orange, action: openUpdates)
                    MetricCard(title: "Projects needing attention", value: snapshot.projectAttentionCount, symbol: "folder.badge.questionmark", tint: snapshot.projectAttentionCount == 0 ? .green : .orange, action: openProjectAttention)
                }

                ConfigurationDriftCard(
                    snapshot: snapshot,
                    isApplying: isApplying,
                    reviewChanges: openConfigurationChanges,
                    applyConfiguration: applyConfiguration
                )

                SectionCard(title: "Configuration", symbol: "slider.horizontal.3") {
                    DetailRow(label: "Apply state", value: applyLabel)
                    DetailRow(label: "Git branch", value: snapshot.configuration.git?.branch ?? "Unavailable")
                    DetailRow(label: "Remote", value: remoteSummary)
                    DetailRow(label: "Working tree", value: snapshot.configuration.git?.dirty == true ? "Uncommitted changes" : "Clean")
                    DetailRow(label: "Repository revision", value: shortRevision(snapshot.configuration.desiredSource?.revision))
                    DetailRow(label: "Machine revision", value: shortRevision(snapshot.configuration.appliedSource?.revision))
                    if let desiredLock = snapshot.configuration.desiredSource?.lockHash,
                       let appliedLock = snapshot.configuration.appliedSource?.lockHash,
                       desiredLock != appliedLock {
                        DetailRow(label: "Lock file", value: "Repository and machine differ")
                    }
                    DetailRow(label: "Location", value: snapshot.configuration.path)
                }

                SectionCard(title: "System services", symbol: "heart.text.square") {
                    HealthRow(name: "Nix", health: snapshot.health.nix)
                    HealthRow(name: "nix-darwin", health: snapshot.health.nixDarwin)
                    HealthRow(name: "Homebrew", health: snapshot.health.homebrew)
                }

                if !snapshot.warnings.isEmpty {
                    SectionCard(title: "Needs attention", symbol: "exclamationmark.triangle.fill") {
                        ForEach(snapshot.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Overview")
    }

    private var applyLabel: String {
        switch snapshot.configuration.applyState {
        case "current": "System is current"
        case "pending": "Changes need applying"
        default: "Baseline needed"
        }
    }

    private var applyColor: Color {
        switch snapshot.configuration.applyState {
        case "current": .green
        case "pending": .orange
        default: .orange
        }
    }

    private var applySymbol: String {
        snapshot.configuration.applyState == "current" ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
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

private struct SoftwareView: View {
    let snapshot: ManagementSnapshot
    let mode: SoftwareMode
    let loadDetails: (SoftwareListItem) async throws -> PackageDetails
    @State private var selectedItem: SoftwareListItem?
    @State private var details: PackageDetails?
    @State private var detailsError: String?
    @State private var isLoadingDetails = false
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItem) {
                ForEach(SoftwareKind.allCases, id: \.self) { kind in
                    SoftwareItemSection(
                        title: sectionTitle(kind),
                        items: filteredItems.filter { $0.kind == kind }
                    )
                }
            }
        }
        .navigationTitle(mode.title)
        .searchable(text: $query, placement: .toolbar, prompt: "Search software")
        .overlay {
            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: query)
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
        let items = mode == .managed ? snapshot.desiredSoftwareItems : snapshot.installedSoftwareItems
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.kind.label.localizedCaseInsensitiveContains(query)
        }
    }

    private func sectionTitle(_ kind: SoftwareKind) -> String {
        switch (mode, kind) {
        case (.managed, .nix): "Nix packages"
        case (.managed, .formula): "Homebrew formulae"
        case (.managed, .cask): "Applications"
        case (.managed, .mas): "Mac App Store"
        case (.installed, .nix): "Active Nix packages"
        case (.installed, .formula): "Installed Homebrew formulae"
        case (.installed, .cask): "Installed applications"
        case (.installed, .mas): "Mac App Store"
        }
    }
}

private enum SoftwareMode: String {
    case managed = "Managed"
    case installed = "Installed"

    var title: String { "\(rawValue) Software" }
}

private struct SoftwareItemSection: View {
    let title: String
    let items: [SoftwareListItem]

    var body: some View {
        if !items.isEmpty {
            Section {
                ForEach(items.sorted { $0.displayName < $1.displayName }) { item in
                    SoftwareItemRow(item: item)
                        .tag(item)
                }
            } header: {
                Text("\(title) · \(items.count)")
            }
        }
    }
}

private struct SoftwareItemRow: View {
    let item: SoftwareListItem

    var body: some View {
        HStack {
            Label(item.displayName, systemImage: item.kind.symbol)
            Spacer()
            if let version = item.desiredVersion ?? item.installedVersions.first {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "info.circle")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct ConfigurationChangesView: View {
    let snapshot: ManagementSnapshot
    let isApplying: Bool
    let loadDetails: (SoftwareListItem) async throws -> PackageDetails
    let applyConfiguration: () -> Void
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

            if snapshot.softwareDifferences.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    Text(emptyDescription)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedItem) {
                    ForEach(SoftwareChangeKind.allCases, id: \.self) { change in
                        DifferenceSection(
                            change: change,
                            differences: filteredDifferences.filter { $0.change == change },
                            item: { item(for: $0) }
                        )
                    }
                }
                .overlay {
                    if filteredDifferences.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
        .navigationTitle("Configuration Changes")
        .searchable(text: $query, placement: .toolbar, prompt: "Search changes")
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

    private var emptyTitle: String {
        switch snapshot.configuration.applyState {
        case "current": "This Mac matches the repository"
        case "unknown": "No machine baseline yet"
        default: "No software list changes"
        }
    }

    private var emptyDescription: String {
        switch snapshot.configuration.applyState {
        case "current": "The desired software configuration is active."
        case "unknown": "Apply once to record the configuration active on this Mac."
        default: "Other configuration or project settings changed and are ready to apply."
        }
    }

    private var emptySymbol: String {
        snapshot.configuration.applyState == "current" ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath"
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
                    Button("Apply Configuration", action: applyConfiguration)
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
        case "current": "Configuration is current"
        case "pending": "Changes are ready to apply"
        default: "Establish this Mac's baseline"
        }
    }

    private var statusDetail: String {
        let count = snapshot.softwareDifferences.count
        if count > 0 {
            return "\(count) software change\(count == 1 ? "" : "s") between the repository and this Mac"
        }
        return snapshot.configuration.applyState == "unknown"
            ? "The active configuration has not been recorded yet"
            : "No software package entries changed"
    }
}

private struct DifferenceSection: View {
    let change: SoftwareChangeKind
    let differences: [SoftwareDifference]
    let item: (SoftwareDifference) -> SoftwareListItem

    var body: some View {
        if !differences.isEmpty {
            Section("\(change.rawValue) · \(differences.count)") {
                ForEach(differences) { difference in
                    let software = item(difference)
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
                    }
                    .padding(.vertical, 4)
                    .tag(software)
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
                        Image(systemName: item.kind.symbol)
                            .font(.system(size: 34))
                            .foregroundStyle(Color.accentColor)
                        Text(details?.displayName ?? item.displayName)
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
        return item.isApplied ? "Applied" : "Not applied"
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
    let openProject: (Project) -> Void
    let syncProjects: () -> Void

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
        .navigationTitle("Projects")
        .overlay {
            if filteredProjects.isEmpty {
                ContentUnavailableView(
                    filter == .attention ? "No projects need attention" : "No projects configured",
                    systemImage: filter == .attention ? "checkmark.circle" : "folder"
                )
            }
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
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? tint.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovered ? tint.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Open details")
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }
}
