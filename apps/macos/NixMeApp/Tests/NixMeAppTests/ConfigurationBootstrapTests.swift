import Foundation
import XCTest

@testable import NixMeApp

final class ConfigurationBootstrapTests: XCTestCase {
    func testConfiguredCheckoutAndDependenciesAreReady() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.appendingPathComponent("checkout", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try createConfiguration(at: checkout)
        try createCommands(allCommands, in: bin)

        let status = ConfigurationBootstrap.inspect(
            environment: ["NIX_ME_CONFIG_DIR": checkout.path, "USER": "tester"],
            homeDirectory: root.appendingPathComponent("home", isDirectory: true),
            currentDirectory: root,
            savedDirectory: nil,
            commandSearchDirectories: [bin]
        )

        XCTAssertEqual(status.checkoutState, .ready)
        XCTAssertEqual(status.configurationDirectory?.path, checkout.resolvingSymlinksInPath().path)
        XCTAssertTrue(status.isReady)
        XCTAssertEqual(status.requiredIssueCount, 0)
        XCTAssertTrue(status.dependencies.allSatisfy(\.isAvailable))
        XCTAssertTrue(status.canCloneToDefaultDestination)
    }

    func testCurrentDirectoryPrecedesConventionalCheckout() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("current", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let conventional = home.appendingPathComponent(".config/nixpkgs", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try createConfiguration(at: current)
        try createConfiguration(at: conventional)
        try createCommands(allCommands, in: bin)

        let status = ConfigurationBootstrap.inspect(
            environment: ["USER": "tester"],
            homeDirectory: home,
            currentDirectory: current,
            savedDirectory: nil,
            commandSearchDirectories: [bin]
        )

        XCTAssertEqual(status.configurationDirectory?.path, current.resolvingSymlinksInPath().path)
    }

    func testCheckoutWithoutManagementAPIRemainsValidConfiguration() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.appendingPathComponent("checkout", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: checkout.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: checkout.appendingPathComponent("flake.nix"),
            atomically: true,
            encoding: .utf8
        )
        try createCommands(allCommands, in: bin)

        let status = ConfigurationBootstrap.inspect(
            configurationDirectory: checkout,
            environment: ["USER": "tester"],
            homeDirectory: root,
            currentDirectory: root,
            savedDirectory: nil,
            commandSearchDirectories: [bin]
        )

        XCTAssertEqual(status.checkoutState, .ready)
        XCTAssertEqual(status.configurationDirectory?.path, checkout.resolvingSymlinksInPath().path)
        XCTAssertEqual(status.checkoutMessage, "Connected to a valid nix-me configuration.")
        XCTAssertTrue(status.isReady)
        XCTAssertEqual(status.requiredIssueCount, 0)
        XCTAssertTrue(status.canUpdateCheckout)
    }

    func testExistingDefaultDestinationDisablesCloneAction() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let checkout = home.appendingPathComponent(".config/nixpkgs", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try createCommands(allCommands, in: bin)

        let status = ConfigurationBootstrap.inspect(
            environment: ["USER": "tester"],
            homeDirectory: home,
            currentDirectory: root,
            savedDirectory: nil,
            commandSearchDirectories: [bin]
        )

        XCTAssertEqual(status.checkoutState, .invalid)
        XCTAssertFalse(status.canCloneToDefaultDestination)
        XCTAssertFalse(status.canUpdateCheckout)
        XCTAssertEqual(status.defaultCloneDestination.path, checkout.path)
    }

    func testMissingRequiredCommandsBlockReadinessButOptionalCommandsDoNot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.appendingPathComponent("checkout", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try createConfiguration(at: checkout)
        try createCommands(["git", "nix", "jq", "make"], in: bin)

        var status = ConfigurationBootstrap.inspect(
            configurationDirectory: checkout,
            environment: ["USER": "tester"],
            homeDirectory: root,
            currentDirectory: root,
            savedDirectory: nil,
            commandSearchDirectories: [bin]
        )

        XCTAssertTrue(status.isReady)
        XCTAssertEqual(
            Set(status.missingOptionalDependencies.map(\.command)), ["brew", "mas", "nix-me-apps"])

        try FileManager.default.removeItem(at: bin.appendingPathComponent("jq"))
        status = ConfigurationBootstrap.inspect(
            configurationDirectory: checkout,
            environment: ["USER": "tester"],
            homeDirectory: root,
            currentDirectory: root,
            savedDirectory: nil,
            commandSearchDirectories: [bin]
        )

        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.missingRequiredDependencies.map(\.command), ["jq"])
        XCTAssertEqual(status.requiredIssueCount, 1)
    }

    func testUpdateCheckoutRebasesLocalWorkOntoLatestRemote() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.appendingPathComponent("checkout", isDirectory: true)
        let git = root.appendingPathComponent("git")
        try FileManager.default.createDirectory(
            at: checkout.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        #!/bin/bash
        [[ "$1" == "-C" && "$2" == "\(checkout.path)" && "$3" == "pull" && "$4" == "--rebase" && "$5" == "--autostash" ]]
        """.write(to: git, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: git.path)

        try await ConfigurationBootstrap.updateCheckout(at: checkout, gitURL: git)
    }

    private var allCommands: [String] {
        ["git", "nix", "jq", "make", "brew", "mas", "nix-me-apps"]
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func createConfiguration(at directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("packages/management-api/bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "{}".write(
            to: directory.appendingPathComponent("flake.nix"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/bash\n".write(
            to: directory.appendingPathComponent("packages/management-api/bin/nix-me-api"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func createCommands(_ commands: [String], in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for command in commands {
            let executable = directory.appendingPathComponent(command)
            try "#!/bin/bash\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
    }
}
