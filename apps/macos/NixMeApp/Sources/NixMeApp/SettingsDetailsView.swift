import AppKit
import SwiftUI

struct SettingsDetailsView: View {
    let application: AppStateSettingsApplication
    let target: AppSettingsTarget
    let review: AppSettingsReview?
    let readAccess: AppSettingsReadAccess
    let revealFile: (String) -> Void

    @State private var showingJSON = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Files, sources & diagnostics").font(.title3.weight(.semibold))
                Spacer()
                Button(copied ? "Copied" : "Copy details", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }
                .buttonStyle(.borderless)
            }
            if let checkedAt = review?.checkedAt {
                Text("Checked \(checkedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = review?.error ?? review?.noPreferences {
                section("Last check") { Text(message).font(.callout) }
            }
            section("Saved copies") {
                Text("Saving for: \(target.label)").font(.callout.weight(.medium))
                if !target.isExported(application) && review?.response?.written != true {
                    Text("No copy has been saved here using Nix Me yet.").foregroundStyle(.secondary)
                }
                reference("Save destination", path: target.destination)
                ForEach(target.sources(in: application)) { source in
                    sourceRow(source)
                }
                let otherSources = application.configurationSources.filter { !$0.path.hasPrefix(target.directory) }
                if !otherSources.isEmpty {
                    Text("Also configured elsewhere").font(.headline).padding(.top, 8)
                    Text("These sources may apply to this Mac, but are not the saved copy being compared.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(otherSources) { source in sourceRow(source) }
                }
            }
            section("Supported settings") {
                if application.exportableSettings.isEmpty {
                    Text("This integration does not expose automatically exportable settings.")
                        .foregroundStyle(.secondary)
                }
                ForEach(application.exportableSettings) { setting in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(setting.label).font(.callout.weight(.medium))
                        Text(setting.source).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if setting.requiresConfirmation == true {
                            Text(readAccess.requiresApproval ? "Permission needed before reading" : "Read access allowed for this session")
                                .font(.caption).foregroundStyle(readAccess.requiresApproval ? OxidePalette.amber : OxidePalette.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                }
            }
            section("Integration files") {
                if let path = application.appPath { reference("Application", path: path) }
                if let path = application.recipePath { reference("Management integration", path: path, revealable: true) }
                ForEach(application.managedPaths, id: \.self) { path in
                    reference("Managed file", path: path, revealable: true)
                }
                ForEach(application.manualSteps, id: \.self) { Text($0).font(.callout) }
            }
            if let preview = review?.response, review?.error == nil, review?.noPreferences == nil {
                if !preview.skipped.isEmpty {
                    section("Not included") {
                        ForEach(preview.skipped) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.kind == "manual" ? "Manual settings" : "Source not read").font(.headline)
                                Text("\(item.bind ?? item.kind): \(item.reason)").font(.callout)
                            }
                            .accessibilityElement(children: .contain)
                        }
                    }
                }
                section("Export format") {
                    Text("This is the reviewed, filtered preview. Opening Details does not read any additional files.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(showingJSON ? "Hide JSON" : "Show JSON") { showingJSON.toggle() }
                        .buttonStyle(.borderless)
                        .accessibilityValue(showingJSON ? "Expanded" : "Collapsed")
                    if showingJSON {
                        Text(preview.preview).font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: target) { _, _ in copied = false }
        .onChange(of: review?.checkedAt) { _, _ in copied = false }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(OxidePalette.green).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OxidePalette.panel)
        .overlay(Rectangle().stroke(OxidePalette.border))
        .accessibilityElement(children: .contain)
    }

    private func sourceRow(_ source: AppStateConfigurationSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            reference(source.label, path: source.path, revealable: true)
            if let paths = source.propertyPaths, !paths.isEmpty {
                Text("\(paths.count) saved settings").font(.caption.weight(.semibold))
                Text(paths.map { AppSettingsProperty(path: $0, currentValue: "", status: .matching).displayName }.joined(separator: "\n"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func reference(_ label: String, path: String, revealable: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.callout.weight(.medium))
                Text(path).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if revealable {
                Button("Reveal \(label)", systemImage: "folder") { revealFile(path) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Reveal \(path)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var report: String {
        AppSettingsDetailsReport(application: application, target: target, review: review).text
    }
}
