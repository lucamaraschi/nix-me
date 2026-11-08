import Foundation

struct AppSettingsDetailsReport {
    let application: AppStateSettingsApplication
    let target: AppSettingsTarget
    let review: AppSettingsReview?

    var text: String {
        var lines = [application.name, "Saving for: \(target.label)", "Destination: \(target.destination)"]
        if let checkedAt = review?.checkedAt { lines += ["Checked: \(checkedAt.ISO8601Format())"] }
        if let message = review?.error ?? review?.noPreferences { lines += ["", "Last check", message] }
        lines += ["", "Configuration sources"]
        lines += application.configurationSources.map { "\($0.label): \($0.path)" }
        for source in application.configurationSources {
            if let paths = source.propertyPaths { lines += paths.map { "Saved property (\(source.label)): \($0)" } }
        }
        lines += ["", "Supported settings"]
        lines += application.exportableSettings.map { "\($0.label): \($0.source)" }
        if let path = application.recipePath { lines += ["", "Integration: \(path)"] }
        if let path = application.appPath { lines += ["Application: \(path)"] }
        lines += application.managedPaths.map { "Managed file: \($0)" }
        lines += application.manualSteps
        // Copy only the preview already obtained through the capture boundary; never read sources here.
        if let preview = review?.response, review?.error == nil, review?.noPreferences == nil {
            lines += ["", "Reviewed export (JSON)", preview.preview]
            lines += preview.skipped.map { "Not included (\($0.bind ?? $0.kind)): \($0.reason)" }
        }
        return lines.joined(separator: "\n")
    }
}

struct AppSettingsReadFailure: Equatable {
    let message: String

    enum Kind { case privacy, filesystem, other }

    var kind: Kind {
        let lower = message.lowercased()
        if lower.contains("operation not permitted") || lower.contains("os error 1)") { return .privacy }
        if lower.contains("permission denied") || lower.contains("os error 13)") { return .filesystem }
        return .other
    }

    var isAccessDenied: Bool { kind != .other }

    var title: String {
        switch kind {
        case .privacy: "macOS blocked access to these settings"
        case .filesystem: "This settings file is not readable by your account"
        case .other: "We couldn't read these preferences"
        }
    }

    var guidance: String? {
        switch kind {
        case .privacy:
            "Resolve Access will guide you through macOS approval and check the result. Nix Me will not change permissions for you."
        case .filesystem:
            "Resolve Access will show the affected source and how to inspect its permissions. Full Disk Access does not fix file ownership."
        case .other: nil
        }
    }
}
