import XCTest

@testable import NixMeApp

final class InstallationRunControlTests: XCTestCase {
    func testPauseAndResumeUseTheSharedControlFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = InstallationRunControl(temporaryDirectory: directory)

        try control.start()
        XCTAssertEqual(try controlValue(control), "running")

        try control.requestPause()
        control.markPaused()
        XCTAssertEqual(control.currentState, .paused)
        XCTAssertEqual(try controlValue(control), "pause")

        let waiter = Task { try await control.waitIfPaused() }
        try await Task.sleep(for: .milliseconds(50))
        try control.resume()
        try await waiter.value

        XCTAssertEqual(control.currentState, .running)
        XCTAssertEqual(try controlValue(control), "running")
    }

    func testStopPersistsAStoppedControlState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = InstallationRunControl(temporaryDirectory: directory)

        try control.start()
        control.requestStop()
        control.markStopped()

        XCTAssertEqual(control.currentState, .stopped)
        XCTAssertEqual(try controlValue(control), "stop")
    }

    func testStopTerminatesTheRegisteredPreActivationProcess() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = InstallationRunControl(temporaryDirectory: directory)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]

        try control.start()
        try process.run()
        try control.register(process)
        control.requestStop()
        process.waitUntilExit()

        XCTAssertFalse(process.isRunning)
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertEqual(control.currentState, .stopping)
    }

    func testOverallProgressUsesObservedPackageProgress() {
        let packages = [
            InstallerPackageActivity(
                id: "nix:a",
                phase: .build,
                manager: .nix,
                name: "a",
                state: .complete,
                detail: "complete",
                fractionCompleted: 1,
                sequence: 1
            ),
            InstallerPackageActivity(
                id: "nix:b",
                phase: .build,
                manager: .nix,
                name: "b",
                state: .building,
                detail: "building",
                fractionCompleted: 0.5,
                sequence: 2
            ),
        ]

        XCTAssertEqual(
            InstallerProgressCalculator.fraction(
                phase: .build,
                isRunning: true,
                isComplete: false,
                steps: [],
                packages: packages
            ),
            0.55,
            accuracy: 0.001
        )
        XCTAssertEqual(
            InstallerProgressCalculator.fraction(
                phase: .verification,
                isRunning: false,
                isComplete: true,
                steps: [],
                packages: []
            ),
            1
        )
    }

    private func controlValue(_ control: InstallationRunControl) throws -> String {
        try String(contentsOf: control.controlFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
