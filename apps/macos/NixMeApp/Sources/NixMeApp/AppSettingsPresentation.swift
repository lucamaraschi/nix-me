import Foundation

struct AppSettingsTarget: Equatable {
    let scope: AppSettingsScope
    let profile: String
    let hostname: String

    var label: String {
        switch scope {
        case .shared: "All machines"
        case .profile: "Profile: \(profile)"
        case .machine: "This Mac: \(hostname)"
        }
    }

    var shortLabel: String {
        switch scope {
        case .shared: "All machines"
        case .profile: profile
        case .machine: "This Mac"
        }
    }

    var directory: String {
        switch scope {
        case .shared: "config/app-state/shared/"
        case .profile: "config/app-state/profiles/\(profile)/"
        case .machine: "config/app-state/machines/\(hostname)/"
        }
    }

    var destination: String { directory + "settings.json" }

    func sources(in application: AppStateSettingsApplication) -> [AppStateConfigurationSource] {
        application.configurationSources.filter { $0.path.hasPrefix(directory) }
    }

    func isExported(_ application: AppStateSettingsApplication) -> Bool {
        // Capture writes this file only; other values files remain separate sources.
        application.configurationSources.contains { $0.path == destination }
    }
}

struct AppSettingsReview {
    let response: AppSettingsCaptureResponse?
    let error: String?
    var noPreferences: String? = nil
    let checkedAt: Date

    var differenceCount: Int {
        guard error == nil, let response, !response.written else { return 0 }
        return response.comparison?.differenceCount ?? (response.changed ? 1 : 0)
    }

    var label: String {
        switch phase {
        case .unreviewed: "Not checked yet"
        case .failed: "Could not check settings"
        case .empty: "No preferences to save yet"
        case .needsUpdate: "Update needed to save"
        case .ready: "\(differenceCount) settings to save"
        case .unchanged: "Reviewed settings match"
        case .saved: "Saved in this session"
        }
    }

    var phase: AppSettingsReviewPhase {
        if error != nil { return .failed }
        if noPreferences != nil { return .empty }
        guard let response else { return .unreviewed }
        if response.written { return .saved }
        if !response.changed { return .unchanged }
        return response.reviewToken == nil ? .needsUpdate : .ready
    }
}

enum AppSettingsReviewPhase {
    case unreviewed, empty, failed, needsUpdate, ready, unchanged, saved
}

struct AppSettingsDetailSummary {
    let application: AppStateSettingsApplication
    let target: AppSettingsTarget
    let review: AppSettingsReview

    private var keptWithoutMatching: Bool {
        review.response?.comparison?.properties.contains { $0.status == .preserved } == true
    }

    var title: String {
        switch review.phase {
        case .ready:
            target.isExported(application) ? "Your preferences have changed" : "Keep \(application.name) the way you like it"
        case .saved: "Your preferences are saved"
        case .unchanged: keptWithoutMatching ? "No changes to save" : "Your saved preferences are up to date"
        case .needsUpdate: "This preview needs a newer version of Nix Me"
        case .failed: "We couldn't read these preferences"
        case .empty: "Nothing to save yet"
        case .unreviewed: "Let's look at your preferences"
        }
    }

    var message: String {
        switch review.phase {
        case .ready:
            "Save the preferences below for \(target.shortLabel). \(application.name) will keep working exactly as it does now."
        case .saved: "A copy is in your local repository for \(target.shortLabel). It hasn't been published or applied to another Mac."
        case .unchanged:
            keptWithoutMatching
                ? "Saving this preview would leave your existing preferences unchanged. An empty value does not remove settings already in the repository."
                : "The preferences we checked match the copy for \(target.shortLabel). There is nothing to save."
        case .needsUpdate: "You can read this preview, but saving is unavailable until Nix Me is updated and the preferences are checked again."
        case .failed: "Nothing was saved. The existing copy in your repository is unchanged."
        case .empty: "Use the app and set your preferences first, then check again. Any existing saved copy is unchanged."
        case .unreviewed: "See which preferences can be kept before saving anything."
        }
    }

