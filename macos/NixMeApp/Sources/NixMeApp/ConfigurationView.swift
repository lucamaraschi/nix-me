import SwiftUI

struct ConfigurationView: View {
    let graph: ConfigurationGraph?
    let error: String?
    let host: Host
    let openFile: (String) -> Void
    let revealFile: (String) -> Void

    @State private var scope = ConfigurationScope.active
    @State private var selectedID: String?
    @State private var query = ""

    var body: some View {
        Group {
            if let graph {
                VStack(spacing: 0) {
                    ConfigurationTopologyHeader(
                        graph: graph,
                        host: host,
                        selectPath: select
                    )

                    HSplitView {
                        hierarchy(graph)
                            .frame(minWidth: 250, idealWidth: 290, maxWidth: 380)

                        if let node = selectedNode(in: graph) {
                            ConfigurationNodeDetail(
                                node: node,
                                graph: graph,
                                selectPath: select,
                                openFile: openFile,
                                revealFile: revealFile
                            )
                            .frame(minWidth: 460)
                        } else {
                            ConfigurationGraphOverview(graph: graph, selectPath: select)
                                .frame(minWidth: 460)
                        }
                    }
                }
            } else if let error {
                ContentUnavailableView(
                    "Configuration map unavailable",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(error)
                )
            } else {
                ProgressView("Mapping configuration…")
                    .controlSize(.large)
            }
        }
        .navigationTitle("Configuration")
        .searchable(text: $query, placement: .toolbar, prompt: "Search configuration files")
        .onChange(of: graph?.hostname, initial: true) {
            guard selectedID == nil, let graph else { return }
            let preferred = graph.activeNodes.first { $0.kind == .machine }
                ?? graph.node(at: "flake.nix")
                ?? graph.activeNodes.first
            selectedID = preferred.map { "file:\($0.path)" }
        }
    }

    private func hierarchy(_ graph: ConfigurationGraph) -> some View {
        VStack(spacing: 0) {
            Picker("Files", selection: $scope) {
                ForEach(ConfigurationScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            List(selection: $selectedID) {
                OutlineGroup(graph.tree(for: visibleNodes(in: graph)), children: \.children) { entry in
                    ConfigurationTreeRow(entry: entry)
                        .tag(entry.id)
                }
            }
            .overlay {
                if visibleNodes(in: graph).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    private func visibleNodes(in graph: ConfigurationGraph) -> [ConfigurationNode] {
        graph.nodes.filter { node in
            let matchesScope = switch scope {
            case .active: node.isActive
            case .all: true
            case .profiles: node.kind == .profile
            }
            let matchesSearch = query.isEmpty
                || node.path.localizedCaseInsensitiveContains(query)
                || node.displayName.localizedCaseInsensitiveContains(query)
                || (node.summary?.localizedCaseInsensitiveContains(query) ?? false)
            return matchesScope && matchesSearch
        }
    }

    private func selectedNode(in graph: ConfigurationGraph) -> ConfigurationNode? {
        guard let selectedID, selectedID.hasPrefix("file:") else { return nil }
        return graph.node(at: String(selectedID.dropFirst("file:".count)))
    }

    private func select(_ path: String) {
        selectedID = "file:\(path)"
    }
}

private enum ConfigurationScope: String, CaseIterable, Identifiable {
    case active = "Active"
    case profiles = "Profiles"
    case all = "All Files"

    var id: String { rawValue }
}

private struct ConfigurationTopologyHeader: View {
    let graph: ConfigurationGraph
    let host: Host
    let selectPath: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.blue.opacity(0.14))
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(host.machineName)
                        .font(.title3.weight(.semibold))
                    Text("Active configuration path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ConfigurationStat(value: graph.activeNodes.count, label: "Active files")
                ConfigurationStat(value: graph.nodes.count, label: "Nix files")
                ConfigurationStat(value: graph.dependencyCount, label: "Links")
            }

            HStack(spacing: 8) {
                TopologyStage(symbol: "square.stack.3d.up", title: "Base", detail: "shared") {
                    selectPath("hosts/types/shared/default.nix")
                }
                topologyArrow
                TopologyStage(symbol: "laptopcomputer", title: "Type", detail: host.machineType ?? "default") {
                    if let machineType = host.machineType {
                        selectPath("hosts/types/\(machineType)/default.nix")
                    }
                }
                topologyArrow
                TopologyStage(symbol: "slider.horizontal.3", title: "Profiles", detail: "\(graph.activeProfiles.count) composed") {
                    if let profile = graph.activeProfiles.first { selectPath(profile.path) }
                }
                topologyArrow
                TopologyStage(symbol: "desktopcomputer", title: "Machine", detail: host.hostname) {
                    selectPath("hosts/machines/\(host.hostname)/default.nix")
                }
            }

            if !graph.activeProfiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        Text("Profiles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(graph.activeProfiles) { profile in
                            Button {
                                selectPath(profile.path)
                            } label: {
                                Label(profile.displayName, systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.bar)
    }

    private var topologyArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
    }
}

private struct ConfigurationStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value, format: .number)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64, alignment: .trailing)
    }
}

