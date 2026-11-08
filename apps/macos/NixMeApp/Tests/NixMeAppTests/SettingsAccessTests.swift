import XCTest
@testable import NixMeApp

final class SettingsAccessTests: XCTestCase {
    func testPrivacyAndFilesystemFailuresHaveDifferentRemedies() {
        let privacy = AppSettingsReadFailure(message: "Operation not permitted (os error 1)")
        XCTAssertEqual(privacy.kind, .privacy)
        XCTAssertTrue(privacy.guidance!.contains("macOS approval"))
        let filesystem = AppSettingsReadFailure(message: "Permission denied (os error 13)")
        XCTAssertEqual(filesystem.kind, .filesystem)
        XCTAssertTrue(filesystem.guidance!.contains("ownership"))
        XCTAssertEqual(AppSettingsReadFailure(message: "missing (os error 2)").kind, .other)
        XCTAssertEqual(AppSettingsReadFailure(message: "connect failed (os error 111)").kind, .other)
        XCTAssertEqual(AppSettingsReadFailure(message: "Invalid JSON").kind, .other)
    }

    func testOpeningSettingsDoesNotImplyAccessWasGranted() {
        let old = AppSettingsReview(response: nil, error: "Operation not permitted", checkedAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(state(nil, old), .waiting)
        XCTAssertEqual(state(Date(timeIntervalSince1970: 2), old), .waiting)
        XCTAssertEqual(SettingsAccessVerification.state(requestedAt: Date(), review: old, busy: true), .checking)
    }

    func testVerificationDistinguishesDenialEmptyAndOtherFailures() {
        let start = Date(timeIntervalSince1970: 1)
        let end = Date(timeIntervalSince1970: 2)
        XCTAssertEqual(state(start, AppSettingsReview(response: nil, error: "Permission denied", checkedAt: end)), .blocked)
        XCTAssertEqual(state(start, AppSettingsReview(response: nil, error: "Unsupported format", checkedAt: end)), .otherFailure)
        XCTAssertEqual(state(start, AppSettingsReview(response: nil, error: nil, noPreferences: "Nothing found", checkedAt: end)), .empty)
        XCTAssertEqual(state(start, AppSettingsReview(response: nil, error: nil, checkedAt: end)), .waiting)
    }

    func testOnlyFreshSuccessfulReadsResolveAccess() throws {
        let response = try preview(skipped: "[]")
        let review = AppSettingsReview(response: response, error: nil, checkedAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(state(Date(timeIntervalSince1970: 1), review), .readable)
        XCTAssertEqual(state(Date(timeIntervalSince1970: 3), review), .waiting)
        let partial = try preview(skipped: #"[{"kind":"file","reason":"Permission denied"}]"#)
        XCTAssertEqual(state(Date(timeIntervalSince1970: 1), AppSettingsReview(response: partial, error: nil,
            checkedAt: Date(timeIntervalSince1970: 2))), .blocked)
    }

    func testAdHocAndUnknownSignaturesAreNotReportedAsStable() {
        XCTAssertEqual(RunningAppIdentity.classify(flags: 2, certificateCount: 0), .adHoc)
        XCTAssertEqual(RunningAppIdentity.classify(flags: 2, certificateCount: 1), .adHoc)
        XCTAssertEqual(RunningAppIdentity.classify(flags: nil, certificateCount: 0), .unknown)
        XCTAssertEqual(RunningAppIdentity.classify(flags: 0, certificateCount: 0), .unknown)
        XCTAssertEqual(RunningAppIdentity.classify(flags: 0, certificateCount: 1), .certificate)
    }

    private func state(_ start: Date?, _ review: AppSettingsReview) -> SettingsAccessVerification.State {
        SettingsAccessVerification.state(requestedAt: start, review: review, busy: false)
    }

    private func preview(skipped: String) throws -> AppSettingsCaptureResponse {
        try JSONDecoder().decode(AppSettingsCaptureResponse.self, from: Data("""
        {"schemaVersion":1,"action":"settings-preview","success":true,"appId":"example",
         "scope":"machine","destination":"config/app-state/machines/test/settings.json",
         "changed":true,"written":false,"tracked":false,"preview":"{}",
         "redaction":{"policy":"default_closed","count":0,"items":[]},"captured":[],
         "skipped":\(skipped),"message":"Preview","reviewToken":"test-token"}
        """.utf8))
    }
}
