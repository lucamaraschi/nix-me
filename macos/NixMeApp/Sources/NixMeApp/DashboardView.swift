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
                applyConfiguration: { showingApplyConfirmation = true },
                isApplying: store.isApplying
            )
        case .software:
            SoftwareView(snapshot: snapshot, mode: $softwareMode)
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

                SectionCard(title: "Configuration", symbol: "slider.horizontal.3") {
                    DetailRow(label: "Apply state", value: applyLabel)
                    DetailRow(label: "Git branch", value: snapshot.configuration.git?.branch ?? "Unavailable")
                    DetailRow(label: "Remote", value: remoteSummary)
                    DetailRow(label: "Working tree", value: snapshot.configuration.git?.dirty == true ? "Uncommitted changes" : "Clean")
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
}

private struct SoftwareView: View {
    let snapshot: ManagementSnapshot
    @Binding var mode: SoftwareMode

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

            List {
                if mode == .managed {
                    SoftwareSection(title: "Nix packages", symbol: "snowflake", names: snapshot.inventory.desired.nixPackages)
                    SoftwareSection(title: "Homebrew formulae", symbol: "terminal", names: snapshot.inventory.desired.homebrew.formulae)
                    SoftwareSection(title: "Applications", symbol: "macwindow", names: snapshot.inventory.desired.homebrew.casks)
                    SoftwareSection(title: "Mac App Store", symbol: "apple.logo", names: snapshot.inventory.desired.homebrew.masApps.keys.sorted())
                } else {
                    SoftwareSection(title: "Active Nix packages", symbol: "snowflake", names: snapshot.inventory.applied.nixPackages)
                    InstalledSoftwareSection(title: "Installed Homebrew formulae", symbol: "terminal", packages: snapshot.inventory.installed.homebrew.formulae)
                    InstalledSoftwareSection(title: "Installed applications", symbol: "macwindow", packages: snapshot.inventory.installed.homebrew.casks)
                }
            }
        }
        .navigationTitle("Managed Software")
    }
}

private enum SoftwareMode: String, CaseIterable, Identifiable {
    case managed = "Managed"
    case installed = "Installed"

    var id: String { rawValue }
}

private struct SoftwareSection: View {
    let title: String
    let symbol: String
    let names: [String]

    var body: some View {
        Section {
            ForEach(names.sorted(), id: \.self) { name in
                Label(name, systemImage: symbol)
            }
        } header: {
            Text("\(title) · \(names.count)")
        }
    }
}

private struct InstalledSoftwareSection: View {
    let title: String
    let symbol: String
    let packages: [InstalledPackage]

    var body: some View {
        Section {
            ForEach(packages.sorted { $0.name < $1.name }) { package in
                HStack {
                    Label(package.name, systemImage: symbol)
                    Spacer()
                    Text(package.versions.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("\(title) · \(packages.count)")
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