    var repositoryStatus: String {
        switch review.phase {
        case .saved: "Saved just now"
        case .unchanged: keptWithoutMatching ? "Saved preferences kept" : "Matches this Mac"
        case .ready: target.isExported(application) ? "Changes to save" : "No saved copy yet"
        default: target.isExported(application) ? "Saved copy not checked" : "No saved copy yet"
        }
    }

}

struct AppSettingsPropertyGroup: Identifiable {
    let title: String
    let properties: [AppSettingsProperty]
    var id: String { title }

    static func groups(_ properties: [AppSettingsProperty], settings: [AppStateExportableSetting]) -> [Self] {
        Dictionary(grouping: properties, by: { $0.displayGroup(settings: settings) })
            .map { Self(title: $0.key, properties: $0.value) }
            .sorted {
                if $0.title == "General" { return $1.title != "General" }
                if $1.title == "General" { return false }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }
}

struct AppSettingsReadAccess {
    let application: AppStateSettingsApplication
    let approved: Bool

    var requiresApproval: Bool { application.requiresExportConfirmation && !approved }
    var previewLabel: String { requiresApproval ? "Allow & Preview" : "Check Again" }
    var previewSymbol: String { requiresApproval ? "hand.raised" : "arrow.clockwise" }
}

// Consent belongs to the source being read, not the destination or preview result.
// Keep it in memory only, and require approval again if the source boundary changes.
struct AppSettingsReadApprovals {
    private struct Source: Hashable {
        let kind: String
        let path: String
        let requiresConfirmation: Bool
    }

    private struct Key: Hashable {
        let checkout: String
        let hostname: String
        let appID: String
        let bundleID: String
        let recipePath: String?
        let sources: Set<Source>

        init(application: AppStateSettingsApplication, checkout: String, hostname: String) {
            self.checkout = checkout
            self.hostname = hostname
            appID = application.id
            bundleID = application.bundleId
            recipePath = application.recipePath
            sources = Set(application.exportableSettings.map {
                Source(kind: $0.kind, path: $0.source, requiresConfirmation: $0.requiresConfirmation == true)
            })
        }
    }

    private var approved: Set<Key> = []

    mutating func grant(_ application: AppStateSettingsApplication, checkout: String, hostname: String) {
        guard application.installed, application.capturable, application.privateState == nil,
            application.requiresExportConfirmation else { return }
        approved.insert(Key(application: application, checkout: checkout, hostname: hostname))
    }

    func contains(_ application: AppStateSettingsApplication, checkout: String, hostname: String) -> Bool {
        guard application.installed, application.capturable, application.privateState == nil else { return false }
        return approved.contains(Key(application: application, checkout: checkout, hostname: hostname))
    }
}

enum AppSettingsCollection: String, CaseIterable, Identifiable {
    case changes = "Changes to keep"
    case attention = "Needs attention"
    case newApps = "Not saved yet"
    case saved = "Saved settings"
    case empty = "Nothing to save yet"
    case unavailable = "Other installed apps"

    var id: Self { self }

    var subtitle: String {
        switch self {
        case .changes: "Your preferences have changed since the saved copy."
        case .attention: "These apps could not be checked. Open one to see what happened."
        case .newApps: "Keep the preferences you care about. You do not need to save every app."
        case .saved: "Copies already in this repository. Each app shows whether it has been checked."
        case .empty: "These apps have not stored any supported preferences on this Mac yet."
        case .unavailable: "These apps cannot save settings automatically."
        }
    }
}

struct AppSettingsCardState {
    let application: AppStateSettingsApplication
    let target: AppSettingsTarget
    let review: AppSettingsReview?
    var readApproved = false

    private var readAccess: AppSettingsReadAccess {
        AppSettingsReadAccess(application: application, approved: readApproved)
    }

    var collection: AppSettingsCollection {
        guard application.capturable else { return .unavailable }
        if let phase = review?.phase {
            switch phase {
            case .failed, .needsUpdate: return .attention
            case .ready: return target.isExported(application) ? .changes : .newApps
            case .saved, .unchanged: return .saved
            case .empty: return .empty
            case .unreviewed: break
            }
        }
        return target.isExported(application) ? .saved : .newApps
    }

