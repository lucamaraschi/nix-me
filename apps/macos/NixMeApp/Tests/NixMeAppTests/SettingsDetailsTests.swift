import XCTest

@testable import NixMeApp

final class SettingsDetailsTests: XCTestCase {
    func testDetailsWithoutApprovalContainsMetadataButNoCapturedValues() throws {
        let report = AppSettingsDetailsReport(application: try application(), target: target(.machine), review: nil).text
        XCTAssertTrue(report.contains("Example"))
        XCTAssertTrue(report.contains("~/Library/Example/config"))
        XCTAssertTrue(report.contains("config/app-state/machines/mac/settings.json"))
        XCTAssertFalse(report.contains("Reviewed export"))
    }

    func testDetailsCopiesOnlyTheExistingReviewedPreview() throws {
        let report = AppSettingsDetailsReport(application: try application(), target: target(.shared), review: try review()).text
        XCTAssertTrue(report.contains("Reviewed export (JSON)\n{\"fontSize\":14}"))
        XCTAssertTrue(report.contains("Not included (manual): Set up separately"))
        XCTAssertTrue(report.contains("Saving for: All machines"))
        XCTAssertFalse(report.contains("review-token"))
    }

    func testFailedReviewDoesNotCopyAnOlderPreview() throws {
        let oldReview = try review()
        let failed = AppSettingsReview(response: oldReview.response, error: "Permission denied", checkedAt: Date())
        let report = AppSettingsDetailsReport(application: try application(), target: target(.machine), review: failed).text
        XCTAssertTrue(report.contains("Permission denied"))
        XCTAssertFalse(report.contains("fontSize"))
        XCTAssertFalse(report.contains("Reviewed export"))
    }

    func testDetailsDistinguishesTheDestinationFromOtherConfigurationSources() throws {
        let report = AppSettingsDetailsReport(application: try application(), target: target(.profile), review: nil).text
        XCTAssertTrue(report.contains("Destination: config/app-state/profiles/work/settings.json"))
        XCTAssertTrue(report.contains("All machines: config/app-state/shared/settings.json"))
    }

    func testAccessErrorsExplainThatRetryingDoesNotGrantPermissions() {
        for message in ["Operation not permitted (os error 1)", "Permission denied (os error 13)"] {
            let failure = AppSettingsReadFailure(message: message)
            XCTAssertTrue(failure.isAccessDenied)
            XCTAssertTrue(failure.guidance?.contains("Resolve Access") == true)
        }
        for message in ["File missing (os error 2)", "Read failed (os error 111)", "Invalid JSON"] {
            let failure = AppSettingsReadFailure(message: message)
            XCTAssertFalse(failure.isAccessDenied)
            XCTAssertNil(failure.guidance)
        }
    }

    private func target(_ scope: AppSettingsScope) -> AppSettingsTarget {
        AppSettingsTarget(scope: scope, profile: "work", hostname: "mac")
    }

    private func application() throws -> AppStateSettingsApplication {
        try JSONDecoder().decode(AppStateSettingsApplication.self, from: Data(#"""
            {"id":"example","name":"Example","bundleId":"org.example.app",
             "installed":true,"capturable":true,"captureKinds":["file"],
             "exportableSettings":[{"kind":"file","label":"Reviewed file",
               "source":"~/Library/Example/config","requiresConfirmation":true}],
             "configurationSources":[{"scope":"shared","label":"All machines",
               "path":"config/app-state/shared/settings.json"}]}
            """#.utf8))
    }

    private func review() throws -> AppSettingsReview {
        let response = try JSONDecoder().decode(AppSettingsCaptureResponse.self, from: Data(#"""
            {"schemaVersion":1,"action":"settings-preview","success":true,"appId":"example",
             "scope":"shared","destination":"config/app-state/shared/settings.json","changed":true,
             "written":false,"tracked":false,"preview":"{\"fontSize\":14}","reviewToken":"review-token",
             "redaction":{"policy":"default_closed","count":0,"items":[]},"captured":[],
             "skipped":[{"kind":"manual","reason":"Set up separately"}],"message":"Preview"}
            """#.utf8))
        return AppSettingsReview(response: response, error: nil, checkedAt: Date())
    }
}
