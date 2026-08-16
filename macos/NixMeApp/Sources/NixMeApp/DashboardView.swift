import SwiftUI

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case software = "Software"
    case projects = "Projects"
    case updates = "Updates"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .software: "shippingbox"
        case .projects: "folder"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @State private var selection: DashboardSection? = .overview
    @State private var softwareMode = SoftwareMode.managed
    @State private var projectFilter = ProjectFilter.all
    @State private var selectedUpdateIDs = Set<String>()
    @State private var showingApplyConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("nix-me")
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

                    if store.snapshot?.configuration.applyState != "current" {
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
            "Software Updates",
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
        store.isLoading || store.isUpdating || store.isApplying
    }

    @ViewBuilder
    private func content(for section: DashboardSection, snapshot: ManagementSnapshot) -> some View {
        switch section {
        case .overview:
            OverviewView(
                snapshot: snapshot,
                openManagedSoftware: {
                    softwareMode = .managed
                    selection = .software
                },
                openInstalledSoftware: {
                    softwareMode = .installed
                    selection = .software
                },
                openUpdates: {
                    selection = .updates
                },
                openProjectAttention: {
                    projectFilter = .attention
                    selection = .projects
                },
                openConfigurationChanges: {
                    softwareMode = .changes
                    selection = .software
                },
                applyConfiguration: { showingApplyConfirmation = true },
                isApplying: store.isApplying
            )
        case .software:
            SoftwareView(snapshot: snapshot, mode: $softwareMode, loadDetails: store.packageDetails)
        case .projects:
            ProjectsView(snapshot: snapshot, filter: $projectFilter, openProject: store.openProject)
        case .updates:
            UpdatesView(
                snapshot: snapshot,
                selectedUpdateIDs: $selectedUpdateIDs,
                isUpdating: store.isUpdating,
                isApplying: store.isApplying,
                isRefreshing: store.isLoading,
                updatingItemCount: store.updatingItemCount,
                updateItems: { updates in
                    Task { await store.updateSoftware(updates) }
                }
            )
        }
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
                    MetricCard(title: "Available updates", value: snapshot.softwareUpdateCount, symbol: "arrow.down.circle.fill", tint: .green, action: openUpdates)
                    MetricCard(title: "Projects needing attention", value: snapshot.projectAttentionCount, symbol: "folder.badge.questionmark", tint: .pink, action: openProjectAttention)
                }

                ConfigurationDriftCard(snapshot: snapshot, action: openConfigurationChanges)

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
                    if snapshot.configuration.applyState != "current" {
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Activate pending changes")
                                    .fontWeight(.medium)
                                Text("Build and switch to the current Nix configuration.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isApplying {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Applying…")
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Apply Configuration", action: applyConfiguration)
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
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
        default: "Apply state unknown"
        }
    }

    private var applyColor: Color {
        switch snapshot.configuration.applyState {
        case "current": .green
        case "pending": .orange
        default: .secondary
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
    @Binding var mode: SoftwareMode
    let loadDetails: (SoftwareListItem) async throws -> PackageDetails
    @State private var selectedItem: SoftwareListItem?
    @State private var details: PackageDetails?
    @State private var detailsError: String?
    @State private var isLoadingDetails = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inventory", selection: $mode) {
                ForEach(SoftwareMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding()

            List(selection: $selectedItem) {
                switch mode {
                case .managed:
                    ForEach(SoftwareKind.allCases, id: \.self) { kind in
                        SoftwareItemSection(title: managedTitle(kind), items: snapshot.desiredSoftwareItems.filter { $0.kind == kind })
                    }
                case .installed:
                    ForEach(SoftwareKind.allCases, id: \.self) { kind in
                        SoftwareItemSection(title: installedTitle(kind), items: snapshot.installedSoftwareItems.filter { $0.kind == kind })
                    }
                case .changes:
                    if snapshot.softwareDifferences.isEmpty {
                        Section {
                            ContentUnavailableView(
                                snapshot.configuration.applyState == "current" ? "Software matches this Mac" : "No package list changes",
                                systemImage: snapshot.configuration.applyState == "current" ? "checkmark.circle" : "doc.text.magnifyingglass",
                                description: Text(snapshot.configuration.applyState == "unknown" ? "Apply the configuration once to establish a machine baseline." : "Other configuration files or project settings differ from the applied system.")
                            )
                        }
                    }
                    ForEach(SoftwareChangeKind.allCases, id: \.self) { change in
                        DifferenceSection(
                            change: change,
                            differences: snapshot.softwareDifferences.filter { $0.change == change },
                            item: { item(for: $0) }
                        )
                    }
                }
            }
        }
        .navigationTitle("Managed Software")
        .inspector(isPresented: Binding(
            get: { selectedItem != nil },
            set: { if !$0 { selectedItem = nil } }
        )) {
            PackageDetailsPanel(item: selectedItem, details: details, error: detailsError, isLoading: isLoadingDetails)
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
        .onChange(of: mode) { _, _ in selectedItem = nil }
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

    private func managedTitle(_ kind: SoftwareKind) -> String {
        switch kind {
        case .nix: "Nix packages"
        case .formula: "Homebrew formulae"
        case .cask: "Applications"
        case .mas: "Mac App Store"
        }
    }

    private func installedTitle(_ kind: SoftwareKind) -> String {
        switch kind {
        case .nix: "Active Nix packages"
        case .formula: "Installed Homebrew formulae"
        case .cask: "Installed applications"
        case .mas: "Mac App Store"
        }
    }
}

private enum SoftwareMode: String, CaseIterable, Identifiable {
    case managed = "Managed"
    case installed = "Installed"
    case changes = "Changes"

    var id: String { rawValue }
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
                            InspectorRow(label: "On this Mac", value: item.appliedVersion ?? item.installedVersions.first ?? (item.isApplied ? "Applied" : "Not applied"))
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
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
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
                if snapshot.configuration.applyState == "pending" {
                    Text("Review Changes")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(tint)
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(tint.opacity(isHovered ? 0.14 : 0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(isHovered ? 0.65 : 0.35), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
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
    let openProject: (Project) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Projects", selection: $filter) {
                ForEach(ProjectFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding()

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
                    Button("Open") { openProject(project) }
                        .disabled(!project.present)
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
    let updateItems: ([SoftwareUpdate]) -> Void
    @State private var pendingBatch: [SoftwareUpdate] = []
    @State private var showingConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            updateToolbar

            List {
                UpdateSection(title: "Nix inputs", symbol: "snowflake", updates: snapshot.updates.nixFlake, selectedUpdateIDs: $selectedUpdateIDs, actionsDisabled: actionsDisabled, updateOne: updateOne)
                UpdateSection(title: "Homebrew formulae", symbol: "terminal", updates: formulaUpdates, selectedUpdateIDs: $selectedUpdateIDs, actionsDisabled: actionsDisabled, updateOne: updateOne)
                UpdateSection(title: "Homebrew applications", symbol: "macwindow", updates: caskUpdates, selectedUpdateIDs: $selectedUpdateIDs, actionsDisabled: actionsDisabled, updateOne: updateOne)
                UpdateSection(title: "Mac App Store", symbol: "apple.logo", updates: snapshot.updates.macAppStore, selectedUpdateIDs: $selectedUpdateIDs, actionsDisabled: actionsDisabled, updateOne: updateOne)
            }
        }
        .navigationTitle("Updates")
        .overlay {
            if snapshot.updates.all.isEmpty {
                ContentUnavailableView(
                    "Everything is current",
                    systemImage: "checkmark.seal.fill",
                    description: Text("No Nix, Homebrew, or Mac App Store updates are currently available.")
                )
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
                Text("\(selectedUpdateIDs.count) selected")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(selectedUpdateIDs.count == allUpdates.count ? "Clear" : "Select All") {
                if selectedUpdateIDs.count == allUpdates.count {
                    selectedUpdateIDs.removeAll()
                } else {
                    selectedUpdateIDs = Set(allUpdates.map(\.id))
                }
            }
            .disabled(actionsDisabled || allUpdates.isEmpty)

            Button("Update Selected") {
                confirm(allUpdates.filter { selectedUpdateIDs.contains($0.id) })
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionsDisabled || selectedUpdateIDs.isEmpty)

            Button("Update All") {
                confirm(allUpdates)
            }
            .disabled(actionsDisabled || allUpdates.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var allUpdates: [SoftwareUpdate] {
        snapshot.updates.all
    }

    private var actionsDisabled: Bool {
        isUpdating || isApplying || isRefreshing
    }

    private var formulaUpdates: [SoftwareUpdate] {
        snapshot.updates.homebrew.filter { $0.kind == "formula" }
    }

    private var caskUpdates: [SoftwareUpdate] {
        snapshot.updates.homebrew.filter { $0.kind == "cask" }
    }

    private func updateOne(_ update: SoftwareUpdate) {
        updateItems([update])
    }

    private func confirm(_ updates: [SoftwareUpdate]) {
        pendingBatch = updates
        showingConfirmation = true
    }
}

private struct UpdateSection: View {
    let title: String
    let symbol: String
    let updates: [SoftwareUpdate]
    @Binding var selectedUpdateIDs: Set<String>
    let actionsDisabled: Bool
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
