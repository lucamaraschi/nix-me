import SwiftUI

struct ConfigurationView: View {
    let graph: ConfigurationGraph?
    let error: String?
    let host: Host
    let openFile: (String) -> Void
    let revealFile: (String) -> Void
    let openAppSettings: () -> Void
    let openChanges: () -> Void

    @State private var browsingFiles = false
    @State private var scope = ConfigurationScope.active
    @State private var selectedID: String?
    @State private var query = ""

    var body: some View {
        Group {
            if let graph {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider()
                    if browsingFiles {
                        HSplitView {
                            hierarchy(graph)
                                .frame(minWidth: 240, idealWidth: 290, maxWidth: 360)
                            if let node = selectedNode(in: graph) {
                                ConfigurationNodeDetail(
                                    node: node, graph: graph, selectPath: select,
                                    openFile: openFile, revealFile: revealFile
                                )
                                .frame(minWidth: 400)
                            } else {
                                ContentUnavailableView(
                                    "Choose a configuration file",
                                    systemImage: "doc.text.magnifyingglass",
                                    description: Text("See what it is for, which files it references, and where it is referenced. Open it in your editor to make changes.")
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        overview(graph)
                    }
                }
            } else if let error {
                ContentUnavailableView(
                    "Configuration could not be read", systemImage: "folder.badge.questionmark",
                    description: Text(error)
                )
            } else {
                ProgressView("Reading configuration files…")
            }
        }
        .navigationTitle("Configuration")
        .onChange(of: graph?.rootPath) { _, _ in resetBrowser() }
        .onChange(of: graph?.hostname) { _, _ in resetBrowser() }
        .onChange(of: scope) { _, _ in clearHiddenSelection() }
        .onChange(of: query) { _, _ in clearHiddenSelection() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("How this Mac is configured")
                        .font(.system(size: 28, weight: .semibold))
                    Text("\(host.machineName) · \(host.hostname)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review Changes", systemImage: "arrow.left.arrow.right", action: openChanges)
                    .buttonStyle(OxideButtonStyle(variant: .secondary))
            }
            HStack(spacing: 8) {
                Button("Overview") { browsingFiles = false }
                    .buttonStyle(OxideButtonStyle(variant: browsingFiles ? .ghost : .primary))
                    .accessibilityAddTraits(browsingFiles ? [] : .isSelected)
                Button("Files & Dependencies") { browsingFiles = true }
                    .buttonStyle(OxideButtonStyle(variant: browsingFiles ? .primary : .ghost))
                    .accessibilityAddTraits(browsingFiles ? .isSelected : [])
                Spacer()
                Text("CHECKOUT · NOT LIVE SYSTEM STATE").oxideLabel()
            }
        }
        .padding(20)
    }

    private func overview(_ graph: ConfigurationGraph) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ONE CONFIGURATION, REUSABLE PARTS").oxideLabel(color: OxidePalette.green)
                    Text("Your machine combines shared defaults, a hardware type, and selected profiles. Its own file adds machine-specific choices.")
                        .font(.title3)
                    Text("This maps the files in your checkout, not what is currently installed. Nix merges these definitions; the cards below are not an override order.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(graph.composition(machineType: host.machineType)) { component in
                        componentCard(component)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("WHERE TO MAKE CHANGES").oxideLabel(color: OxidePalette.secondary)
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("System & software definitions", systemImage: "doc.text").font(.headline)
                            Text("Inspect a card above, then open its file in your editor. Use Changes to review and apply the result.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Browse Configuration Files") { browsingFiles = true }
                                .buttonStyle(OxideButtonStyle(variant: .secondary))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Preferences inside apps", systemImage: "slider.horizontal.3").font(.headline)
                            Text("Capture supported preferences from installed apps and save them for all machines, a profile, or just this Mac.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Open App Settings", action: openAppSettings)
                                .buttonStyle(OxideButtonStyle(variant: .secondary))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .oxidePanel()

                HStack(alignment: .top) {
                    Image(systemName: "folder").foregroundStyle(OxidePalette.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(graph.rootPath).font(.caption.monospaced()).textSelection(.enabled)
                        Text("\(graph.nodes.count) Nix files · \(graph.activeNodes.count) detected for this machine. Dynamic imports may not appear in this static map.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if graph.node(at: "flake.nix") != nil {
                        Button("Open Entry Point") { openFile("flake.nix") }
                            .buttonStyle(OxideButtonStyle(variant: .secondary))
                    }
                }
            }
            .padding(20)
        }
    }

