import XCTest
@testable import NixMeApp

final class MachineDriftTests: XCTestCase {
    func testProposalMustMatchBothSelectionAndScan() {
        let proposal = MachineDriftProposal(token: "scan", ids: ["cask:app"], proposalToken: "review", destination: "test.json", needsSavingSupport: false, files: [])
        XCTAssertTrue(proposal.matches(MachineDriftRequest(token: "scan", ids: ["cask:app"])))
        XCTAssertFalse(proposal.matches(MachineDriftRequest(token: "other", ids: ["cask:app"])))
        XCTAssertFalse(proposal.matches(MachineDriftRequest(token: "scan", ids: ["cask:other"])))
    }

    func testSoftwareDoesNotRequireReadingFileContents() throws {
        XCTAssertTrue(MachineDriftSelection.canPrepare([try item("formula:tool", kind: "formula")]))
        XCTAssertFalse(MachineDriftSelection.canPrepare([try item("cask:app", kind: "cask", canKeep: false)]))
        XCTAssertFalse(MachineDriftSelection.canPrepare([]))
    }

    func testChangingDestinationRequiresNewReview() {
        var proposal = MachineDriftProposal(token: "scan", ids: ["cask:app"], proposalToken: "review", destination: "dev.json", needsSavingSupport: false, files: [])
        proposal.destinationID = "profile:dev"
        XCTAssertTrue(proposal.matches(MachineDriftRequest(token: "scan", ids: ["cask:app"], destinationID: "profile:dev")))
        XCTAssertFalse(proposal.matches(MachineDriftRequest(token: "scan", ids: ["cask:app"], destinationID: "shared:all")))
    }

    func testDotfilesRestrictTheDestinationToThisMachine() throws {
        let shared = MachineDriftDestination(id: "shared:all", scope: "shared", name: "all", source: "shared.nix", path: "shared.json", hosts: ["one", "two"])
        XCTAssertTrue(shared.accepts([try item("formula:tool", kind: "formula")]))
        XCTAssertFalse(shared.accepts([try item("file:config", kind: "file")]))
        XCTAssertEqual(shared.title, "Shared defaults")
    }

    func testEachItemKeepsItsOwnDestinationWithMachineDefault() throws {
        let app = try item("cask:app", kind: "cask")
        let tool = try item("formula:tool", kind: "formula")
        let file = try item("file:config", kind: "file")
        let choices = [app.id: "profile:work", file.id: "shared:all", "cask:unselected": "profile:dev"]
        let selected = MachineDriftSelection.destinationsByItem([app, tool, file], choices: choices, host: "test")
        XCTAssertEqual(selected, [app.id: "profile:work", tool.id: "machine:test", file.id: "machine:test"])
        XCTAssertEqual(MachineDriftSelection.destinationsByItem([app], choices: choices, host: "test"), [app.id: "profile:work"])
    }

    func testMixedDestinationReviewIsBoundToEveryItemAssignment() {
        var proposal = MachineDriftProposal(token: "scan", ids: ["cask:app", "formula:tool"], proposalToken: "review", destination: "dev.json", needsSavingSupport: false, files: [])
        let destinations = ["cask:app": "machine:test", "formula:tool": "profile:dev"]
        proposal.destinationsByItem = destinations
        var request = MachineDriftRequest(token: "scan", ids: ["formula:tool", "cask:app"], destinationsByItem: destinations)
        XCTAssertTrue(proposal.matches(request))
        request.destinationsByItem?["cask:app"] = "profile:dev"
        XCTAssertFalse(proposal.matches(request))
        request.destinationsByItem = ["formula:tool": "profile:dev"]
        XCTAssertFalse(proposal.matches(request))
    }

    func testIncompleteScanDoesNotClaimNoDrift() {
        let plan = MachineDriftPlan(schemaVersion: 1, host: "test", token: "token", checkedAt: "now", destination: "test.json", items: [], warnings: ["Homebrew unavailable"])
        XCTAssertEqual(plan.summary, "Some areas could not be checked")
    }

    func testRestoreLabelsWarnOfUninstallation() throws {
        XCTAssertEqual(try item("cask:app", kind: "cask").restoreEffect, "Uninstall app")
        XCTAssertEqual(try item("file:config", kind: "file").restoreEffect, "Back up and restore config")
    }

    func testSavingAnExtraAppChangesConfigurationNotMachine() throws {
        let app = try item("cask:app", kind: "cask")
        XCTAssertEqual(app.saveEffect, "Add app to the configuration")
        XCTAssertEqual(app.restoreEffect, "Uninstall app")
    }

    func testPublicationStatusNeverClaimsAFreshRemoteCheck() {
        let saved = MachineDriftPublication(path: "test.json", state: "localChanges")
        XCTAssertEqual(saved.title, "Configuration changes to commit")
        let clean = MachineDriftPublication(path: "test.json", state: "matchesLastKnownUpstream")
        XCTAssertTrue(clean.detail.contains("Remote status has not been refreshed"))
    }

    private func item(_ id: String, kind: String, canKeep: Bool = true) throws -> MachineDriftItem {
        let name = id.components(separatedBy: ":").last!
        return MachineDriftItem(id: id, kind: kind, name: name, change: "extra", current: "Local", expected: "Absent", canKeep: canKeep, canRestore: true, note: "", conflict: nil)
    }
}