    var summary: String {
        guard application.capturable else {
            return application.privateState != nil ? "Private settings stay on this Mac" : "Automatic saving is not available"
        }
        if let review, review.phase != .unreviewed {
            switch review.phase {
            case .ready:
                return target.isExported(application)
                    ? "\(review.differenceCount) settings differ from your saved copy"
                    : "\(review.differenceCount) settings ready to save"
            case .saved: return "Saved locally. Ready for your Git review."
            case .unchanged: return "Checked. Your saved settings match."
            case .failed: return "Could not read settings. Nothing was saved."
            case .needsUpdate: return "Update Nix Me before saving this preview."
            case .empty: return "No preferences to save yet"
            case .unreviewed: break
            }
        }
        if readAccess.requiresApproval { return "Permission needed to preview the settings file" }
        if readApproved { return "Read access allowed. Ready to preview settings." }
        return target.isExported(application)
            ? "Saved copy available. Not checked yet." : "Checking which preferences can be saved…"
    }

    var action: String {
        if !application.capturable { return "Why not?" }
        switch review?.phase ?? .unreviewed {
        case .ready: return target.isExported(application) ? "See changes" : "See settings"
        case .saved, .unchanged: return "View saved settings"
        case .failed, .needsUpdate: return "View issue"
        case .empty: return "View details"
        case .unreviewed: return readAccess.requiresApproval ? "Review access" : "View settings"
        }
    }
}

extension AppSettingsProperty {
    private func documentedSetting(_ settings: [AppStateExportableSetting]) -> AppStateExportableSetting? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard components.count == 1, let component = components.first else { return nil }
        let key = component.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        let matches = settings.filter { $0.kind == "preference" && $0.source.hasSuffix("/" + key) }
        return matches.count == 1 ? matches.first : nil
    }

    func displayName(settings: [AppStateExportableSetting]) -> String {
        guard let label = documentedSetting(settings)?.label else { return displayName }
        return label.components(separatedBy: " > ").last ?? label
    }

    func displayGroup(settings: [AppStateExportableSetting]) -> String {
        if isReviewedSource(settings: settings) { return "Settings file" }
        if let label = documentedSetting(settings)?.label {
            let sections = label.components(separatedBy: " > ").dropLast()
            return sections.last(where: { !["Settings", "Preferences"].contains($0) }) ?? "General"
        }
        return "Preferences"
    }

    func isReviewedSource(settings: [AppStateExportableSetting]) -> Bool {
        settings.count == 1 && settings[0].kind == "file" && settings[0].requiresConfirmation == true
            && path.split(separator: "/").count == 1
            && (try? JSONDecoder().decode(String.self, from: Data(currentValue.utf8))) != nil
    }

    var displayValue: String {
        switch currentValue {
        case "true": "Yes"
        case "false": "No"
        default: (try? JSONDecoder().decode(String.self, from: Data(currentValue.utf8))) ?? currentValue
        }
    }

    var displayName: String {
        path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map {
            let key = $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            let words = key.replacingOccurrences(of: "(?<=[a-z0-9])(?=[A-Z])", with: " ", options: .regularExpression)
            return words.prefix(1).uppercased() + words.dropFirst()
        }.joined(separator: " / ")
    }
}

struct AppSettingsSummary {
    let applications: [AppStateSettingsApplication]
    let target: AppSettingsTarget
    let reviews: [String: AppSettingsReview]

    var supported: [AppStateSettingsApplication] { applications.filter { $0.installed && $0.capturable } }
    var exportedCount: Int { supported.filter(target.isExported).count }
    var differentCount: Int { supported.filter { (reviews[$0.id]?.differenceCount ?? 0) > 0 }.count }
    var uncheckedCount: Int { supported.filter { reviews[$0.id] == nil }.count }
    var failedCount: Int { supported.filter { reviews[$0.id]?.error != nil }.count }
}
