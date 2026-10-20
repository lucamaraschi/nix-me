import XCTest

@testable import NixMeApp

final class FirstInstallationStoreTests: XCTestCase {
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
