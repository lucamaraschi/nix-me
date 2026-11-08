import SwiftUI

struct SettingsPropertyComparisonView: View {
    let comparison: AppSettingsComparison
    let written: Bool
    var settings: [AppStateExportableSetting] = []
    @State private var showUnchanged = false

    private var changed: [AppSettingsProperty] {
        comparison.properties.filter { [.notSaved, .different].contains($0.status) }
    }

    private var unchanged: [AppSettingsProperty] {
        comparison.properties.filter { $0.status == .matching }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !changed.isEmpty {
                HStack {
                    Text(written ? "What you saved" : "What will be saved").font(.headline)
                    Spacer()
                    Text("\(changed.count) \(changed.count == 1 ? "item" : "items")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                groupedPreferences(changed)
            }
            if !unchanged.isEmpty {
                DisclosureGroup("\(unchanged.count) \(unchanged.count == 1 ? "preference already matches" : "preferences already match")", isExpanded: $showUnchanged) {
                    groupedPreferences(unchanged).padding(.top, 12)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            let kept = comparison.preservedCount + comparison.properties.filter { $0.status == .preserved }.count
            if kept > 0 {
                Label("\(kept) other saved \(kept == 1 ? "preference stays" : "preferences stay") untouched.", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func groupedPreferences(_ properties: [AppSettingsProperty]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(AppSettingsPropertyGroup.groups(properties, settings: settings)) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.title).font(.callout.weight(.semibold))
                        .foregroundStyle(OxidePalette.green).padding(.horizontal, 16).padding(.vertical, 12)
                    ForEach(group.properties) { property in
                        Divider()
                        preference(property).padding(16)
                    }
                }
                .background(OxidePalette.panel)
                .overlay(Rectangle().stroke(OxidePalette.border))
            }
        }
    }

    @ViewBuilder
    private func preference(_ property: AppSettingsProperty) -> some View {
        if property.isReviewedSource(settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                Text(settings[0].source).font(.caption.monospaced()).foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Text(property.displayValue).font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled).padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: 200).background(OxidePalette.background)
                Text("The complete file is shown above. Scroll to read it before saving.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(property.displayName(settings: settings)).font(.callout.weight(.medium))
                            .help(property.path).textSelection(.enabled)
                        if property.status == .different && !written {
                            Text("Different from the saved copy").font(.caption).foregroundStyle(OxidePalette.amber)
                        }
                    }
                    Spacer(minLength: 0)
                    if property.displayValue.count <= 80 && !property.displayValue.contains("\n") {
                        Text(property.displayValue).font(.callout).textSelection(.enabled)
                            .foregroundStyle(OxidePalette.primary).multilineTextAlignment(.trailing)
                            .frame(maxWidth: 230, alignment: .trailing)
                    }
                }
                if property.displayValue.count > 80 || property.displayValue.contains("\n") {
                    ScrollView {
                        Text(property.displayValue).font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }
                    .frame(height: property.displayValue.count > 200 ? 160 : 70)
                    .background(OxidePalette.background)
                }
            }
        }
    }
}

struct SettingsOverviewCard: View {
    let catalog: AppStateSettingsCatalog?
    let target: AppSettingsTarget
    let reviews: [String: AppSettingsReview]
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("APP SETTINGS", systemImage: "slider.horizontal.3")
                .oxideLabel(color: OxidePalette.green)
            Text(target.label).font(.title3.weight(.semibold))
            if let catalog {
                let summary = AppSettingsSummary(applications: catalog.applications, target: target, reviews: reviews)
                Text(
                    reviews.isEmpty
                        ? "Check your apps for unsaved settings"
                        : "\(summary.differentCount) reviewed apps have settings to save"
                )
                .font(.headline).foregroundStyle(summary.differentCount > 0 ? OxidePalette.amber : OxidePalette.primary)
                Text("\(summary.exportedCount) of \(summary.supported.count) supported apps have a saved copy here")
                Text("\(summary.uncheckedCount) not checked yet · \(summary.failedCount) could not be checked")
                    .foregroundStyle(.secondary)
                Text(
                    "Open App Settings to find what has changed and keep the preferences you care about. Nothing is saved automatically."
                )
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Settings catalog unavailable. Refresh to retry.").foregroundStyle(.secondary)
            }
            Button("Review App Settings", systemImage: "arrow.right", action: openSettings)
                .buttonStyle(OxideButtonStyle(variant: .secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .oxidePanel()
    }
}

struct RepositoryOverviewCard: View {
    let git: GitState?
    let openRepository: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("CENTRAL REPOSITORY // GIT", systemImage: "arrow.up.doc")
                .oxideLabel(color: OxidePalette.green)
            Text(title).font(.title3.weight(.semibold))
            if let git {
                Text("\(git.ahead) commits ahead · \(git.behind) behind last known upstream")
                Text(git.upstream ?? "No upstream configured").font(.caption.monospaced())
            }
            Text(
                "Save writes settings into your local checkout. Review the files, commit, then push with your Git client. Applying the system does not publish settings."
            )
            .font(.callout).foregroundStyle(.secondary)
            Text("Upstream status is local Git metadata, not a fresh network check. Other checkout changes may be included.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Repository Folder", systemImage: "folder", action: openRepository)
                .buttonStyle(OxideButtonStyle(variant: .secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .oxidePanel()
    }

    private var title: String {
        guard let git, git.repository else { return "Repository status unavailable" }
        if git.dirty { return "Local files need Git review" }
        if git.ahead > 0 && git.behind > 0 { return "Branches have diverged" }
        if git.ahead > 0 { return "Commits ready to push" }
        if git.behind > 0 { return "Upstream changes to review" }
        return git.upstream == nil ? "Set an upstream in your Git client" : "No local changes to publish"
    }
}
