import Foundation

enum ApplyActionEventKind: String, Sendable {
    case command
    case output
    case package
}

enum ApplyPackageManager: String, CaseIterable, Sendable {
    case nix
    case homebrew

    var title: String {
        switch self {
        case .nix: "Nix store"
        case .homebrew: "Homebrew"
        }
    }
}

enum ApplyPackageState: String, Sendable {
    case queued
    case downloading
    case building
    case installing
    case complete
    case failed
    case cancelled

    var title: String {
        switch self {
        case .queued: "Queued"
        case .downloading: "Fetching"
        case .building: "Building"
        case .installing: "Installing"
        case .complete: "Complete"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        }
    }
}

struct ApplyPackageProgress: Equatable, Sendable {
    let manager: ApplyPackageManager
    let name: String
    let state: ApplyPackageState
    let detail: String
    let fractionCompleted: Double?

    init(
        manager: ApplyPackageManager,
        name: String,
        state: ApplyPackageState,
        detail: String,
        fractionCompleted: Double? = nil
    ) {
        self.manager = manager
        self.name = name
        self.state = state
        self.detail = detail
        self.fractionCompleted = fractionCompleted.map { min(max($0, 0), 1) }
    }

    var id: String { "\(manager.rawValue):\(name)" }
}

struct ApplyActionEvent: Equatable, Sendable {
    let kind: ApplyActionEventKind
    let phase: ApplyActionPhase?
    let message: String
    let package: ApplyPackageProgress?

    static func command(_ command: String, phase: ApplyActionPhase?) -> Self {
        Self(kind: .command, phase: phase, message: command, package: nil)
    }

    static func output(_ output: String, phase: ApplyActionPhase?) -> Self {
        Self(kind: .output, phase: phase, message: output, package: nil)
    }

    static func package(_ package: ApplyPackageProgress, phase: ApplyActionPhase?) -> Self {
        Self(kind: .package, phase: phase, message: package.detail, package: package)
    }
}

enum ApplyActionEventParser {
    static func command(from line: String) -> ApplyActionEvent? {
        let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3,
              fields[0] == "NIX_ME_COMMAND",
              let phase = ApplyActionPhase(rawValue: String(fields[1]))
        else { return nil }
        return .command(String(fields[2]), phase: phase)
    }

