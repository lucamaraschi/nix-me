import Foundation

enum ConfigurationNodeKind: String, CaseIterable, Identifiable {
    case root
    case machine
    case profile
    case machineType
    case module
    case project
    case overlay
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .root: "Root"
        case .machine: "Machine"
        case .profile: "Profile"
        case .machineType: "Machine type"
        case .module: "Module"
        case .project: "Project set"
        case .overlay: "Overlay"
        case .other: "Other"
        }
    }
}

struct ConfigurationNode: Identifiable, Hashable {
    let path: String
    let kind: ConfigurationNodeKind
    let imports: [String]
    let isActive: Bool
    let lineCount: Int
    let summary: String?

    var id: String { path }

    var displayName: String {
        let url = URL(fileURLWithPath: path)
        if url.lastPathComponent == "default.nix" {
            return url.deletingLastPathComponent().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

struct ConfigurationTreeNode: Identifiable {
    let id: String
    let name: String
    let filePath: String?
    let isActive: Bool
    let children: [ConfigurationTreeNode]?
}

struct ConfigurationGraph {
    let rootPath: String
    let hostname: String
    let nodes: [ConfigurationNode]

    var activeNodes: [ConfigurationNode] {
        nodes.filter(\.isActive)
    }

    var activeProfiles: [ConfigurationNode] {
        activeNodes.filter { $0.kind == .profile }.sorted { $0.displayName < $1.displayName }
    }

    var dependencyCount: Int {
        nodes.reduce(0) { $0 + $1.imports.count }
    }

    func node(at path: String) -> ConfigurationNode? {
        nodes.first { $0.path == path }
    }

    func importers(of path: String) -> [ConfigurationNode] {
        nodes.filter { $0.imports.contains(path) }.sorted { $0.path < $1.path }
    }

    func tree(for nodes: [ConfigurationNode]) -> [ConfigurationTreeNode] {
        let root = MutableConfigurationTreeNode(name: "", relativePath: "")
        for node in nodes.sorted(by: { $0.path < $1.path }) {
            let components = node.path.split(separator: "/").map(String.init)
            var parent = root
            for (index, component) in components.enumerated() {
                let relativePath = components[...index].joined(separator: "/")
                let child = parent.children[component] ?? MutableConfigurationTreeNode(
                    name: component,
                    relativePath: relativePath
                )
                parent.children[component] = child
                parent = child
            }
            parent.filePath = node.path
            parent.isActive = node.isActive
        }
        return root.children.values.map(\.frozen).sorted(by: ConfigurationTreeNode.sort)
    }
}

private final class MutableConfigurationTreeNode {
    let name: String
    let relativePath: String
    var filePath: String?
    var isActive = false
    var children: [String: MutableConfigurationTreeNode] = [:]

    init(name: String, relativePath: String) {
        self.name = name
        self.relativePath = relativePath
    }

    var frozen: ConfigurationTreeNode {
        let frozenChildren = children.values.map(\.frozen).sorted(by: ConfigurationTreeNode.sort)
        return ConfigurationTreeNode(
            id: filePath.map { "file:\($0)" } ?? "directory:\(relativePath)",
            name: name,
            filePath: filePath,
            isActive: isActive || frozenChildren.contains(where: \.isActive),
            children: frozenChildren.isEmpty ? nil : frozenChildren
        )
    }
}

private extension ConfigurationTreeNode {
    static func sort(_ left: ConfigurationTreeNode, _ right: ConfigurationTreeNode) -> Bool {
        let leftDirectory = left.children != nil
        let rightDirectory = right.children != nil
        if leftDirectory != rightDirectory {
            return leftDirectory
        }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
}

struct ConfigurationGraphScanner {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(directory: URL, hostname: String, machineType: String?) throws -> ConfigurationGraph {
        let root = directory.standardizedFileURL
        let fileURLs = try nixFiles(in: root)
        let paths = Set(fileURLs.map { relativePath(for: $0, root: root) })
        var importsByPath: [String: [String]] = [:]
        var sourceByPath: [String: String] = [:]

        for url in fileURLs {
            let path = relativePath(for: url, root: root)
            let source = try String(contentsOf: url, encoding: .utf8)
            sourceByPath[path] = source
            importsByPath[path] = resolvedImports(in: source, sourceURL: url, root: root, knownPaths: paths)
        }

        let activePaths = activePaths(
            root: root,
            hostname: hostname,
            machineType: machineType,
            knownPaths: paths,
            importsByPath: importsByPath,
            flakeSource: sourceByPath["flake.nix"] ?? ""
        )

        let nodes = paths.sorted().map { path in
            let source = sourceByPath[path] ?? ""
            return ConfigurationNode(
                path: path,
                kind: kind(for: path),
                imports: importsByPath[path] ?? [],
                isActive: activePaths.contains(path),
                lineCount: source.split(separator: "\n", omittingEmptySubsequences: false).count,
                summary: summary(from: source)
            )
        }

        return ConfigurationGraph(rootPath: root.path, hostname: hostname, nodes: nodes)
    }

    private func nixFiles(in root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if ["build", ".build", "result"].contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true && (url.pathExtension == "nix" || url.lastPathComponent == "flake.nix") {
                files.append(url.standardizedFileURL)
            }
        }
        return files
    }

    private func resolvedImports(
        in source: String,
        sourceURL: URL,
        root: URL,
        knownPaths: Set<String>
    ) -> [String] {
        relativeReferences(in: source).compactMap { reference in
            guard !reference.contains("${") else { return nil }
            let candidate = URL(fileURLWithPath: reference, relativeTo: sourceURL.deletingLastPathComponent())
                .standardizedFileURL
            let possibleURLs = [
                candidate,
                candidate.appendingPathExtension("nix"),
                candidate.appendingPathComponent("default.nix")
            ]
            return possibleURLs.lazy
                .map { relativePath(for: $0, root: root) }
                .first(where: knownPaths.contains)
        }
        .uniqued()
        .sorted()
    }

    private func relativeReferences(in source: String) -> [String] {
        let pattern = #"(?<![A-Za-z0-9_$])(\.{1,2}/[A-Za-z0-9_./${}-]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[matchRange])
        }
    }

    private func activePaths(
        root: URL,
        hostname: String,
        machineType: String?,
        knownPaths: Set<String>,
        importsByPath: [String: [String]],
        flakeSource: String
    ) -> Set<String> {
        var seeds = Set<String>()

        func add(_ path: String) {
            if knownPaths.contains(path) { seeds.insert(path) }
        }

        add("flake.nix")
        add("nix/hosts/types/shared/default.nix")
        add("nix/hosts/machines/\(hostname)/default.nix")
        add("nix/modules/home-manager/default.nix")
        add("nix/overlays/airjack.nix")
        if let machineType {
            add("nix/hosts/types/\(machineType)/default.nix")
        }

        if let hostBlock = darwinConfigurationBlock(named: hostname, in: flakeSource) {
            let flakeURL = root.appendingPathComponent("flake.nix")
            for reference in relativeReferences(in: hostBlock) where !reference.contains("${") {
                let url = URL(fileURLWithPath: reference, relativeTo: flakeURL.deletingLastPathComponent())
                    .standardizedFileURL
                let possible = [url, url.appendingPathExtension("nix"), url.appendingPathComponent("default.nix")]
                if let path = possible.map({ relativePath(for: $0, root: root) }).first(where: knownPaths.contains) {
                    seeds.insert(path)
                }
            }
        }

        var active = seeds
        var pending = Array(seeds.filter { $0 != "flake.nix" })
        while let path = pending.popLast() {
            for importedPath in importsByPath[path] ?? [] where !active.contains(importedPath) {
                active.insert(importedPath)
                pending.append(importedPath)
            }
        }
        return active
    }

    private func darwinConfigurationBlock(named hostname: String, in source: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: hostname)
        let pattern = #"(?m)(?:"\#(escaped)"|\b\#(escaped)\b)\s*=\s*mkDarwinSystem\s*\{"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let fullRange = NSRange(source.startIndex..., in: source)
        guard let match = expression.firstMatch(in: source, range: fullRange),
              let matchRange = Range(match.range, in: source),
              let openingBrace = source[matchRange].lastIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...index])
                }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func kind(for path: String) -> ConfigurationNodeKind {
        if path == "flake.nix" { return .root }
        if path.hasPrefix("nix/hosts/machines/") { return .machine }
        if path.hasPrefix("nix/hosts/profiles/") { return .profile }
        if path.hasPrefix("nix/hosts/types/") { return .machineType }
        if path.hasPrefix("nix/modules/") { return .module }
        if path.hasPrefix("nix/projects/") { return .project }
        if path.hasPrefix("nix/overlays/") { return .overlay }
        return .other
    }

    private func summary(from source: String) -> String? {
        let comments = source.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(8)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("#") && !$0.hasPrefix("#!") }
            .map { String($0.drop(while: { $0 == "#" || $0 == " " })) }
            .filter { !$0.isEmpty }
        guard !comments.isEmpty else { return nil }
        return comments.prefix(2).joined(separator: " ")
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
