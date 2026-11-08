import Foundation

struct MachineDriftPlan: Decodable {
    let schemaVersion: Int
    let host: String
    let token: String
    let checkedAt: String
    let destination: String
    let items: [MachineDriftItem]
    let warnings: [String]
    var canKeepChanges: Bool? = nil
    var needsSavingSupport: Bool? = nil
    var publication: MachineDriftPublication? = nil
    var destinations: [MachineDriftDestination]? = nil

    var summary: String {
        if items.isEmpty { return warnings.isEmpty ? "No drift found in checked areas" : "Some areas could not be checked" }
        return "\(items.count) local difference\(items.count == 1 ? "" : "s") to review"
    }
}

struct MachineDriftDestination: Decodable, Identifiable {
    let id: String
    let scope: String
    let name: String
    let source: String
    let path: String
    let hosts: [String]

    var title: String {
        switch scope {
        case "shared": return "Shared defaults"
        case "type": return "Machine type: \(name)"
        case "profile": return "Profile: \(name)"
        default: return "This machine: \(name)"
        }
    }
    var symbol: String {
        switch scope {
        case "shared": return "network"
        case "type": return "laptopcomputer"
        case "profile": return "slider.horizontal.3"
        default: return "desktopcomputer"
        }
    }
    func accepts(_ items: [MachineDriftItem]) -> Bool {
        scope == "machine" || !items.contains(where: { $0.kind == "file" })
    }
}

struct MachineDriftItem: Decodable, Identifiable {
    let id: String
    let kind: String
    let name: String
    let change: String
    let current: String
    let expected: String
    let canKeep: Bool
    let canRestore: Bool
    let note: String
    let conflict: Bool?

    var category: String { kind == "file" ? "Managed dotfiles" : kind == "cask" ? "Applications" : "Command-line tools" }
    var symbol: String { kind == "file" ? "doc.text" : kind == "cask" ? "macwindow" : "terminal" }
    var restoreEffect: String {
        if kind == "file" { return "Back up and restore \(name)" }
        return change == "extra" ? "Uninstall \(name)" : "Install \(name)"
    }

    var saveEffect: String {
        if kind == "file" { return change == "missing" ? "Stop managing \(name)" : "Save this Mac's version of \(name)" }
        return change == "extra" ? "Add \(name) to the configuration" : "Remove \(name) from the configuration"
    }
}

struct MachineDriftRequest: Encodable {
    let token: String
    let ids: [String]
    var reviewToken: String? = nil
    var proposalToken: String? = nil
    var destinationID: String? = nil
    var destinationsByItem: [String: String]? = nil
}

struct MachineDriftProposal: Decodable {
    struct File: Decodable, Identifiable {
        let path: String
        let before: String?
        let after: String
        let difference: String
        var id: String { path }
    }
    let token: String
    let ids: [String]
    let proposalToken: String
    let destination: String
    let needsSavingSupport: Bool
    let files: [File]
    var localFiles: [MachineDriftPreview.File] = []
    var destinationID: String? = nil
    var destinationsByItem: [String: String]? = nil
    var destinations: [MachineDriftDestination]? = nil
    var affectedHosts: [String]? = nil
    struct Impact: Decodable, Identifiable {
        let host: String
        let effects: [String]
        var id: String { host }
    }
    var impact: [Impact]? = nil

    func matches(_ request: MachineDriftRequest) -> Bool {
        guard token == request.token && Set(ids) == Set(request.ids) else { return false }
        if let destinationsByItem {
            let requested = request.destinationsByItem ?? request.destinationID.map { destination in
                Dictionary(uniqueKeysWithValues: request.ids.map { ($0, destination) })
            }
            return destinationsByItem == requested
        }
        return request.destinationsByItem == nil && destinationID == request.destinationID
    }
}

struct MachineDriftPublication: Decodable {
    let path: String
    let state: String

    var title: String {
        switch state {
        case "localChanges": return "Configuration changes to commit"
        case "differentFromUpstream": return "Configuration differs from last-known upstream"
        default: return "Saved in the configuration repository"
        }
    }
    var detail: String {
        switch state {
        case "localChanges": return "Review these files, then commit and push with your Git client. Saving does not publish them."
        case "differentFromUpstream": return "Review the difference before pushing. Remote status has not been refreshed."
        case "matchesLastKnownUpstream": return "Matches the last-known upstream copy. Remote status has not been refreshed."
        default: return "Git publication status is unavailable. Check your Git client before assuming these changes are published."
        }
    }
}

struct MachineDriftPreview: Decodable {
    struct File: Decodable, Identifiable {
        let id: String
        let current: String?
        let expected: String
        var difference: String? = nil
    }
    let files: [File]
    let reviewToken: String
}

struct MachineDriftResult: Decodable {
    struct Item: Decodable, Identifiable {
        let id: String
        let success: Bool
        let message: String
    }
    let success: Bool
    let message: String
    let results: [Item]
    var action: String? = nil
    var filesWritten: [String]? = nil
}

enum MachineDriftSelection {
    static func canPrepare(_ items: [MachineDriftItem]) -> Bool {
        !items.isEmpty && items.allSatisfy(\.canKeep)
    }

    static func destinationsByItem(_ items: [MachineDriftItem], choices: [String: String], host: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: items.map { item in
            (item.id, item.kind == "file" ? "machine:\(host)" : choices[item.id] ?? "machine:\(host)")
        })
    }
}