    static func package(from rawLine: String) -> ApplyPackageProgress? {
        let line = stripANSI(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        if let progress = nixProgress(from: line) {
            return progress
        }
        return homebrewProgress(from: line)
    }

    private static func nixProgress(from line: String) -> ApplyPackageProgress? {
        if line.hasPrefix("/nix/store/"), line.hasSuffix(".drv") {
            let name = nixStoreName(line)
            return ApplyPackageProgress(manager: .nix, name: name, state: .queued, detail: line)
        }

        if let path = quotedStorePath(in: line, after: "building '") {
            return ApplyPackageProgress(
                manager: .nix,
                name: nixStoreName(path),
                state: .building,
                detail: line
            )
        }

        if let path = quotedStorePath(in: line, after: "copying path '") {
            return ApplyPackageProgress(
                manager: .nix,
                name: nixStoreName(path),
                state: .downloading,
                detail: line
            )
        }

        if line.hasPrefix("["), let range = line.range(of: "] building ") {
            let remainder = line[range.upperBound...]
            let name = remainder
                .split(separator: " ", maxSplits: 1)
                .first
                .map(String.init) ?? "Nix derivation"
            return ApplyPackageProgress(manager: .nix, name: name, state: .building, detail: line)
        }

        return nil
    }

    private static func homebrewProgress(from line: String) -> ApplyPackageProgress? {
        let prefixes: [(String, ApplyPackageState)] = [
            ("==> Installing Cask ", .installing),
            ("==> Upgrading Cask ", .installing),
            ("==> Installing ", .installing),
            ("==> Upgrading ", .installing),
            ("==> Pouring ", .installing),
            ("==> Fetching downloads for: ", .downloading),
            ("==> Fetching ", .downloading),
        ]

        for (prefix, state) in prefixes where line.hasPrefix(prefix) {
            let rawName = String(line.dropFirst(prefix.count))
            let name = homebrewName(rawName)
            guard !name.isEmpty else { return nil }
            return ApplyPackageProgress(manager: .homebrew, name: name, state: state, detail: line)
        }

        if line.hasPrefix("🍺") {
            let value = line.dropFirst().trimmingCharacters(in: .whitespaces)
            let name: String
            if value.hasPrefix("/") {
                let components = value.split(separator: "/")
                if let cellar = components.firstIndex(of: "Cellar"), components.indices.contains(cellar + 1) {
                    name = String(components[cellar + 1])
                } else {
                    name = URL(fileURLWithPath: value).lastPathComponent
                }
            } else {
                name = value.split(separator: " ").first.map(String.init) ?? "Homebrew package"
            }
            return ApplyPackageProgress(manager: .homebrew, name: name, state: .complete, detail: line)
        }

        return nil
    }

    private static func quotedStorePath(in line: String, after prefix: String) -> String? {
        guard let start = line.range(of: prefix) else { return nil }
        let remainder = line[start.upperBound...]
        guard let end = remainder.firstIndex(of: "'") else { return nil }
        return String(remainder[..<end])
    }

    private static func nixStoreName(_ path: String) -> String {
        var name = URL(fileURLWithPath: path).lastPathComponent
        if name.hasSuffix(".drv") {
            name.removeLast(4)
        }
        if let separator = name.firstIndex(of: "-"), name.distance(from: name.startIndex, to: separator) >= 20 {
            name = String(name[name.index(after: separator)...])
        }
        return name
    }

    private static func homebrewName(_ value: String) -> String {
        var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = name.range(of: " dependencies for ") {
            name = String(name[range.upperBound...])
        }
        if let separator = name.range(of: "--") {
            name = String(name[..<separator.lowerBound])
        }
        if let colon = name.firstIndex(of: ":") {
            name = String(name[..<colon])
        }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private static func stripANSI(_ value: String) -> String {
        value.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }
}

enum InstallerConsoleEntryKind: Sendable {
    case command
    case output
    case status
    case error
}

enum InstallerActivityState: String, Sendable {
    case queued
    case running
    case complete
    case failed
    case cancelled

    var title: String { rawValue.uppercased() }
}

enum InstallerProgressCalculator {
    static func fraction(
        phase: FirstInstallationPhase,
        isRunning: Bool,
        isComplete: Bool,
        steps: [InstallerStepActivity],
        packages: [InstallerPackageActivity]
    ) -> Double {
        guard !isComplete else { return 1 }
        let phases = Double(FirstInstallationPhase.allCases.count)
        let base = Double(phase.rawValue) / phases
        let currentSteps = steps.filter { $0.phase == phase }
        let currentPackages = packages.filter { $0.phase == phase }
        let work = currentSteps.map { activityFraction($0.state) }
            + currentPackages.map { packageFraction($0) }
        let activeFraction: Double
        if work.isEmpty {
            activeFraction = isRunning ? 0.08 : 0
        } else {
            activeFraction = work.reduce(0, +) / Double(work.count)
        }
        return min(0.995, max(0, base + activeFraction / phases))
    }

    private static func activityFraction(_ state: InstallerActivityState) -> Double {
        switch state {
        case .queued: 0
        case .running: 0.35
        case .complete: 1
        case .failed, .cancelled: 0
        }
    }

    private static func packageFraction(_ package: InstallerPackageActivity) -> Double {
        switch package.state {
        case .queued: 0
        case .downloading, .building, .installing: package.fractionCompleted ?? 0.35
        case .complete: 1
        case .failed, .cancelled: 0
        }
    }
}

struct InstallerStepActivity: Identifiable, Sendable {
    let id: UUID
    let phase: FirstInstallationPhase
    let title: String
    let detail: String
    let state: InstallerActivityState
    let sequence: Int

    init(
        id: UUID = UUID(),
        phase: FirstInstallationPhase,
        title: String,
        detail: String,
        state: InstallerActivityState,
        sequence: Int
    ) {
        self.id = id
        self.phase = phase
        self.title = title
        self.detail = detail
        self.state = state
        self.sequence = sequence
    }
}

struct InstallerConsoleEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp = Date()
    let kind: InstallerConsoleEntryKind
    let message: String
}

struct InstallerPackageActivity: Identifiable, Sendable {
    let id: String
    let phase: FirstInstallationPhase
    let manager: ApplyPackageManager
    let name: String
    let state: ApplyPackageState
    let detail: String
    let fractionCompleted: Double?
    let sequence: Int
}

enum InstallerDiagnosticReport {
    static func render(
        hostname: String,
        configurationDirectory: URL,
        phase: FirstInstallationPhase,
        phaseMessage: String,
        errorMessage: String?,
        errorDetails: String?,
        steps: [InstallerStepActivity],
        packages: [InstallerPackageActivity],
        console: [InstallerConsoleEntry],
        generatedAt: Date = Date()
    ) -> String {
        let timestamp = ISO8601DateFormatter().string(from: generatedAt)
        var lines = [
            "# Nix Me installer diagnostic",
            "",
            "> Generated for troubleshooting. Review local paths and usernames before sharing.",
            "",
            "## Context",
            "",
            "- Generated: `\(timestamp)`",
            "- Host: `\(hostname)`",
            "- Configuration: `\(configurationDirectory.path)`",
            "- Current phase: `\(phase.title)`",
            "- Status: \(phaseMessage)",
        ]

        if let errorMessage {
            lines += ["", "## Failure", "", errorMessage]
            if let errorDetails, errorDetails != errorMessage {
                lines += ["", "```text", errorDetails, "```"]
            }
        }

        lines += ["", "## Execution timeline", ""]
        for itemPhase in FirstInstallationPhase.allCases {
            let phaseSteps = steps.filter { $0.phase == itemPhase }.sorted { $0.sequence < $1.sequence }
            let phasePackages = packages.filter { $0.phase == itemPhase }.sorted { $0.sequence < $1.sequence }
            guard !phaseSteps.isEmpty || !phasePackages.isEmpty else { continue }
            lines += ["### \(itemPhase.title)", ""]
            for step in phaseSteps {
                lines.append("- [\(step.state == .complete ? "x" : " ")] **\(step.state.title)** \(step.title): `\(inline(step.detail))`")
            }
            for package in phasePackages {
                let progress = package.fractionCompleted.map { " \(Int($0 * 100))%" } ?? ""
                lines.append("- [\(package.state == .complete ? "x" : " ")] **\(package.state.title.uppercased())** \(package.manager.title) / \(package.name)\(progress)")
            }
            lines.append("")
        }

        lines += ["## Full command and output log", "", "```text"]
        let formatter = ISO8601DateFormatter()
        for entry in console {
            lines.append("[\(formatter.string(from: entry.timestamp))] \(prefix(entry.kind)) \(entry.message)")
        }
        lines += ["```", ""]
        return lines.joined(separator: "\n")
    }

    private static func prefix(_ kind: InstallerConsoleEntryKind) -> String {
        switch kind {
        case .command: "$"
        case .output: "|"
        case .status: "::"
        case .error: "!!"
        }
    }

    private static func inline(_ value: String) -> String {
        value.replacingOccurrences(of: "`", with: "'")
    }
}

enum InstallerShell {
    static func command(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(quote).joined(separator: " ")
    }

    static func quote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if value.unicodeScalars.allSatisfy(safe.contains) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
