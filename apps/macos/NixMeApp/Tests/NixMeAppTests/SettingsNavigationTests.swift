import XCTest
@testable import NixMeApp

final class SettingsNavigationTests: XCTestCase {
    func testAutomaticChecksSeparateSaveCapabilityFromSavedConfiguration() throws {
        let unsaved = try application(installed: true, capturable: true, configured: false)
        let saved = try application(installed: true, capturable: true, configured: true)
        let manual = try application(installed: true, capturable: false, configured: true)

        XCTAssertTrue(unsaved.canCheckSettingsAutomatically)
        XCTAssertTrue(saved.canCheckSettingsAutomatically)
        XCTAssertFalse(manual.canCheckSettingsAutomatically)
    }

    func testAutomaticChecksSkipUninstalledApplications() throws {
        let absent = try application(installed: false, capturable: true, configured: true)
        XCTAssertFalse(absent.canCheckSettingsAutomatically)
    }

    func testCompositionLinksOnlyExistingFilesForSelectedMachine() {
        let graph = ConfigurationGraph(rootPath: "/checkout", hostname: "test-mac", nodes: [
            node("nix/hosts/types/shared/default.nix", .machineType),
            node("nix/hosts/types/macbook-pro/default.nix", .machineType),
            node("nix/hosts/machines/test-mac/default.nix", .machine),
            node("nix/hosts/machines/another-mac/default.nix", .machine, active: false),
            node("nix/hosts/profiles/work.nix", .profile),
            node("nix/hosts/profiles/dev.nix", .profile),
            node("nix/hosts/profiles/gaming.nix", .profile, active: false),
        ])
        let components = graph.composition(machineType: "macbook-pro")
        XCTAssertEqual(components.map(\.id), ["shared", "hardware", "profiles", "machine"])
        XCTAssertEqual(components[2].nodes.map(\.displayName), ["dev", "work"])
        XCTAssertEqual(components[3].nodes.map(\.path), ["nix/hosts/machines/test-mac/default.nix"])
        XCTAssertEqual(components[1].nodes.map(\.path), ["nix/hosts/types/macbook-pro/default.nix"])
    }

    func testMissingCompositionFilesDoNotCreateDeadLinks() {
        let graph = ConfigurationGraph(rootPath: "/checkout", hostname: "unknown", nodes: [])
        XCTAssertTrue(graph.composition(machineType: nil).allSatisfy { $0.nodes.isEmpty })
        XCTAssertTrue(graph.composition(machineType: "missing").allSatisfy { $0.nodes.isEmpty })
    }

    func testBuildResultSymlinkDoesNotHideConfigurationDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("result").path, withDestinationPath: "/nix/store/missing-test-result")
        // A plain file named build also must not prune a sibling's descendants.
        try Data().write(to: root.appendingPathComponent("build"))
        let paths = [
            "flake.nix", "nix/hosts/types/shared/default.nix",
            "nix/hosts/machines/test-mac/default.nix", "nix/hosts/profiles/work.nix",
            "extra/definition.nix", "another/definition.nix",
        ]
        for path in paths {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }
        let graph = try ConfigurationGraphScanner().scan(directory: root, hostname: "test-mac", machineType: nil)
        XCTAssertEqual(Set(graph.nodes.map(\.path)), Set(paths))
    }

    private func node(_ path: String, _ kind: ConfigurationNodeKind, active: Bool = true) -> ConfigurationNode {
        ConfigurationNode(path: path, kind: kind, imports: [], isActive: active, lineCount: 1, summary: nil)
    }

    private func application(installed: Bool, capturable: Bool, configured: Bool) throws -> AppStateSettingsApplication {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "example", "name": "Example", "bundleId": "com.example.app",
            "installed": installed, "capturable": capturable, "configured": configured,
            "captureKinds": [], "recipeAvailable": true,
            "configurationSources": configured ? [["scope": "shared", "label": "All machines", "path": "config/app-state/shared/settings.json"]] : [],
        ])
        return try JSONDecoder().decode(AppStateSettingsApplication.self, from: data)
    }
}
