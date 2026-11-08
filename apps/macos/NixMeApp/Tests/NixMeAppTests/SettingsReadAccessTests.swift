import XCTest

@testable import NixMeApp

final class SettingsReadAccessTests: XCTestCase {
    func testAllowActionBecomesCheckAgainImmediatelyAfterApproval() throws {
        let app = try application()
        var approvals = AppSettingsReadApprovals()
        let before = access(app, approvals)
        XCTAssertTrue(before.requiresApproval)
        XCTAssertEqual(before.previewLabel, "Allow & Preview")
        XCTAssertEqual(before.previewSymbol, "hand.raised")

        approvals.grant(app, checkout: "/checkout", hostname: "mac")
        let after = access(app, approvals)
        XCTAssertFalse(after.requiresApproval)
        XCTAssertEqual(after.previewLabel, "Check Again")
        XCTAssertEqual(after.previewSymbol, "arrow.clockwise")
        XCTAssertFalse(app.canCheckSettingsAutomatically, "Approval must not enable background file reads")
    }

    func testApprovalSurvivesNewDestinationOrFailedAndEmptyReviews() throws {
        let app = try application()
        var approvals = AppSettingsReadApprovals()
        approvals.grant(app, checkout: "/checkout", hostname: "mac")
        let reviews: [AppSettingsReview?] = [
            nil,
            AppSettingsReview(response: nil, error: "Read failed", checkedAt: Date()),
            AppSettingsReview(response: nil, error: nil, noPreferences: "No file yet", checkedAt: Date()),
        ]
        for scope in [AppSettingsScope.machine, .shared, .profile] {
            for review in reviews {
                let state = AppSettingsCardState(application: app,
                    target: AppSettingsTarget(scope: scope, profile: "work", hostname: "mac"), review: review,
                    readApproved: approvals.contains(app, checkout: "/checkout", hostname: "mac"))
                XCTAssertNotEqual(state.action, "Review access")
                XCTAssertFalse(state.summary.contains("Permission needed"))
                XCTAssertEqual(access(app, approvals).previewLabel, "Check Again")
            }
        }
    }

    func testApprovalDoesNotCarryAcrossSourceOrCheckoutBoundaries() throws {
        let app = try application()
        var approvals = AppSettingsReadApprovals()
        approvals.grant(app, checkout: "/checkout", hostname: "mac")

        XCTAssertFalse(approvals.contains(app, checkout: "/other-checkout", hostname: "mac"))
        XCTAssertFalse(approvals.contains(app, checkout: "/checkout", hostname: "other-mac"))
        for changed in [
            try application(id: "other-app"),
            try application(bundleID: "com.example.other"),
            try application(recipePath: "recipes/replacement.yaml"),
            try application(sources: ["~/other-config"]),
            try application(sources: ["~/config", "~/extra-config"]),
        ] {
            XCTAssertFalse(approvals.contains(changed, checkout: "/checkout", hostname: "mac"))
            XCTAssertTrue(access(changed, approvals).requiresApproval)
        }
    }

    func testApprovalSurvivesCatalogReloadAndSourceReorderingButNotNewSession() throws {
        var approvals = AppSettingsReadApprovals()
        approvals.grant(try application(sources: ["~/config", "~/extra-config"]), checkout: "/checkout", hostname: "mac")
        let reloaded = try application(sources: ["~/extra-config", "~/config"])
        XCTAssertTrue(approvals.contains(reloaded, checkout: "/checkout", hostname: "mac"))
        XCTAssertFalse(AppSettingsReadApprovals().contains(reloaded, checkout: "/checkout", hostname: "mac"))
    }

    func testPrivateOrUnavailableApplicationsCannotGainReadApproval() throws {
        for app in [try application(privateState: true), try application(installed: false), try application(capturable: false)] {
            var approvals = AppSettingsReadApprovals()
            approvals.grant(app, checkout: "/checkout", hostname: "mac")
            XCTAssertFalse(approvals.contains(app, checkout: "/checkout", hostname: "mac"))
        }
    }

    func testOrdinaryPreferencesNeverOfferAllowAction() throws {
        let app = try application(requiresConfirmation: false)
        XCTAssertFalse(access(app, AppSettingsReadApprovals()).requiresApproval)
        XCTAssertEqual(access(app, AppSettingsReadApprovals()).previewLabel, "Check Again")
    }

    private func access(_ app: AppStateSettingsApplication, _ approvals: AppSettingsReadApprovals) -> AppSettingsReadAccess {
        AppSettingsReadAccess(application: app, approved: approvals.contains(app, checkout: "/checkout", hostname: "mac"))
    }

    private func application(
        id: String = "example", bundleID: String = "com.example.app", recipePath: String = "recipes/example.yaml",
        sources: [String] = ["~/config"], requiresConfirmation: Bool = true,
        privateState: Bool = false, installed: Bool = true, capturable: Bool = true
    ) throws -> AppStateSettingsApplication {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id, "name": "Example", "bundleId": bundleID, "recipePath": recipePath,
            "installed": installed, "capturable": capturable, "captureKinds": ["file"],
            "configurationSources": [], "exportableSettings": sources.map {
                ["kind": "file", "label": "Settings", "source": $0, "requiresConfirmation": requiresConfirmation] as [String: Any]
            },
            "privateState": privateState ? ["readiness": "ready", "exclusionReason": "Private data"] : NSNull(),
        ])
        return try JSONDecoder().decode(AppStateSettingsApplication.self, from: data)
    }
}