private struct TopologyStage: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ConfigurationTreeRow: View {
    let entry: ConfigurationTreeNode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.children == nil ? "doc.text" : "folder")
                .foregroundStyle(entry.children == nil ? Color.secondary : Color.blue)
            Text(entry.name)
                .lineLimit(1)
            Spacer()
            if entry.isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .help("Used by this Mac")
            }
        }
    }
}

private struct ConfigurationGraphOverview: View {
    let graph: ConfigurationGraph
    let selectPath: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ContentUnavailableView {
                    Label("Explore the configuration", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Select a file to inspect its role and dependency relationships.")
                }

                if !graph.activeProfiles.isEmpty {
                    Text("Active Profiles")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(graph.activeProfiles) { profile in
                            Button { selectPath(profile.path) } label: {
                                ConfigurationRelationshipRow(node: profile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
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
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(node.kind.color.opacity(0.14))
                        Image(systemName: node.kind.symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(node.kind.color)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(node.displayName)
                                .font(.title2.weight(.semibold))
                            if node.isActive {
                                Label("Active", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(node.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let summary = node.summary {
                            Text(summary)
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)
                        }
                    }

                    Spacer()

                    Menu {
                        Button("Open File", systemImage: "arrow.up.forward.app") { openFile(node.path) }
                        Button("Reveal in Finder", systemImage: "folder") { revealFile(node.path) }
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .menuStyle(.borderlessButton)
                }

                HStack(spacing: 12) {
                    NodeMetric(value: node.kind.label, label: "Role", symbol: node.kind.symbol)
                    NodeMetric(value: "\(node.lineCount)", label: "Lines", symbol: "text.alignleft")
                    NodeMetric(value: "\(node.imports.count)", label: "Imports", symbol: "arrow.down.right")
                    NodeMetric(value: "\(graph.importers(of: node.path).count)", label: "Used by", symbol: "arrow.up.left")
                }

                relationshipSection(
                    title: "Imports",
                    description: "Configuration included by this file",
                    nodes: node.imports.compactMap(graph.node)
                )
                relationshipSection(
                    title: "Used By",
                    description: "Files that include this configuration",
                    nodes: graph.importers(of: node.path)
                )
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func relationshipSection(title: String, description: String, nodes: [ConfigurationNode]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if nodes.isEmpty {
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 7)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                    ForEach(nodes) { relatedNode in
                        Button { selectPath(relatedNode.path) } label: {
                            ConfigurationRelationshipRow(node: relatedNode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct NodeMetric: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(.blue)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ConfigurationRelationshipRow: View {
    let node: ConfigurationNode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: node.kind.symbol)
                .foregroundStyle(node.kind.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(.callout.weight(.medium))
                Text(node.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

private extension ConfigurationNodeKind {
    var symbol: String {
        switch self {
        case .root: "square.stack.3d.up"
        case .machine: "desktopcomputer"
        case .profile: "slider.horizontal.3"
        case .machineType: "laptopcomputer"
        case .module: "puzzlepiece.extension"
        case .project: "folder.badge.gearshape"
        case .overlay: "square.3.layers.3d"
        case .other: "doc.text"
        }
    }

    var color: Color {
        switch self {
        case .root: .blue
        case .machine: .green
        case .profile: .orange
        case .machineType: .cyan
        case .module: .indigo
        case .project: .teal
        case .overlay: .pink
        case .other: .secondary
        }
    }
}
