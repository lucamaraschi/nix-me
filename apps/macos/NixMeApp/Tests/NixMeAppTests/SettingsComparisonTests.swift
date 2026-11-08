import XCTest

@testable import NixMeApp

final class SettingsComparisonTests: XCTestCase {
    func testExportIsDestinationSpecificAndExcludesBuiltInDefaults() throws {
        let app = try application(sources: [
            ["scope": "builtIn", "label": "Defaults", "path": "packages/app-state/values/rectangle.yaml"],
            ["scope": "shared", "label": "All machines", "path": "config/app-state/shared/settings.json"],
            [
                "scope": "profile", "label": "Work", "path": "config/app-state/profiles/work/settings.json",
                "propertyPaths": ["/gapSize"],
            ],
            ["scope": "machine", "label": "Mac", "path": "config/app-state/machines/mac/manual.json"],
        ])
        XCTAssertTrue(target(.shared).isExported(app))
        XCTAssertTrue(target(.profile, "work").isExported(app))
        XCTAssertFalse(target(.profile, "work-extra").isExported(app))
        XCTAssertFalse(target(.machine).isExported(app))
        XCTAssertEqual(target(.machine).sources(in: app).count, 1)
        XCTAssertEqual(target(.profile, "work").sources(in: app).first?.propertyPaths, ["/gapSize"])
        let defaults = try application(sources: [
            ["scope": "builtIn", "label": "Defaults", "path": "packages/app-state/values/rectangle.yaml"]
        ])
        XCTAssertFalse(target(.shared).isExported(defaults))
    }

    func testUnknownAndFailedAreNotReportedAsMatching() throws {
        let app = try application(sources: [])
        let unknown = AppSettingsSummary(applications: [app], target: target(.machine), reviews: [:])
        XCTAssertEqual(unknown.uncheckedCount, 1)
        XCTAssertEqual(unknown.differentCount, 0)
        let failed = AppSettingsSummary(
            applications: [app], target: target(.machine),
            reviews: [
                app.id: AppSettingsReview(response: nil, error: "Could not read", checkedAt: Date())
            ])
        XCTAssertEqual(failed.failedCount, 1)
        XCTAssertEqual(failed.uncheckedCount, 0)
        XCTAssertEqual(failed.differentCount, 0)
    }