    private func componentCard(_ component: ConfigurationComponent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(component.title, systemImage: component.symbol)
                .font(.headline).foregroundStyle(OxidePalette.green)
            Text(component.explanation).font(.callout).foregroundStyle(.secondary)
            if component.nodes.isEmpty {
                Text("No matching file detected in this checkout.")
                    .font(.caption).foregroundStyle(OxidePalette.secondary)
            } else {
                ForEach(component.nodes) { node in
                    Button { select(node.path) } label: { ConfigurationRelationshipRow(node: node) }
                        .buttonStyle(.plain)
                        .help("Inspect \(node.path)")
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading)
        .oxidePanel()
    }

    private func hierarchy(_ graph: ConfigurationGraph) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Show files", selection: $scope) {
                ForEach(ConfigurationScope.allCases) { scope in Text(scope.rawValue).tag(scope) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 12)
            TextField("Search files", text: $query)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 12)
            Text("Green marks files detected for \(host.hostname).")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            List(selection: $selectedID) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    OutlineGroup(graph.tree(for: visibleNodes(in: graph)), children: \.children) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.children == nil ? "doc.text" : "folder")
                                .foregroundStyle(entry.isActive ? OxidePalette.green : OxidePalette.secondary)
                            Text(entry.name).lineLimit(1)
                        }
                        .tag(entry.id)
                    }
                } else {
                    ForEach(visibleNodes(in: graph)) { node in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(node.displayName)
                            Text(node.path).font(.caption2).foregroundStyle(.secondary)
                        }
                        .tag("file:\(node.path)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if visibleNodes(in: graph).isEmpty {
                    ContentUnavailableView("No matching files", systemImage: "doc.text.magnifyingglass", description: Text("Try All Files or clear the search."))
                }
            }
        }
        .background(OxidePalette.sidebar)
    }

    private func visibleNodes(in graph: ConfigurationGraph) -> [ConfigurationNode] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return graph.nodes.filter { node in
            let matchesScope = switch scope {
            case .active: node.isActive
            case .all: true
            case .profiles: node.kind == .profile
            }
            return matchesScope && (search.isEmpty
                || node.path.localizedCaseInsensitiveContains(search)
                || (node.summary?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    private func selectedNode(in graph: ConfigurationGraph) -> ConfigurationNode? {
        guard let selectedID, selectedID.hasPrefix("file:") else { return nil }
        return graph.node(at: String(selectedID.dropFirst("file:".count)))
    }

    private func select(_ path: String) {
        scope = .all
        query = ""
        selectedID = "file:\(path)"
        browsingFiles = true
    }

    private func clearHiddenSelection() {
        guard let graph, let node = selectedNode(in: graph) else { return }
        if !visibleNodes(in: graph).contains(node) { selectedID = nil }
    }

    private func resetBrowser() {
        selectedID = nil
        query = ""
        browsingFiles = false
    }
}

private enum ConfigurationScope: String, CaseIterable, Identifiable {
    case active = "This Mac"
    case profiles = "Profiles"
    case all = "All Files"
    var id: String { rawValue }
}

private struct ConfigurationNodeDetail: View {
    let node: ConfigurationNode
    let graph: ConfigurationGraph
    let selectPath: (String) -> Void
    let openFile: (String) -> Void
    let revealFile: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(node.kind.label.uppercased()).oxideLabel(color: OxidePalette.green)
                    Text(node.displayName).font(.title.weight(.semibold))
                    Text(node.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(node.kind.explanation).foregroundStyle(.secondary)
                    if let summary = node.summary { Text(summary).font(.callout) }
                    Label(node.isActive ? "Detected in this machine's configuration" : "Not detected for this machine", systemImage: node.isActive ? "checkmark.circle" : "minus.circle")
                        .font(.caption).foregroundStyle(node.isActive ? OxidePalette.green : OxidePalette.secondary)
                    HStack {
                        Button("Open in Editor", systemImage: "square.and.pencil") { openFile(node.path) }
                            .buttonStyle(OxideButtonStyle(variant: .primary))
                        Button("Show in Finder", systemImage: "folder") { revealFile(node.path) }
                            .buttonStyle(OxideButtonStyle(variant: .secondary))
                    }
                    .padding(.top, 6)
                }
                Divider()
                relationshipSection(
                    title: "References from this file", explanation: "Follow a file to see the definitions it contributes.",
                    nodes: node.imports.compactMap(graph.node)
                )
                relationshipSection(
                    title: "Referenced by", explanation: "These files reference this definition.",
                    nodes: graph.importers(of: node.path)
                )
                Text("Relationships come from a static scan of local Nix files. Conditional and generated imports may be incomplete; this is not the evaluated merge order.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .id(node.path)
    }

    private func relationshipSection(title: String, explanation: String, nodes: [ConfigurationNode]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title) · \(nodes.count)").font(.headline)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
            if nodes.isEmpty {
                Text("No local file references detected.").font(.callout).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                    ForEach(nodes) { related in
                        Button { selectPath(related.path) } label: { ConfigurationRelationshipRow(node: related) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ConfigurationRelationshipRow: View {
    let node: ConfigurationNode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(node.isActive ? OxidePalette.green : OxidePalette.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.displayName).font(.callout.weight(.semibold))
                Text(node.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OxidePalette.background.opacity(0.6))
        .overlay(Rectangle().stroke(OxidePalette.border))
        .contentShape(Rectangle())
    }
}

private extension ConfigurationNodeKind {
    var explanation: String {
        switch self {
        case .root: "The entry point that connects machine definitions and external inputs."
        case .machine: "Choices and customizations specific to one machine."
        case .profile: "A reusable group of software and settings that machines can opt into."
        case .machineType: "Defaults shared by machines of the same hardware type."
        case .module: "Implementation of system or user features included by other configuration files."
        case .project: "Repositories and destinations used when syncing development projects."
        case .overlay: "Customizations to the packages provided by Nix."
        case .other: "A supporting Nix definition. Follow its references to understand how it is used."
        }
    }
}
