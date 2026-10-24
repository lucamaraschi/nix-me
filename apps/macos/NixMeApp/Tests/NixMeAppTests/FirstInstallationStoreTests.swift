import XCTest

@testable import NixMeApp

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
}