    func testComparisonDecodesStatusesAndRetainsExactPropertyPaths() throws {
        let comparison = try JSONDecoder().decode(
            AppSettingsComparison.self,
            from: Data(
                #"""
                {"properties":[
                    {"path":"/editor.fontSize","currentValue":"14","status":"notSaved"},
                    {"path":"/nested/a~1b","currentValue":"false","status":"different"},
                    {"path":"/empty","currentValue":"null","status":"matching"}
                ],"preservedCount":2}
                """#.utf8))
        XCTAssertEqual(comparison.differenceCount, 2)
        XCTAssertEqual(comparison.properties.map(\.path), ["/editor.fontSize", "/nested/a~1b", "/empty"])
        XCTAssertEqual(comparison.preservedCount, 2)
    }

    func testOlderPreviewResponseDecodesAndSavedReviewIsNoLongerPending() throws {
        let json = #"""
            {"schemaVersion":1,"action":"settings-save","success":true,"appId":"rectangle",
             "scope":"shared","destination":"config/app-state/shared/settings.json","changed":true,
             "written":true,"tracked":true,"preview":"{}","redaction":{"policy":"default_closed","count":0,"items":[]},
             "captured":[],"skipped":[],"message":"Saved"}
            """#
        let response = try JSONDecoder().decode(AppSettingsCaptureResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.reviewToken)
        XCTAssertNil(response.comparison)
        let review = AppSettingsReview(response: response, error: nil, checkedAt: Date())
        XCTAssertEqual(review.differenceCount, 0)
        XCTAssertEqual(review.label, "Saved in this session")
    }

    func testReviewFlowOnlyOffersSavingAfterFreshSupportedPreview() throws {
        XCTAssertEqual(AppSettingsReview(response: nil, error: nil, checkedAt: Date()).phase, .unreviewed)
        XCTAssertEqual(try review(changed: true).phase, .ready)
        XCTAssertEqual(try review(changed: false).phase, .unchanged)
        XCTAssertEqual(try review(changed: true, written: true).phase, .saved)
        XCTAssertEqual(try review(changed: true, token: nil).phase, .needsUpdate)
    }

    func testFailedReviewCannotExposeSaveEvenWithPreviousResponse() throws {
        let previous = try review(changed: true)
        let failed = AppSettingsReview(response: previous.response, error: "Read failed", checkedAt: Date())
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.differenceCount, 0)
        XCTAssertEqual(failed.label, "Could not check settings")
    }

    func testReadableSettingNamesRetainExactPaths() {
        let property = AppSettingsProperty(path: "/windowSettings/gapSize", currentValue: "8", status: .different)
        XCTAssertEqual(property.displayName, "Window Settings / Gap Size")
        XCTAssertEqual(property.path, "/windowSettings/gapSize")
        let escaped = AppSettingsProperty(path: "/editor.fontSize/a~1b/~0name", currentValue: "null", status: .matching)
        XCTAssertEqual(escaped.displayName, "Editor.font Size / A/b / ~name")
    }

    func testReviewUsesDocumentedLabelsWithoutGuessingAmbiguousKeys() {
        let property = AppSettingsProperty(path: "/SUEnableAutomaticChecks", currentValue: "true", status: .notSaved)
        let setting = AppStateExportableSetting(
            kind: "preference",
            label: "Settings > About > Automatically check for updates",
            source: "com.example.App/SUEnableAutomaticChecks", requiresConfirmation: false)
        XCTAssertEqual(property.displayName(settings: [setting]), "Automatically check for updates")
        XCTAssertEqual(property.displayName(settings: [setting, setting]), property.displayName)
        XCTAssertEqual(property.displayValue, "Yes")
        XCTAssertEqual(property.currentValue, "true")
    }

    func testCollectionSeparatesFirstSavesFromChangesToSavedCopies() throws {
        let app = try application(sources: [
            ["scope": "machine", "label": "Mac", "path": "config/app-state/machines/mac/settings.json"]
        ])
        let changed = try review(changed: true)
        let savedTarget = AppSettingsCardState(application: app, target: target(.machine), review: changed)
        let newTarget = AppSettingsCardState(application: app, target: target(.shared), review: changed)
        XCTAssertEqual(savedTarget.collection, .changes)
        XCTAssertEqual(savedTarget.action, "See changes")
        XCTAssertEqual(newTarget.collection, .newApps)
        XCTAssertEqual(newTarget.action, "See settings")
    }

    func testSavedButUncheckedCardDoesNotClaimPreferencesMatch() throws {
        let app = try application(sources: [
            ["scope": "machine", "label": "Mac", "path": "config/app-state/machines/mac/settings.json"]
        ])
        let state = AppSettingsCardState(application: app, target: target(.machine), review: nil)
        XCTAssertEqual(state.collection, .saved)
        XCTAssertEqual(state.summary, "Saved copy available. Not checked yet.")
    }

    func testCollectionShowsFailuresRatherThanStaleMatchingOrReadyStates() throws {
        let app = try application(sources: [])
        let failed = AppSettingsReview(response: try review(changed: false).response, error: "Read failed", checkedAt: Date())
        for result in [failed, try review(changed: true, token: nil)] {
            let state = AppSettingsCardState(application: app, target: target(.machine), review: result)
            XCTAssertEqual(state.collection, .attention)
            XCTAssertEqual(state.action, "View issue")
        }
    }

    func testConfirmedMatchingAndSavedReviewsMoveIntoSavedCollection() throws {
        let app = try application(sources: [])
        for result in [try review(changed: false), try review(changed: true, written: true)] {
            let state = AppSettingsCardState(application: app, target: target(.machine), review: result)
            XCTAssertEqual(state.collection, .saved)
            XCTAssertEqual(state.action, "View saved settings")
        }
    }

    func testAutomaticChecksNeverReadConsentRequiredOrPrivateSettings() throws {
        let reviewedFile = try application(sources: [], requiresConfirmation: true)
        XCTAssertFalse(reviewedFile.canCheckSettingsAutomatically)
        let state = AppSettingsCardState(application: reviewedFile, target: target(.machine), review: nil)
        XCTAssertEqual(state.action, "Review access")
        XCTAssertEqual(state.summary, "Permission needed to preview the settings file")
        let privateApp = try application(sources: [], privateState: true)
        XCTAssertFalse(privateApp.canCheckSettingsAutomatically)
        XCTAssertTrue(try application(sources: []).canCheckSettingsAutomatically)
    }

    func testNoPreferencesIsNeitherFailureNorMatching() throws {
        let app = try application(sources: [])
        let review = AppSettingsReview(response: nil, error: nil, noPreferences: "Nothing found", checkedAt: Date())
        XCTAssertEqual(review.phase, .empty)
        XCTAssertEqual(review.differenceCount, 0)
        let state = AppSettingsCardState(application: app, target: target(.machine), review: review)
        XCTAssertEqual(state.collection, .empty)
        XCTAssertEqual(state.summary, "No preferences to save yet")
        let summary = AppSettingsSummary(applications: [app], target: target(.machine), reviews: [app.id: review])
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.uncheckedCount, 0)
    }

    func testDetailSummaryDistinguishesFirstSaveFromUpdatingASavedCopy() throws {
        let app = try application(sources: [
            ["scope": "machine", "label": "Mac", "path": "config/app-state/machines/mac/settings.json"]
        ])
        let firstSave = AppSettingsDetailSummary(application: app, target: target(.shared), review: try review(changed: true))
        XCTAssertEqual(firstSave.repositoryStatus, "No saved copy yet")
        XCTAssertEqual(firstSave.title, "Keep Rectangle the way you like it")
        XCTAssertTrue(firstSave.message.contains("All machines"))
        let update = AppSettingsDetailSummary(application: app, target: target(.machine), review: try review(changed: true))
        XCTAssertEqual(update.repositoryStatus, "Changes to save")
        XCTAssertEqual(update.title, "Your preferences have changed")
    }

    func testDetailSummaryUsesSaveResponseBeforeCatalogRefresh() throws {
        let app = try application(sources: [])
        let saved = AppSettingsDetailSummary(application: app, target: target(.shared), review: try review(changed: true, written: true))
        XCTAssertEqual(saved.repositoryStatus, "Saved just now")
        XCTAssertEqual(saved.title, "Your preferences are saved")
        XCTAssertTrue(saved.message.contains("hasn't been published"))
        let matching = AppSettingsDetailSummary(application: app, target: target(.shared), review: try review(changed: false))
        XCTAssertEqual(matching.repositoryStatus, "Matches this Mac")
        XCTAssertTrue(matching.message.contains("preferences we checked"))
    }

    func testDetailSummaryDoesNotCallFailedOrOldPreviewsUpToDate() throws {
        let app = try application(sources: [])
        for review in [try review(changed: true, token: nil), AppSettingsReview(response: nil, error: "Read failed", checkedAt: Date())] {
            let summary = AppSettingsDetailSummary(application: app, target: target(.machine), review: review)
            XCTAssertNotEqual(summary.repositoryStatus, "Matches this Mac")
            XCTAssertNotEqual(summary.title, "Your preferences are saved")
        }
    }

    func testPropertyGroupsUseDocumentedAppSectionsWithoutGuessingValues() {
        let settings = [
            AppStateExportableSetting(kind: "preference", label: "Zoom > Settings > General > Language",
                source: "example/language", requiresConfirmation: false),
            AppStateExportableSetting(kind: "preference", label: "Settings > Layout > Gaps",
                source: "example/gap", requiresConfirmation: false),
        ]
        let properties = [
            AppSettingsProperty(path: "/gap", currentValue: "4", status: .different),
            AppSettingsProperty(path: "/language", currentValue: "\"follow system language\"", status: .notSaved),
            AppSettingsProperty(path: "/unknown", currentValue: "1", status: .notSaved),
        ]
        let groups = AppSettingsPropertyGroup.groups(properties, settings: settings)
        XCTAssertEqual(groups.map(\.title), ["General", "Layout", "Preferences"])
        XCTAssertEqual(groups[0].properties[0].displayValue, "follow system language")
        XCTAssertEqual(groups[1].properties[0].displayValue, "4")
        XCTAssertEqual(groups[2].properties[0].displayValue, "1")
    }

    func testSourceFilePreviewShowsReadableTextWithoutChangingRawData() throws {
        let value = "font-size = 14\n# a comment\n"
        let raw = String(data: try JSONEncoder().encode(value), encoding: .utf8)!
        let property = AppSettingsProperty(path: "/config", currentValue: raw, status: .notSaved)
        let settings = [AppStateExportableSetting(kind: "file", label: "Settings file", source: "~/config", requiresConfirmation: true)]
        XCTAssertTrue(property.isReviewedSource(settings: settings))
        XCTAssertEqual(property.displayGroup(settings: settings), "Settings file")
        XCTAssertEqual(property.displayValue, value)
        XCTAssertEqual(property.currentValue, raw)
        XCTAssertFalse(property.isReviewedSource(settings: []))
        XCTAssertEqual(AppSettingsProperty(path: "/string", currentValue: "\"true\"", status: .matching).displayValue, "true")
    }

    func testPreservedEmptyObjectIsNotPresentedAsAMatchingPreference() throws {
        let original = try review(changed: false).response!
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json["comparison"] = ["properties": [["path": "/config", "currentValue": "{}", "status": "preserved"]], "preservedCount": 0]
        let response = try JSONDecoder().decode(AppSettingsCaptureResponse.self, from: JSONSerialization.data(withJSONObject: json))
        let summary = AppSettingsDetailSummary(application: try application(sources: []), target: target(.machine),
            review: AppSettingsReview(response: response, error: nil, checkedAt: Date()))
        XCTAssertEqual(summary.title, "No changes to save")
        XCTAssertEqual(summary.repositoryStatus, "Saved preferences kept")
    }

    private func review(changed: Bool, written: Bool = false, token: String? = "review-token") throws -> AppSettingsReview {
        let json: [String: Any] = [
            "schemaVersion": 1, "action": "settings-preview", "success": true, "appId": "rectangle",
            "scope": "machine", "destination": "config/app-state/machines/mac/settings.json",
            "changed": changed, "written": written, "tracked": false, "preview": "{}",
            "redaction": ["policy": "default_closed", "count": 0, "items": []],
            "captured": [], "skipped": [], "message": "Reviewed", "reviewToken": token as Any? ?? NSNull(),
        ]
        let response = try JSONDecoder().decode(
            AppSettingsCaptureResponse.self, from: JSONSerialization.data(withJSONObject: json))
        return AppSettingsReview(response: response, error: nil, checkedAt: Date())
    }

    private func target(_ scope: AppSettingsScope, _ profile: String = "") -> AppSettingsTarget {
        AppSettingsTarget(scope: scope, profile: profile, hostname: "mac")
    }

    private func application(
        sources: [[String: Any]], requiresConfirmation: Bool = false, privateState: Bool = false
    ) throws -> AppStateSettingsApplication {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "rectangle", "name": "Rectangle", "bundleId": "com.knollsoft.Rectangle",
            "installed": true, "capturable": true, "configured": !sources.isEmpty,
            "captureKinds": ["defaults"], "configurationSources": sources,
            "exportableSettings": [
                [
                    "kind": "file", "label": "Settings", "source": "~/config",
                    "requiresConfirmation": requiresConfirmation,
                ]
            ],
            "privateState": privateState ? ["readiness": "ready", "exclusionReason": "Private data"] : NSNull(),
        ])
        return try JSONDecoder().decode(AppStateSettingsApplication.self, from: data)
    }
}
