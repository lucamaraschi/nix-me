import XCTest

@testable import NixMeApp

@MainActor
final class FirstInstallationStoreTests: XCTestCase {
    func testMachineConfigurationsLoadSavedHostsAndTheirProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        {
          outputs = inputs: let
            defaultUsername = "default-user";
          in {
            darwinConfigurations = {
              "bellerofonte" = mkDarwinSystem {
                hostname = "bellerofonte";
                machineType = "macbook-pro";
                machineName = "Bellerofonte";
                username = "batman";
                extraModules = [
                  ./nix/hosts/profiles/dev.nix
                  ./nix/hosts/profiles/local-ai.nix
                  { apps.manager.enable = true; }
                ];
              };
              "vm-test" = mkDarwinSystem {
                hostname = "vm-test";
                machineType = "vm";
                machineName = "VM";
                username = username;
              };
            };
          };
        }
        """.write(
            to: directory.appendingPathComponent("flake.nix"),
            atomically: true,
            encoding: .utf8
        )

        let machines = FirstInstallationStore.machineConfigurations(
            in: directory,
            fallbackUsername: "current-user"
        )

        XCTAssertEqual(machines.map(\.id), ["bellerofonte", "vm-test"])
        XCTAssertEqual(machines[0].machineName, "Bellerofonte")
        XCTAssertEqual(machines[0].machineType, "macbook-pro")
        XCTAssertEqual(machines[0].username, "batman")
        XCTAssertEqual(machines[0].profiles, ["dev", "local-ai"])
        XCTAssertEqual(machines[1].username, "current-user")
    }

    func testSavedMachineSuggestionRequiresAnExactHostnameMatch() {
        let machines = [
            InstallationMachineConfiguration(
                id: "bellerofonte",
                hostname: "bellerofonte",
                machineName: "Bellerofonte",
                username: "batman",
                machineType: "macbook-pro",
                profiles: ["dev"]
            )
        ]

        XCTAssertEqual(
            FirstInstallationStore.suggestedMachineID(
                in: machines,
                detectedHostname: "bellerofonte"
            ),
            "bellerofonte"
        )
        XCTAssertNil(
            FirstInstallationStore.suggestedMachineID(
                in: machines,
                detectedHostname: "lucas-macbook-pro"
            )
        )
    }

    func testMachineTypeDetectionRecognizesAppleVirtualMachines() {
        XCTAssertEqual(
            FirstInstallationStore.machineType(forHardwareModel: "VirtualMac2,1"),
            "vm"
        )
    }

    func testMachineTypeDetectionKeepsPhysicalMacFamiliesDistinct() {
        XCTAssertEqual(
            FirstInstallationStore.machineType(forHardwareModel: "MacBookPro18,3"),
            "macbook-pro"
        )
        XCTAssertEqual(
            FirstInstallationStore.machineType(forHardwareModel: "Macmini9,1"),
            "macmini"
        )
        XCTAssertEqual(
            FirstInstallationStore.machineType(forHardwareModel: "MacBookAir10,1"),
            "macbook"
        )
    }

    func testSuccessfulInstallationCreatesBootstrapCompletionMarker() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }

        FirstInstallationStore.recordSuccessfulInstallation(environment: [
            "NIX_ME_SETUP_COMPLETION_MARKER": marker.path,
        ])

        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testSuccessfulInstallationWithoutBootstrapMarkerIsANoOp() {
        FirstInstallationStore.recordSuccessfulInstallation(environment: [:])
    }

    func testErrorSummaryPrefersTheConcreteFailureNearTheEnd() {
        let error = ManagementAPIError.commandFailed(
            1,
            """
            751:817: execution error: setting up /Applications/Nix Apps...
            setting up pam...
            ln: failed to create symbolic link '/etc/pam.d/sudo_local': Operation not permitted (1)
            """
        )

        XCTAssertEqual(
            FirstInstallationStore.errorSummary(error),
            "ln: failed to create symbolic link '/etc/pam.d/sudo_local': Operation not permitted (1)"
        )
    }

    func testRepeatedProgressDoesNotCreateDuplicateConsoleEntries() {
        XCTAssertFalse(FirstInstallationStore.shouldAppendProgress(
            currentPhase: .preparation,
            currentMessage: "Checking the host, configuration, and required tools",
            nextPhase: .preparation,
            nextMessage: "Checking the host, configuration, and required tools"
        ))
        XCTAssertTrue(FirstInstallationStore.shouldAppendProgress(
            currentPhase: .preparation,
            currentMessage: "Checking the host, configuration, and required tools",
            nextPhase: .build,
            nextMessage: "Evaluating and building the new system generation"
        ))
    }

    func testInterruptedInstallationRestoresTheExplicitHostSelection() throws {
        let directory = try makeConfigurationDirectory(hostname: "bellerofonte")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (persistence, cleanup) = makeSessionPersistence()
        defer { cleanup() }

        persistence.save(session(
            configurationDirectory: directory,
            selection: .existing,
            hostname: "bellerofonte",
            installAttempted: true
        ))

        let store = FirstInstallationStore(
            configurationDirectory: directory,
            sessionPersistence: persistence
        )

        XCTAssertEqual(store.machineSelection, .existing("bellerofonte"))
        XCTAssertEqual(store.hostname, "bellerofonte")
        XCTAssertEqual(store.screen, .review)
        XCTAssertTrue(store.resumeMessage?.contains("interrupted") == true)
    }

    func testCreatedHostBecomesAnExistingSelectionWhenSetupRestarts() throws {
        let directory = try makeConfigurationDirectory(hostname: "bellerofonte")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (persistence, cleanup) = makeSessionPersistence()
        defer { cleanup() }

        persistence.save(session(
            configurationDirectory: directory,
            selection: .createNew,
            hostname: "bellerofonte",
            installAttempted: true
        ))

        let store = FirstInstallationStore(
            configurationDirectory: directory,
            sessionPersistence: persistence
        )

        XCTAssertEqual(store.machineSelection, .existing("bellerofonte"))
        XCTAssertTrue(store.configurationExists)
        XCTAssertEqual(store.screen, .review)
    }

    func testSetupSessionDoesNotLeakAcrossConfigurationCheckouts() throws {
        let firstDirectory = try makeConfigurationDirectory(hostname: "bellerofonte")
        let secondDirectory = try makeConfigurationDirectory(
            hostname: "unrelated-\(UUID().uuidString.lowercased())"
        )
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let (persistence, cleanup) = makeSessionPersistence()
        defer { cleanup() }

        persistence.save(session(
            configurationDirectory: firstDirectory,
            selection: .existing,
            hostname: "bellerofonte",
            installAttempted: true
        ))

        let store = FirstInstallationStore(
            configurationDirectory: secondDirectory,
            sessionPersistence: persistence
        )

        XCTAssertNil(store.resumeMessage)
        XCTAssertEqual(store.machineSelection, nil)
        XCTAssertEqual(store.screen, .welcome)
    }

    private func makeConfigurationDirectory(hostname: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        {
          outputs = inputs: {
            darwinConfigurations = {
              "\(hostname)" = mkDarwinSystem {
                hostname = "\(hostname)";
                machineType = "macbook-pro";
                machineName = "Bellerofonte";
                username = "batman";
                extraModules = [ ./nix/hosts/profiles/dev.nix ];
              };
            };
          };
        }
        """.write(
            to: directory.appendingPathComponent("flake.nix"),
            atomically: true,
            encoding: .utf8
        )
        return directory
    }

    private func makeSessionPersistence() -> (
        FirstInstallationSessionPersistence,
        () -> Void
    ) {
        let suiteName = "FirstInstallationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (
            FirstInstallationSessionPersistence(defaults: defaults),
            { defaults.removePersistentDomain(forName: suiteName) }
        )
    }

    private func session(
        configurationDirectory: URL,
        selection: FirstInstallationSessionSelection,
        hostname: String,
        installAttempted: Bool
    ) -> FirstInstallationSession {
        FirstInstallationSession(
            schemaVersion: FirstInstallationSession.schemaVersion,
            configurationDirectory: FirstInstallationSessionPersistence.normalizedPath(
                configurationDirectory
            ),
            selection: selection,
            hostname: hostname,
            machineName: "Bellerofonte",
            username: "batman",
            machineType: "macbook-pro",
            selectedProfiles: ["dev"],
            appStateEnabled: true,
            installAttempted: installAttempted
        )
    }
}
